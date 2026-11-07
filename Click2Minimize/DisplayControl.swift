import Cocoa
import IOKit
import os.log

private let log = Logger(subsystem: "com.idemfactor.Click2Minimize", category: "display")

/// Brightness of the display under the pointer, through whichever route the
/// display supports:
/// 1. DisplayServices (private): built-in and Apple displays.
/// 2. DDC/CI over IOAVService (private, Apple silicon): most external monitors.
/// 3. Gamma dimming: any other display (can only dim).
/// Each change shows the native brightness OSD.
enum DisplayControl {
    static let steps: Float = 16

    static func display(under p: CGPoint) -> CGDirectDisplayID {
        var id: CGDirectDisplayID = 0, count: UInt32 = 0
        CGGetDisplaysWithPoint(p, 1, &id, &count)
        return count > 0 ? id : CGMainDisplayID()
    }

    static func stepBrightness(up: Bool, at point: CGPoint) {
        let id = display(under: point)
        let delta = (up ? 1 : -1) / steps
        if DisplayServices.canChange(id), let current = DisplayServices.get(id) {
            let value = clamp(current + delta)
            DisplayServices.set(id, value)
            OSD.showBrightness(value, on: id)
        } else if DDC.isAvailable(for: id) {
            DDC.step(id, delta: delta) { value in OSD.showBrightness(value, on: id) }
        } else {
            let value = Gamma.step(id, delta: delta)
            OSD.showBrightness(value, on: id)
        }
    }

    static func restoreGamma() { Gamma.restore() }

    static func clamp(_ v: Float) -> Float { max(0, min(1, (v * steps).rounded() / steps)) }
}

// MARK: - DisplayServices

private enum DisplayServices {
    private typealias CanChangeFn = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let canChangeFn = handle.flatMap { dlsym($0, "DisplayServicesCanChangeBrightness") }.map { unsafeBitCast($0, to: CanChangeFn.self) }
    private static let getFn = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }

    static func canChange(_ id: CGDirectDisplayID) -> Bool { canChangeFn?(id) ?? false }

    static func get(_ id: CGDirectDisplayID) -> Float? {
        var v: Float = 0
        guard let getFn, getFn(id, &v) == 0 else { return nil }
        return v
    }

    static func set(_ id: CGDirectDisplayID, _ v: Float) { _ = setFn?(id, v) }
}

// MARK: - DDC/CI (Apple silicon)

private enum DDC {
    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias I2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static let create = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOAVServiceCreateWithService").map { unsafeBitCast($0, to: CreateFn.self) }
    private static let readI2C = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOAVServiceReadI2C").map { unsafeBitCast($0, to: I2CFn.self) }
    private static let writeI2C = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOAVServiceWriteI2C").map { unsafeBitCast($0, to: I2CFn.self) }

    private static let queue = DispatchQueue(label: "Click2Minimize DDC queue")
    private static let brightnessVCP: UInt8 = 0x10
    private static var services: [CGDirectDisplayID: CFTypeRef] = [:]
    private static var levels: [CGDirectDisplayID: Float] = [:]   // 0...1, guarded by queue
    private static var scanned = false

    struct Framebuffer { var productID = 0, vendorID = 0, serial = 0 }

    static func isAvailable(for id: CGDirectDisplayID) -> Bool {
        guard CGDisplayIsBuiltin(id) == 0, create != nil else { return false }
        if !scanned { scan() }
        return services[id] != nil
    }

    /// Walks the IORegistry: each external `DCPAVServiceProxy` follows the
    /// framebuffer (`AppleCLCD2` / `IOMobileFramebufferShim`) it drives, whose
    /// attributes identify the monitor.
    private static func scan() {
        scanned = true
        guard let create else { return }
        var found: [(Framebuffer, CFTypeRef)] = []
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(IORegistryGetRootEntry(kIOMainPortDefault), kIOServicePlane,
                                            IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var current = Framebuffer()
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            var nameBuf = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &nameBuf)
            let name = String(cString: nameBuf)
            if name == "AppleCLCD2" || name == "IOMobileFramebufferShim" {
                current = Framebuffer()
                if let attrs = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
                   let product = attrs["ProductAttributes"] as? [String: Any] {
                    current.productID = product["ProductID"] as? Int ?? 0
                    current.vendorID = product["LegacyManufacturerID"] as? Int ?? 0
                    current.serial = product["SerialNumber"] as? Int ?? 0
                }
            } else if name == "DCPAVServiceProxy",
                      let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                          .takeRetainedValue() as? String, location == "External",
                      let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() {
                found.append((current, service))
            }
        }

