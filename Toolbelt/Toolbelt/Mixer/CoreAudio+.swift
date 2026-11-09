import CoreAudio
import Foundation

/// Small typed wrappers over AudioObjectGetPropertyData.
enum CA {
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func value<T>(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
        var addr = address(selector)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, $0) }
        return status == noErr ? value : nil
    }

    static func array<T>(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector, _ zero: T) -> [T] {
        var addr = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var items = [T](repeating: zero, count: Int(size) / MemoryLayout<T>.stride)
        let status = items.withUnsafeMutableBytes { AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { return [] }
        return Array(items.prefix(Int(size) / MemoryLayout<T>.stride))
    }

    static func string(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &ref) == noErr else { return nil }
        return ref?.takeRetainedValue() as String?
    }

    static var defaultOutputDevice: AudioObjectID? {
        value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(kAudioObjectUnknown))
            .flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    static var processObjects: [AudioObjectID] {
        array(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList, AudioObjectID(0))
    }

    static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        (value(process, kAudioProcessPropertyIsRunningOutput, UInt32(0)) ?? 0) != 0
    }

    static func pid(_ process: AudioObjectID) -> pid_t? {
        value(process, kAudioProcessPropertyPID, pid_t(-1)).flatMap { $0 < 0 ? nil : $0 }
    }
}

struct AudioError: LocalizedError {
    let what: String
    let status: OSStatus
    var errorDescription: String? { "\(what) failed (\(status))" }

    static func check(_ status: OSStatus, _ what: String) throws {
        if status != noErr { throw AudioError(what: what, status: status) }
    }
}
