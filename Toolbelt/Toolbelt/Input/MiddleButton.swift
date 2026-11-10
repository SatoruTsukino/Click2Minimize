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
        if let m = Synth.middle(.otherMouseDown, at: e.location, template: e) { Synth.post(m) }
        return true
    }

    func trackpadDragged(_ e: CGEvent) -> Bool {
        guard convertingTrackpad else { return false }
        if let m = Synth.middle(.otherMouseDragged, at: e.location, template: e) { Synth.post(m) }
        return true
    }

    func trackpadUp(_ e: CGEvent) -> Bool {
        guard convertingTrackpad else { return false }
        convertingTrackpad = false
        if let m = Synth.middle(.otherMouseUp, at: e.location, template: e) { Synth.post(m) }
        return true
    }

    /// A light three-finger tap (Lighter mode): a full middle click at the pointer.
    func tap() {
        let p = Synth.cursor
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            if let m = Synth.middle(type, at: p) { Synth.post(m) }
        }
    }
}