        var online = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
        CGGetOnlineDisplayList(16, &online, &count)
        let externals = online.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 && !DisplayServices.canChange($0) }
        var remaining = found
        for id in externals {
            let model = Int(CGDisplayModelNumber(id)), vendor = Int(CGDisplayVendorNumber(id)), serial = Int(CGDisplaySerialNumber(id))
            let index = remaining.firstIndex { $0.0.productID == model && $0.0.vendorID == vendor && $0.0.serial == serial }
                ?? remaining.firstIndex { $0.0.productID == model && $0.0.vendorID == vendor }
                ?? (externals.count == 1 && remaining.count == 1 ? 0 : nil)
            if let index { services[id] = remaining.remove(at: index).1 }
        }
        log.info("DDC: \(services.count) external display(s) controllable")
    }

    static func step(_ id: CGDirectDisplayID, delta: Float, completion: @escaping (Float) -> Void) {
        guard let service = services[id] else { return }
        queue.async {
            let current = levels[id] ?? read(service) ?? 0.5
            let value = DisplayControl.clamp(current + delta)
            levels[id] = value
            write(service, value: UInt16(value * 100))
            DispatchQueue.main.async { completion(value) }
        }
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(UInt8(0x6E ^ 0x51), ^) // destination 0x37<<1, source 0x51
    }

    private static func write(_ service: CFTypeRef, value: UInt16) {
        guard let writeI2C else { return }
        var packet: [UInt8] = [0x84, 0x03, brightnessVCP, UInt8(value >> 8), UInt8(value & 0xFF)]
        packet.append(checksum(packet))
        for _ in 0..<2 { // monitors often drop the first packet
            usleep(10_000)
            _ = packet.withUnsafeMutableBytes { writeI2C(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
        }
    }

    /// Reads the current brightness as 0...1, or nil if the monitor doesn't answer.
    private static func read(_ service: CFTypeRef) -> Float? {
        guard let writeI2C, let readI2C else { return nil }
        var request: [UInt8] = [0x82, 0x01, brightnessVCP]
        request.append(checksum(request))
        var reply = [UInt8](repeating: 0, count: 11)
        for _ in 0..<3 {
            usleep(10_000)
            _ = request.withUnsafeMutableBytes { writeI2C(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
            usleep(50_000)
            let status = reply.withUnsafeMutableBytes { readI2C(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
            // Reply: src, len, 0x02 (VCP reply), result, vcp, type, max(2), current(2), checksum.
            if status == kIOReturnSuccess, reply[2] == 0x02, reply[3] == 0, reply[4] == brightnessVCP {
                let maxValue = Float(UInt16(reply[6]) << 8 | UInt16(reply[7]))
                let current = Float(UInt16(reply[8]) << 8 | UInt16(reply[9]))
                if maxValue > 0 { return current / maxValue }
            }
        }
        return nil
    }
}

// MARK: - Gamma fallback

private enum Gamma {
    private static var levels: [CGDirectDisplayID: Float] = [:]

    static func step(_ id: CGDirectDisplayID, delta: Float) -> Float {
        let value = max(0.1, DisplayControl.clamp((levels[id] ?? 1) + delta))
        levels[id] = value
        CGSetDisplayTransferByFormula(id, 0, value, 1, 0, value, 1, 0, value, 1)
        return value
    }

    static func restore() {
        guard !levels.isEmpty else { return }
        CGDisplayRestoreColorSyncSettings()
        levels = [:]
    }
}

// MARK: - On-screen display

/// The native brightness / volume HUD, via the private OSD framework.
enum OSD {
    private typealias ShowFn = @convention(c) (AnyObject, Selector, Int64, UInt32, UInt32, UInt32, UInt32, UInt32, Bool) -> Void
    private static let brightnessImage: Int64 = 1

    private static let manager: AnyObject? = {
        _ = dlopen("/System/Library/PrivateFrameworks/OSD.framework/OSD", RTLD_LAZY)
        guard let cls = NSClassFromString("OSDManager") as? NSObject.Type else { return nil }
        return cls.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue()
    }()

    static func showBrightness(_ value: Float, on display: CGDirectDisplayID) {
        let sel = NSSelectorFromString("showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:")
        guard let manager, let method = class_getInstanceMethod(type(of: manager), sel) else { return }
        let show = unsafeBitCast(method_getImplementation(method), to: ShowFn.self)
        show(manager, sel, brightnessImage, display, 0x1F4, 1000, UInt32(value * 64), 64, false)
    }
}
