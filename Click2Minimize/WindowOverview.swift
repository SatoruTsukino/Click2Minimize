import ApplicationServices
import Cocoa
import ScreenCaptureKit
import SwiftUI
import os.log

private let log = Logger(subsystem: "com.idemfactor.Click2Minimize", category: "overview")

/// Window thumbnails. Minimized windows can't be captured, so a picture is
/// taken just before Click2Minimize minimizes or stashes one.
final class SnapshotCache {
    static let shared = SnapshotCache()
    private var images: [CGWindowID: CGImage] = [:]
    private var order: [CGWindowID] = []

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    func image(_ id: CGWindowID) -> CGImage? { images[id] }

    private func store(_ id: CGWindowID, _ image: CGImage) {
        if images[id] == nil { order.append(id) }
        images[id] = image
        while order.count > 80 { images.removeValue(forKey: order.removeFirst()) }
    }

    /// Captures the given windows (when permitted), then calls back on main.
    func capture(_ ids: [CGWindowID], completion: @escaping () -> Void = {}) {
        guard Self.hasPermission, !ids.isEmpty else { completion(); return }
        Task {
            var captured: [(CGWindowID, CGImage)] = []
            if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) {
                for w in content.windows where ids.contains(w.windowID) {
                    let config = SCStreamConfiguration()
                    let scale = min(1, 640 / max(w.frame.width, 1))
                    config.width = max(1, Int(w.frame.width * scale * 2))
                    config.height = max(1, Int(w.frame.height * scale * 2))
                    config.showsCursor = false
                    let filter = SCContentFilter(desktopIndependentWindow: w)
                    if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                        captured.append((w.windowID, img))
                    }
                }
            }
            let results = captured
            await MainActor.run {
                results.forEach { self.store($0.0, $0.1) }
                completion()
            }
        }
    }
}

/// Full-screen grid of every window, including minimized and hidden ones,
/// which macOS Mission Control leaves out.
final class WindowOverview: ObservableObject {
    static let shared = WindowOverview()

    struct Item: Identifiable {
        enum State { case normal, minimized, hidden }
        let id: Int
        let element: AXUIElement
        let windowID: CGWindowID?
        let app: NSRunningApplication
        let title: String
        let state: State
    }

    @Published private(set) var items: [Item] = []
    @Published var hovered: Int?
    @Published private(set) var imageVersion = 0

    private var window: NSWindow?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    var isVisible: Bool { window?.isVisible ?? false }

    /// Snapshots are only worth taking while an overview trigger is enabled.
    static var wantsSnapshots: Bool {
        (Pref.overviewFourFinger.bool || Pref.overviewScreenEdge.bool || Pref.overviewRightSideButtons.bool) &&
            SnapshotCache.hasPermission
    }

    func toggle() { isVisible ? dismiss() : show() }

    func show() {
        items = collect()
        guard !items.isEmpty else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let screen = ScreenGeometry.screen(containing: Synth.cursor) ?? NSScreen.main ?? NSScreen.screens[0]
        let w = window ?? makeWindow()
        window = w
        w.setFrame(screen.frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.dismiss(); return nil }
            return e
        }
        SnapshotCache.shared.capture(items.filter { $0.state == .normal }.compactMap(\.windowID)) { [weak self] in
            self?.imageVersion += 1
        }
    }

    func dismiss(restoreFocus: Bool = true) {
        window?.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        hovered = nil
        if restoreFocus { previousApp?.activate() }
    }

    func choose(_ item: Item) {
        dismiss(restoreFocus: false)
        WindowOps.focus(item.element, of: item.app)
    }

    /// Middle click closes the hovered window.
    func closeHovered() -> Bool {
        guard let i = hovered, let item = items.first(where: { $0.id == i }) else { return isVisible }
        WindowOps.close(item.element)
        items.removeAll { $0.id == i }
        hovered = nil
        if items.isEmpty { dismiss() }
        return true
    }

    func image(for item: Item) -> CGImage? { item.windowID.flatMap(SnapshotCache.shared.image) }

    private func collect() -> [Item] {
        let me = ProcessInfo.processInfo.processIdentifier
        var result: [Item] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != me {
            for w in AX.windows(app.processIdentifier) where AX.isStandardWindow(w) {
                let state: Item.State = app.isHidden ? .hidden : (AX.isMinimized(w) ? .minimized : .normal)
                result.append(Item(id: result.count, element: w, windowID: AX.windowID(w), app: app,
                                   title: AX.title(w), state: state))
            }
        }
        return result
    }

    private func makeWindow() -> NSWindow {
        let w = OverviewWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .popUpMenu
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        w.contentView = NSHostingView(rootView: OverviewView(model: self))
        return w
    }
}

private final class OverviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

struct OverviewView: View {
    @ObservedObject var model: WindowOverview

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                .onTapGesture { model.dismiss() }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 24)], spacing: 24) {
                    ForEach(model.items) { item in card(item) }
                }
                .padding(48)
            }
        }
        .accessibilityLabel("Window overview")
    }

    private func card(_ item: WindowOverview.Item) -> some View {
        let isHovered = model.hovered == item.id
        return VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.15))
                if let img = model.image(for: item) {
                    Image(decorative: img, scale: 2).resizable().aspectRatio(contentMode: .fit)
                } else if let icon = item.app.icon {
                    Image(nsImage: icon).resizable().frame(width: 72, height: 72)
                }
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: isHovered ? 3 : 0))
            .overlay(alignment: .topTrailing) {
                if item.state != .normal {
                    Text(item.state == .minimized ? "Minimized" : "Hidden")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                        .padding(6)
                }
            }
            HStack(spacing: 6) {
                if let icon = item.app.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                Text(item.title.isEmpty ? (item.app.localizedName ?? "") : item.title)
                    .font(.callout).lineLimit(1)
            }
        }
        .id("\(item.id)-\(model.imageVersion)")
        .contentShape(Rectangle())
        .onHover { model.hovered = $0 ? item.id : (model.hovered == item.id ? nil : model.hovered) }
        .onTapGesture { model.choose(item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.choose(item) }
    }
}

/// Temporarily hides every app, and brings them all back on the next trigger.
enum Stash {
    private static var stashed: [NSRunningApplication] = []

    static func toggle() {
        if !stashed.isEmpty {
            stashed.filter { !$0.isTerminated }.forEach { $0.unhide() }
            stashed = []
            return
        }
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != me && $0.bundleIdentifier != "com.apple.finder"
        }
        guard !apps.isEmpty else { return }
        let hideAll = {
            apps.forEach { $0.hide() }
            stashed = apps
        }
        if WindowOverview.wantsSnapshots {
            let ids = apps.flatMap { AX.windows($0.processIdentifier) }.filter { !AX.isMinimized($0) }.compactMap(AX.windowID)
            SnapshotCache.shared.capture(ids, completion: hideAll)
        } else {
            hideAll()
        }
        log.debug("stashed \(apps.count) app(s)")
    }
}
