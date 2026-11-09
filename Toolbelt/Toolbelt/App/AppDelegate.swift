import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var menu: MenuPanel? // built on first use: no SwiftUI graph at idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }

        // One instance only: two would tap the same audio twice (echo) and fight over the Dock.
        let me = NSRunningApplication.current
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0 != me }), let url = other.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) } // reopen shows the running copy's menu
            }
            return
        }
        Ingest.purge() // shelf leftovers from a previous run

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: "Toolbelt")
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        Prefs.shared.onChange = { [weak self] in self?.applyPrefs() }
        // Accessibility trust changes broadcast this; re-apply so the Dock tap installs without a relaunch.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Permissions.shared.refresh()
                self?.applyPrefs()
            }
        }
        applyPrefs()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MixerModel.shared.shutdown() // release taps so no app stays muted
    }

    private func applyPrefs() {
        let prefs = Prefs.shared
        if prefs.dockClick { DockClick.shared.start() } else { DockClick.shared.stop() }
        if prefs.shakeShelf { DragMonitor.shared.start() } else { DragMonitor.shared.stop() }
        MixerModel.shared.setEnabled(prefs.mixer)
    }

    /// `open -a Toolbelt` while running shows the menu: a way in when the status item is hidden by the notch or Menu Bar settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if menu?.isVisible != true { togglePopover() }
        return false
    }

    @objc private func togglePopover() {
        if let menu, menu.isVisible {
            menu.close()
            return
        }
        Permissions.shared.refresh()
        let panel = menu ?? MenuPanel(rootView: PopoverView())
        panel.onClose = { MixerModel.shared.setMetering(false) }
        menu = panel
        var icon: CGRect?
        if let button = statusItem?.button, let window = button.window {
            icon = window.convertToScreen(button.convert(button.bounds, to: nil))
        }
        panel.show(below: icon)
        MixerModel.shared.setMetering(true)
    }
}
