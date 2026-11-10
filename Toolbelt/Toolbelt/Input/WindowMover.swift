import ApplicationServices
import Foundation

/// Drags one window at a time (ported from Click2Minimize 3.0). Callers pass the offset from where the
/// drag started. Accessibility writes run on a background queue and only the newest position is sent,
/// so a slow app never backs up the event tap and the window never jumps from re-reading a stale position.
@MainActor
final class WindowMover {
    static let shared = WindowMover()

    private nonisolated let queue = DispatchQueue(label: "io.github.satorutsukino.Toolbelt.window-mover", qos: .userInteractive)
    private nonisolated let state = State()
    private var origin = CGPoint.zero
    private(set) var isMoving = false

    /// Guarded window + pending position shared with the writer queue.
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var window: AXUIElement?
        var pending: CGPoint?
        var writing = false
    }

    /// Starts moving `w`. Returns false if its position can't be read.
    @discardableResult
    func begin(_ w: AXUIElement) -> Bool {
        guard let p = AX.position(w) else { return false }
        origin = p
        state.lock.withLock {
            state.window = w
            state.pending = nil
        }
        isMoving = true
        return true
    }

    func move(to offset: CGVector) {
        guard isMoving else { return }
        let target = CGPoint(x: (origin.x + offset.dx).rounded(), y: (origin.y + offset.dy).rounded())
        let start: Bool = state.lock.withLock {
            state.pending = target
            defer { state.writing = true }
            return !state.writing
        }
        if start {
            let state = self.state
            queue.async { Self.drain(state) }
        }
    }

    /// Ends the drag; the last pending position is still written.
    func end() { isMoving = false }

    private nonisolated static func drain(_ state: State) {
        while true {
            let next: (AXUIElement, CGPoint)? = state.lock.withLock {
                guard let w = state.window, let p = state.pending else {
                    state.writing = false
                    return nil
                }
                state.pending = nil
                return (w, p)
            }
            guard let (w, p) = next else { return }
            AX.setPosition(w, p)
        }
    }

    /// A middle press becomes a window drag only past this distance, so plain clicks stay clicks.
    nonisolated static let dragThreshold: CGFloat = 4

    nonisolated static func isDrag(from a: CGPoint, to b: CGPoint) -> Bool {
        hypot(b.x - a.x, b.y - a.y) > dragThreshold
    }
}
