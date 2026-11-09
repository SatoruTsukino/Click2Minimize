import AppKit
import QuickLookThumbnailing

struct ShelfItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64?

    init(url: URL) {
        self.url = url
        size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }
}

enum ShelfLayout: String, CaseIterable, Identifiable {
    case stack, grid, list
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .stack: "square.stack.3d.down.right"
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

@MainActor
final class ShelfModel: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var selection: Set<UUID> = []
    @Published private(set) var thumbnails: [URL: NSImage] = [:]
    @Published private(set) var busy = 0
    @Published private(set) var message: String?
    @Published var isTargeted = false
    @Published var preview: URL?
    @Published var layout: ShelfLayout {
        didSet { UserDefaults.standard.set(layout.rawValue, forKey: "shelfLayout") }
    }

    /// Called when the last item leaves by drag-out.
    var onEmptied: (() -> Void)?

    init() {
        layout = ShelfLayout(rawValue: UserDefaults.standard.string(forKey: "shelfLayout") ?? "") ?? .stack
    }

    var allURLs: [URL] { items.map(\.url) }

    func add(_ urls: [URL]) {
        let existing = Set(items.map(\.url))
        items += urls.filter { !existing.contains($0) }.map(ShelfItem.init)
    }

    /// Removes items; the shelf's own temp files among them are deleted after `discardAfter` seconds.
    func remove(_ urls: [URL], discardAfter delay: TimeInterval = 0) {
        let drop = Set(urls)
        items.removeAll { drop.contains($0.url) }
        selection = selection.filter { id in items.contains { $0.id == id } }
        for url in urls { thumbnails[url] = nil }
        Ingest.discard(urls, after: delay)
    }

    func clear() {
        Ingest.discard(allURLs)
        items = []
        selection = []
        thumbnails = [:]
        message = nil
        preview = nil
    }

    /// Items were dropped somewhere outside the shelf: they leave it (temp files after a grace period).
    func draggedOut(_ urls: [URL]) {
        remove(urls, discardAfter: 60)
        if items.isEmpty { onEmptied?() }
    }

    /// URLs an item acts on: the whole selection if the item is part of it.
    func targets(for item: ShelfItem) -> [URL] {
        selection.contains(item.id) ? items.filter { selection.contains($0.id) }.map(\.url) : [item.url]
    }

    var selectedOrAll: [URL] {
        let sel = items.filter { selection.contains($0.id) }
        return (sel.isEmpty ? items : sel).map(\.url)
    }

    func select(_ item: ShelfItem, extend: Bool) {
        if extend {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        } else {
            selection = [item.id]
        }
    }

    func selectAll() { selection = Set(items.map(\.id)) }

    func loadThumbnail(_ url: URL) async {
        guard thumbnails[url] == nil else { return }
        thumbnails[url] = NSWorkspace.shared.icon(forFile: url.path)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 160, height: 160),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                   representationTypes: .thumbnail)
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
           items.contains(where: { $0.url == url }) {
            thumbnails[url] = rep.nsImage
        }
    }

    func run(_ action: ConvertAction, on urls: [URL]) {
        busy += 1
        message = nil
        Task {
            do {
                let outputs = try await Converter.run(action, on: urls)
                add(outputs)
                flash("\(action.title): \(outputs.count) file\(outputs.count == 1 ? "" : "s")")
            } catch {
                flash("\(action.title) failed: \(error.localizedDescription)")
            }
            busy -= 1
        }
    }

    private func flash(_ text: String) {
        message = text
        Task {
            try? await Task.sleep(for: .seconds(5))
            if message == text { message = nil }
        }
    }
}
