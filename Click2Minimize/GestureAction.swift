import Carbon.HIToolbox
import Cocoa

/// What a configurable gesture does.
enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case none
    case minimizeWindow, closeWindow, toggleFullscreen, toggleFill, moveToNextDisplay
    case hideApp, quitApp
    case missionControl, appExpose, showDesktop, launchpad
    case windowOverview, stash
    case previousSpace, nextSpace
    case back, forward
    case keyShortcut, runShortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Do nothing"
        case .minimizeWindow: return "Minimize window"
        case .closeWindow: return "Close window"
        case .toggleFullscreen: return "Toggle full screen"
        case .toggleFill: return "Toggle fill screen"
        case .moveToNextDisplay: return "Move window to next display"
        case .hideApp: return "Hide app"
        case .quitApp: return "Quit app"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Show Desktop"
        case .launchpad: return "Launchpad / Apps"
        case .windowOverview: return "Window overview"
        case .stash: return "Stash / restore windows"
        case .previousSpace: return "Previous desktop"
        case .nextSpace: return "Next desktop"
        case .back: return "Navigate back"
        case .forward: return "Navigate forward"
        case .keyShortcut: return "Keyboard shortcut…"
        case .runShortcut: return "Run Shortcuts.app shortcut…"
        }
    }
}

struct GestureAction: Codable, Equatable {
    var kind: ActionKind = .none
    var shortcut: KeyShortcut?
    var shortcutName: String = ""

    var isSet: Bool {
        switch kind {
        case .none: return false
        case .keyShortcut: return shortcut != nil
        case .runShortcut: return !shortcutName.isEmpty
        default: return true
        }
    }
}

/// Per-app replacement for universal back / forward.
struct NavigationOverride: Codable, Equatable {
    var back: KeyShortcut?
    var forward: KeyShortcut?
}

enum ActionRunner {
    /// Apps that use the side buttons and sideways swipes themselves (CAD and
    /// design tools), so universal navigation leaves them alone.
    static let navigationExcludedApps: Set<String> = [
        "org.blenderfoundation.blender", "com.figma.Desktop", "com.autodesk.mas.fusion360",
        "com.autodesk.fusion360", "com.autodesk.AutoCAD", "com.sketchup.SketchUp",
    ]

    static var universalNavigationApplies: Bool {
        guard Pref.universalNavigation.bool else { return false }
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return true }
        return !navigationExcludedApps.contains(id)
    }

    /// Performs an action. `point` targets the window under it; otherwise the focused window.
    static func perform(_ action: GestureAction, at point: CGPoint? = nil) {
        let window = { point.flatMap(AX.window(at:)) ?? AX.focusedWindow() }
        let app = { () -> NSRunningApplication? in
            if let w = window() { return NSRunningApplication(processIdentifier: AX.pid(w)) }
            return NSWorkspace.shared.frontmostApplication
        }
        switch action.kind {
        case .none: break
        case .minimizeWindow: if let w = window() { WindowOps.withWindow(w, WindowOps.minimize) }
        case .closeWindow: if let w = window() { WindowOps.withWindow(w, WindowOps.close) }
        case .toggleFullscreen: if let w = window() { WindowOps.toggleFullscreen(w) }
        case .toggleFill: if let w = window() { WindowOps.withWindow(w, WindowOps.toggleFill) }
        case .moveToNextDisplay: if let w = window() { WindowOps.withWindow(w, WindowOps.moveToNextDisplay) }
        case .hideApp: app()?.hide()
        case .quitApp: app()?.terminate()
        case .missionControl: dockFeature("com.apple.expose.awake", fallbackApp: "Mission Control")
        case .appExpose: dockFeature("com.apple.expose.front.awake", fallbackApp: nil)
        case .showDesktop: dockFeature("com.apple.showdesktop.awake", fallbackApp: nil)
        case .launchpad: dockFeature("com.apple.launchpad.toggle", fallbackApp: "Launchpad")
        case .windowOverview: WindowOverview.shared.toggle()
        case .stash: Stash.toggle()
        case .previousSpace: Synth.key(kVK_LeftArrow, flags: .maskControl)
        case .nextSpace: Synth.key(kVK_RightArrow, flags: .maskControl)
        case .back: navigate(back: true)
        case .forward: navigate(back: false)
        case .keyShortcut: action.shortcut.map(Synth.shortcut)
        case .runShortcut: runShortcut(named: action.shortcutName)
        }
    }

    /// Back / forward with per-app overrides; defaults to ⌘[ and ⌘].
    static func navigate(back: Bool) {
        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           let o = Pref.navigationOverrides.decoded([String: NavigationOverride].self)?[id],
           let s = back ? o.back : o.forward {
            Synth.shortcut(s)
            return
        }
        Synth.key(back ? kVK_ANSI_LeftBracket : kVK_ANSI_RightBracket, flags: .maskCommand)
    }

    private static func dockFeature(_ notification: String, fallbackApp: String?) {
        if SystemPrivate.coreDock(notification) { return }
        if let name = fallbackApp {
            let url = URL(fileURLWithPath: "/System/Applications/\(name).app")
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    private static func runShortcut(named name: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", name]
        try? p.run()
    }

    /// Terminates an app, optionally without waiting for it to save.
    static func terminate(_ app: NSRunningApplication) {
        if Pref.forceKillOnTerminate.bool { app.forceTerminate() } else { app.terminate() }
    }
}
