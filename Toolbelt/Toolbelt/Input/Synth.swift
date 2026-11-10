import CoreGraphics

/// Posting synthesized mouse events. Events Toolbelt replays carry `marker`, so the input tap
/// lets them through untouched instead of handling them a second time.
enum Synth {
    static let marker: Int64 = 0x546F_6F6C // "Tool"

    static var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    static func isOwn(_ e: CGEvent) -> Bool { e.getIntegerValueField(.eventSourceUserData) == marker }

    /// A middle-button event at `p`, copying click state and flags from `template`.
    static func middle(_ type: CGEventType, at p: CGPoint, template: CGEvent? = nil) -> CGEvent? {
        let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .center)
        if let t = template {
            e?.flags = t.flags
            e?.setIntegerValueField(.mouseEventClickState, value: max(1, t.getIntegerValueField(.mouseEventClickState)))
        } else {
            e?.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        return e
    }

    /// Posts an event that features should see (e.g. a middle click made from a trackpad gesture).
    static func post(_ e: CGEvent) { e.post(tap: .cghidEventTap) }

    /// Posts an event that must reach apps unchanged.
    static func replay(_ e: CGEvent) {
        e.setIntegerValueField(.eventSourceUserData, value: marker)
        e.post(tap: .cghidEventTap)
    }
}
