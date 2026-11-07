import Cocoa
import ServiceManagement
import SwiftUI
import os.log

private let log = Logger(subsystem: "com.idemfactor.Click2Minimize", category: "app")

@main
struct Click2MinimizeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage(Pref.showInMenuBar.rawValue) private var showInMenuBar = true

    init() { Pref.registerDefaults() }

    var body: some Scene {
        MenuBarExtra("Click2Minimize", image: "MenuBarIcon", isInserted: $showInMenuBar) {
            Button("Settings…") { appDelegate.openSettings() }.keyboardShortcut(",")
            Button("Check for Updates…") { Updater.check(interactive: true) }
            Divider()
            Button("Accessibility Settings…") { Permissions.openAccessibilitySettings() }
            Divider()
            Button("Restart Click2Minimize") { Updater.relaunchApp() }
            Button("Quit Click2Minimize") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: NSWindow?
    private var trustTimer: Timer?
    private var nativeCommandTabDisabled: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        NSApp.setActivationPolicy(.accessory)
        if Pref.launchAtLogin.bool { LoginItem.set(true) }

        AppSwitcher.shared.start()
        GameMode.start { EventRouter.shared.refreshPauseState() }
        observeSystem()
        startWhenTrusted()
        Updater.check(interactive: false)
        log.info("Click2Minimize \(Updater.currentVersion, privacy: .public) launched")
    }

    /// Launching the app again (e.g. when the menu-bar icon is hidden) opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        SystemPrivate.setNativeCommandTab(enabled: true)
        DisplayControl.restoreGamma()
        WindowMover.shared.end() // never leave the pointer detached
    }

    private func startWhenTrusted() {
        if AX.isTrusted(), EventRouter.shared.start() {
            Trackpad.shared.refresh()
            return
        }
        Permissions.explainAccessibility()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard AX.isTrusted(), EventRouter.shared.start() else { return }
            timer.invalidate()
            self?.trustTimer = nil
            Trackpad.shared.refresh()
            log.info("accessibility granted, engine started")
        }
    }

    private func observeSystem() {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Trackpad.shared.refresh()
            EventRouter.shared.refreshPauseState()
            let wantDisabled = Pref.switcherCmdTab.bool
            if self?.nativeCommandTabDisabled != wantDisabled {
                self?.nativeCommandTabDisabled = wantDisabled
                AppSwitcher.shared.applyCommandTabSetting()
            }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            // Trackpads re-enumerate after sleep (and when a Magic Trackpad reconnects).
            Trackpad.shared.restart()
        }
    }

    func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Click2Minimize"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 780, height: 600))
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func set(_ on: Bool) -> Bool {
        do {
            if on, !isEnabled { try SMAppService.mainApp.register() }
            if !on, isEnabled { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            log.error("launch-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

enum Permissions {
    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    static func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() { openScreenRecordingSettings() }
    }

    /// Accessibility is required for everything. The engine starts on its own once it is granted.
    static func explainAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        Click2Minimize needs Accessibility access to read the Dock and control windows.

        Enable Click2Minimize in System Settings › Privacy & Security › Accessibility. \
        It starts working as soon as access is granted: no relaunch needed.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            AX.promptForTrust()
            openAccessibilitySettings()
        }
    }
}
