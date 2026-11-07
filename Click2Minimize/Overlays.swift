import Cocoa

/// Translucent preview of where a snapped window will land.
final class SnapOverlay {
    static let shared = SnapOverlay()

    private lazy var window: NSWindow = {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 12
        v.layer?.borderWidth = 2
        w.contentView = v
        return w
    }()

    func show(_ globalFrame: CGRect) {
        let frame = ScreenGeometry.toCocoa(globalFrame).insetBy(dx: 6, dy: 6)
        if let layer = window.contentView?.layer {
            layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        }
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    func hide() { window.orderOut(nil) }
}
