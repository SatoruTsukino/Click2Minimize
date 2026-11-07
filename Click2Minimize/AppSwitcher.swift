import Carbon.HIToolbox
import Cocoa
import SwiftUI

/// Enhanced app switcher plus the per-app features configured alongside it:
/// pinned apps, global show / hide hotkeys and auto-quit after idling.
final class AppSwitcher: ObservableObject {
    static let shared = AppSwitcher()

    enum Trigger { case cmdTab, rightScroll, swipe }

    struct Entry: Identifiable {
        let id: String           // bundle identifier
        let name: String
        let icon: NSImage
        let app: NSRunningApplication?
        let url: URL?
        let pinned: Bool
    }

    @Published private(set) var entries: [Entry] = []
    @Published var selected = 0
    private(set) var activeTrigger: Trigger?
    var isVisible: Bool { activeTrigger != nil }

    private var panel: NSPanel?
    private var history: [String] = []                 // bundle IDs, most recent first
    private var knownURLs: [String: URL] = [:]
    private var autoQuitWork: [pid_t: DispatchWorkItem] = [:]
    private var lastLetter: Character?

    // MARK: Lifecycle

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.didActivate(app)
        }
        nc.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.scheduleAutoQuit(app)
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.autoQuitWork.removeValue(forKey: app.processIdentifier)?.cancel()
            if !Pref.switcherKeepTerminated.bool, let id = app.bundleIdentifier { self?.history.removeAll { $0 == id } }
        }
        if let front = NSWorkspace.shared.frontmostApplication { didActivate(front) }
        applyCommandTabSetting()
    }

    /// The native ⌘⇥ is turned off only while our replacement is enabled.
    func applyCommandTabSetting() {
        SystemPrivate.setNativeCommandTab(enabled: !Pref.switcherCmdTab.bool)
    }

    private func didActivate(_ app: NSRunningApplication) {
        EventRouter.shared.refreshPauseState()
        autoQuitWork.removeValue(forKey: app.processIdentifier)?.cancel()
        guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        history.removeAll { $0 == id }
        history.insert(id, at: 0)
        if let url = app.bundleURL { knownURLs[id] = url }
        if history.count > 60 { history.removeLast() }
    }

    /// Most recently used app other than `app` that has something to show.
    func previousApp(excluding app: NSRunningApplication) -> NSRunningApplication? {
        for id in history where id != app.bundleIdentifier {
            if let candidate = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
               !candidate.isHidden { return candidate }
        }
        return nil
    }

    // MARK: Auto-quit

    private func scheduleAutoQuit(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier,
              let minutes = Pref.appAutoQuitMinutes.decoded([String: Int].self)?[id], minutes > 0 else { return }
        autoQuitWork[app.processIdentifier]?.cancel()
        let work = DispatchWorkItem { if !app.isActive && !app.isTerminated { app.terminate() } }
        autoQuitWork[app.processIdentifier] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(minutes * 60), execute: work)
    }

    // MARK: Per-app hotkeys

    /// Shows, hides or launches the app bound to a hotkey.
    private func handleAppShortcut(_ e: CGEvent) -> Bool {
        guard let map = Pref.appShortcuts.decoded([String: KeyShortcut].self),
              let id = map.first(where: { $0.value.matches(e) })?.key else { return false }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            if app.isActive { app.hide() } else { app.unhide(); app.activate() }
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
        return true
    }

    // MARK: Entries

    private func buildEntries() -> [Entry] {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        let byID = Dictionary(running.compactMap { a in a.bundleIdentifier.map { ($0, a) } }, uniquingKeysWith: { a, _ in a })
        let pinned = Pref.pinnedApps.strings
        var order: [String] = []
        for id in pinned + history + running.compactMap(\.bundleIdentifier) where !order.contains(id) { order.append(id) }

        return order.compactMap { id in
            let app = byID[id]
            if app == nil && !pinned.contains(id) && !Pref.switcherKeepTerminated.bool { return nil }
            guard let url = app?.bundleURL ?? knownURLs[id] ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                return nil
            }
            let name = app?.localizedName ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return Entry(id: id, name: name, icon: app?.icon ?? NSWorkspace.shared.icon(forFile: url.path),
                         app: app, url: url, pinned: pinned.contains(id))
        }
    }

    // MARK: Showing

    func show(trigger: Trigger, offset: Int = 1) {
        entries = buildEntries()
        guard !entries.isEmpty else { return }
        activeTrigger = trigger
        // Like ⌘⇥: start on the previously used app (or the last entry when going backwards).
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if offset < 0 {
            selected = entries.count - 1
        } else if let previous = history.first(where: { id in id != frontID && entries.contains { $0.id == id } }) {
            selected = entries.firstIndex { $0.id == previous } ?? 0
        } else {
            selected = entries.firstIndex { $0.id != frontID } ?? 0
        }
        presentPanel()
    }

    private func presentPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = NSSize(width: 360, height: CGFloat(visibleRows) * SwitcherView.rowHeight + SwitcherView.padding * 2)
        let screen = ScreenGeometry.screen(containing: Synth.cursor) ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2, width: size.width, height: size.height),
                       display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .popUpMenu
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = NSHostingView(rootView: SwitcherView(model: self))
        return p
    }

    func move(_ delta: Int) {
        guard !entries.isEmpty else { return }
        selected = (selected + delta + entries.count) % entries.count
    }

    func cancel() {
        activeTrigger = nil
        panel?.orderOut(nil)
    }

    func commit() {
        guard isVisible else { return }
        let entry = entries.indices.contains(selected) ? entries[selected] : nil
        cancel()
        guard let entry else { return }
        if let app = entry.app, !app.isTerminated {
            app.unhide()
            app.activate()
            // Bring back a window if everything was minimized.
            let windows = AX.windows(app.processIdentifier)
            if !windows.isEmpty, windows.allSatisfy(AX.isMinimized) { WindowOps.restoreLastMinimized(of: app) }
        } else if let url = entry.url {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    // MARK: Input while visible

    func handleScroll(_ dy: CGFloat) -> Bool {
        guard isVisible, dy != 0 else { return isVisible }
        let down = Pref.switcherReverseScroll.bool ? dy > 0 : dy < 0
        move(down ? 1 : -1)
        return true
    }

    private func entryIndex(at p: CGPoint) -> Int? {
        guard let panel, panel.isVisible else { return nil }
        let frame = ScreenGeometry.toGlobal(panel.frame)
        guard frame.contains(p) else { return nil }
        let row = Int((p.y - frame.minY - SwitcherView.padding) / SwitcherView.rowHeight)
        let i = visibleRange.lowerBound + row
        return visibleRange.contains(i) ? i : nil
    }

    var visibleRows: Int { min(entries.count, max(3, Pref.switcherMaxRows.int)) }

    /// Slice of entries on screen; it follows the selection so it stays centred.
    var visibleRange: Range<Int> {
        let rows = visibleRows
        let start = max(0, min(selected - rows / 2, entries.count - rows))
        return start..<(start + rows)
    }

    /// Left click: pick the entry under the pointer, or cancel when clicking elsewhere.
    func handleClick(at p: CGPoint) -> Bool {
        if let i = entryIndex(at: p) {
            selected = i
            commit()
        } else {
            cancel()
        }
        return true
    }

    func terminateEntry(at p: CGPoint) -> Bool {
        guard let i = entryIndex(at: p), let app = entries[i].app else { return isVisible }
        ActionRunner.terminate(app)
        entries.remove(at: i)
        if entries.isEmpty { cancel() } else { selected = min(selected, entries.count - 1) }
        return true
    }

    /// Keyboard: ⌘⇥ replacement, navigation keys while open, per-app hotkeys.
    func handleKey(_ type: CGEventType, _ e: CGEvent) -> Bool {
        let code = Int(e.getIntegerValueField(.keyboardEventKeycode))
        let flags = e.flags

        if type == .flagsChanged {
            if activeTrigger == .cmdTab && !flags.contains(.maskCommand) { commit() }
            return false
        }

        if type == .keyDown, code == kVK_Tab, flags.contains(.maskCommand), Pref.switcherCmdTab.bool,
           flags.intersection([.maskControl, .maskAlternate]).isEmpty {
            let delta = flags.contains(.maskShift) ? -1 : 1
            if isVisible { move(delta) } else { show(trigger: .cmdTab, offset: delta) }
            return true
        }

        guard isVisible else {
            return type == .keyDown && handleAppShortcut(e)
        }
        guard type == .keyDown else { return true }
        switch code {
        case kVK_Escape: cancel()
        case kVK_Return: commit()
        case kVK_UpArrow, kVK_LeftArrow, kVK_ANSI_Grave: move(-1)
        case kVK_DownArrow, kVK_RightArrow, kVK_Tab: move(1)
        case kVK_ANSI_Q where flags.contains(.maskCommand):
            if let app = entries[safe: selected]?.app { ActionRunner.terminate(app) }
            cancel()
        case kVK_ANSI_H where flags.contains(.maskCommand):
            entries[safe: selected]?.app?.hide()
            cancel()
        default:
            jumpToLetter(e)
        }
        return true
    }

    /// Typing a letter cycles through apps whose name starts with it.
    private func jumpToLetter(_ e: CGEvent) {
        guard let ch = NSEvent(cgEvent: e)?.charactersIgnoringModifiers?.lowercased().first, ch.isLetter || ch.isNumber else { return }
        let n = entries.count
        let start = ch == lastLetter ? selected + 1 : 0
        lastLetter = ch
        for k in 0..<n {
            let i = (start + k) % n
            if entries[i].name.lowercased().first == ch { selected = i; return }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

struct SwitcherView: View {
    static let rowHeight: CGFloat = 44
    static let padding: CGFloat = 12
    @ObservedObject var model: AppSwitcher

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.visibleRange), id: \.self) { i in
                let entry = model.entries[i]
                let isSelected = i == model.selected
                HStack(spacing: 10) {
                    Image(nsImage: entry.icon).resizable().frame(width: 30, height: 30)
                    Text(entry.name).font(.system(size: 14, weight: isSelected ? .semibold : .regular)).lineLimit(1)
                    Spacer()
                    if entry.pinned { Image(systemName: "pin.fill").font(.caption) }
                    if entry.app == nil { Image(systemName: "power").font(.caption) }
                }
                .padding(.horizontal, 12)
                .frame(height: Self.rowHeight)
                .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor : .clear))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .opacity(entry.app == nil && !isSelected ? 0.6 : 1)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(Self.padding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("App switcher")
    }
}
