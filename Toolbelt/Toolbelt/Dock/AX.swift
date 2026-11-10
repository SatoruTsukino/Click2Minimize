import ApplicationServices
import AppKit

/// Thin Accessibility helpers. All calls use a short messaging timeout so the event tap never stalls.
enum AX {
    static let systemWide: AXUIElement = {
        let el = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(el, 0.25)
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

    static func application(_ pid: pid_t) -> AXUIElement {
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 0.25)
        return el
    }

    static func subrole(_ el: AXUIElement) -> String { get(el, kAXSubroleAttribute) ?? "" }
    static func parent(_ el: AXUIElement) -> AXUIElement? { get(el, kAXParentAttribute) }
    static func windows(_ pid: pid_t) -> [AXUIElement] { get(application(pid), kAXWindowsAttribute) ?? [] }
    static func isMinimized(_ w: AXUIElement) -> Bool { get(w, kAXMinimizedAttribute) ?? false }
    static func isFullscreen(_ w: AXUIElement) -> Bool { get(w, "AXFullScreen") ?? false }

    /// Standard, on-screen (not minimized) windows of an app.
    static func visibleWindows(_ pid: pid_t) -> [AXUIElement] {
        windows(pid).filter { subrole($0) == kAXStandardWindowSubrole && !isMinimized($0) }
    }

    /// The window containing the element under `p` (top-left global coordinates).
    static func window(at p: CGPoint) -> AXUIElement? {
        guard var el = element(at: p) else { return nil }
        for _ in 0..<12 {
            if (get(el, kAXRoleAttribute) as String?) == kAXWindowRole { return el }
            if let w: AXUIElement = get(el, kAXWindowAttribute) { return w }
            guard let parent = parent(el) else { return nil }
            el = parent
        }
        return nil
    }

    static func position(_ w: AXUIElement) -> CGPoint? {
        guard let v: AXValue = get(w, kAXPositionAttribute) else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v, .cgPoint, &p) ? p : nil
    }

    @discardableResult
    static func setPosition(_ w: AXUIElement, _ p: CGPoint) -> Bool {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return set(w, kAXPositionAttribute, v)
    }
}
