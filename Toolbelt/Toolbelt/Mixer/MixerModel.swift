import AppKit
import CoreAudio

@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsiblePID(_ pid: pid_t) -> pid_t

struct MixerApp: Identifiable, Equatable {
    let id: String // bundle ID of the responsible app
    let name: String
    let icon: NSImage?
    var processes: [AudioObjectID]
    var volume: Float
    var muted: Bool
    var gain: Float { muted ? 0 : volume }
}

/// Persists volume and mute per bundle ID.
struct MixerStore {
    let defaults: UserDefaults
    private let key = "mixer.apps"

    func settings(_ id: String) -> (volume: Float, muted: Bool) {
        let entry = (defaults.dictionary(forKey: key)?[id] as? [String: Any]) ?? [:]
        // Snapped on read too: a stored 99.8 % would otherwise keep a tap (and CPU) busy forever.
        return (MixerModel.snapped((entry["volume"] as? NSNumber)?.floatValue ?? 1), entry["muted"] as? Bool ?? false)
    }

    func save(_ id: String, volume: Float, muted: Bool) {
        var all = defaults.dictionary(forKey: key) ?? [:]
        if volume == 1, !muted { all[id] = nil } else { all[id] = ["volume": volume, "muted": muted] }
        defaults.set(all, forKey: key)
    }
}

/// Per-app volume. Event-driven through Core Audio property listeners (no polling). A tap exists only
/// for apps that need one: volume ≠ 100 %, muted, or while the popover shows meters.
@MainActor
final class MixerModel: ObservableObject {
    static let shared = MixerModel()

    @Published private(set) var apps: [MixerApp] = []
    @Published private(set) var levels: [String: Float] = [:]
    @Published private(set) var lastError: String?

