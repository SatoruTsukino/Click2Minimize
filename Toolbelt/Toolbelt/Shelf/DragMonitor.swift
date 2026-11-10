import AppKit

/// Watches system-wide drags that carry content and opens the shelf when the pointer is shaken.
/// Mouse monitors need no Accessibility permission. A drag carries content when the drag pasteboard
/// changed after mouse-down. Only `leftMouseDragged` does work, and only during a content drag.
@MainActor
final class DragMonitor {
    static let shared = DragMonitor()

    private var monitors: [Any] = []
    private let dragPasteboard = NSPasteboard(name: .drag)
    /// Drag pasteboard change count as last seen. Only drags change it, so it is refreshed while
    /// probing drags, and a plain click costs no pasteboard IPC.
    private lazy var lastCount = dragPasteboard.changeCount
    private var isContentDrag = false
    private var shownThisDrag = false
    private var shake = ShakeDetector()
    /// Drag events seen this press. Content drags write the drag pasteboard within the first few
    /// events, so after `probeLimit` an ordinary drag (window move, selection) costs nothing more.
    private var probes = 0
    private let probeLimit = 30

    func start() {
        guard monitors.isEmpty else { return }
        func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping @MainActor () -> Void) {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in MainActor.assumeIsolated(handler) }) {
                monitors.append(m)
            }
            if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { e in
                MainActor.assumeIsolated(handler)
                return e
            }) { monitors.append(m) }
        }
        add(.leftMouseDown) { [weak self] in self?.mouseDown() }
        add(.leftMouseDragged) { [weak self] in self?.mouseDragged() }
        add(.leftMouseUp) { [weak self] in self?.mouseUp() } // flag check only, no IPC
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func mouseDown() {
        RadialController.shared.dragEnded() // in case the last drag's mouse-up never reached us
        isContentDrag = false
        shownThisDrag = false
        probes = 0
        shake = ShakeDetector(tuning: .for(Prefs.shared.shakeSensitivity))
    }

    private func mouseUp() {
        guard isContentDrag else { return }
        isContentDrag = false
        // Let a drop on a petal land before the ring goes away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { RadialController.shared.dragEnded() }
    }

    private func mouseDragged() {
        guard !shownThisDrag else { return }
        if !isContentDrag {
            guard probes < probeLimit else { return }
            probes += 1
            let count = dragPasteboard.changeCount
            guard count != lastCount else { return }
            lastCount = count
            guard Ingest.canRead(dragPasteboard) else { return }
            isContentDrag = true
            RadialController.shared.dragBegan(dragPasteboard)
        }
        let point = NSEvent.mouseLocation
        if Prefs.shared.shakeShelf, shake.add(point, at: ProcessInfo.processInfo.systemUptime) {
            shownThisDrag = true
            ShelfController.shared.show(at: point)
        }
    }
}
