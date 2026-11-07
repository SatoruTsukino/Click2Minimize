import ApplicationServices
import Cocoa
import os.log

private let log = Logger(subsystem: "com.idemfactor.Click2Minimize", category: "windows")

/// Window operations shared by Dock clicks, mouse gestures, trackpad gestures and actions.
enum WindowOps {
    /// Frames to restore when a "fill screen" toggle is undone, keyed by window id.
    private static var framesBeforeFill: [CGWindowID: CGRect] = [:]
    /// Windows minimized by Click2Minimize, most recent last, per process.
    private(set) static var minimizedByPID: [pid_t: [AXUIElement]] = [:]

    /// Runs a window gesture, honouring the "exit full screen first" preference.
    /// Returns false when the window is full-screen and gestures must skip it.
    @discardableResult
    static func withWindow(_ w: AXUIElement, allowFullscreen: Bool = false, _ body: @escaping (AXUIElement) -> Void) -> Bool {
        if !allowFullscreen && AX.isFullscreen(w) {
            guard Pref.exitFullscreenBeforeGestures.bool else { return false }
            AX.set(w, "AXFullScreen", kCFBooleanFalse)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { body(w) }
            return true
        }
        body(w)
        return true
    }

    static func minimize(_ w: AXUIElement) {
        let pid = AX.pid(w)
        let commit = {
            if AX.set(w, kAXMinimizedAttribute, kCFBooleanTrue) {
                minimizedByPID[pid, default: []].append(w)
                if minimizedByPID[pid]!.count > 30 { minimizedByPID[pid]!.removeFirst() }
            }
        }
        // Keep a picture of the window for the overview: minimized windows can't be captured later.
        if WindowOverview.wantsSnapshots, let id = AX.windowID(w) {
            SnapshotCache.shared.capture([id]) { commit() }
        } else {
            commit()
        }
    }

    /// Minimizes every visible window of an app. Returns true if any was minimized.
    @discardableResult
    static func minimizeAll(of app: NSRunningApplication) -> Bool {
        let visible = AX.windows(app.processIdentifier).filter { !AX.isMinimized($0) && AX.role($0) == kAXWindowRole }
        visible.forEach(minimize)
        return !visible.isEmpty
    }

    /// Restores the most recently minimized window of an app, if any.
    @discardableResult
    static func restoreLastMinimized(of app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        var stack = minimizedByPID[pid] ?? []
        while let w = stack.popLast() {
            if AX.isMinimized(w) {
                minimizedByPID[pid] = stack
                AX.set(w, kAXMinimizedAttribute, kCFBooleanFalse)
                return true
            }
        }
        minimizedByPID[pid] = []
        if let w = AX.windows(pid).last(where: AX.isMinimized) {
            AX.set(w, kAXMinimizedAttribute, kCFBooleanFalse)
            return true
        }
        return false
    }

    static func close(_ w: AXUIElement) {
        if let button: AXUIElement = AX.get(w, kAXCloseButtonAttribute) {
            AX.perform(button, kAXPressAction)
        }
    }

    static func toggleFullscreen(_ w: AXUIElement) {
        AX.set(w, "AXFullScreen", AX.isFullscreen(w) ? kCFBooleanFalse : kCFBooleanTrue)
    }

    /// Fills the screen's visible area, or restores the previous frame if already filled.
    static func toggleFill(_ w: AXUIElement) {
        guard let frame = AX.frame(w), let screen = ScreenGeometry.screen(for: frame) else { return }
        let target = ScreenGeometry.visibleFrame(screen)
        let id = AX.windowID(w)
        if GestureMath.roughlyEqual(frame, target), let id, let original = framesBeforeFill.removeValue(forKey: id) {
            animate(w, to: original)
            return
        }
        if let id { framesBeforeFill[id] = frame }
        animate(w, to: target)
    }

    static func snap(_ w: AXUIElement, to zone: SnapZone) {
        guard let frame = AX.frame(w), let screen = ScreenGeometry.screen(for: frame) else { return }
        if let id = AX.windowID(w), framesBeforeFill[id] == nil { framesBeforeFill[id] = frame }
        animate(w, to: zone.frame(in: ScreenGeometry.visibleFrame(screen)))
    }

    static func snapTarget(for w: AXUIElement, zone: SnapZone) -> CGRect? {
        guard let frame = AX.frame(w), let screen = ScreenGeometry.screen(for: frame) else { return nil }
        return zone.frame(in: ScreenGeometry.visibleFrame(screen))
    }

    /// Moves a window to the next display, keeping its relative position.
    static func moveToNextDisplay(_ w: AXUIElement) {
        let screens = NSScreen.screens
        guard screens.count > 1, let frame = AX.frame(w),
              let current = ScreenGeometry.screen(for: frame),
              let i = screens.firstIndex(of: current) else { return }
        let next = screens[(i + 1) % screens.count]
        let target = GestureMath.relocate(frame, from: ScreenGeometry.visibleFrame(current),
                                          to: ScreenGeometry.visibleFrame(next))
        animate(w, to: target)
    }

    // MARK: Animation

    private static var animations: [CGWindowID: Timer] = [:]

    /// Moves / resizes a window with a short ease-out, unless animations are
    /// off or the system asks for reduced motion.
    static func animate(_ w: AXUIElement, to target: CGRect) {
        guard Pref.animateWindows.bool, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let from = AX.frame(w), let id = AX.windowID(w) else {
            AX.setFrame(w, target)
            return
        }
        animations[id]?.invalidate()
        let start = Date(), duration = 0.18
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { t in
            let progress = min(1, Date().timeIntervalSince(start) / duration)
            guard progress < 1 else {
                t.invalidate()
                animations[id] = nil
                AX.setFrame(w, target)
                return
            }
            let e = CGFloat(1 - pow(1 - progress, 3))
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { (a + (b - a) * e).rounded() }
            AX.setPosition(w, CGPoint(x: mix(from.minX, target.minX), y: mix(from.minY, target.minY)))
            AX.setSize(w, CGSize(width: mix(from.width, target.width), height: mix(from.height, target.height)))
        }
        RunLoop.main.add(timer, forMode: .common)
        animations[id] = timer
    }

    static func scale(_ w: AXUIElement, by factor: CGFloat) {
        guard let frame = AX.frame(w) else { return }
        AX.setFrame(w, GestureMath.scaled(frame, by: factor))
    }

    /// Brings a specific window forward, unhiding / unminimizing as needed.
    static func focus(_ w: AXUIElement, of app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        if AX.isMinimized(w) { AX.set(w, kAXMinimizedAttribute, kCFBooleanFalse) }
        AX.perform(w, kAXRaiseAction)
        AX.set(w, kAXMainAttribute, kCFBooleanTrue)
        app.activate()
    }
}
