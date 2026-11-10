import AppKit

/// Middle-button features (ADR-008): quitting the app under a Dock icon, middle-dragging windows,
/// quitting a switcher row, and turning a three-finger trackpad press into a middle click.
@MainActor
final class MiddleButton {
    static let shared = MiddleButton()

    private struct Press {
        var start = CGPoint.zero
        var held: CGEvent?        // the original down, replayed if the press turns out to be a plain click
        var moving = false
        var swallow = false       // handled on down; drop the rest of this press
    }

    private var press: Press?
    private var convertingTrackpad = false

    // MARK: Middle button

    func handle(_ type: CGEventType, _ e: CGEvent) -> Bool {
        guard e.getIntegerValueField(.mouseEventButtonNumber) == 2 else { return false }
        let prefs = Prefs.shared
        let p = e.location
        switch type {
        case .otherMouseDown:
            press = nil
            if AppSwitcher.shared.isVisible {
                AppSwitcher.shared.quitRow(at: p)
                press = Press(start: p, swallow: true)
                return true
            }
            if prefs.dockMiddleQuit, DockClick.shared.quitApp(at: p) {
                press = Press(start: p, swallow: true)
                return true
            }
            guard prefs.middleDragMove else { return false }
            press = Press(start: p, held: e.copy())
            return true
        case .otherMouseDragged:
            guard var current = press else { return false }
            if current.swallow { return true }
            if !current.moving, WindowMover.isDrag(from: current.start, to: p),
               let w = AX.window(at: current.start), !AX.isFullscreen(w), WindowMover.shared.begin(w) {
                current.moving = true
                // Tactile confirmation that the window is grabbed (R5.7); only a trackpad can play it.
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            if current.moving {
                WindowMover.shared.move(to: CGVector(dx: p.x - current.start.x, dy: p.y - current.start.y))
            }
            press = current
            return true
        default: // up
            guard let current = press else { return false }
            press = nil
            if current.swallow { return true }
            if current.moving {
                WindowMover.shared.end()
                return true
            }
            // A plain middle click: let the app have it after all.
            if let held = current.held { Synth.replay(held) }
            if let up = e.copy() { Synth.replay(up) }
            return true
        }
    }

    // MARK: Trackpad three-finger press → middle button (MIDL-02)

    func trackpadDown(_ e: CGEvent) -> Bool {
        guard Trackpad.shared.pressIsMiddle else { return false }
        convertingTrackpad = true
        let start = e.location
        if let m = Synth.middle(.otherMouseDown, at: start, template: e) { Synth.post(m) }
        // Three pressed fingers don't move the pointer (R6.1): the fingers carry the pointer, and the
        // drag becomes middle-drag events, so window moving works exactly as with a mouse.
        _ = Self.warpSource
        CGAssociateMouseAndMouseCursorPosition(0)
        Trackpad.shared.beginFollow { offset in
            let p = CGPoint(x: start.x + offset.dx, y: start.y + offset.dy)
            CGWarpMouseCursorPosition(p)
            if let m = Synth.middle(.otherMouseDragged, at: p) { Synth.post(m) }
        }
        return true
    }

    func trackpadDragged(_ e: CGEvent) -> Bool {
        convertingTrackpad // the fingers drive the drag; swallow system drags meanwhile
    }

    func trackpadUp(_ e: CGEvent) -> Bool {
        guard convertingTrackpad else { return false }
        convertingTrackpad = false
        Trackpad.shared.endFollow()
        CGAssociateMouseAndMouseCursorPosition(1)
        if let m = Synth.middle(.otherMouseUp, at: Synth.cursor, template: e) { Synth.post(m) }
        return true
    }

    /// Lets the pointer be warped every frame without the system freezing it briefly after each warp.
    private static let warpSource: CGEventSource? = {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        return source
    }()

    /// A light three-finger tap (Lighter mode): a full middle click at the pointer.
    func tap() {
        let p = Synth.cursor
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            if let m = Synth.middle(type, at: p) { Synth.post(m) }
        }
    }
}
