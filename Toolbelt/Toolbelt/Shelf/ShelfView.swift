import AppKit
import QuickLook
import SwiftUI

struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(8)
        .background(VisualEffect().clipShape(RoundedRectangle(cornerRadius: 14)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(model.isTargeted ? Color.accentColor : .clear, lineWidth: 2))
        .quickLookPreview($model.preview, in: model.allURLs)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: close) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close and clear the shelf")
            Text(model.items.isEmpty ? "Shelf" : "\(model.items.count) item\(model.items.count == 1 ? "" : "s")")
                .font(.headline)
            Spacer()
            if !model.items.isEmpty {
                Picker("Layout", selection: $model.layout) {
                    ForEach(ShelfLayout.allCases) { Image(systemName: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button {
                    ShelfMenu.build(model.selectedOrAll, model: model)
                        .popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
                } label: { Image(systemName: "ellipsis.circle") }
                    .buttonStyle(.plain)
                    .help("Actions")
            }
        }
    }

    @ViewBuilder private var content: some View {
        if model.items.isEmpty {
            Label("Drop files here", systemImage: "tray.and.arrow.down").foregroundStyle(.secondary)
        } else if model.items.count == 1 || model.layout == .stack {
            pile
        } else if model.layout == .grid {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], spacing: 6) {
                    ForEach(model.items) { gridCell($0) }
                }
                .padding(.horizontal, 6)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 2) { ForEach(model.items) { listRow($0) } }
            }
        }
    }

    /// All items as one stack that fills the shelf: one click selects them all, one drag takes them all.
    private var pile: some View {
        let shown = Array(model.items.suffix(3))
        let allSelected = model.selection.count == model.items.count
        return VStack(spacing: 4) {
            ZStack {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    let depth = CGFloat(shown.count - 1 - index)
                    thumbnail(item.url)
                        .shadow(radius: 2)
                        .rotationEffect(.degrees(Double(depth) * -6))
                        .offset(x: depth * -8, y: depth * -4)
                        .task { await model.loadThumbnail(item.url) }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(allSelected ? Color.accentColor.opacity(0.25) : .clear))
            Text(model.items.count == 1 ? model.items[0].url.lastPathComponent : "Drag to take all \(model.items.count)")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
        .overlay(Interaction(
            model: model, urls: { model.allURLs },
            click: { _ in model.selectAll() },
            doubleClick: { if model.items.count == 1 { NSWorkspace.shared.open(model.items[0].url) } else { model.layout = .grid } }))
    }

    private func gridCell(_ item: ShelfItem) -> some View {
        VStack(spacing: 2) {
            thumbnail(item.url).frame(width: 52, height: 52)
            Text(item.url.lastPathComponent)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
        }
        .padding(4)
        .frame(width: 76, height: 84)
        .background(RoundedRectangle(cornerRadius: 8).fill(model.selection.contains(item.id) ? Color.accentColor.opacity(0.3) : .clear))
        .task { await model.loadThumbnail(item.url) }
        .overlay(itemInteraction(item))
    }

    private func listRow(_ item: ShelfItem) -> some View {
        HStack(spacing: 8) {
            thumbnail(item.url).frame(width: 24, height: 24)
            Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let size = item.size {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(model.selection.contains(item.id) ? Color.accentColor.opacity(0.3) : .clear))
        .task { await model.loadThumbnail(item.url) }
        .overlay(itemInteraction(item))
    }

    private func itemInteraction(_ item: ShelfItem) -> Interaction {
        Interaction(model: model, urls: { model.targets(for: item) },
                    click: { model.select(item, extend: $0.contains(.command) || $0.contains(.shift)) },
                    doubleClick: { NSWorkspace.shared.open(item.url) })
    }

    private func thumbnail(_ url: URL) -> some View {
        Image(nsImage: model.thumbnails[url] ?? NSImage())
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    @ViewBuilder private var footer: some View {
        if model.busy > 0 {
            ProgressView().controlSize(.small)
        } else if let message = model.message {
            Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

// MARK: - AppKit interaction

/// Click, double-click, Space (Quick Look), right-click menu and drag-out for one shelf element.
/// AppKit, because a drag session reports where it ended: items dropped outside leave the shelf.
private struct Interaction: NSViewRepresentable {
    let model: ShelfModel
    let urls: () -> [URL]
    let click: (NSEvent.ModifierFlags) -> Void
    let doubleClick: () -> Void

    func makeNSView(context: Context) -> InteractionView { InteractionView() }

    func updateNSView(_ view: InteractionView, context: Context) {
        view.model = model
        view.urls = urls
        view.click = click
        view.doubleClick = doubleClick
    }

    final class InteractionView: NSView, NSDraggingSource {
        var model: ShelfModel?
        var urls: () -> [URL] = { [] }
        var click: (NSEvent.ModifierFlags) -> Void = { _ in }
        var doubleClick: () -> Void = {}
        private var downEvent: NSEvent?

        override var acceptsFirstResponder: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.makeKey()
            window?.makeFirstResponder(self)
            downEvent = event
            if event.clickCount == 2 { doubleClick() } else { click(event.modifierFlags) }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let down = downEvent else { return }
            let a = down.locationInWindow, b = event.locationInWindow
            guard hypot(a.x - b.x, a.y - b.y) > 3 else { return }
            downEvent = nil
            let items = urls().enumerated().map { index, url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let offset = CGFloat(min(index, 4)) * 4
                let p = convert(event.locationInWindow, from: nil)
                item.setDraggingFrame(CGRect(x: p.x - 24 + offset, y: p.y - 24 - offset, width: 48, height: 48),
                                      contents: model?.thumbnails[url] ?? NSWorkspace.shared.icon(forFile: url.path))
                return item
            }
            guard !items.isEmpty else { return }
            beginDraggingSession(with: items, event: event, source: self)
        }

        override func keyDown(with event: NSEvent) {
            if event.charactersIgnoringModifiers == " ", let model {
                model.preview = model.preview == nil ? urls().first : nil
            } else {
                super.keyDown(with: event)
            }
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard let model else { return nil }
            return ShelfMenu.build(urls(), model: model)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            guard operation != [], let model else { return }
            let urls = session.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
            model.draggedOut(urls)
        }
    }
}

/// The shelf's context menu (items and the header "…" button).
@MainActor
enum ShelfMenu {
    static func build(_ urls: [URL], model: ShelfModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(Item("Quick Look") { model.preview = urls.first })
        menu.addItem(Item("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) })
        let groups = ConvertAction.grouped(Converter.actions(for: urls, tools: .detect()))
        if !groups.isEmpty { menu.addItem(.separator()) }
        for group in groups {
            let sub = NSMenu()
            for action in group.actions { sub.addItem(Item(action.title) { model.run(action, on: urls) }) }
            let parent = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            parent.submenu = sub
            menu.addItem(parent)
        }
        menu.addItem(.separator())
        menu.addItem(Item(urls.count > 1 ? "Remove \(urls.count) From Shelf" : "Remove From Shelf") { model.remove(urls) })
        return menu
    }

    final class Item: NSMenuItem {
        private let handler: () -> Void

        init(_ title: String, _ handler: @escaping () -> Void) {
            self.handler = handler
            super.init(title: title, action: #selector(fire), keyEquivalent: "")
            target = self
        }

        required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

        @objc private func fire() { handler() }
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
