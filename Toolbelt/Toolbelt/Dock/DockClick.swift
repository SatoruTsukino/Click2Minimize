import AppKit
import ApplicationServices

enum DockDecision: Equatable { case passThrough, minimize, hide }

/// Clicking the Dock icon of the app that is already frontmost minimizes its windows or hides it.
/// Events arrive from the shared `InputTap` (ADR-008).
/// Dock items are hit-tested live through Accessibility at the pointer: correct with magnification,
/// auto-hide and multiple displays, and no AppleScript / Automation permission.
@MainActor
final class DockClick {
    static let shared = DockClick()

    /// Pure decision table, unit tested.
    nonisolated static func decide(isApp: Bool, isActive: Bool, isHidden: Bool, isFullscreen: Bool,
                                   visibleWindows: Int, clickCount: Int, mode: DockMode) -> DockDecision {
        guard isApp, isActive, !isHidden, !isFullscreen, clickCount == 1, visibleWindows > 0 else { return .passThrough }
        return mode == .minimize ? .minimize : .hide
    }

    /// Finder's Dock icon opens the chosen app instead (DOCK-06). Pure, unit tested.
    nonisolated static func finderAlternate(itemURL: URL?, isApp: Bool, enabled: Bool, path: String) -> URL? {
        guard enabled, isApp, !path.isEmpty, itemURL?.lastPathComponent == "Finder.app" else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Left mouse-down from `InputTap`. Returns true when the click was handled and must not reach the Dock.
    func handleDown(_ event: CGEvent) -> Bool {
        let p = event.location
        guard Self.isNearDock(p), let item = Self.dockItem(at: p) else { return false }
        let prefs = Prefs.shared
        if let url = Self.finderAlternate(itemURL: item.url, isApp: item.isApp, enabled: prefs.finderOpensApp, path: prefs.finderAppPath) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return true
        }
        guard prefs.dockClick, item.isApp, let app = item.runningApp, app.isActive else { return false }
        let windows = AX.visibleWindows(app.processIdentifier)
        let decision = Self.decide(
            isApp: true, isActive: true, isHidden: app.isHidden,
            isFullscreen: AX.windows(app.processIdentifier).contains(where: AX.isFullscreen),
            visibleWindows: windows.count,
            clickCount: Int(event.getIntegerValueField(.mouseEventClickState)),
            mode: Prefs.shared.dockMode)
        switch decision {
        case .passThrough:
            return false
        case .hide:
            app.hide()
        case .minimize:
            for w in windows { AX.set(w, kAXMinimizedAttribute, kCFBooleanTrue) }
        }
        return true
    }

    /// Middle-click on an app's Dock icon quits it (DOCK-07). Never Finder.
    func quitApp(at p: CGPoint) -> Bool {
        guard Self.isNearDock(p), let item = Self.dockItem(at: p), item.isApp, let app = item.runningApp,
              app.bundleIdentifier != "com.apple.finder" else { return false }
        app.terminate()
        return true
    }

    // MARK: Hit testing

    struct Item {
        let title: String
        let url: URL?
        let subrole: String
        var isApp: Bool { subrole == "AXApplicationDockItem" }

        var runningApp: NSRunningApplication? {
            let apps = NSWorkspace.shared.runningApplications
            if let url = url?.standardizedFileURL,
               let app = apps.first(where: { $0.bundleURL?.standardizedFileURL == url }) { return app }
            return apps.first { $0.localizedName == title }
        }
    }

    private static let dockDefaults = UserDefaults(suiteName: "com.apple.dock")

    private static var dockPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    }

    static func dockItem(at p: CGPoint) -> Item? {
        guard let dock = dockPID, var el = AX.element(at: p), AX.pid(el) == dock else { return nil }
        for _ in 0..<3 {
            let sub = AX.subrole(el)
            if sub.hasSuffix("DockItem") {
                return Item(title: AX.get(el, kAXTitleAttribute) ?? "", url: AX.get(el, kAXURLAttribute), subrole: sub)
            }
            guard let parent = AX.parent(el) else { break }
            el = parent
        }
        return nil
    }

    /// Cheap pre-filter so ordinary clicks never pay for an AX query: is `p` (top-left global
    /// coordinates) within the Dock band of the display it is on?
    static func isNearDock(_ p: CGPoint) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        let screens = NSScreen.screens.map { s -> CGRect in
            let f = s.frame
            return CGRect(x: f.minX, y: primary.frame.maxY - f.maxY, width: f.width, height: f.height)
        }
        guard let f = screens.first(where: { $0.contains(p) }) else { return false }
        let orientation = dockDefaults?.string(forKey: "orientation") ?? "bottom"
        return nearDock(p, screen: f, orientation: orientation, band: dockBand)
    }

    /// Dock thickness plus margin, from the Dock's own settings, so ordinary clicks near the bottom
    /// of a window don't cost an AX query.
    static var dockBand: CGFloat {
        band(tileSize: dockDefaults?.object(forKey: "tilesize") as? Double,
             magnifies: dockDefaults?.bool(forKey: "magnification") ?? false,
             largeSize: dockDefaults?.object(forKey: "largesize") as? Double)
    }

    nonisolated static func band(tileSize: Double?, magnifies: Bool, largeSize: Double?) -> CGFloat {
        let tile = tileSize ?? 48
        let icon = magnifies ? max(tile, largeSize ?? 128) : tile
        return CGFloat(icon) + 24
    }

    nonisolated static func nearDock(_ p: CGPoint, screen f: CGRect, orientation: String, band: CGFloat = 220) -> Bool {
        switch orientation {
        case "left": p.x - f.minX < band
        case "right": f.maxX - p.x < band
        default: f.maxY - p.y < band
        }
    }
}
