import ApplicationServices
import Cocoa

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Thin Accessibility helpers.
enum AX {
    static let systemWide: AXUIElement = {
        let el = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(el, 0.25) // never stall the event tap for long
        return el
    }()

    static func get<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        return ref as? T
    }

    @discardableResult
    static func set(_ el: AXUIElement, _ attr: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(el, attr as CFString, value) == .success
    }

    static func element(at p: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &el) == .success else { return nil }
        return el
    }

    static func pid(_ el: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        return pid
    }

    static func role(_ el: AXUIElement) -> String { get(el, kAXRoleAttribute) ?? "" }
    static func subrole(_ el: AXUIElement) -> String { get(el, kAXSubroleAttribute) ?? "" }
    static func parent(_ el: AXUIElement) -> AXUIElement? { get(el, kAXParentAttribute) }
    static func children(_ el: AXUIElement) -> [AXUIElement] { get(el, kAXChildrenAttribute) ?? [] }

    static func actions(_ el: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    @discardableResult
    static func perform(_ el: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(el, action as CFString) == .success
    }

    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let posVal: AXValue = get(el, kAXPositionAttribute),
              let sizeVal: AXValue = get(el, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(posVal, .cgPoint, &p)
        AXValueGetValue(sizeVal, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    static func setPosition(_ el: AXUIElement, _ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) { set(el, kAXPositionAttribute, v) }
    }

    static func setSize(_ el: AXUIElement, _ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) { set(el, kAXSizeAttribute, v) }
    }

    /// Position, then size, then position again: apps that clamp size to the
    /// current screen otherwise end up misplaced when moving across displays.
    static func setFrame(_ el: AXUIElement, _ f: CGRect) {
        setPosition(el, f.origin)
        setSize(el, f.size)
        setPosition(el, f.origin)
    }

    static func windowID(_ el: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(el, &id) == .success && id != 0 ? id : nil
    }

    static func application(_ pid: pid_t) -> AXUIElement {
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 0.5)
        return el
    }

    static func windows(_ pid: pid_t) -> [AXUIElement] { get(application(pid), kAXWindowsAttribute) ?? [] }

    static func isStandardWindow(_ w: AXUIElement) -> Bool {
        role(w) == kAXWindowRole && subrole(w) == kAXStandardWindowSubrole
    }

    static func isMinimized(_ w: AXUIElement) -> Bool { get(w, kAXMinimizedAttribute) ?? false }
    static func isFullscreen(_ w: AXUIElement) -> Bool { get(w, "AXFullScreen") ?? false }
    static func title(_ w: AXUIElement) -> String { get(w, kAXTitleAttribute) ?? "" }

    /// The top-level window containing the element under a point.
    static func window(at p: CGPoint) -> AXUIElement? {
        guard var el = element(at: p) else { return nil }
        if pid(el) == ProcessInfo.processInfo.processIdentifier { return nil }
        if role(el) == kAXWindowRole { return el }
        if let w: AXUIElement = get(el, kAXWindowAttribute) { return w }
        for _ in 0..<20 {
            guard let p = parent(el) else { return nil }
            if role(p) == kAXWindowRole { return p }
            el = p
        }
        return nil
    }

    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return get(application(app.processIdentifier), kAXFocusedWindowAttribute)
    }

    static func isTrusted() -> Bool { AXIsProcessTrusted() }

    static func promptForTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

/// Screen geometry in the y-down global coordinates used by AX and CGEvent.
enum ScreenGeometry {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func toGlobal(_ r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func toCocoa(_ r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func screen(containing p: CGPoint) -> NSScreen? {
        NSScreen.screens.first { toGlobal($0.frame).contains(p) }
    }

    /// Screen that holds most of a frame.
    static func screen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            area(toGlobal(a.frame).intersection(frame)) < area(toGlobal(b.frame).intersection(frame))
        }
    }

    static func visibleFrame(_ s: NSScreen) -> CGRect { toGlobal(s.visibleFrame) }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
}
