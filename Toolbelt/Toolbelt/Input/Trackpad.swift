import AppKit
import CoreGraphics

enum TrackpadMiddle: String, CaseIterable, Identifiable {
    case off, standard, lighter
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .standard: "Standard"
        case .lighter: "Lighter"
        }
    }
    var detail: String {
        switch self {
        case .off: "Three fingers behave as macOS sets them."
        case .standard: "Click with three fingers for a middle click."
        case .lighter: "A light three-finger tap also middle-clicks, no press needed."
        }
    }
}

/// Recognises a light three-finger tap from raw contact frames. Pure, unit tested.
struct TapDetector {
    static let maxDuration: TimeInterval = 0.25
    static let maxTravel: Float = 0.03 // normalized trackpad units

    private var start: TimeInterval?
    private var maxFingers = 0
    private var anchor: (x: Float, y: Float)?
    private var travel: Float = 0
    private var pressed = false

    /// Feed one frame: contact positions (0...1), time, and whether a mouse button is down.
    /// Returns true when the frame ends a three-finger tap.
    mutating func frame(_ points: [(x: Float, y: Float)], at t: TimeInterval, buttonDown: Bool) -> Bool {
        let n = Float(max(points.count, 1))
        return frame(count: points.count, cx: points.map(\.x).reduce(0, +) / n, cy: points.map(\.y).reduce(0, +) / n,
                     at: t, buttonDown: buttonDown)
    }

    /// Allocation-free form used on the multitouch thread: finger count and their centroid.
    mutating func frame(count: Int, cx: Float, cy: Float, at t: TimeInterval, buttonDown: Bool) -> Bool {
        if count == 0 {
            guard let start else { return false } // idle: nothing to reset
            defer { self = TapDetector() }
            return maxFingers == 3 && t - start < Self.maxDuration && travel < Self.maxTravel && !pressed
        }
        if start == nil { start = t }
        pressed = pressed || buttonDown
        maxFingers = max(maxFingers, count)
        if count == 3 {
            if let a = anchor { travel = max(travel, hypot(cx - a.x, cy - a.y)) } else { anchor = (cx, cy) }
        }
        return false
    }
}

/// Reads raw trackpad contacts through the private MultitouchSupport framework (dlopen at runtime;
/// pattern from Click2Minimize 3.0). Runs only while the trackpad middle click is on. All per-frame work
/// happens on the framework's thread; the main thread is woken only for a detected tap.
@MainActor
final class Trackpad {
    static let shared = Trackpad()

