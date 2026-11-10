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
        if points.isEmpty {
            defer { self = TapDetector() }
            guard let start else { return false }
            return maxFingers == 3 && t - start < Self.maxDuration && travel < Self.maxTravel && !pressed
        }
        if start == nil { start = t }
        pressed = pressed || buttonDown
        maxFingers = max(maxFingers, points.count)
        if points.count == 3 {
            let c = (x: points.map(\.x).reduce(0, +) / 3, y: points.map(\.y).reduce(0, +) / 3)
            if let a = anchor { travel = max(travel, hypot(c.x - a.x, c.y - a.y)) } else { anchor = c }
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
    }
    private nonisolated static let shared_ = Shared()

    private nonisolated static let callback: ContactCallback = { _, data, count, timestamp, _ in
        var points: [(x: Float, y: Float)] = []
        if let data, count > 0 {
            points.reserveCapacity(Int(count))
            for i in 0..<Int(count) {
                let base = data + i * 96 // sizeof(MTTouch)
                points.append((base.load(fromByteOffset: 32, as: Float.self), base.load(fromByteOffset: 36, as: Float.self)))
            }
        }
        let buttonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let s = shared_
        let tapped: Bool = s.lock.withLock {
            s.fingers = points.count
            return s.detector.frame(points, at: timestamp, buttonDown: buttonDown) && s.tapsEnabled
        }
        if tapped { DispatchQueue.main.async { MiddleButton.shared.tap() } }
        return 0
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
