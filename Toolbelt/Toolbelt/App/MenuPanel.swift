import AppKit
import SwiftUI

/// Toolbelt's menu: a floating panel pinned by its TOP edge, so it grows downward as the
/// mixer list changes. (An NSPopover anchored to a status item that macOS hides — Menu Bar
/// settings or the notch — sits at the screen top and grows upward, off screen.)
final class MenuPanel: NSPanel, NSWindowDelegate {
    /// Screen y of the top edge, and preferred center x; set by `show`.
    var anchor: (top: CGFloat, midX: CGFloat)?
    var onClose: (() -> Void)?

    init<Content: View>(rootView: Content) {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .statusBar
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        delegate = self

        // The hosting controller drives the panel size from SwiftUI's preferred size.
        let host = NSHostingController(rootView: rootView
            .background(MenuMaterial())
            .clipShape(RoundedRectangle(cornerRadius: 12)))
        host.sizingOptions = [.preferredContentSize]
        contentViewController = host
    }

    override var canBecomeKey: Bool { true }

    /// Where the panel's top-centre goes: under the status icon when it is on screen, otherwise
    /// the top-right corner under the menu bar of the screen with the pointer.
    static func anchor(icon: CGRect?, screens: [CGRect], visible: CGRect) -> (top: CGFloat, midX: CGFloat) {
        if let icon, screens.contains(where: { $0.intersects(icon) }) {
            return (icon.minY - 4, icon.midX)
        }
        return (visible.maxY - 4, visible.maxX - 168)
    }

    func show(below icon: CGRect?) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        anchor = Self.anchor(icon: icon, screens: NSScreen.screens.map(\.frame), visible: screen?.visibleFrame ?? .zero)
        setFrame(frame, display: false) // place with the current size
        makeKeyAndOrderFront(nil)
    }

    override func setFrame(_ rect: NSRect, display: Bool) {
        super.setFrame(pinned(rect), display: display)
    }

    override func setFrame(_ rect: NSRect, display: Bool, animate: Bool) {
        super.setFrame(pinned(rect), display: display, animate: animate)
    }

    /// Keeps the top edge fixed and the panel on screen horizontally whatever size SwiftUI asks for.
    func pinned(_ rect: NSRect) -> NSRect {
        guard let anchor else { return rect }
        var r = rect
        r.origin.y = anchor.top - r.height
        r.origin.x = anchor.midX - r.width / 2
        if let v = (NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.top - 1)) } ?? NSScreen.main)?.visibleFrame {
            r.origin.x = min(max(r.minX, v.minX + 8), v.maxX - r.width - 8)
        }
        return r
    }

    override func cancelOperation(_ sender: Any?) { close() } // Esc

    func windowDidResignKey(_ notification: Notification) { close() } // click away, like a menu

    override func close() {
        guard isVisible else { return }
        super.close()
        onClose?()
    }
}

private struct MenuMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .menu
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
