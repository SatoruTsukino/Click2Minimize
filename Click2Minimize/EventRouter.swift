import Carbon.HIToolbox
import Cocoa
import os.log

private let log = Logger(subsystem: "com.idemfactor.Click2Minimize", category: "events")

/// Owns the single CGEvent tap and routes each event to the feature that
/// claims it. A handler either passes the event on or swallows it; swallowed
/// clicks that turn out not to be gestures are replayed.
final class EventRouter {
    static let shared = EventRouter()

    private var tap: CFMachPort?

    // MARK: Pause state (game mode / excluded apps), refreshed on app activation

    private(set) var isPaused = false
    private var frontmostExcluded = false
    var gesturesBlocked: Bool { isPaused || frontmostExcluded }

    func refreshPauseState() {
        let app = NSWorkspace.shared.frontmostApplication
        frontmostExcluded = app?.bundleIdentifier.map { Pref.excludedApps.strings.contains($0) } ?? false
        isPaused = Pref.pauseInGameMode.bool && (app.map(Self.isGame) ?? false)
    }

    private static func isGame(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL,
              let category = Bundle(url: url)?.infoDictionary?["LSApplicationCategoryType"] as? String else { return false }
        return category.contains("games")
    }

    // MARK: Tap lifecycle

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                    .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                    .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                                    .mouseMoved, .scrollWheel, .keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: { _, type, event, _ in EventRouter.shared.handle(type, event) },
                                          userInfo: nil) else {
            log.error("failed to create event tap: accessibility permission missing?")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        refreshPauseState()
        log.info("event tap installed")
        return true
    }

    // MARK: Per-button tracking

    private struct ButtonTrack {
        var down = false
        var start = CGPoint.zero
        var path: [CGPoint] = []
        var held: CGEvent?          // the mouse-down we swallowed, replayed if no gesture happens
        var consumed = false        // a gesture used this press: swallow the rest
        var dragging = false
        var menuDismissed = false
        var window: AXUIElement?
        var windowOrigin = CGPoint.zero
    }

    private var right = ButtonTrack()
    private var middle = ButtonTrack()
    private var middleSimulated = false   // current middle press comes from a 3-finger click
    private var leftDragWindow: AXUIElement?
    private var leftDragOrigin = CGPoint.zero
    private var leftDragStart = CGPoint.zero
    private var discardLeftUp = false
    private var discardOtherUp: Set<Int64> = []
    private var pendingDoubleRight: DispatchWorkItem?
    private var scrollAccumulator: CGFloat = 0
    private var lastScrollAction = Date.distantPast
    private var lastTilt = Date.distantPast

    private var passed: Unmanaged<CGEvent>? = nil

    // MARK: Dispatch

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker || isPaused { return pass }

        let consumed: Bool
        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            consumed = AppSwitcher.shared.handleKey(type, event)
        case .mouseMoved:
            DockController.shared.handleMouseMoved(event.location)
            consumed = false
        case .leftMouseDown: consumed = leftDown(event)
        case .leftMouseDragged: consumed = leftDragged(event)
        case .leftMouseUp: consumed = leftUp(event)
        case .rightMouseDown: consumed = rightDown(event)
        case .rightMouseDragged: consumed = rightDragged(event)
        case .rightMouseUp: consumed = rightUp(event)
        case .otherMouseDown, .otherMouseDragged, .otherMouseUp: consumed = other(type, event)
        case .scrollWheel: consumed = scroll(event)
        default: consumed = false
        }
        return consumed ? nil : pass
    }

    // MARK: Left button

    private func leftDown(_ e: CGEvent) -> Bool {
        let p = e.location
        if AppSwitcher.shared.isVisible { return AppSwitcher.shared.handleClick(at: p) }

        if right.down, Pref.rightLeftClickToMinimize.bool, !gesturesBlocked {
            if let w = AX.window(at: p) { WindowOps.withWindow(w) { WindowOps.minimize($0) } }
            markRightConsumed()
            discardLeftUp = true
            return true
        }

        if Trackpad.shared.touchCount == 3, !gesturesBlocked {
            if Pref.threeFingerDragToMove.bool, Trackpad.shared.threeFingerMoved, let w = AX.window(at: p),
               AX.frame(w) != nil, !AX.isFullscreen(w) {
                leftDragWindow = w
                leftDragOrigin = AX.frame(w)!.origin
                leftDragStart = p
                if Pref.threeFingerPinchToResize.bool { Trackpad.shared.pinchTarget = w }
                return true
            }
            if Pref.threeFingerClickToMiddle.bool, !Trackpad.shared.threeFingerMoved,
               let m = Synth.mouse(.otherMouseDown, at: p, button: .center, template: e) {
                middleSimulated = true
                if !other(.otherMouseDown, m) { Synth.post(m) }
                return true
            }
        }

        if DockController.shared.handleLeftDown(e) {
            discardLeftUp = true
            return true
        }

        if e.getIntegerValueField(.mouseEventClickState) == 2, !gesturesBlocked, handleScreenEdgeDoubleClick(p) {
            discardLeftUp = true
            return true
        }
        return false
    }

    /// Double-click on the camera housing / top-centre: toggle full screen.
    /// Double-click on the top or bottom screen edge: window overview / stash.
    private func handleScreenEdgeDoubleClick(_ p: CGPoint) -> Bool {
        guard let screen = ScreenGeometry.screen(containing: p) else { return false }
        let f = ScreenGeometry.toGlobal(screen.frame)
        let atTop = p.y - f.minY <= 3, atBottom = f.maxY - p.y <= 3
        if atTop, Pref.doubleClickNotchToFullscreen.bool, abs(p.x - f.midX) < 110 {
            AX.focusedWindow().map(WindowOps.toggleFullscreen)
            return true
        }
        guard Pref.overviewScreenEdge.bool, atTop || atBottom else { return false }
        if atTop { WindowOverview.shared.toggle() } else { Stash.toggle() }
        return true
    }

    private func leftDragged(_ e: CGEvent) -> Bool {
        if let w = leftDragWindow {
            let p = e.location
            AX.setPosition(w, CGPoint(x: leftDragOrigin.x + p.x - leftDragStart.x, y: leftDragOrigin.y + p.y - leftDragStart.y))
            return true
        }
        if middleSimulated, let m = Synth.mouse(.otherMouseDragged, at: e.location, button: .center) {
            if !other(.otherMouseDragged, m) { Synth.post(m) }
            return true
        }
        return discardLeftUp
    }

    private func leftUp(_ e: CGEvent) -> Bool {
        if leftDragWindow != nil {
            leftDragWindow = nil
            Trackpad.shared.pinchTarget = nil
            return true
        }
        if middleSimulated, let m = Synth.mouse(.otherMouseUp, at: e.location, button: .center, template: e) {
            middleSimulated = false
            if !other(.otherMouseUp, m) { Synth.post(m) }
            return true
        }
        if discardLeftUp {
            discardLeftUp = false
            return true
        }
        return false
    }

    // MARK: Right button

    private var rightDragFeatures: Bool {
        Pref.rightDragDownToMinimize.bool || Pref.rightDragUpToFullscreen.bool || Pref.rightDragToSnap.bool ||
            Pref.drawCircleClockwise.action.isSet || Pref.drawCircleCounterClockwise.action.isSet ||
            Pref.drawShakeHorizontal.action.isSet || Pref.drawShakeVertical.action.isSet
    }

    private var rightFeatures: Bool {
        rightDragFeatures || Pref.rightLeftClickToMinimize.bool || Pref.tripleRightClickToClose.bool ||
            Pref.doubleRightClickToFill.bool || Pref.doubleRightClickTitleToNextDisplay.bool ||
            Pref.twoFingerTopDoubleClickToNextDisplay.bool || Pref.switcherRightScroll.bool ||
            Pref.overviewRightSideButtons.bool || Pref.tiltLeft.action.isSet || Pref.tiltRight.action.isSet ||
            leftRightAction != .none
    }

    private var leftRightAction: WindowToggle { WindowToggle(rawValue: Pref.leftRightClickAction.string) ?? .none }

    /// A gesture took over the current right-button press.
    private func markRightConsumed() {
        right.consumed = true
        if right.held == nil && !right.menuDismissed {
            right.menuDismissed = true
            Synth.escape() // the press already opened a context menu
        }
    }

    private func rightDown(_ e: CGEvent) -> Bool {
        right = ButtonTrack()
        guard !gesturesBlocked, rightFeatures else { return false }
        let p = e.location
        right.down = true
        right.start = p
        right.path = [p]

        // Left button held, then right click.
        if NSEvent.pressedMouseButtons & 1 != 0, leftRightAction != .none {
            right.consumed = true
            right.held = e // nothing to replay: swallow
            if let w = AX.window(at: p) {
                if leftRightAction == .fullscreen {
                    WindowOps.toggleFullscreen(w)
                } else {
                    WindowOps.withWindow(w) { WindowOps.toggleFill($0) }
                }
            }
            return true
        }

        let clicks = e.getIntegerValueField(.mouseEventClickState)
        if clicks >= 2, handleMultiRightClick(clicks, at: p) {
            right.consumed = true
            right.held = e
            return true
        }

        if Pref.suppressContextMenus.bool && (rightDragFeatures || Pref.switcherRightScroll.bool) {
            right.held = e.copy()
            return true
        }
        return false
    }

    /// Double / triple right clicks. The first click already opened a context menu; dismiss it.
    private func handleMultiRightClick(_ clicks: Int64, at p: CGPoint) -> Bool {
        let triple = Pref.tripleRightClickToClose.bool
        if clicks >= 3, triple {
            pendingDoubleRight?.cancel()
            pendingDoubleRight = nil
            if let w = AX.window(at: p) { WindowOps.close(w) }
            return true
        }
        guard clicks == 2 else { return false }

        let twoFingerTop = Pref.twoFingerTopDoubleClickToNextDisplay.bool && Trackpad.shared.twoFingersAtTop
        let window = AX.window(at: p)
        let onTitle = window.flatMap(AX.frame).map { p.y - $0.minY < 32 } ?? false
        let action: ((AXUIElement) -> Void)?
        if twoFingerTop || (onTitle && Pref.doubleRightClickTitleToNextDisplay.bool) {
            action = WindowOps.moveToNextDisplay
        } else if Pref.doubleRightClickToFill.bool {
            action = WindowOps.toggleFill
        } else {
            action = nil
        }
        guard action != nil || triple else { return false }
        Synth.escape() // close the menu the first click opened
        guard let action, let w = window else { return true } // a triple can still follow
        let run = { _ = WindowOps.withWindow(w, action) }
        if triple {
            let work = DispatchWorkItem(block: { run() })
            pendingDoubleRight = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
        } else {
            run()
        }
        return true
    }

    private func rightDragged(_ e: CGEvent) -> Bool {
        guard right.down else { return false }
        if right.consumed { return right.held != nil }
        let p = e.location
        right.path.append(p)
        guard rightDragFeatures else { return right.held != nil }
        if !right.dragging, hypot(p.x - right.start.x, p.y - right.start.y) > 14 {
            right.dragging = true
            if right.held == nil && !right.menuDismissed {
                right.menuDismissed = true
                Synth.escape()
            }
            right.window = AX.window(at: right.start)
        }
        if right.dragging { updateSnapPreview() }
        return right.dragging || right.held != nil
    }

    private func zone(for d: Direction8) -> SnapZone? {
        switch d {
        case .down where Pref.rightDragDownToMinimize.bool, .up where Pref.rightDragUpToFullscreen.bool: return nil
        default: return Pref.rightDragToSnap.bool ? SnapZone.from(d) : nil
        }
    }

    private func updateSnapPreview() {
        guard Pref.rightDragToSnap.bool, let w = right.window, let d = GestureMath.lineDirection(right.path),
              let zone = zone(for: d), let target = WindowOps.snapTarget(for: w, zone: zone) else {
            SnapOverlay.shared.hide()
            return
        }
        SnapOverlay.shared.show(target)
    }

    private func rightUp(_ e: CGEvent) -> Bool {
        defer { right = ButtonTrack() }
        guard right.down else { return false }
        SnapOverlay.shared.hide()
        if AppSwitcher.shared.activeTrigger == .rightScroll {
            AppSwitcher.shared.commit()
            return right.held != nil
        }
        if right.consumed { return right.held != nil }

        if right.dragging, performRightDrag() { return right.held != nil }

        // Not a gesture: deliver the click we held back.
        if let held = right.held {
            Synth.replay(held)
            if let up = e.copy() { Synth.post(up) }
            return true
        }
        return false
    }

    private func performRightDrag() -> Bool {
        let start = right.start
        switch GestureMath.classify(right.path) {
        case .circle(let clockwise):
            let a = clockwise ? Pref.drawCircleClockwise.action : Pref.drawCircleCounterClockwise.action
            guard a.isSet else { return false }
            ActionRunner.perform(a, at: start)
        case .shakeHorizontal:
            guard Pref.drawShakeHorizontal.action.isSet else { return false }
            ActionRunner.perform(Pref.drawShakeHorizontal.action, at: start)
        case .shakeVertical:
            guard Pref.drawShakeVertical.action.isSet else { return false }
            ActionRunner.perform(Pref.drawShakeVertical.action, at: start)
        case .line(let d):
            guard let w = right.window else { return false }
            if d == .down, Pref.rightDragDownToMinimize.bool {
                WindowOps.withWindow(w) { WindowOps.minimize($0) }
            } else if d == .up, Pref.rightDragUpToFullscreen.bool {
                WindowOps.toggleFullscreen(w)
            } else if let zone = zone(for: d) {
                WindowOps.withWindow(w) { WindowOps.snap($0, to: zone) }
            } else {
                return false
            }
        case .none:
            return false
        }
        return true
    }

    // MARK: Middle and side buttons

    private var middleFeatures: Bool {
        Pref.middleClickToTerminate.bool || Pref.middleClickCloseButton.bool || Pref.middleClickDismissNotifications.bool ||
            Pref.middleDragToMove.bool || Pref.middleScrollToResize.bool
    }

    private func other(_ type: CGEventType, _ e: CGEvent) -> Bool {
        let button = e.getIntegerValueField(.mouseEventButtonNumber)
        if button == 2 { return middleButton(type, e) }
        guard button == 3 || button == 4 else { return false }
        if type == .otherMouseUp { return discardOtherUp.remove(button) != nil }
        guard type == .otherMouseDown else { return discardOtherUp.contains(button) }

        if right.down, Pref.overviewRightSideButtons.bool {
            markRightConsumed()
            discardOtherUp.insert(button)
            if button == 4 { WindowOverview.shared.toggle() } else { Stash.toggle() }
            return true
        }
        if Pref.universalNavigation.bool, !gesturesBlocked {
            discardOtherUp.insert(button)
            ActionRunner.navigate(back: button == 3)
            return true
        }
        return false
    }

    private func middleButton(_ type: CGEventType, _ e: CGEvent) -> Bool {
        let p = e.location
        switch type {
        case .otherMouseDown:
            middle = ButtonTrack()
            let overlays = AppSwitcher.shared.isVisible || WindowOverview.shared.isVisible
            guard middleFeatures || overlays else { return false }
            middle.down = true
            middle.start = p
            middle.held = e.copy()
            return true
        case .otherMouseDragged:
            guard middle.down else { return false }
            if Pref.middleDragToMove.bool, !gesturesBlocked {
                if middle.window == nil, hypot(p.x - middle.start.x, p.y - middle.start.y) > 4,
                   let w = AX.window(at: middle.start), !AX.isFullscreen(w), let f = AX.frame(w) {
                    middle.window = w
                    middle.windowOrigin = f.origin
                }
                if let w = middle.window {
                    middle.consumed = true
                    AX.setPosition(w, CGPoint(x: middle.windowOrigin.x + p.x - middle.start.x,
                                              y: middle.windowOrigin.y + p.y - middle.start.y))
                }
            }
            return true
        default:
            defer { middle = ButtonTrack() }
            guard middle.down else { return false }
            if middle.consumed || middleClick(at: middle.start) { return true }
            if let held = middle.held {
                Synth.replay(held)
                if let up = e.copy() { Synth.post(up) }
                return true
            }
            return false
        }
    }

    /// A plain middle click: the first feature that recognises the target wins.
    private func middleClick(at p: CGPoint) -> Bool {
        if WindowOverview.shared.isVisible { return WindowOverview.shared.closeHovered() }
        if AppSwitcher.shared.isVisible { return AppSwitcher.shared.terminateEntry(at: p) }
        if DockController.shared.handleMiddleClick(at: p) { return true }
        if gesturesBlocked { return false }
        if Pref.middleClickDismissNotifications.bool, ButtonFinder.dismissNotification(at: p) { return true }
        if Pref.middleClickCloseButton.bool, ButtonFinder.pressNearbyButton(at: p) { return true }
        return false
    }

    // MARK: Scroll wheel

    private func scroll(_ e: CGEvent) -> Bool {
        if Trackpad.shared.edgeSlideActive { return true }
        let dy = CGFloat(e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        let dx = CGFloat(e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))

        if AppSwitcher.shared.isVisible, AppSwitcher.shared.handleScroll(dy) { return true }

        if right.down {
            if Pref.switcherRightScroll.bool, dy != 0 {
                markRightConsumed()
                if AppSwitcher.shared.isVisible { _ = AppSwitcher.shared.handleScroll(dy) } else {
                    AppSwitcher.shared.show(trigger: .rightScroll)
                }
                return true
            }
            let tilt = dx < 0 ? Pref.tiltLeft.action : Pref.tiltRight.action
            if dx != 0, dy == 0, tilt.isSet {
                markRightConsumed()
                if Date().timeIntervalSince(lastTilt) > 0.4 {
                    lastTilt = Date()
                    ActionRunner.perform(tilt, at: right.start)
                }
                return true
            }
        }

        if middle.down, Pref.middleScrollToResize.bool, dy != 0, !gesturesBlocked {
            middle.consumed = true
            if let w = AX.window(at: middle.start) {
                WindowOps.withWindow(w) { WindowOps.scale($0, by: dy > 0 ? 1.04 : 0.96) }
            }
            return true
        }

        guard !gesturesBlocked else { return false }
        let flags = e.flags
        let mods = flags.intersection(KeyShortcut.relevantFlags)
        let momentum = e.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
        let continuous = e.getIntegerValueField(.scrollWheelEventIsContinuous) != 0

        // Physical finger / wheel direction (y-down), independent of natural scrolling.
        let inverted = NSEvent(cgEvent: e)?.isDirectionInvertedFromDevice ?? false
        let fingerX = inverted ? dx : -dx, fingerY = inverted ? dy : -dy
        let vertical = abs(fingerY) >= abs(fingerX)
        func arrow(_ positive: Bool) -> Int {
            vertical ? (positive ? kVK_DownArrow : kVK_UpArrow) : (positive ? kVK_RightArrow : kVK_LeftArrow)
        }

        if flags.contains(.maskSecondaryFn), mods.isEmpty, Pref.inPageScrolling.bool {
            if !momentum, Date().timeIntervalSince(lastScrollAction) > 0.5, max(abs(dx), abs(dy)) > 0 {
                lastScrollAction = Date()
                Synth.key(arrow((vertical ? fingerY : fingerX) > 0), flags: .maskCommand)
            }
            return true
        }

        if !mods.isEmpty, Pref.modifierArrowKeys.bool {
            guard !momentum else { return true }
            scrollAccumulator += vertical ? fingerY : fingerX
            let threshold: CGFloat = continuous ? 6 : 1
            while abs(scrollAccumulator) >= threshold {
                let positive = scrollAccumulator > 0
                scrollAccumulator -= positive ? threshold : -threshold
                Synth.key(arrow(positive), flags: mods)
            }
            return true
        }
        return false
    }
}
