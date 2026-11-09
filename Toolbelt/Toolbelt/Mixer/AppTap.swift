import AudioToolbox
import CoreAudio
import Foundation

/// One app's audio, captured by a private process tap (which mutes the original) and played again
/// through a private aggregate device of the current output with a gain applied.
/// Created and invalidated on `TapEngine`'s queue; `gain` and `takePeak()` are safe from any thread.
final class AppTap: @unchecked Sendable {
    let processes: [AudioObjectID]
    let deviceUID: String
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    /// [0] gain, [1] peak since last read. Word-sized floats shared with the IO thread.
    private let state = UnsafeMutablePointer<Float>.allocate(capacity: 2)

    var gain: Float {
        get { state[0] }
        set { state[0] = newValue }
    }

    init(processes: [AudioObjectID], gain: Float, outputDevice: AudioObjectID) throws {
        self.processes = processes
        state[0] = gain
        state[1] = 0
        guard let uid = CA.string(outputDevice, kAudioDevicePropertyDeviceUID) else {
            state.deallocate() // init fails before deinit can run
            throw AudioError(what: "Output device", status: -1)
        }
        deviceUID = uid
        do { try start() } catch {
            invalidate()
            throw error
        }
    }

    deinit {
        invalidate()
        state.deallocate() // after the IOProc stopped; readers on the main thread hold `self`
    }

    private func start() throws {
        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true
        desc.name = "Toolbelt"
        try AudioError.check(AudioHardwareCreateProcessTap(desc, &tapID), "Create tap")

        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Toolbelt Mixer",
            kAudioAggregateDeviceUIDKey: "toolbelt.mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        try AudioError.check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregateID), "Create aggregate")

        let state = self.state
        try AudioError.check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            let peak = Gain.render(input: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)),
                                   output: UnsafeMutableAudioBufferListPointer(output), gain: state[0])
            if peak > state[1] { state[1] = peak }
        }, "Create IOProc")
        try AudioError.check(AudioDeviceStart(aggregateID, procID), "Start device")
    }

    /// Peak level since the last call.
    func takePeak() -> Float {
        let p = state[1]
        state[1] = 0
        return p
    }

    private var invalidated = false

    /// Stops rendering and releases the tap; the app's audio is unmuted as the tap goes away.
    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
    }
}
