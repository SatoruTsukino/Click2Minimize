import ApplicationServices
import Cocoa
import os.log

private let log = Logger(subsystem: "com.idemfactor.Click2Minimize", category: "dock")

/// Dock behaviours: click-to-minimize (the free core), click modes, Finder
/// replacement, hover Exposé, Dock lock and haptic fidget.
///
/// Dock items are hit-tested live through Accessibility at the pointer, which
/// stays correct with magnification, auto-hide and multiple displays, and
/// needs no Automation (AppleScript) permission.
final class DockController {
    static let shared = DockController()

    struct Item {
        let element: AXUIElement
        let title: String
        let url: URL?
        let subrole: String

        var isApplication: Bool { subrole == "AXApplicationDockItem" }

        var runningApp: NSRunningApplication? {
            guard isApplication else { return nil }
            let apps = NSWorkspace.shared.runningApplications
            if let url = url?.standardizedFileURL,
               let app = apps.first(where: { $0.bundleURL?.standardizedFileURL == url }) {
                return app
            }
            return apps.first { $0.localizedName == title }
        }
    }

    private var dockPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    }

    // MARK: Hit testing

    /// The Dock edge of the display under `p`, widened to cover magnified icons.
    private func isNearDock(_ p: CGPoint) -> Bool {
        guard let screen = ScreenGeometry.screen(containing: p) else { return false }
        let f = ScreenGeometry.toGlobal(screen.frame)
        let band: CGFloat = 220
        switch Self.orientation {
        case "left": return p.x - f.minX < band
        case "right": return f.maxX - p.x < band
        default: return f.maxY - p.y < band
        }
    }

    func item(at p: CGPoint) -> Item? {
        guard isNearDock(p), let dock = dockPID, var el = AX.element(at: p), AX.pid(el) == dock else { return nil }
        for _ in 0..<3 {
            let sub = AX.subrole(el)
            if sub.hasSuffix("DockItem") {
                return Item(element: el, title: AX.get(el, kAXTitleAttribute) ?? "",
                            url: AX.get(el, kAXURLAttribute), subrole: sub)
            }
            guard let parent = AX.parent(el) else { break }
            el = parent
        }
        return nil
    }

    // MARK: Clicks

    /// Left mouse-down. Returns true when the click was handled and must be swallowed.
    func handleLeftDown(_ event: CGEvent) -> Bool {
        let p = event.location
        guard let item = item(at: p) else { return false }
        let clicks = event.getIntegerValueField(.mouseEventClickState)

        if item.isApplication, Pref.finderAlternateEnabled.bool,
           item.url?.lastPathComponent == "Finder.app", !Pref.finderAlternatePath.string.isEmpty {
            let url = URL(fileURLWithPath: Pref.finderAlternatePath.string)
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return true
        }

        guard let app = item.runningApp else { return false }

        if clicks == 2, Pref.doubleClickToHideOthers.bool {
            app.unhide()
            app.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { NSWorkspace.shared.hideOtherApplications() }
            return true
        }

        guard clicks == 1, Pref.clickToMinimize.bool, app.isActive, !app.isHidden,
              !Self.isFullscreen(app) else { return false }

        let action = DockClickAction(rawValue: Pref.dockClickAction.string) ?? .minimizeAll
        switch action {
        case .hideApp:
            if Self.isStageManagerOn {
                // Hiding fights Stage Manager; fall back to minimizing.
                Pref.dockClickAction.set(DockClickAction.minimizeAll.rawValue)
                return minimizeAll(app)
            }
            app.hide()
            return true
        case .minimizeAll:
            return minimizeAll(app)
        case .minimizeFront:
            guard let w: AXUIElement = AX.get(AX.application(app.processIdentifier), kAXFocusedWindowAttribute),
                  !AX.isMinimized(w) else { return false }
            WindowOps.minimize(w)
            if visibleWindows(app).count <= 1 { concedeFocus(from: app) }
            return true
        case .cycleWindows:
            let visible = visibleWindows(app)
            if visible.count > 1, let back = visible.last {
                AX.perform(back, kAXRaiseAction)
                AX.set(back, kAXMainAttribute, kCFBooleanTrue)
                return true
            }
            return minimizeAll(app)
        }
    }

    private func visibleWindows(_ app: NSRunningApplication) -> [AXUIElement] {
        AX.windows(app.processIdentifier).filter { AX.role($0) == kAXWindowRole && !AX.isMinimized($0) }
    }

    private func minimizeAll(_ app: NSRunningApplication) -> Bool {
        guard WindowOps.minimizeAll(of: app) else { return false }
        concedeFocus(from: app)
        log.debug("minimized windows for \(app.localizedName ?? "?", privacy: .public)")
        return true
    }

    /// After the last window goes away, hand focus to the previously used app so
    /// the next Dock click on this one restores it instead of doing nothing.
    private func concedeFocus(from app: NSRunningApplication) {
        guard Pref.concedeFocusOnMinimize.bool else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            AppSwitcher.shared.previousApp(excluding: app)?.activate()
        }
    }

    /// Middle click on a Dock icon terminates the app.
    func handleMiddleClick(at p: CGPoint) -> Bool {
        guard Pref.middleClickToTerminate.bool, let app = item(at: p)?.runningApp,
              app.bundleIdentifier != "com.apple.finder" else { return false }
        ActionRunner.terminate(app)
        return true
    }

    // MARK: Mission Control, App Exposé and Stage Manager

    /// Middle-clicking a window thumbnail in Mission Control / App Exposé closes
    /// that window. The thumbnails belong to the Dock process and carry the
    /// window's title, which is matched against the apps' real windows.
    func closeMissionControlWindow(at p: CGPoint) -> Bool {
        guard let dock = dockPID, let el = AX.element(at: p), AX.pid(el) == dock,
              !AX.subrole(el).hasSuffix("DockItem") else { return false }
        let title = (AX.get(el, kAXTitleAttribute) as String?).flatMap { $0.isEmpty ? nil : $0 }
            ?? AX.get(el, kAXDescriptionAttribute) ?? ""
        guard !title.isEmpty else { return false }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let w = AX.windows(app.processIdentifier).first(where: { AX.title($0) == title }) {
                WindowOps.close(w)
                return true
            }
        }
        return false
    }

    /// Middle-clicking an app in the Stage Manager strip quits it.
    func terminateStageManagerApp(at p: CGPoint) -> Bool {
        guard Self.isStageManagerOn, var el = AX.element(at: p),
              NSRunningApplication(processIdentifier: AX.pid(el))?.bundleIdentifier == "com.apple.WindowManager" else { return false }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for _ in 0..<6 {
            let label = [AX.get(el, kAXTitleAttribute) as String?, AX.get(el, kAXDescriptionAttribute) as String?]
                .compactMap { $0 }.joined(separator: " ")
            if !label.isEmpty, let app = apps.first(where: { $0.localizedName.map(label.contains) ?? false }) {
                ActionRunner.terminate(app)
                return true
            }
            guard let parent = AX.parent(el) else { break }
            el = parent
        }
        return false
    }

    // MARK: Dock Fidget (trackpad control)

    /// Frame of the Dock's icon list, or nil while it is hidden off-screen.
    func iconListFrame() -> CGRect? {
        guard let dock = dockPID,
              let list = AX.children(AX.application(dock)).first(where: { AX.role($0) == kAXListRole }),
              let frame = AX.frame(list), frame.width > 0 else { return nil }
        let onScreen = NSScreen.screens.contains { ScreenGeometry.toGlobal($0.frame).insetBy(dx: 1, dy: 1).intersects(frame) }
        return onScreen ? frame : nil
    }

    private var controlFrame: CGRect?

    /// Detaches the pointer from the trackpad and parks it on the Dock edge,
    /// which also reveals an auto-hidden Dock.
    func beginTrackpadControl() -> Bool {
        guard let main = NSScreen.screens.first else { return false }
        let f = ScreenGeometry.toGlobal(main.frame)
        let cursor = Synth.cursor
        let edge: CGPoint
        switch Self.orientation {
        case "left": edge = CGPoint(x: f.minX, y: cursor.y)
        case "right": edge = CGPoint(x: f.maxX - 1, y: cursor.y)
        default: edge = CGPoint(x: f.midX, y: f.maxY - 1)
        }
        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(edge)
        controlFrame = nil
        return true
    }

    /// Maps the finger's horizontal position across the Dock's icons.
    func trackpadControl(x: Float) {
        if controlFrame == nil { controlFrame = iconListFrame() }
        guard let f = controlFrame else { return }
        let t = CGFloat(max(0, min(1, (x - 0.1) / 0.8)))
        let vertical = Self.orientation == "left" || Self.orientation == "right"
        let p = vertical ? CGPoint(x: f.midX, y: f.minY + t * f.height) : CGPoint(x: f.minX + t * f.width, y: f.midY)
        CGWarpMouseCursorPosition(p)
        handleMouseMoved(p)
    }

    func endTrackpadControl() {
        controlFrame = nil
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: Pointer movement

    private var hoveredTitle: String?
    private var hoverWork: DispatchWorkItem?
    private var lastMoveCheck = Date.distantPast

    func handleMouseMoved(_ p: CGPoint) {
        if Pref.lockDockToMainScreen.bool { keepDockOnMainScreen(p) }
        guard Pref.hoverToExpose.bool || Pref.dockFidget.bool else { return }
        guard Date().timeIntervalSince(lastMoveCheck) > 0.05 else { return }
        lastMoveCheck = Date()

        let item = isNearDock(p) ? self.item(at: p) : nil
        guard item?.title != hoveredTitle else { return }
        hoveredTitle = item?.title
        hoverWork?.cancel()
        guard let item else { return }

        if Pref.dockFidget.bool {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if Pref.hoverToExpose.bool, item.runningApp != nil {
            let work = DispatchWorkItem { [weak self] in self?.expose(item, at: p) }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
        }
    }

    private func expose(_ item: Item, at p: CGPoint) {
        guard NSEvent.pressedMouseButtons == 0, self.item(at: Synth.cursor)?.title == item.title,
              let app = item.runningApp else { return }
        if let action = AX.actions(item.element).first(where: { $0.localizedCaseInsensitiveContains("expose") }) {
            AX.perform(item.element, action)
            return
        }
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            SystemPrivate.coreDock("com.apple.expose.front.awake")
        }
    }

    /// The Dock jumps to a display when the pointer presses against that
    /// display's Dock edge. Keep the pointer one point away from that edge on
    /// secondary displays, unless another display continues past it.
    private func keepDockOnMainScreen(_ p: CGPoint) {
        guard NSScreen.screens.count > 1, let main = NSScreen.screens.first,
              let screen = ScreenGeometry.screen(containing: p), screen != main else { return }
        let f = ScreenGeometry.toGlobal(screen.frame)
        var target = p
        switch Self.orientation {
        case "left": if p.x <= f.minX + 1 { target.x = f.minX + 2 }
        case "right": if p.x >= f.maxX - 2 { target.x = f.maxX - 3 }
        default: if p.y >= f.maxY - 2 { target.y = f.maxY - 3 }
        }
        guard target != p else { return }
        let beyond = CGPoint(x: p.x + (target.x - p.x) * -3, y: p.y + (target.y - p.y) * -3)
        if ScreenGeometry.screen(containing: beyond) != nil { return }
        CGWarpMouseCursorPosition(target)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: System state

    private static var dockDefaults: UserDefaults? { UserDefaults(suiteName: "com.apple.dock") }

    static var orientation: String { dockDefaults?.string(forKey: "orientation") ?? "bottom" }

    static var isStageManagerOn: Bool {
        UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
    }

    static var minimizesIntoAppIcon: Bool { dockDefaults?.bool(forKey: "minimize-to-application") ?? false }

    static var autohidesInstantly: Bool {
        guard let d = dockDefaults, d.object(forKey: "autohide-delay") != nil else { return false }
        return d.double(forKey: "autohide-delay") == 0
    }

    static func setMinimizeIntoAppIcon(_ on: Bool) {
        dockDefaults?.set(on, forKey: "minimize-to-application")
        restartDock()
    }

    /// Removes the Dock's reveal delay (and turns auto-hide on), or restores the defaults.
    static func setInstantAutohide(_ on: Bool) {
        if on {
            dockDefaults?.set(true, forKey: "autohide")
            dockDefaults?.set(0.0, forKey: "autohide-delay")
            dockDefaults?.set(0.4, forKey: "autohide-time-modifier")
        } else {
            dockDefaults?.removeObject(forKey: "autohide-delay")
            dockDefaults?.removeObject(forKey: "autohide-time-modifier")
        }
        restartDock()
    }

    static func restartDock() {
        dockDefaults?.synchronize()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Dock"]
        try? p.run()
    }

    /// True if the app has a full-screen window: clicking its icon then should switch to it, not minimize.
    static func isFullscreen(_ app: NSRunningApplication) -> Bool {
        AX.windows(app.processIdentifier).contains(where: AX.isFullscreen)
    }
}
