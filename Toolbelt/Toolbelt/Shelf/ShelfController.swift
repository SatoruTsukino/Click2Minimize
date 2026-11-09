import AppKit
import SwiftUI

/// The single floating shelf. Non-activating: showing it never takes focus from the frontmost app.
@MainActor
final class ShelfController {
    static let shared = ShelfController()

    let model = ShelfModel()
    private lazy var panel: ShelfPanel = makePanel()
    private let size = CGSize(width: 300, height: 230)

    var isVisible: Bool { panel.isVisible }

    /// Shows the shelf centred on `point` (Cocoa screen coordinates). A visible shelf with items stays put.
    func show(at point: CGPoint) {
        if panel.isVisible, !model.items.isEmpty { return }
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var frame = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        if let v = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, v.minX), v.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, v.minY), v.maxY - frame.height)
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
        model.clear()
    }

    private func makePanel() -> ShelfPanel {
        let panel = ShelfPanel(contentRect: CGRect(origin: .zero, size: size),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let drop = DropView(model: model)
        let host = NSHostingView(rootView: ShelfView(model: model, close: { [weak self] in self?.close() }))
        host.translatesAutoresizingMaskIntoConstraints = false
        drop.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: drop.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: drop.trailingAnchor),
            host.topAnchor.constraint(equalTo: drop.topAnchor),
            host.bottomAnchor.constraint(equalTo: drop.bottomAnchor),
        ])
        panel.contentView = drop
        model.onEmptied = { [weak self] in self?.close() }
        return panel
    }
}

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// AppKit drop target: reads the pasteboard synchronously (more reliable than SwiftUI item providers,
/// and supports file promises from apps like Photos and Mail).
final class DropView: NSView {
    private let model: ShelfModel

    init(model: ShelfModel) {
        self.model = model
        super.init(frame: .zero)
        registerForDraggedTypes(Ingest.readableTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // A drag that started in this app (the shelf's own items) has a local source: ignore it.
        guard sender.draggingSource == nil else { return [] }
        model.isTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { model.isTargeted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        model.isTargeted = false
        let pb = sender.draggingPasteboard
        let urls = Ingest.read(pb)
        if !urls.isEmpty {
            model.add(urls)
            return true
        }
        let promises = Ingest.promises(pb)
        guard !promises.isEmpty else { return false }
        let folder = Ingest.newSlot()
        for promise in promises {
            promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: .main) { [weak self] url, error in
                guard error == nil else { return }
                MainActor.assumeIsolated { self?.model.add([url]) }
            }
        }
        return true
    }
}
