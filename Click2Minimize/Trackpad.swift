import Carbon.HIToolbox
import Cocoa
import os.log

private let log = Logger(subsystem: "com.idemfactor.Click2Minimize", category: "trackpad")

/// One contact reported by MultitouchSupport. Normalized coordinates: 0...1, y grows upward.
struct Touch {
    let id: Int32
    let state: Int32
    let x: Float
    let y: Float
    let majorAxis: Float
}

/// Reads raw trackpad contacts through the private MultitouchSupport framework
/// (loaded at runtime) and turns them into gestures. The framework is only
/// started while a trackpad feature is enabled.
final class Trackpad {
    static let shared = Trackpad()

    // MARK: Framework binding

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
              let e = dlsym(h, "MTDeviceStop") else {
            log.error("MultitouchSupport unavailable")
            return nil
        }
        return API(createList: unsafeBitCast(a, to: CreateListFn.self), register: unsafeBitCast(b, to: RegisterFn.self),
                   unregister: unsafeBitCast(c, to: RegisterFn.self), start: unsafeBitCast(d, to: StartFn.self),
                   stop: unsafeBitCast(e, to: StopFn.self))
    }()

    private var devices: CFArray?
    private var deviceRefs: [UnsafeMutableRawPointer] = []

    /// Contact frames arrive on a private thread; copy them out and process on main.
    private static let callback: ContactCallback = { _, data, count, _, _ in
        var touches: [Touch] = []
        if let data, count > 0 {
            touches.reserveCapacity(Int(count))
            for i in 0..<Int(count) {
                let base = data + i * 96 // sizeof(MTTouch)
                touches.append(Touch(id: base.load(fromByteOffset: 16, as: Int32.self),
                                     state: base.load(fromByteOffset: 20, as: Int32.self),
                                     x: base.load(fromByteOffset: 32, as: Float.self),
                                     y: base.load(fromByteOffset: 36, as: Float.self),
                                     majorAxis: base.load(fromByteOffset: 60, as: Float.self)))
            }
        }
        DispatchQueue.main.async { Trackpad.shared.process(touches) }
        return 0
    }

    static var anyFeatureEnabled: Bool {
        let prefs: [Pref] = [.threeFingerSwipeDownToMinimize, .switcherThreeFingerSwipe, .universalNavigation,
                             .inPageScrolling, .threeFingerClickToMiddle, .threeFingerDragToMove,
                             .threeFingerPinchToResize, .overviewFourFinger, .edgeSlide,
                             .twoFingerTopDoubleClickToNextDisplay]
        return prefs.contains { $0.bool } || Pref.rotateClockwise.action.isSet || Pref.rotateCounterClockwise.action.isSet
    }

    /// Starts or stops monitoring to match the current preferences.
    func refresh() {
        let wanted = Self.anyFeatureEnabled && AX.isTrusted()
        if wanted && deviceRefs.isEmpty { start() } else if !wanted && !deviceRefs.isEmpty { stop() }
    }

    func restart() {
        stop()
        refresh()
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
        log.info("monitoring \(self.deviceRefs.count) multitouch device(s)")
    }

    private func stop() {
        guard let api else { return }
        for ref in deviceRefs {
            api.unregister(ref, Self.callback)
            api.stop(ref)
        }
        deviceRefs = []
        devices = nil
        touches = []
        endSession()
    }

    // MARK: State shared with the event router

    private(set) var touches: [Touch] = []
    var touchCount: Int { touches.count }

    /// True when the 3-finger contact moved since it began (distinguishes a drag from a click).
    var threeFingerMoved: Bool { session.count == 3 && session.travel > 0.02 }

    /// Both fingers rest on the top part of the trackpad.
    var twoFingersAtTop: Bool { touches.count == 2 && touches.allSatisfy { $0.y > 0.8 } }

    private(set) var edgeSlideActive = false

    /// Window being dragged by 3 fingers; pinching resizes it.
    var pinchTarget: AXUIElement? {
        didSet { lastPinchSpan = nil }
    }

    /// Window moved by the fingers themselves after a light 3-finger press:
    /// pressure is only needed to start, not while moving.
    private var moveTarget: AXUIElement?
    private var moveLastCentroid: (Float, Float)?
    private var moveStarted = false

    func beginWindowMove(_ w: AXUIElement) {
        moveTarget = w
        moveLastCentroid = nil
        moveStarted = false
        pinchTarget = Pref.threeFingerPinchToResize.bool ? w : nil
    }

    private func endWindowMove() {
        guard moveTarget != nil else { return }
        moveTarget = nil
        pinchTarget = nil
    }
    private var lastPinchSpan: Float?
    private var lastPinchTime = Date.distantPast

    // MARK: Gesture session

    private struct Session {
        var count = 0
        var start: [Int32: (Float, Float)] = [:]
        var startCentroid: (Float, Float) = (0, 0)
        var startSpan: Float = 0
        var startAngle: Float = 0
        var travel: Float = 0
        var fired = false
        var switcherAnchorY: Float?
        var edgeFinger: Int32?
        var edgeIsLeft = false
        var edgeLastY: Float = 0
        var dockArmed = false
        var dockActive = false
    }

    private var session = Session()

    private static func centroid(_ t: [Touch]) -> (Float, Float) {
        let n = Float(t.count)
        return (t.map(\.x).reduce(0, +) / n, t.map(\.y).reduce(0, +) / n)
    }

    private static func span(_ t: [Touch], _ c: (Float, Float)) -> Float {
        t.map { hypotf($0.x - c.0, $0.y - c.1) }.reduce(0, +) / Float(t.count)
    }

    private static func angle(_ t: [Touch]) -> Float {
        let s = t.sorted { $0.id < $1.id }
        return atan2f(s[1].y - s[0].y, s[1].x - s[0].x)
    }

    private func process(_ raw: [Touch]) {
        let limit = Float(Pref.palmThreshold.double)
        let active = raw.filter { ($0.state == 3 || $0.state == 4) && (limit <= 0 || $0.majorAxis <= limit) }
        touches = active
        if active.count != session.count {
            endSession(newCount: active.count)
            beginSession(active)
        } else if !active.isEmpty {
            update(active)
        }
    }

    private func beginSession(_ t: [Touch]) {
        session = Session()
        session.count = t.count
        guard !t.isEmpty else { return }
        for touch in t { session.start[touch.id] = (touch.x, touch.y) }
        session.startCentroid = Self.centroid(t)
        session.startSpan = Self.span(t, session.startCentroid)
        if t.count == 2 {
            session.startAngle = Self.angle(t)
            if Pref.edgeSlide.bool { armEdgeSlide(t) }
        }
        // Dock Fidget: a single finger starting on the bottom edge.
        if t.count == 1, Pref.dockFidget.bool, t[0].y < 0.08, !EventRouter.shared.gesturesBlocked {
            session.dockArmed = true
        }
    }

    private func endSession(newCount: Int = 0) {
        if session.switcherAnchorY != nil, AppSwitcher.shared.activeTrigger == .swipe {
            if newCount > 3 { AppSwitcher.shared.cancel() } else if newCount < 3 { AppSwitcher.shared.commit() }
        }
        if session.count == 3, newCount < 3 { endWindowMove() }
        if session.dockActive { DockController.shared.endTrackpadControl() }
        edgeSlideActive = false
    }

    private func update(_ t: [Touch]) {
        let c = Self.centroid(t)
        let dx = c.0 - session.startCentroid.0, dy = c.1 - session.startCentroid.1
        session.travel = max(session.travel, hypotf(dx, dy))

        switch t.count {
        case 1:
            updateDockFidget(t[0], dx: dx)
        case 2:
            if edgeSlideActive { updateEdgeSlide(t) } else { detectRotation(t, c) }
        case 3:
            if let w = moveTarget {
                moveWindow(w, c)
                if let p = pinchTarget { pinch(p, t, c) }
                return // moving a window is never a swipe
            }
            if let w = pinchTarget { pinch(w, t, c); return }
            if session.switcherAnchorY != nil { scrollSwitcher(t, c); return }
            detectThreeFingerSwipe(dx: dx, dy: dy, t, c)
        case 4:
            guard !session.fired, Pref.overviewFourFinger.bool, abs(dy) > 0.12, abs(dy) > abs(dx) * 1.5 else { return }
            session.fired = true
            if dy > 0 { WindowOverview.shared.toggle() } else { Stash.toggle() }
        default:
            break
        }
    }

    // MARK: Three-finger swipes

    /// 3-finger swipes are off while the system's three-finger drag is on (every
    /// drag would also read as a swipe) and while a button is pressed.
    private var threeFingerSwipesAllowed: Bool {
        !SystemTrackpad.threeFingerDrag && NSEvent.pressedMouseButtons == 0
    }

    private func detectThreeFingerSwipe(dx: Float, dy: Float, _ t: [Touch], _ c: (Float, Float)) {
        guard !session.fired, threeFingerSwipesAllowed, !EventRouter.shared.gesturesBlocked else { return }
        let threshold: Float = 0.12
        let vertical = abs(dy) > threshold && abs(dy) > abs(dx) * 1.5
        let horizontal = abs(dx) > threshold && abs(dx) > abs(dy) * 1.5
        guard vertical || horizontal else { return }

        let flags = Synth.currentFlags
        let fnOnly = flags.contains(.maskSecondaryFn) && flags.intersection(KeyShortcut.relevantFlags).isEmpty
        if fnOnly {
            guard Pref.inPageScrolling.bool else { return }
            session.fired = true
            let key = vertical ? (dy > 0 ? kVK_UpArrow : kVK_DownArrow) : (dx > 0 ? kVK_RightArrow : kVK_LeftArrow)
            Synth.key(key, flags: .maskCommand)
            return
        }
        guard flags.intersection(KeyShortcut.relevantFlags).isEmpty else { return } // skipped with modifiers

        if vertical && dy < 0, Pref.threeFingerSwipeDownToMinimize.bool {
            session.fired = true
            if let w = AX.window(at: Synth.cursor) { WindowOps.withWindow(w) { WindowOps.minimize($0) } }
        } else if vertical && dy > 0, Pref.switcherThreeFingerSwipe.bool {
            session.fired = true
            AppSwitcher.shared.show(trigger: .swipe)
            session.switcherAnchorY = c.1
        } else if horizontal, ActionRunner.universalNavigationApplies {
            session.fired = true
            ActionRunner.navigate(back: dx < 0)
        }
    }

    private func scrollSwitcher(_ t: [Touch], _ c: (Float, Float)) {
        guard let anchor = session.switcherAnchorY else { return }
        // Spreading the fingers cancels.
        if Self.span(t, c) > session.startSpan * 1.6 { AppSwitcher.shared.cancel(); session.switcherAnchorY = nil; return }
        let step: Float = 0.06
        let delta = anchor - c.1 // moving fingers down moves the highlight down
        if abs(delta) >= step {
            AppSwitcher.shared.move(delta > 0 ? 1 : -1)
            session.switcherAnchorY = anchor - (delta > 0 ? step : -step)
        }
    }

    private func moveWindow(_ w: AXUIElement, _ c: (Float, Float)) {
        defer { moveLastCentroid = c }
        guard let last = moveLastCentroid else { return }
        // Map the trackpad's width to roughly a screen width; its height is ~1/1.55 of that.
        let width = Float(NSScreen.main?.frame.width ?? 1440)
        let dx = (c.0 - last.0) * width, dy = -(c.1 - last.1) * width / 1.55
        guard abs(dx) + abs(dy) >= 1, let frame = AX.frame(w) else { return }
        if !moveStarted {
            moveStarted = true
            EventRouter.shared.threeFingerMoveBegan()
        }
        AX.setPosition(w, CGPoint(x: frame.minX + CGFloat(dx), y: frame.minY + CGFloat(dy)))
    }

    private func pinch(_ w: AXUIElement, _ t: [Touch], _ c: (Float, Float)) {
        guard Pref.threeFingerPinchToResize.bool else { return }
        let s = Self.span(t, c)
        guard let last = lastPinchSpan else { lastPinchSpan = s; return }
        guard Date().timeIntervalSince(lastPinchTime) > 0.03, last > 0 else { return }
        let ratio = s / last
        guard abs(ratio - 1) > 0.03 else { return }
        lastPinchSpan = s
        lastPinchTime = Date()
        WindowOps.scale(w, by: CGFloat(ratio))
    }

    // MARK: Two-finger rotation

    private func detectRotation(_ t: [Touch], _ c: (Float, Float)) {
        guard !session.fired, !EventRouter.shared.gesturesBlocked else { return }
        let cw = Pref.rotateClockwise.action, ccw = Pref.rotateCounterClockwise.action
        guard cw.isSet || ccw.isSet else { return }
        let delta = Float(GestureMath.normalizedAngle(CGFloat(Self.angle(t) - session.startAngle)))
        let spanRatio = Self.span(t, c) / max(session.startSpan, 0.001)
        guard abs(delta) > 0.6, session.travel < 0.12, spanRatio > 0.7, spanRatio < 1.4 else { return }
        session.fired = true
        // Normalized y grows upward, so a positive angle change is counter-clockwise.
        ActionRunner.perform(delta > 0 ? ccw : cw)
    }

    // MARK: Edge slide (brightness / volume)

    /// One finger rests in the centre strip, the other slides along a side edge.
    private func armEdgeSlide(_ t: [Touch]) {
        let centre = t.first { $0.x > 0.3 && $0.x < 0.7 }
        let edge = t.first { $0.x < 0.12 || $0.x > 0.88 }
        guard let centre, let edge, centre.id != edge.id else { return }
        session.edgeFinger = edge.id
        session.edgeIsLeft = edge.x < 0.5
        session.edgeLastY = edge.y
        edgeSlideActive = true
    }

    private func updateEdgeSlide(_ t: [Touch]) {
        guard let finger = t.first(where: { $0.id == session.edgeFinger }) else { return }
        let step: Float = 0.05
        let dy = finger.y - session.edgeLastY
        guard abs(dy) >= step else { return }
        session.edgeLastY += dy > 0 ? step : -step
        if session.edgeIsLeft {
            DisplayControl.stepBrightness(up: dy > 0, at: Synth.cursor)
        } else {
            Synth.media(dy > 0 ? .soundUp : .soundDown)
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    // MARK: Dock Fidget

    /// Sliding sideways from the bottom edge takes over the pointer and runs it
    /// along the Dock (revealing an auto-hidden Dock), with a haptic tick per icon.
    private func updateDockFidget(_ touch: Touch, dx: Float) {
        if session.dockActive {
            DockController.shared.trackpadControl(x: touch.x)
            return
        }
        guard session.dockArmed else { return }
        if touch.y > 0.2 { session.dockArmed = false; return }
        if abs(dx) > 0.04, touch.y < 0.15 {
            session.dockArmed = false
            session.dockActive = DockController.shared.beginTrackpadControl()
        }
    }
}
