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