    private let store = MixerStore(defaults: .standard)
    private var enabled = false
    private var metering = false
    private let engine = TapEngine()
    /// Latest taps from the engine; read here only for gain changes and meters.
    private var taps: [String: AppTap] = [:]
    private var watchedProcesses: Set<AudioObjectID> = []
    private var meterTimer: Timer?
    private var refreshScheduled = false
    private var permissionRequested = false

    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { MainActor.assumeIsolated { self?.scheduleRefresh() } }
    }

    private lazy var outputListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { MainActor.assumeIsolated { self?.outputChanged() } }
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        let system = AudioObjectID(kAudioObjectSystemObject)
        var list = CA.address(kAudioHardwarePropertyProcessObjectList)
        var output = CA.address(kAudioHardwarePropertyDefaultOutputDevice)
        if on {
            AudioObjectAddPropertyListenerBlock(system, &list, nil, listener)
            AudioObjectAddPropertyListenerBlock(system, &output, nil, outputListener)
            refresh()
        } else {
            AudioObjectRemovePropertyListenerBlock(system, &list, nil, listener)
            AudioObjectRemovePropertyListenerBlock(system, &output, nil, outputListener)
            for p in watchedProcesses { unwatch(p) }
            watchedProcesses = []
            owners = [:]
            engine.removeAll(wait: false)
            taps = [:]
            apps = []
        }
    }

    func setMetering(_ on: Bool) {
        metering = on
        meterTimer?.invalidate()
        meterTimer = nil
        if on, enabled {
            meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { _ in
                MainActor.assumeIsolated { MixerModel.shared.updateLevels() }
            }
        } else {
            levels = [:]
        }
        reconcileTaps()
    }

    /// Values within 4 % of 100 % snap to it, so "normal" is easy to hit and needs no tap.
    nonisolated static func snapped(_ volume: Float) -> Float { abs(volume - 1) < 0.04 ? 1 : volume }

    func setVolume(_ id: String, _ volume: Float) { update(id) { $0.volume = Self.snapped(volume) } }
    func toggleMute(_ id: String) { update(id) { $0.muted.toggle() } }

    /// Synchronously releases every tap (quit).
    func shutdown() {
        engine.removeAll(wait: true)
        taps = [:]
    }

    // MARK: Internals

    private func update(_ id: String, _ change: (inout MixerApp) -> Void) {
        guard let i = apps.firstIndex(where: { $0.id == id }) else { return }
        change(&apps[i])
        store.save(id, volume: apps[i].volume, muted: apps[i].muted)
        taps[id]?.gain = apps[i].gain // immediate, while the engine catches up
        reconcileTaps()
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in // coalesce listener storms
            MainActor.assumeIsolated {
                self?.refreshScheduled = false
                self?.refresh()
            }
        }
    }

    private struct Owner {
        let id: String
        let name: String
        let icon: NSImage?
    }

    /// Owning app per process object, resolved once: an object's PID never changes, so a refresh
    /// costs one HAL read (IsRunningOutput) per process. `nil` value = not a user-facing app.
    private var owners: [AudioObjectID: Owner?] = [:]

    private func owner(of obj: AudioObjectID) -> Owner? {
        if let cached = owners[obj] { return cached }
        var found: Owner?
        if let pid = CA.pid(obj), pid != getpid(), let app = Self.owningApp(pid), let id = app.bundleIdentifier {
            found = Owner(id: id, name: app.localizedName ?? id, icon: app.icon)
        }
        owners[obj] = .some(found)
        return found
    }

    private func refresh() {
        guard enabled else { return }
        let objects = CA.processObjects
        let current = Set(objects)
        for p in current.subtracting(watchedProcesses) { watch(p) }
        for p in watchedProcesses.subtracting(current) {
            unwatch(p)
            owners[p] = nil
        }
        watchedProcesses = current

        let previous = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var grouped: [String: MixerApp] = [:]
        var order: [String] = []
        for obj in objects {
            guard let owner = owner(of: obj), CA.isRunningOutput(obj) else { continue }
            if grouped[owner.id] == nil {
                let saved = previous[owner.id].map { ($0.volume, $0.muted) } ?? store.settings(owner.id)
                grouped[owner.id] = MixerApp(id: owner.id, name: owner.name, icon: owner.icon,
                                             processes: [], volume: saved.0, muted: saved.1)
                order.append(owner.id)
            }
            grouped[owner.id]?.processes.append(obj)
        }
        let next = order.compactMap { grouped[$0] }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard next != apps else { return } // nothing changed: no UI update, no tap work
        apps = next
        reconcileTaps()
    }

    /// The user-facing app behind an audio process (e.g. Safari for a WebContent helper).
    private static func owningApp(_ pid: pid_t) -> NSRunningApplication? {
        let owner = responsiblePID(pid)
        for candidate in [owner, pid] where candidate > 0 {
            if let app = NSRunningApplication(processIdentifier: candidate), app.bundleIdentifier != nil,
               app.activationPolicy != .prohibited {
                return app
            }
        }
        return nil
    }

    /// `IsRunningOutput` itself never notifies (verified: a new process goes 0 → 1 silently), but
    /// `IsRunning` and `Devices` change at the same moments, so watch those and re-read output state.
    private static let watchedSelectors = [kAudioProcessPropertyIsRunning, kAudioProcessPropertyDevices]

    private func watch(_ p: AudioObjectID) {
        for selector in Self.watchedSelectors {
            var addr = CA.address(selector)
            AudioObjectAddPropertyListenerBlock(p, &addr, nil, listener)
        }
    }

    private func unwatch(_ p: AudioObjectID) {
        for selector in Self.watchedSelectors {
            var addr = CA.address(selector)
            AudioObjectRemovePropertyListenerBlock(p, &addr, nil, listener)
        }
    }

    private func outputChanged() {
        reconcileTaps(rebuild: true) // taps are bound to the old device
    }

    private func reconcileTaps(rebuild: Bool = false) {
        let wanted = apps.filter { enabled && (metering || $0.gain != 1) }
        if !wanted.isEmpty {
            switch AudioCaptureTCC.status() {
            case .denied:
                lastError = "Allow Toolbelt in System Audio Recording to change app volumes."
                engine.reconcile([]) { [weak self] r in MainActor.assumeIsolated { self?.taps = r.taps } }
                return
            case .unknown where !permissionRequested:
                permissionRequested = true
                Permissions.shared.requestAudio { [weak self] _ in self?.reconcileTaps() }
                return
            default:
                break
            }
        }
        let wants = wanted.map { TapEngine.Want(id: $0.id, name: $0.name, processes: $0.processes, gain: $0.gain) }
        engine.reconcile(wants, rebuild: rebuild) { [weak self] result in
            MainActor.assumeIsolated {
                self?.taps = result.taps
                self?.lastError = result.errors.first
            }
        }
    }

    private func updateLevels() {
        var next = levels
        for (id, tap) in taps {
            let peak = min(tap.takePeak(), 1)
            next[id] = max(peak, (levels[id] ?? 0) * 0.75) // fast attack, smooth release
        }
        let changed = next.contains { abs($0.value - (levels[$0.key] ?? 0)) > 0.01 }
        if changed { levels = next }
    }
}
