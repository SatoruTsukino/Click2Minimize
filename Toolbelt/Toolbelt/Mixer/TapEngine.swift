import CoreAudio
import Foundation

/// Owns every `AppTap` and does all HAL create/destroy work on one serial queue, so a slow
/// Core Audio call never stalls the menu. Results are handed back to the main thread.
final class TapEngine: @unchecked Sendable {
    struct Want: Sendable {
        let id: String
        let name: String
        let processes: [AudioObjectID]
        let gain: Float
    }

    struct Result: Sendable {
        let taps: [String: AppTap]
        let errors: [String]
    }

    private let queue = DispatchQueue(label: "toolbelt.taps", qos: .userInitiated)
    private var taps: [String: AppTap] = [:] // queue only
    private var device: AudioObjectID?      // queue only

    /// Makes the set of taps match `wanted`. `rebuild` drops every tap first (output device changed).
    func reconcile(_ wanted: [Want], rebuild: Bool = false, done: @escaping @Sendable (Result) -> Void) {
        queue.async { [self] in
            let current = CA.defaultOutputDevice
            if rebuild || current != device {
                taps.values.forEach { $0.invalidate() }
                taps = [:]
                device = current
            }
            let ids = Set(wanted.map(\.id))
            for (id, tap) in taps where !ids.contains(id) {
                tap.invalidate()
                taps[id] = nil
            }
            var errors: [String] = []
            if let device {
                for want in wanted {
                    if let tap = taps[want.id], Set(tap.processes) == Set(want.processes) {
                        tap.gain = want.gain
                        continue
                    }
                    taps[want.id]?.invalidate()
                    taps[want.id] = nil
                    do {
                        taps[want.id] = try AppTap(processes: want.processes, gain: want.gain, outputDevice: device)
                    } catch {
                        errors.append("\(want.name): \(error.localizedDescription)")
                    }
                }
            }
            let result = Result(taps: taps, errors: errors)
            DispatchQueue.main.async { done(result) }
        }
    }

    /// Releases every tap. `wait` blocks until done (used at quit so no app stays muted).
    func removeAll(wait: Bool) {
        let work = { [self] in
            taps.values.forEach { $0.invalidate() }
            taps = [:]
        }
        if wait { queue.sync(execute: work) } else { queue.async(execute: work) }
    }
}
