import Carbon.HIToolbox
import Cocoa

/// Value stamped on every event Click2Minimize posts so its own tap ignores them.
let syntheticEventMarker: Int64 = 0x0C2B_0C2B

struct KeyShortcut: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt64

    static let relevantFlags: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    init(keyCode: UInt16, flags: CGEventFlags) {
        self.keyCode = keyCode
        modifiers = flags.intersection(Self.relevantFlags).rawValue
    }

    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }

    func matches(_ event: CGEvent) -> Bool {
        UInt16(event.getIntegerValueField(.keyboardEventKeycode)) == keyCode &&
            event.flags.intersection(Self.relevantFlags) == flags
    }

    var display: String {
        var s = ""
        if flags.contains(.maskControl) { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift) { s += "⇧" }
        if flags.contains(.maskCommand) { s += "⌘" }
        return s + KeyShortcut.keyName(keyCode)
    }

    static func keyName(_ code: UInt16) -> String {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
            kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
            kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        ]
        if let s = special[Int(code)] { return s }
        return layoutCharacter(code)?.uppercased() ?? "#\(code)"
    }

    /// Character the key produces in the current keyboard layout.
    private static func layoutCharacter(_ code: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var len = 0
            let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
            guard status == noErr, len > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: len)
        }
    }
}

/// Posts synthetic keyboard, media-key and mouse events.
enum Synth {
    private static let source = CGEventSource(stateID: .hidSystemState)

    static func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        event.post(tap: .cghidEventTap)
    }

    static func key(_ code: Int, flags: CGEventFlags = []) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else { continue }
            e.flags = flags
            post(e)
        }
    }

    static func shortcut(_ s: KeyShortcut) { key(Int(s.keyCode), flags: s.flags) }

    /// Closes an open context menu (or any popup that honours Escape).
    static func escape() { key(kVK_Escape) }

    enum MediaKey: Int { case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3 }

    /// Media keys go through the system so the native volume / brightness HUD appears.
    static func media(_ key: MediaKey) {
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: (key.rawValue << 16) | (state << 8), data2: -1)
            if let cg = event?.cgEvent { post(cg) }
        }
    }

    /// Re-posts a copy of an event that was held back by the tap.
    static func replay(_ event: CGEvent) {
        if let copy = event.copy() { post(copy) }
    }

    static func mouse(_ type: CGEventType, at point: CGPoint, button: CGMouseButton, template: CGEvent? = nil) -> CGEvent? {
        let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        if let t = template { e?.setIntegerValueField(.mouseEventClickState, value: t.getIntegerValueField(.mouseEventClickState)) }
        return e
    }

    static var currentFlags: CGEventFlags { CGEventSource.flagsState(.combinedSessionState) }

    static var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }
}

/// Private CoreGraphics / CoreDock entry points, resolved at runtime so a
/// missing symbol degrades gracefully instead of failing to launch.
enum SystemPrivate {
    private static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT

    private typealias SymbolicHotKeyFn = @convention(c) (Int32, Bool) -> Int32
    private typealias CoreDockNotifyFn = @convention(c) (CFString, Int) -> Void

    /// Enables or disables the native ⌘⇥ / ⌘⇧⇥ hotkeys (ids 1 and 2).
    static func setNativeCommandTab(enabled: Bool) {
        guard let sym = dlsym(defaultHandle, "CGSSetSymbolicHotKeyEnabled") else { return }
        let fn = unsafeBitCast(sym, to: SymbolicHotKeyFn.self)
        _ = fn(1, enabled)
        _ = fn(2, enabled)
    }

    /// Sends a Dock notification such as "com.apple.expose.awake".
    @discardableResult
    static func coreDock(_ name: String) -> Bool {
        guard let sym = dlsym(defaultHandle, "CoreDockSendNotification") else { return false }
        unsafeBitCast(sym, to: CoreDockNotifyFn.self)(name as CFString, 0)
        return true
    }
}
