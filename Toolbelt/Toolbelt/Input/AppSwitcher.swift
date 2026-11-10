import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Vertical ⌘⇥ replacement (ported and trimmed from Click2Minimize 3.0; ADR-008).
/// Keys arrive from the shared `InputTap`; the panel is built on first use.
@MainActor
final class AppSwitcher: ObservableObject {
    static let shared = AppSwitcher()

    struct Entry: Identifiable, Equatable {
        let id: pid_t
        let name: String
        let icon: NSImage?
        let isHidden: Bool
    }

    @Published private(set) var entries: [Entry] = []
    @Published var selected = 0
    private(set) var isVisible = false
    private var apps: [pid_t: NSRunningApplication] = [:]
    private var history: [pid_t] = []    // most recent first
    private var observers: [NSObjectProtocol] = []
    private var panel: NSPanel?
    private var lastLetter: Character?

    // MARK: Enable / disable

    func setEnabled(_ on: Bool) {
        Self.setNativeCommandTab(enabled: !on)
        guard on != !observers.isEmpty else { return }
        if on {
            let nc = NSWorkspace.shared.notificationCenter
            observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
                let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { app.map(AppSwitcher.shared.didActivate) }
            })
            observers.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { n in
                let pid = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { AppSwitcher.shared.history.removeAll { $0 == pid } }
            })
            if let front = NSWorkspace.shared.frontmostApplication { didActivate(front) }
        } else {
            observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
            observers = []
            history = []
            cancel()
        }
    }

    /// Native ⌘⇥ / ⌘⇧⇥ are symbolic hotkeys 1 and 2; the private setter is resolved at runtime.
    static func setNativeCommandTab(enabled: Bool) {
        typealias Fn = @convention(c) (Int32, Bool) -> Int32
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetSymbolicHotKeyEnabled") else { return }
        let fn = unsafeBitCast(sym, to: Fn.self)
        _ = fn(1, enabled)
        _ = fn(2, enabled)
    }

    private func didActivate(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular, app.processIdentifier != getpid() else { return }
        history.removeAll { $0 == app.processIdentifier }
        history.insert(app.processIdentifier, at: 0)
        if history.count > 60 { history.removeLast() }
    }

    // MARK: Ordering (pure, unit tested)

    /// Running apps in most-recently-used order; apps never activated follow in launch order.
    nonisolated static func order(running: [pid_t], history: [pid_t]) -> [pid_t] {
        let alive = Set(running)
        var out = history.filter(alive.contains)
        let seen = Set(out)
        out += running.filter { !seen.contains($0) }
        return out
    }

    /// Like ⌘⇥: forward starts on the app used before the frontmost one; backward on the last.
    nonisolated static func initialSelection(order: [pid_t], front: pid_t?, backward: Bool) -> Int {
        guard !order.isEmpty else { return 0 }
        if backward { return order.count - 1 }
        if order.first == front { return min(1, order.count - 1) }
        return 0
    }

    // MARK: Showing

    private func show(backward: Bool) {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid() && !$0.isTerminated
        }
        apps = Dictionary(running.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let pids = Self.order(running: running.map(\.processIdentifier), history: history)
        entries = pids.compactMap { pid in
            apps[pid].map { Entry(id: pid, name: $0.localizedName ?? "App", icon: $0.icon, isHidden: $0.isHidden) }
        }
        guard !entries.isEmpty else { return }
        selected = Self.initialSelection(order: pids, front: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                         backward: backward)
        isVisible = true
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = NSSize(width: 340, height: CGFloat(entries.count) * SwitcherView.rowHeight + SwitcherView.padding * 2)
        let mouse = NSEvent.mouseLocation
        let vf = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame ?? .zero
        let height = min(size.height, vf.height - 40)
        panel.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.midY - height / 2, width: size.width, height: height), display: true)
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
        p.setAccessibilityLabel("App switcher")
        return p
    }

    func cancel() {
        isVisible = false
        panel?.orderOut(nil)
    }

    private func move(_ delta: Int) {
        guard !entries.isEmpty else { return }
        selected = (selected + delta + entries.count) % entries.count
    }

    private func commit() {
        guard isVisible else { return }
        let entry = entries.indices.contains(selected) ? entries[selected] : nil
        cancel()
        guard let entry, let app = apps[entry.id], !app.isTerminated else { return }
        app.unhide()
        app.activate()
        // SWCH-02: bring back a window when every window is minimized.
        let windows = AX.windows(app.processIdentifier).filter { AX.subrole($0) == kAXStandardWindowSubrole }
        if !windows.isEmpty, windows.allSatisfy(AX.isMinimized), let w = windows.first {
            AX.set(w, kAXMinimizedAttribute, kCFBooleanFalse)
        }
    }

    // MARK: Mouse

    private func row(at p: CGPoint) -> Int? {
        guard isVisible, let panel, let primary = NSScreen.screens.first else { return nil }
        // Tap coordinates are top-left global; convert the panel frame to match.
        let f = panel.frame
        let top = primary.frame.maxY - f.maxY
        guard p.x >= f.minX, p.x <= f.maxX, p.y >= top, p.y <= top + f.height else { return nil }
        let i = Int((p.y - top - SwitcherView.padding) / SwitcherView.rowHeight)
        return entries.indices.contains(i) ? i : nil
    }

    /// Left click while open: pick the row under the pointer, or cancel when clicking elsewhere.
    func handleClick(at p: CGPoint) {
        if let i = row(at: p) {
            selected = i
            commit()
        } else {
            cancel()
        }
    }

    /// Middle click while open quits the app on that row.
    func quitRow(at p: CGPoint) {
        guard let i = row(at: p), let app = apps[entries[i].id] else { return }
        app.terminate()
        entries.remove(at: i)
        if entries.isEmpty { cancel() } else { selected = min(selected, entries.count - 1) }
    }

    // MARK: Keyboard

    /// Returns true when the key event was handled and must not reach the frontmost app.
    func handleKey(_ type: CGEventType, _ e: CGEvent) -> Bool {
        let code = Int(e.getIntegerValueField(.keyboardEventKeycode))
        let flags = e.flags
        if type == .flagsChanged {
            if isVisible, !flags.contains(.maskCommand) { commit() }
            return false
        }
        if code == kVK_Tab, flags.contains(.maskCommand), flags.intersection([.maskControl, .maskAlternate]).isEmpty {
            let backward = flags.contains(.maskShift)
            if isVisible { move(backward ? -1 : 1) } else { show(backward: backward) }
            return true
        }
        guard isVisible else { return false }
        switch code {
        case kVK_Escape: cancel()
        case kVK_Return: commit()
        case kVK_UpArrow, kVK_LeftArrow, kVK_ANSI_Grave: move(-1)
        case kVK_DownArrow, kVK_RightArrow: move(1)
        case kVK_ANSI_Q where flags.contains(.maskCommand):
            if entries.indices.contains(selected), let app = apps[entries[selected].id] { app.terminate() }
            cancel()
        case kVK_ANSI_H where flags.contains(.maskCommand):
            if entries.indices.contains(selected) { apps[entries[selected].id]?.hide() }
            cancel()
        default:
            jumpToLetter(e)
        }
        return true
    }

    /// Typing a letter cycles through apps whose name starts with it.
    private func jumpToLetter(_ e: CGEvent) {
        guard let ch = NSEvent(cgEvent: e)?.charactersIgnoringModifiers?.lowercased().first, ch.isLetter || ch.isNumber else { return }
        let start = ch == lastLetter ? selected + 1 : 0
        lastLetter = ch
        for k in 0..<entries.count {
            let i = (start + k) % entries.count
            if entries[i].name.lowercased().first == ch {
                selected = i
                return
            }
        }
    }
}

struct SwitcherView: View {
    static let rowHeight: CGFloat = 40
    static let padding: CGFloat = 10
    @ObservedObject var model: AppSwitcher

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.entries.enumerated()), id: \.element.id) { i, entry in
                        let isSelected = i == model.selected
                        HStack(spacing: 10) {
                            if let icon = entry.icon { Image(nsImage: icon).resizable().frame(width: 26, height: 26) }
                            Text(entry.name).font(.system(size: 13, weight: isSelected ? .semibold : .regular)).lineLimit(1)
                            Spacer()
                            if entry.isHidden { Image(systemName: "eye.slash").font(.caption).accessibilityLabel("Hidden") }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: Self.rowHeight)
                        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor : .clear))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .id(i)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(Self.padding)
            }
            .scrollDisabled(true)
            .onChange(of: model.selected) { _, i in proxy.scrollTo(i, anchor: .center) }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
