import AppKit
import ApplicationServices
import ServiceManagement

/// Accessibility, system-audio capture and login-item state, refreshed on demand (never polled).
@MainActor
final class Permissions: ObservableObject {
    static let shared = Permissions()

    enum Audio { case granted, denied, unknown }

    @Published private(set) var accessibility = AXIsProcessTrusted()
    @Published private(set) var audio: Audio = AudioCaptureTCC.status()
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    func refresh() {
        accessibility = AXIsProcessTrusted()
        audio = AudioCaptureTCC.status()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        open("Privacy_Accessibility")
    }

    func openAudioSettings() { open("Privacy_AudioCapture") }

    func requestAudio(_ done: @escaping @MainActor (Bool) -> Void) {
        AudioCaptureTCC.request { granted in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.refresh()
                    done(granted)
                }
            }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Toolbelt: launch at login failed: \(error.localizedDescription)")
        }
        refresh()
    }

    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// System-audio capture consent. There is no public preflight API, so this uses the TCC
/// framework's `TCCAccessPreflight` / `TCCAccessRequest` when available and reports `.unknown` otherwise.
/// Knowing about a denial matters: a tap without consent records silence while muting the app.
enum AudioCaptureTCC {
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    static func status() -> Permissions.Audio {
        guard let sym = dlsym(handle, "TCCAccessPreflight") else { return .unknown }
        switch unsafeBitCast(sym, to: Preflight.self)(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .unknown
        }
    }

    static func request(_ done: @escaping (Bool) -> Void) {
        guard let sym = dlsym(handle, "TCCAccessRequest") else { return done(true) }
        unsafeBitCast(sym, to: Request.self)(service, nil, done)
    }
}
