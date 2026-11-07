import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, dock, windows, switcher, gestures, universal, advanced
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .dock: return "Dock"
        case .windows: return "Window Controls"
        case .switcher: return "App Switcher & Overview"
        case .gestures: return "Shortcut Gestures"
        case .universal: return "Universal"
        case .advanced: return "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .dock: return "dock.rectangle"
        case .windows: return "macwindow.on.rectangle"
        case .switcher: return "rectangle.stack"
        case .gestures: return "hand.draw"
        case .universal: return "globe"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

struct SettingsView: View {
    @State private var section: SettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { s in
                Label(s.title, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            Group {
                switch section ?? .general {
                case .general: GeneralPane()
                case .dock: DockPane()
                case .windows: WindowsPane()
                case .switcher: SwitcherPane()
                case .gestures: GesturesPane()
                case .universal: UniversalPane()
                case .advanced: AdvancedPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((section ?? .general).title)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

// MARK: - Building blocks

/// A preference toggle with an optional explanation underneath.
struct PrefToggle: View {
    @AppStorage private var isOn: Bool
    let title: String
    let caption: String?

    init(_ pref: Pref, _ title: String, _ caption: String? = nil) {
        _isOn = AppStorage(wrappedValue: pref.defaultValue as? Bool ?? false, pref.rawValue)
        self.title = title
        self.caption = caption
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
            if let caption { Text(caption) }
        }
    }
}

/// Records a key combination. Escape cancels, Delete clears.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(recording ? "Press shortcut…" : (shortcut?.display ?? "Record Shortcut")) {
                recording ? stop() : start()
            }
            .frame(minWidth: 120)
            if shortcut != nil && !recording {
                Button { shortcut = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            switch Int(e.keyCode) {
            case 53: stop()                                   // Escape
            case 51, 117: shortcut = nil; stop()              // Delete
            default:
                let flags = CGEventFlags(rawValue: UInt64(e.modifierFlags.rawValue))
                let candidate = KeyShortcut(keyCode: e.keyCode, flags: flags)
                let isFunctionKey = (96...122).contains(Int(e.keyCode))
                guard candidate.modifiers != 0 || isFunctionKey else { NSSound.beep(); return nil }
                shortcut = candidate
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Picks what a gesture does.
struct ActionPicker: View {
    @CodablePref private var action: GestureAction
    let title: String

    init(_ pref: Pref, _ title: String) {
        _action = CodablePref(pref, default: GestureAction())
        self.title = title
    }

    var body: some View {
        Picker(title, selection: Binding(get: { action.kind }, set: { action.kind = $0 })) {
            ForEach(ActionKind.allCases) { Text($0.title).tag($0) }
        }
        if action.kind == .keyShortcut {
            LabeledContent("Shortcut") { ShortcutRecorder(shortcut: Binding(get: { action.shortcut }, set: { action.shortcut = $0 })) }
        }
        if action.kind == .runShortcut {
            TextField("Shortcut name", text: Binding(get: { action.shortcutName }, set: { action.shortcutName = $0 }),
                      prompt: Text("Name in Shortcuts.app"))
        }
    }
}

enum AppChooser {
    /// Lets the user pick an application bundle.
    static func choose(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func bundleID(_ url: URL) -> String? { Bundle(url: url)?.bundleIdentifier }

    static func name(for id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for id: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

struct AppLabel: View {
    let bundleID: String
    var body: some View {
        HStack(spacing: 8) {
            if let icon = AppChooser.icon(for: bundleID) { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
            Text(AppChooser.name(for: bundleID))
        }
    }
}

private struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Label(text, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
    }
}

// MARK: - General

struct GeneralPane: View {
    @AppStorage(Pref.showInMenuBar.rawValue) private var showInMenuBar = true
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var trusted = AX.isTrusted()
    @State private var screenRecording = SnapshotCache.hasPermission
    @State private var message: String?
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent("Accessibility") {
                    if trusted { Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } else {
                        Button("Grant Access…") { AX.promptForTrust(); Permissions.openAccessibilitySettings() }
                    }
                }
                LabeledContent("Screen Recording (optional)") {
                    if screenRecording { Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } else {
                        Button("Grant Access…") { Permissions.requestScreenRecording() }
                    }
                }
                Text("Screen Recording only adds window thumbnails to the window overview. Everything else works without it.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Permissions") }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        if LoginItem.set(on) { Pref.launchAtLogin.set(on) } else { launchAtLogin = LoginItem.isEnabled }
                    }
                Toggle(isOn: $showInMenuBar) {
                    Text("Show in menu bar")
                    Text("When hidden, open Settings by launching Click2Minimize again.")
                }
                PrefToggle(.pauseInGameMode, "Pause in Game Mode", "Suspends every feature while macOS Game Mode is on or a game is in front.")
            } header: { Text("App") }

            Section {
                Text("New here? Turn features on one at a time: there's a lot in here.")
                    .foregroundStyle(.secondary)
                Button("Enable Recommended Settings") { Recommended.apply(); message = "Recommended settings enabled." }
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
            } header: { Text("Getting Started") }

            Section {
                LabeledContent("Version", value: "v\(Updater.currentVersion)")
                Button("Check for Updates…") { Updater.check(interactive: true) }
                Text("Click2Minimize is free: every feature, no license, no trial, no telemetry.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("About") }
        }
        .onReceive(refresh) { _ in
            trusted = AX.isTrusted()
            screenRecording = SnapshotCache.hasPermission
        }
    }
}

enum Recommended {
    static let prefs: [Pref] = [.clickToMinimize, .concedeFocusOnMinimize, .doubleClickToHideOthers,
                                .middleClickToTerminate, .rightDragDownToMinimize, .rightDragToSnap,
                                .middleDragToMove, .universalNavigation, .exitFullscreenBeforeGestures,
                                .threeFingerClickToMiddle]
    static func apply() { prefs.forEach { $0.set(true) } }
}

// MARK: - Dock

struct DockPane: View {
    @AppStorage(Pref.dockClickAction.rawValue) private var clickAction = DockClickAction.minimizeAll.rawValue
    @AppStorage(Pref.finderAlternatePath.rawValue) private var finderAlternate = ""
    @State private var minimizeIntoIcon = DockController.minimizesIntoAppIcon
    @State private var instantAutohide = DockController.autohidesInstantly

    var body: some View {
        Form {
            Section {
                PrefToggle(.clickToMinimize, "Click a focused app's Dock icon to minimize it",
                           "The original Click2Minimize behaviour. Click again to bring the windows back.")
                Picker("A click on the focused app's icon will", selection: $clickAction) {
                    ForEach(DockClickAction.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if clickAction == DockClickAction.hideApp.rawValue && DockController.isStageManagerOn {
                    Hint("Hiding is not compatible with Stage Manager, so minimizing is used instead.")
                }
                PrefToggle(.concedeFocusOnMinimize, "Hand focus to the previous app after the last window is minimized",
                           "A side effect: switching between the last two apps may change order.")
            } header: { Text("Click Dock Icon") }

            Section {
                PrefToggle(.doubleClickToHideOthers, "Double-click an app's icon to hide all other apps")
                PrefToggle(.middleClickToTerminate, "Middle-click an app's icon to quit it",
                           "Also quits apps in the app switcher and Stage Manager, and closes windows in Mission Control and App Exposé.")
                PrefToggle(.forceKillOnTerminate, "Quit immediately without waiting",
                           "Much more responsive, but unsaved work can be lost.")
                PrefToggle(.hoverToExpose, "Hover over an app's icon to show its windows (App Exposé)")
                PrefToggle(.finderAlternateEnabled, "Clicking the Finder icon opens another app")
                LabeledContent("Alternate app") {
                    HStack {
                        Text(finderAlternate.isEmpty ? "None" : FileManager.default.displayName(atPath: finderAlternate))
                            .foregroundStyle(.secondary)
                        Button("Choose…") {
                            if let url = AppChooser.choose(message: "Choose an app to open when clicking the Finder Dock icon") {
                                finderAlternate = url.path
                            }
                        }
                    }
                }
            } header: { Text("More Dock Clicks") }

            Section {
                PrefToggle(.lockDockToMainScreen, "Lock the Dock to the main display",
                           "Stops the Dock jumping to another display when the pointer touches its bottom edge.")
                PrefToggle(.dockFidget, "Dock Fidget",
                           "Slide one finger sideways from the bottom edge of the trackpad to run the pointer along the Dock, revealing it if auto-hidden. Ticks on each icon (haptics need a Force Touch trackpad).")
                Toggle(isOn: $instantAutohide) {
                    Text("Auto-hide the Dock and reveal it instantly")
                    Text("Removes the reveal delay. Restarts the Dock.")
                }
                .onChange(of: instantAutohide) { _, on in DockController.setInstantAutohide(on) }
                Toggle(isOn: $minimizeIntoIcon) {
                    Text("Minimize windows into the app's icon")
                    Text("macOS Dock setting. Restarts the Dock.")
                }
                .onChange(of: minimizeIntoIcon) { _, on in DockController.setMinimizeIntoAppIcon(on) }
            } header: { Text("Dock Behaviour") }
        }
    }
}

// MARK: - Windows

struct WindowsPane: View {
    @AppStorage(Pref.leftRightClickAction.rawValue) private var leftRight = WindowToggle.none.rawValue
    @AppStorage(Pref.closeButtonKeywords.rawValue) private var keywords = "close, cancel, dismiss, hide, clear"
    @AppStorage(Pref.closeButtonMaxDistance.rawValue) private var maxDistance = 80.0
    @AppStorage(Pref.closeButtonSearchDepth.rawValue) private var searchDepth = 4
    @AppStorage(Pref.middleClickCloseButton.rawValue) private var closeButton = false

    var body: some View {
        Form {
            Section {
                PrefToggle(.rightDragDownToMinimize, "Right-drag down on a window", "Hold the right button (or press with 2 fingers) and drag down.")
                PrefToggle(.rightLeftClickToMinimize, "Hold the right button, then left-click")
                PrefToggle(.threeFingerSwipeDownToMinimize, "Swipe down with 3 fingers", "Minimizes the window under the pointer.")
            } header: { Text("Minimize without reaching for the yellow button") }

            Section {
                PrefToggle(.tripleRightClickToClose, "Triple right-click on a window")
                PrefToggle(.middleClickCloseButton, "Middle-click near a button to press it",
                           "Finds the closest button matching a keyword, so small close buttons need no aiming.")
                if closeButton {
                    TextField("Keywords", text: $keywords, prompt: Text("close, dismiss"))
                    LabeledContent("Search distance") {
                        Slider(value: $maxDistance, in: 20...200, step: 10) { Text("Search distance") }
                        Text("\(Int(maxDistance)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                    Stepper("Search depth: \(searchDepth) levels", value: $searchDepth, in: 1...10)
                }
                PrefToggle(.middleClickDismissNotifications, "Middle-click a notification banner to dismiss it")
            } header: { Text("Close without reaching for the red button") }

            Section {
                PrefToggle(.rightDragUpToFullscreen, "Right-drag up on a window to toggle full screen")
                PrefToggle(.doubleRightClickToFill, "Double right-click on a window to fill the screen",
                           "Fill keeps the window on the same desktop. Do it again to restore the window.")
                Picker("Hold the left button, then right-click", selection: $leftRight) {
                    ForEach(WindowToggle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                PrefToggle(.doubleClickNotchToFullscreen, "Double-click the camera area at the top of the screen to toggle full screen")
            } header: { Text("Full Screen & Fill without reaching for the green button") }

            Section {
                PrefToggle(.middleDragToMove, "Middle-drag anywhere on a window to move it")
                PrefToggle(.threeFingerDragToMove, "3-finger drag anywhere on a window to move it",
                           "Press lightly with 3 fingers, then move: pressure is only needed to start. Also works with macOS three-finger drag.")
            } header: { Text("Move without reaching for the title bar") }

            Section {
                PrefToggle(.middleScrollToResize, "Hold the middle button and scroll to resize")
                PrefToggle(.threeFingerPinchToResize, "Pinch during a 3-finger drag to resize")
            } header: { Text("Resize without reaching for the borders") }

            Section {
                PrefToggle(.rightDragToSnap, "Right-drag in a direction to snap the window",
                           "Left/right: halves. Diagonals: quarters. Up: maximize. Down: bottom half. A preview shows where it lands; Esc or a left tap cancels.")
                PrefToggle(.doubleRightClickTitleToNextDisplay, "Double right-click a window's title bar to move it to the next display")
                PrefToggle(.twoFingerTopDoubleClickToNextDisplay, "Double-click with 2 fingers at the top of the trackpad to move it to the next display")
            } header: { Text("Snap & Warp") }

            Section {
                PrefToggle(.exitFullscreenBeforeGestures, "Exit full screen before window gestures",
                           "When off, full-screen windows ignore most window gestures.")
                PrefToggle(.suppressContextMenus, "Hold back context menus until a right-drag is ruled out",
                           "Avoids menus flashing open before gestures. Adds a tiny delay to context menus.")
                PrefToggle(.animateWindows, "Animate window moves and resizes", "Skipped when Reduce Motion is on.")
            } header: { Text("Options") }
        }
    }
}

// MARK: - Switcher & overview

struct SwitcherPane: View {
    @AppStorage(Pref.switcherMaxRows.rawValue) private var maxRows = 10
    @CodablePref(.appShortcuts, default: [:]) private var shortcuts: [String: KeyShortcut]
    @CodablePref(.appAutoQuitMinutes, default: [:]) private var autoQuit: [String: Int]
    @State private var pinned = Pref.pinnedApps.strings
    @State private var extraApps: [String] = []
    @State private var screenRecording = SnapshotCache.hasPermission

    private var apps: [String] {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .compactMap(\.bundleIdentifier)
        var all: [String] = []
        for id in pinned + Array(shortcuts.keys) + Array(autoQuit.keys) + extraApps + running where !all.contains(id) { all.append(id) }
        return all
    }

    var body: some View {
        Form {
            Section {
                PrefToggle(.switcherCmdTab, "Replace ⌘⇥", "Takes over the macOS app switcher hotkey.")
                PrefToggle(.switcherRightScroll, "Hold the right button and scroll",
                           "Release the button to switch. Left-click to cancel.")
                PrefToggle(.switcherThreeFingerSwipe, "Swipe up with 3 fingers",
                           "Keep fingers down and move them to pick an app. Lift to switch, spread to cancel.")
                GestureConflictHint()
            } header: { Text("Open the App Switcher") }

            Section {
                Stepper("Visible rows: \(maxRows)", value: $maxRows, in: 3...20)
                PrefToggle(.switcherKeepTerminated, "Keep quit apps in the list", "Picking one relaunches it.")
                PrefToggle(.switcherReverseScroll, "Reverse scrolling direction", "For mouse wheels that feel backwards.")
                Text("While the switcher is open: type a letter to jump to apps starting with it, ⌘Q quits, ⌘H hides, Esc cancels.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Switcher Options") }

            Section {
                ForEach(apps, id: \.self) { id in appRow(id) }
                Button("Add App…") {
                    if let url = AppChooser.choose(message: "Choose an app to configure"), let id = AppChooser.bundleID(url),
                       !apps.contains(id) { extraApps.append(id) }
                }
            } header: { Text("Per-App Settings") } footer: {
                Text("Pin apps to the top of the switcher, give them a hotkey that shows or hides them, or make them quit after idling.")
            }

            Section {
                PrefToggle(.overviewFourFinger, "Swipe up / down with 4 fingers")
                FourFingerConflictHint()
                PrefToggle(.overviewScreenEdge, "Double-click the top / bottom edge of the screen")
                PrefToggle(.overviewRightSideButtons, "Hold the right button and press a side button", "Forward: overview. Back: stash.")
                if !screenRecording {
                    LabeledContent("Window thumbnails") { Button("Grant Screen Recording…") { Permissions.requestScreenRecording() } }
                }
            } header: { Text("Window Overview & Stash") } footer: {
                Text("The overview shows every window, including minimized and hidden ones, which Mission Control leaves out. Middle-click a window there to close it. The stash hides all apps and brings them back on the next gesture.")
            }
        }
        .onAppear { screenRecording = SnapshotCache.hasPermission }
    }

    private func appRow(_ id: String) -> some View {
        HStack {
            AppLabel(bundleID: id)
            Spacer()
            Button {
                if pinned.contains(id) { pinned.removeAll { $0 == id } } else { pinned.append(id) }
                Pref.pinnedApps.set(pinned)
            } label: { Image(systemName: pinned.contains(id) ? "pin.fill" : "pin") }
                .buttonStyle(.borderless)
                .help("Pin to the top of the switcher")
                .accessibilityLabel(pinned.contains(id) ? "Unpin" : "Pin")
            ShortcutRecorder(shortcut: Binding(get: { shortcuts[id] }, set: { shortcuts[id] = $0 }))
            Text("Quit after").foregroundStyle(.secondary).fixedSize()
            TextField("Quit after idle minutes", value: Binding(get: { autoQuit[id] }, set: { autoQuit[id] = ($0 ?? 0) > 0 ? $0 : nil }),
                      format: .number, prompt: Text("Never"))
                .labelsHidden()
                .frame(width: 56)
                .help("Quit the app after this many idle minutes")
            Text("min").foregroundStyle(.secondary).fixedSize()
        }
    }
}

// MARK: - Gestures

struct GesturesPane: View {
    var body: some View {
        Form {
            Section {
                ActionPicker(.drawCircleClockwise, "Circle clockwise")
                ActionPicker(.drawCircleCounterClockwise, "Circle counter-clockwise")
                ActionPicker(.drawShakeHorizontal, "Shake horizontally")
                ActionPicker(.drawShakeVertical, "Shake vertically")
            } header: { Text("Right-Drag Drawing") } footer: {
                Text("Hold the right button (or press with 2 fingers on the trackpad) and draw. Window actions apply to the window where the drawing starts.")
            }
            Section {
                ActionPicker(.rotateClockwise, "Rotate clockwise")
                ActionPicker(.rotateCounterClockwise, "Rotate counter-clockwise")
            } header: { Text("2-Finger Rotation") } footer: { Text("Turn two fingers on the trackpad like a knob.") }
            Section {
                ActionPicker(.tiltLeft, "Tilt left")
                ActionPicker(.tiltRight, "Tilt right")
            } header: { Text("Mouse Wheel Tilt") } footer: { Text("Hold the right button, then tilt the wheel. Needs a mouse with a tilting wheel.") }
        }
    }
}

// MARK: - Universal

struct UniversalPane: View {
    @CodablePref(.navigationOverrides, default: [:]) private var overrides: [String: NavigationOverride]

    var body: some View {
        Form {
            Section {
                PrefToggle(.universalNavigation, "Back / forward in every app",
                           "Swipe left / right with 3 fingers, or press the mouse's side buttons. Sends ⌘[ and ⌘] unless an app has its own shortcuts below. Blender, Figma, Fusion 360, AutoCAD and SketchUp are left alone.")
                GestureConflictHint()
                ForEach(overrides.keys.sorted(), id: \.self) { id in
                    HStack {
                        AppLabel(bundleID: id)
                        Spacer()
                        Text("Back").foregroundStyle(.secondary)
                        ShortcutRecorder(shortcut: Binding(get: { overrides[id]?.back }, set: { overrides[id, default: .init()].back = $0 }))
                        Text("Forward").foregroundStyle(.secondary)
                        ShortcutRecorder(shortcut: Binding(get: { overrides[id]?.forward }, set: { overrides[id, default: .init()].forward = $0 }))
                        Button { overrides[id] = nil } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("Remove")
                    }
                }
                Button("Add App-Specific Shortcuts…") {
                    if let url = AppChooser.choose(message: "Choose an app to configure swipe shortcuts for"),
                       let id = AppChooser.bundleID(url) { overrides[id] = overrides[id] ?? NavigationOverride() }
                }
            } header: { Text("Universal Navigation") }

            Section {
                PrefToggle(.inPageScrolling, "Jump to the top / bottom of a page",
                           "Hold fn and swipe with 3 fingers or scroll the wheel. Left / right jumps to the start / end of a line.")
                PrefToggle(.modifierArrowKeys, "Hold modifiers and swipe or scroll to press arrow keys",
                           "For example, ⌥ + swipe left moves one word left, ⌘⇧ + swipe down selects to the end.")
            } header: { Text("Keyboard-Free Navigation") }

            Section {
                PrefToggle(.threeFingerClickToMiddle, "3-finger click acts as a middle click",
                           "Lets trackpad users use every middle-click feature.")
                PrefToggle(.edgeSlide, "Slide along the trackpad edge to change brightness / volume",
                           "Rest one finger in the middle, slide another along the left edge (brightness of the display under the pointer, external monitors included) or the right edge (volume).")
            } header: { Text("Trackpad") }
        }
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    @AppStorage(Pref.palmThreshold.rawValue) private var palm = 14.0
    @State private var excluded = Pref.excludedApps.strings
    @State private var status: String?
    @CodablePref(.restartShortcut, default: nil) private var restartShortcut: KeyShortcut?

    var body: some View {
        Form {
            Section {
                ForEach(excluded, id: \.self) { id in
                    HStack {
                        AppLabel(bundleID: id)
                        Spacer()
                        Button { excluded.removeAll { $0 == id }; Pref.excludedApps.set(excluded) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless).accessibilityLabel("Remove")
                    }
                }
                Button("Add App…") {
                    if let url = AppChooser.choose(message: "Choose an app to exclude from gestures"),
                       let id = AppChooser.bundleID(url), !excluded.contains(id) {
                        excluded.append(id)
                        Pref.excludedApps.set(excluded)
                    }
                }
            } header: { Text("Excluded Apps") } footer: {
                Text("Mouse and trackpad gestures are skipped while one of these apps is in front. Dock clicks keep working.")
            }

            Section {
                LabeledContent("Palm rejection") {
                    Slider(value: $palm, in: 6...30, step: 1) { Text("Palm rejection") }
                    Text("\(Int(palm))").monospacedDigit().frame(width: 30, alignment: .trailing)
                }
                Text("The largest touch treated as a fingertip. Lower it if your palm triggers gestures.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Trackpad") }

            NativeSettingsSection()

            Section {
                LabeledContent("Restart shortcut") {
                    ShortcutRecorder(shortcut: $restartShortcut)
                }
                Button("Restart Click2Minimize") { Updater.relaunchApp() }
            } header: { Text("Restart") }

            Section {
                HStack {
                    Button("Save Settings…", action: save)
                    Button("Restore Settings…", action: restore)
                }
                if let status { Text(status).font(.callout).foregroundStyle(.secondary) }
            } header: { Text("Backup") }

            Section {
                Button("Reset All Settings…", role: .destructive, action: reset)
            }
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Click2Minimize Settings.plist"
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackup.export(to: url)
            status = "Your settings were saved to \(url.lastPathComponent)."
        } catch { status = error.localizedDescription }
    }

    private func restore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let confirm = NSAlert()
        confirm.messageText = "Restore settings?"
        confirm.informativeText = "This overwrites your current settings with the contents of \(url.lastPathComponent). Click2Minimize will relaunch."
        confirm.addButton(withTitle: "Restore")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        do {
            try SettingsBackup.restore(from: url)
            Updater.relaunchApp()
        } catch { status = error.localizedDescription }
    }

    private func reset() {
        let confirm = NSAlert()
        confirm.messageText = "Reset all settings?"
        confirm.informativeText = "Every feature goes back to its default. Click2Minimize will relaunch. This cannot be undone."
        confirm.addButton(withTitle: "Reset")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        Pref.allCases.forEach { UserDefaults.standard.removeObject(forKey: $0.rawValue) }
        Updater.relaunchApp()
    }
}

// MARK: - System gesture conflicts and native settings

/// Shown when macOS still owns 3-finger swipes that Click2Minimize uses.
struct GestureConflictHint: View {
    @State private var refresh = 0
    var body: some View {
        let _ = refresh
        if SystemTrackpad.threeFingerDrag || SystemTrackpad.threeFingerSwipesUsedBySystem {
            HStack {
                Hint(SystemTrackpad.threeFingerDrag
                     ? "macOS three-finger drag is on, so 3-finger swipes are off."
                     : "macOS also uses 3-finger swipes, so both will react.")
                Spacer()
                Button("Hand to Click2Minimize") { SystemTrackpad.handThreeFingerSwipesToClick2Minimize(); refresh += 1 }
            }
        }
    }
}

struct FourFingerConflictHint: View {
    @State private var refresh = 0
    var body: some View {
        let _ = refresh
        if SystemTrackpad.fourFingerVerticalUsedBySystem {
            HStack {
                Hint("macOS uses 4-finger up / down for Mission Control too.")
                Spacer()
                Button("Hand to Click2Minimize") { SystemTrackpad.handFourFingerVerticalToClick2Minimize(); refresh += 1 }
            }
        }
    }
}

struct NativeSettingsSection: View {
    @State private var threeFingerDrag = SystemTrackpad.threeFingerDrag
    @State private var alertVolume = 100.0

    var body: some View {
        Section {
            Toggle(isOn: $threeFingerDrag) {
                Text("Native three-finger drag")
                Text("Drag with three fingers on a title bar to move a window. Conflicts with Click2Minimize's 3-finger swipes: turning it on turns them off.")
            }
            .onChange(of: threeFingerDrag) { _, on in
                guard on != SystemTrackpad.threeFingerDrag else { return }
                SystemTrackpad.setThreeFingerDrag(on)
                if on { [Pref.threeFingerSwipeDownToMinimize, .switcherThreeFingerSwipe].forEach { $0.set(false) } }
            }
            LabeledContent("Alert volume (beep)") {
                Slider(value: $alertVolume, in: 0...100, step: 5) { Text("Alert volume") } onEditingChanged: { editing in
                    if !editing { AlertVolume.set(alertVolume) }
                }
                Text("\(Int(alertVolume))%").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            LabeledContent("Scroll speed for mouse & trackpad") {
                HStack {
                    Button("Mouse…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Mouse-Settings.extension")!) }
                    Button("Trackpad…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!) }
                }
            }
            Text("For the most responsive gestures, set both tracking and scrolling speed high.")
                .font(.callout).foregroundStyle(.secondary)
        } header: { Text("macOS Native Settings") }
        .onAppear {
            threeFingerDrag = SystemTrackpad.threeFingerDrag
            AlertVolume.read { alertVolume = $0 }
        }
    }
}
