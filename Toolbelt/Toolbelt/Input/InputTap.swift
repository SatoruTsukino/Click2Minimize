import AppKit

/// The one event tap Toolbelt installs. Its mask covers only the events the enabled features need,
/// and it is removed entirely when none are on (ADR-008).
@MainActor
final class InputTap {
    static let shared = InputTap()

    struct Features: Equatable {
        var dockClick = false      // left clicks on the Dock (minimize / hide / Finder alternate)
        var middle = false         // middle-button features (Dock quit, middle-drag)
        var trackpadPress = false  // three-finger press becomes a middle click
        var switcher = false       // ⌘⇥ replacement

        var isEmpty: Bool { !dockClick && !middle && !trackpadPress && !switcher }
    }

    nonisolated static func mask(for f: Features) -> CGEventMask {
        var types: [CGEventType] = []
        if f.dockClick || f.switcher { types += [.leftMouseDown, .leftMouseUp] }
        if f.trackpadPress { types += [.leftMouseDown, .leftMouseDragged, .leftMouseUp] }
        if f.middle || f.trackpadPress || f.switcher { types += [.otherMouseDown, .otherMouseDragged, .otherMouseUp] }
        if f.switcher { types += [.keyDown, .flagsChanged] }
        return types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private(set) var features = Features()
    private var swallowLeftUp = false

    var isRunning: Bool { tap != nil }

    /// Installs, rebuilds or removes the tap. Returns false when Accessibility is not granted.
    @discardableResult
    func update(_ f: Features) -> Bool {
        if f == features, tap != nil || f.isEmpty { return true }
        stop()
        features = f
        guard !f.isEmpty else { return true }
        guard AXIsProcessTrusted() else { return false }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: Self.mask(for: f),
                                          callback: { _, type, event, _ in
                                              MainActor.assumeIsolated { InputTap.shared.handle(type, event) }
                                          }, userInfo: nil) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        swallowLeftUp = false
    }

    private func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(e)
        default:
            break
        }
        if Synth.isOwn(e) { return Unmanaged.passUnretained(e) }
        return consumed(type, e) ? nil : Unmanaged.passUnretained(e)
    }

    private func consumed(_ type: CGEventType, _ e: CGEvent) -> Bool {
        let f = features
        switch type {
        case .keyDown, .flagsChanged:
            return f.switcher && AppSwitcher.shared.handleKey(type, e)
        case .leftMouseDown:
            if f.switcher, AppSwitcher.shared.isVisible {
                AppSwitcher.shared.handleClick(at: e.location)
                swallowLeftUp = true
                return true
            }
            if f.trackpadPress, MiddleButton.shared.trackpadDown(e) { return true }
            if f.dockClick, DockClick.shared.handleDown(e) {
                swallowLeftUp = true
                return true
            }
            return false
        case .leftMouseDragged:
            return MiddleButton.shared.trackpadDragged(e)
        case .leftMouseUp:
            if MiddleButton.shared.trackpadUp(e) { return true }
            if swallowLeftUp {
                swallowLeftUp = false
                return true
            }
            return false
        case .otherMouseDown, .otherMouseDragged, .otherMouseUp:
            return MiddleButton.shared.handle(type, e)
        default:
            return false
        }
    }
}