    private typealias ContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer) -> Void

    private struct API {
        let createList: CreateListFn, register: RegisterFn, unregister: RegisterFn, start: StartFn, stop: StopFn
    }

    private lazy var api: API? = {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let h = dlopen(path, RTLD_LAZY),
              let a = dlsym(h, "MTDeviceCreateList"), let b = dlsym(h, "MTRegisterContactFrameCallback"),
              let c = dlsym(h, "MTUnregisterContactFrameCallback"), let d = dlsym(h, "MTDeviceStart"),
              let e = dlsym(h, "MTDeviceStop") else { return nil }
        return API(createList: unsafeBitCast(a, to: CreateListFn.self), register: unsafeBitCast(b, to: RegisterFn.self),
                   unregister: unsafeBitCast(c, to: RegisterFn.self), start: unsafeBitCast(d, to: StartFn.self),
                   stop: unsafeBitCast(e, to: StopFn.self))
    }()

    private var devices: CFArray?
    private var deviceRefs: [UnsafeMutableRawPointer] = []
    private(set) var mode = TrackpadMiddle.off

    /// State shared with the framework's callback thread.
    private final class Shared: @unchecked Sendable {
        let lock = NSLock()
        var fingers = 0
        var detector = TapDetector()
        var tapsEnabled = false
        var buttonDown = false
        // Finger-follow (three-finger press-and-drag): latest centroid, delivered to main coalesced.
        var follow = false
        var followScheduled = false
        var cx: Float = 0, cy: Float = 0
    }
    private nonisolated static let shared_ = Shared()

    /// Runs ~90 times a second while a finger is on the trackpad, so it allocates nothing and makes no
    /// IPC calls: the button state comes from the input tap (`noteButton`).
    private nonisolated static let callback: ContactCallback = { _, data, count, timestamp, _ in
        let n = Int(max(count, 0))
        var sx: Float = 0, sy: Float = 0
        if let data {
            for i in 0..<n {
                let base = data + i * 96 // sizeof(MTTouch)
                sx += base.load(fromByteOffset: 32, as: Float.self)
                sy += base.load(fromByteOffset: 36, as: Float.self)
            }
        }
        let d = Float(max(n, 1))
        let s = shared_
        s.lock.lock()
        s.fingers = n
        let tapped = s.detector.frame(count: n, cx: sx / d, cy: sy / d, at: timestamp, buttonDown: s.buttonDown) && s.tapsEnabled
        var deliver = false
        if s.follow, n >= 2 {
            s.cx = sx / d
            s.cy = sy / d
            deliver = !s.followScheduled
            if deliver { s.followScheduled = true }
        }
        s.lock.unlock()
        if tapped { DispatchQueue.main.async { MiddleButton.shared.tap() } }
        if deliver { DispatchQueue.main.async { Trackpad.shared.deliverFollow() } }
        return 0
    }

    /// Called by the input tap on every left button down/up.
    nonisolated static func noteButton(_ down: Bool) {
        shared_.lock.withLock { shared_.buttonDown = down }
    }

    // MARK: Finger follow

    /// A pressed three-finger drag doesn't move the pointer, so the fingers themselves drive it:
    /// `handler` gets the offset in points from where the press began. Ported idea from Click2Minimize 3.0.
    private var followHandler: ((CGVector) -> Void)?
    private var followStart: (x: Float, y: Float)?

    func beginFollow(_ handler: @escaping (CGVector) -> Void) {
        followHandler = handler
        followStart = nil
        Self.shared_.lock.withLock {
            Self.shared_.follow = true
            Self.shared_.followScheduled = false
        }
    }

    func endFollow() {
        followHandler = nil
        followStart = nil
        Self.shared_.lock.withLock { Self.shared_.follow = false }
    }

    private func deliverFollow() {
        let c: (x: Float, y: Float) = Self.shared_.lock.withLock {
            Self.shared_.followScheduled = false
            return (Self.shared_.cx, Self.shared_.cy)
        }
        guard let handler = followHandler else { return }
        guard let start = followStart else { followStart = c; return }
        handler(Self.offset(from: start, to: c))
    }

    /// Normalized trackpad travel to screen points. The pad is ~1.6× wider than tall, so equal finger
    /// travel gives equal pointer travel; y is flipped (pad y grows upward, screen y downward).
    nonisolated static func offset(from a: (x: Float, y: Float), to b: (x: Float, y: Float)) -> CGVector {
        CGVector(dx: CGFloat(b.x - a.x) * 1400, dy: CGFloat(a.y - b.y) * 875)
    }

    /// Fingers currently on the trackpad.
    var fingerCount: Int { Self.shared_.lock.withLock { Self.shared_.fingers } }

    /// macOS Three Finger Drag (Accessibility) owns three-finger presses, so Standard steps aside.
    static var systemThreeFingerDrag: Bool {
        let keys = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
        return keys.contains { UserDefaults(suiteName: $0)?.bool(forKey: "TrackpadThreeFingerDrag") == true }
    }

    /// True when a left press happening now should become a middle press.
    var pressIsMiddle: Bool { mode != .off && !Self.systemThreeFingerDrag && fingerCount == 3 }

    func setMode(_ m: TrackpadMiddle) {
        mode = m
        Self.shared_.lock.withLock { Self.shared_.tapsEnabled = m == .lighter }
        if m == .off { stop() } else if deviceRefs.isEmpty { start() }
    }

    private func start() {
        guard let api, let list = api.createList()?.takeRetainedValue() else { return }
        devices = list
        for i in 0..<CFArrayGetCount(list) {
            guard let dev = CFArrayGetValueAtIndex(list, i) else { continue }
            let ref = UnsafeMutableRawPointer(mutating: dev)
            api.register(ref, Self.callback)
            api.start(ref, 0)
            deviceRefs.append(ref)
        }
    }

    private func stop() {
        guard let api else { return }
        for ref in deviceRefs {
            api.unregister(ref, Self.callback)
            api.stop(ref)
        }
        deviceRefs = []
        devices = nil
        Self.shared_.lock.withLock {
            Self.shared_.fingers = 0
            Self.shared_.detector = TapDetector()
        }
    }
}
