import Cocoa
import notify
import os.log

private let log = Logger(subsystem: "com.idemfactor.Click2Minimize", category: "system")

/// macOS Game Mode, observed through its (undocumented) Darwin notification.
enum GameMode {
    private static let name = "com.apple.system.game_mode_status_changed"
    private static let invalidToken: Int32 = -1   // NOTIFY_TOKEN_INVALID
    private static let statusOK: UInt32 = 0       // NOTIFY_STATUS_OK
    private static var token: Int32 = invalidToken
    private(set) static var isActive = false

    static func start(onChange: @escaping () -> Void) {
        guard token == invalidToken else { return }
        let status = notify_register_dispatch(name, &token, .main) { t in
            isActive = state(t)
            log.info("Game Mode \(isActive ? "on" : "off", privacy: .public)")
            onChange()
        }
        if status == statusOK {
            isActive = state(token)
        } else {
            log.error("could not observe Game Mode (status \(status))")
        }
    }

    private static func state(_ t: Int32) -> Bool {
        var value: UInt64 = 0
        return notify_get_state(t, &value) == statusOK && value != 0
    }
}

/// The system trackpad gesture settings that collide with Click2Minimize's own
/// gestures. Written to the trackpad preference domains and applied live with
/// the private `activateSettings` tool, as System Settings itself does.
enum SystemTrackpad {
    private static let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
    private static let globalKeys = [
        "TrackpadThreeFingerHorizSwipeGesture": "com.apple.trackpad.threeFingerHorizSwipeGesture",
        "TrackpadThreeFingerVertSwipeGesture": "com.apple.trackpad.threeFingerVertSwipeGesture",
        "TrackpadFourFingerHorizSwipeGesture": "com.apple.trackpad.fourFingerHorizSwipeGesture",
        "TrackpadFourFingerVertSwipeGesture": "com.apple.trackpad.fourFingerVertSwipeGesture",
    ]

    static func value(_ key: String) -> Int {
        for d in domains {
            if let v = CFPreferencesCopyAppValue(key as CFString, d as CFString) as? Int { return v }
        }
        return 0
    }

    private static func write(_ values: [String: Int]) {
        for (key, v) in values {
            for d in domains {
                CFPreferencesSetValue(key as CFString, v as CFNumber, d as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            }
            if let global = globalKeys[key] {
                CFPreferencesSetValue(global as CFString, v as CFNumber, kCFPreferencesAnyApplication,
                                      kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
            }
        }
        domains.forEach { CFPreferencesSynchronize($0 as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) }
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        apply()
    }

    private static func apply() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        p.arguments = ["-u"]
        do { try p.run() } catch { log.error("activateSettings failed: \(error.localizedDescription, privacy: .public)") }
    }

    static var threeFingerDrag: Bool { value("TrackpadThreeFingerDrag") != 0 }
    static var threeFingerSwipesUsedBySystem: Bool {
        value("TrackpadThreeFingerHorizSwipeGesture") != 0 || value("TrackpadThreeFingerVertSwipeGesture") != 0
    }
    static var fourFingerVerticalUsedBySystem: Bool { value("TrackpadFourFingerVertSwipeGesture") != 0 }

    /// Native three-finger drag. Like System Settings, turning it on moves the
    /// system's swipes to four fingers.
    static func setThreeFingerDrag(_ on: Bool) {
        var v: [String: Int] = ["TrackpadThreeFingerDrag": on ? 1 : 0]
        if on {
            v["TrackpadThreeFingerHorizSwipeGesture"] = 0
            v["TrackpadThreeFingerVertSwipeGesture"] = 0
            v["TrackpadFourFingerHorizSwipeGesture"] = 2
            v["TrackpadFourFingerVertSwipeGesture"] = 2
        }
        write(v)
    }

    /// Frees 3-finger swipes for Click2Minimize: system swipes move to four fingers.
    static func handThreeFingerSwipesToClick2Minimize() {
        write(["TrackpadThreeFingerDrag": 0,
               "TrackpadThreeFingerHorizSwipeGesture": 0, "TrackpadThreeFingerVertSwipeGesture": 0,
               "TrackpadFourFingerHorizSwipeGesture": 2,
               "TrackpadFourFingerVertSwipeGesture": Pref.overviewFourFinger.bool ? 0 : 2])
    }

    /// Frees the 4-finger up / down swipe (Mission Control / App Exposé) for the window overview.
    static func handFourFingerVerticalToClick2Minimize() {
        write(["TrackpadFourFingerVertSwipeGesture": 0])
    }
}

/// System alert (beep) volume, 0...100.
enum AlertVolume {
    static func read(completion: @escaping (Double) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let out = osascript("alert volume of (get volume settings)")
            let value = Double(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 100
            DispatchQueue.main.async { completion(value) }
        }
    }

    static func set(_ value: Double) {
        let v = Int(max(0, min(100, value)))
        DispatchQueue.global(qos: .utility).async { _ = osascript("set volume alert volume \(v)") }
    }

    /// `set volume` is a Standard Addition: it runs in the osascript process and needs no Automation permission.
    private static func osascript(_ source: String) -> String {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
