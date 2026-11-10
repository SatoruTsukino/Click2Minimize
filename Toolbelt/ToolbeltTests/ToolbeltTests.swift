import AVFoundation
import CoreAudio
import SwiftUI
import XCTest
@testable import Toolbelt

final class DockDecisionTests: XCTestCase {
    func decide(app: Bool = true, active: Bool = true, hidden: Bool = false, full: Bool = false,
                windows: Int = 2, clicks: Int = 1, mode: DockMode = .minimize) -> DockDecision {
        DockClick.decide(isApp: app, isActive: active, isHidden: hidden, isFullscreen: full,
                         visibleWindows: windows, clickCount: clicks, mode: mode)
    }

    func testActiveAppMinimizesOrHides() {
        XCTAssertEqual(decide(), .minimize)
        XCTAssertEqual(decide(mode: .hide), .hide)
    }

    func testPassThroughCases() {
        XCTAssertEqual(decide(app: false), .passThrough)
        XCTAssertEqual(decide(active: false), .passThrough)
        XCTAssertEqual(decide(hidden: true), .passThrough)
        XCTAssertEqual(decide(full: true), .passThrough)
        XCTAssertEqual(decide(windows: 0), .passThrough) // lets the Dock restore minimized windows
        XCTAssertEqual(decide(clicks: 2), .passThrough)
    }

    func testDockBand() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertTrue(DockClick.nearDock(CGPoint(x: 700, y: 880), screen: screen, orientation: "bottom"))
        XCTAssertFalse(DockClick.nearDock(CGPoint(x: 700, y: 400), screen: screen, orientation: "bottom"))
        XCTAssertTrue(DockClick.nearDock(CGPoint(x: 10, y: 400), screen: screen, orientation: "left"))
        XCTAssertTrue(DockClick.nearDock(CGPoint(x: 1430, y: 400), screen: screen, orientation: "right"))
        let band = DockClick.band(tileSize: 48, magnifies: false, largeSize: nil)
        XCTAssertEqual(band, 72)
        XCTAssertFalse(DockClick.nearDock(CGPoint(x: 700, y: 800), screen: screen, orientation: "bottom", band: band),
                       "click 100 px above the screen bottom is not on a 48 px Dock")
        XCTAssertEqual(DockClick.band(tileSize: 48, magnifies: true, largeSize: 100), 124)
    }
}

final class ShakeDetectorTests: XCTestCase {
    func testZigZagTriggers() {
        var d = ShakeDetector(tuning: .for(.normal))
        var hit = false
        var t: TimeInterval = 0
        for i in 0..<12 {
            let x: CGFloat = i % 2 == 0 ? 100 : 160
            for step in 0..<4 {
                let p = CGPoint(x: x + CGFloat(step) * (i % 2 == 0 ? 1 : -1), y: 300)
                t += 0.01
                if d.add(p, at: t) { hit = true }
            }
        }
        XCTAssertTrue(hit)
    }

    func testStraightDragDoesNot() {
        var d = ShakeDetector(tuning: .for(.highest))
        for i in 0..<200 { XCTAssertFalse(d.add(CGPoint(x: CGFloat(i) * 3, y: 200), at: Double(i) * 0.01)) }
    }
}

final class IngestTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("tb-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func testTextBecomesFile() throws {
        let pb = NSPasteboard(name: .init("tb-\(UUID().uuidString)"))
        pb.clearContents()
        pb.setString("hello", forType: .string)
        XCTAssertTrue(Ingest.canRead(pb))
        let urls = Ingest.read(pb, folder: folder)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(try String(contentsOf: urls[0], encoding: .utf8), "hello")
        pb.releaseGlobally()
    }

    func testFileURLsPassThrough() {
        let file = folder.appendingPathComponent("a.txt")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        let pb = NSPasteboard(name: .init("tb-\(UUID().uuidString)"))
        pb.clearContents()
        pb.writeObjects([file as NSURL])
        XCTAssertEqual(Ingest.read(pb, folder: folder).map(\.standardizedFileURL), [file.standardizedFileURL])
        pb.releaseGlobally()
    }

    func testDiscardOnlyDeletesTempFiles() throws {
        let slot = Ingest.newSlot()
        let temp = slot.appendingPathComponent("t.txt")
        FileManager.default.createFile(atPath: temp.path, contents: Data())
        let user = folder.appendingPathComponent("keep.txt")
        FileManager.default.createFile(atPath: user.path, contents: Data())
        XCTAssertTrue(Ingest.isTemporary(temp))
        XCTAssertFalse(Ingest.isTemporary(user))
        Ingest.discard([temp, user])
        let gone = expectation(description: "deleted")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { gone.fulfill() }
        wait(for: [gone], timeout: 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: slot.path), "empty slot removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: user.path), "user files are never deleted")
    }

    func testDataDropsGetOwnSlot() {
        let pb = NSPasteboard(name: .init("tb-\(UUID().uuidString)"))
        pb.clearContents()
        pb.setString("a", forType: .string)
        let a = Ingest.read(pb)[0], b = Ingest.read(pb)[0]
        XCTAssertEqual(a.lastPathComponent, "Text.txt")
        XCTAssertEqual(b.lastPathComponent, "Text.txt")
        XCTAssertNotEqual(a, b)
        Ingest.discard([a, b])
        pb.releaseGlobally()
    }

    func testUniqueNames() {
        FileManager.default.createFile(atPath: folder.appendingPathComponent("x.png").path, contents: Data())
        XCTAssertEqual(Ingest.uniqueURL(in: folder, name: "x.png").lastPathComponent, "x 2.png")
    }
}

final class ConverterTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("tb-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func makePNG(width: Int = 400, height: Int = 200) throws -> URL {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let url = folder.appendingPathComponent("pic.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    func pixelSize(_ url: URL) -> (Int, Int, String?) {
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        return (p[kCGImagePropertyPixelWidth] as! Int, p[kCGImagePropertyPixelHeight] as! Int, CGImageSourceGetType(src) as String?)
    }

    func testActionAvailability() {
        let none = Tools(ffmpeg: nil, soffice: nil)
        let all = Tools(ffmpeg: URL(fileURLWithPath: "/x/ffmpeg"), soffice: URL(fileURLWithPath: "/x/soffice"))
        let img = [URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.HEIC")]
        XCTAssertTrue(Converter.actions(for: img, tools: none).contains(.convertImage(.jpeg)))
        XCTAssertTrue(Converter.actions(for: [URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/a.mov")], tools: all).isEmpty)
        let mov = [URL(fileURLWithPath: "/a.mov")]
        XCTAssertFalse(Converter.actions(for: mov, tools: none).contains(.ffmpeg(.gif)))
        XCTAssertTrue(Converter.actions(for: mov, tools: all).contains(.ffmpeg(.gif)))
        XCTAssertTrue(Converter.actions(for: [URL(fileURLWithPath: "/a.mkv")], tools: all).contains(.ffmpeg(.mp4)))
        XCTAssertTrue(Converter.actions(for: [URL(fileURLWithPath: "/a.mp3")], tools: all).contains(.ffmpeg(.wav)))
        XCTAssertTrue(Converter.actions(for: [URL(fileURLWithPath: "/a.docx")], tools: none).isEmpty)
        XCTAssertEqual(Converter.actions(for: [URL(fileURLWithPath: "/a.docx")], tools: all), [.toPDF])
    }

    func testImageConvertCompressResize() async throws {
        let png = try makePNG()
        let jpg = try await Converter.run(.convertImage(.jpeg), on: [png], tools: Tools())[0]
        XCTAssertEqual(jpg.lastPathComponent, "pic.jpg")
        XCTAssertEqual(pixelSize(jpg).2, UTType.jpeg.identifier)

        let compressed = try await Converter.run(.compress, on: [png], tools: Tools())[0]
        XCTAssertEqual(compressed.lastPathComponent, "pic (compressed).jpg")

        let half = try await Converter.run(.resize(.half), on: [png], tools: Tools())[0]
        XCTAssertEqual(pixelSize(half).0, 200)
        XCTAssertEqual(pixelSize(half).1, 100)
        XCTAssertEqual(pixelSize(half).2, UTType.png.identifier)

        let fit = try await Converter.run(.resize(.fit(1024)), on: [png], tools: Tools())[0]
        XCTAssertEqual(pixelSize(fit).0, 400, "never upscales")

        let again = try await Converter.run(.convertImage(.jpeg), on: [png], tools: Tools())[0]
        XCTAssertEqual(again.lastPathComponent, "pic.jpg", "clean name in its own slot")
        XCTAssertNotEqual(again, jpg, "never overwrites")
        for out in [jpg, compressed, half, fit, again] {
            XCTAssertTrue(Ingest.isTemporary(out), "outputs go to the shelf temp folder")
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["pic.png"], "source folder untouched")
    }

    func makeMovie() async throws -> URL {
        let url = folder.appendingPathComponent("clip.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for i in 0..<15 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 15))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    func testVideoExportAndRemoveAudio() async throws {
        let mov = try await makeMovie()
        let mp4 = try await Converter.run(.video(.mp4), on: [mov], tools: Tools())[0]
        XCTAssertEqual(mp4.pathExtension, "mp4")
        let tracks = try await AVURLAsset(url: mp4).loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let silent = try await Converter.run(.removeAudio, on: [mov], tools: Tools())[0]
        let audio = try await AVURLAsset(url: silent).loadTracks(withMediaType: .audio)
        XCTAssertTrue(audio.isEmpty)
    }

    func testExternalToolFailureReportsStderr() async {
        do {
            try await External.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "echo boom >&2; exit 3"])
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "boom")
        }
    }

    func testFFmpegWhenInstalled() async throws {
        guard let ffmpeg = Tools.detect().ffmpeg else { throw XCTSkip("ffmpeg not installed") }
        let mov = try await makeMovie()
        let gif = try await Converter.run(.ffmpeg(.gif), on: [mov], tools: Tools(ffmpeg: ffmpeg))[0]
        XCTAssertGreaterThan((try FileManager.default.attributesOfItem(atPath: gif.path)[.size] as? Int) ?? 0, 0)
    }
}

final class GainTests: XCTestCase {
    func list(_ buffers: [[Float]], channels: [Int]) -> UnsafeMutableAudioBufferListPointer {
        let abl = AudioBufferList.allocate(maximumBuffers: buffers.count)
        for (i, b) in buffers.enumerated() {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: b.count)
            p.initialize(from: b, count: b.count)
            abl[i] = AudioBuffer(mNumberChannels: UInt32(channels[i]), mDataByteSize: UInt32(b.count * 4), mData: p)
        }
        return abl
    }

    func floats(_ b: AudioBuffer) -> [Float] {
        Array(UnsafeBufferPointer(start: b.mData!.assumingMemoryBound(to: Float.self), count: Int(b.mDataByteSize) / 4))
    }

    func testInterleavedGainAndPeak() {
        let input = list([[0.5, -0.25, 0.1, 0.2]], channels: [2])
        let output = list([[9, 9, 9, 9]], channels: [2])
        let peak = Gain.render(input: input, output: output, gain: 0.5)
        XCTAssertEqual(floats(output[0]), [0.25, -0.125, 0.05, 0.1])
        XCTAssertEqual(peak, 0.25, accuracy: 1e-6)
    }

    func testInterleavedToPlanar() {
        let input = list([[1, 2, 3, 4]], channels: [2])
        let output = list([[0, 0], [0, 0]], channels: [1, 1])
        _ = Gain.render(input: input, output: output, gain: 1)
        XCTAssertEqual(floats(output[0]), [1, 3])
        XCTAssertEqual(floats(output[1]), [2, 4])
    }

    func testMonoSpreadsAndExtraChannelsSilenced() {
        let mono = list([[0.3, 0.6]], channels: [1])
        let stereo = list([[9, 9, 9, 9]], channels: [2])
        _ = Gain.render(input: mono, output: stereo, gain: 1)
        XCTAssertEqual(floats(stereo[0]), [0.3, 0.3, 0.6, 0.6])

        let st = list([[1, 2]], channels: [2])
        let quad = list([[9, 9, 9, 9]], channels: [4])
        _ = Gain.render(input: st, output: quad, gain: 1)
        XCTAssertEqual(floats(quad[0]), [1, 2, 0, 0])
    }

    func testMuteIsSilence() {
        let input = list([[0.9, 0.9]], channels: [2])
        let output = list([[1, 1]], channels: [2])
        XCTAssertEqual(Gain.render(input: input, output: output, gain: 0), 0)
        XCTAssertEqual(floats(output[0]), [0, 0])
    }
}

final class SnapTests: XCTestCase {
    func testSnapsNearHundred() {
        XCTAssertEqual(MixerModel.snapped(0.97), 1)
        XCTAssertEqual(MixerModel.snapped(1.03), 1)
        XCTAssertEqual(MixerModel.snapped(0.9), 0.9)
        XCTAssertEqual(MixerModel.snapped(1.2), 1.2)
    }
}

final class MixerListTests: XCTestCase {
    func apps(_ n: Int) -> [MixerApp] {
        (0..<n).map { MixerApp(id: "app\($0)", name: "App \($0)", icon: nil, processes: [], volume: 1, muted: false) }
    }

    /// Headless layout check (no window): the list never grows past 6 rows.
    @MainActor func testListHeightCapsAtSixRows() {
        func height(_ n: Int) -> CGFloat {
            NSHostingView(rootView: MixerList(apps: apps(n), levels: [:]).frame(width: 290)).fittingSize.height
        }
        XCTAssertEqual(height(2), 2 * MixerList.rowHeight, accuracy: 0.5)
        XCTAssertEqual(height(6), 6 * MixerList.rowHeight, accuracy: 0.5)
        XCTAssertEqual(height(20), 6 * MixerList.rowHeight, accuracy: 0.5)
        XCTAssertEqual(height(0), 0, accuracy: 0.5)
    }
}

final class MenuPanelTests: XCTestCase {
    func testAnchorUnderVisibleIconElseTopRight() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let icon = CGRect(x: 1200, y: 876, width: 24, height: 24)
        let a = MenuPanel.anchor(icon: icon, screens: [screen], visible: visible)
        XCTAssertEqual(a.top, 872)
        XCTAssertEqual(a.midX, 1212)
        let hidden = MenuPanel.anchor(icon: CGRect(x: -500, y: 2000, width: 24, height: 24), screens: [screen], visible: visible)
        XCTAssertEqual(hidden.top, 871, "hidden icon: under the menu bar")
        XCTAssertEqual(hidden.midX, 1272)
        XCTAssertEqual(MenuPanel.anchor(icon: nil, screens: [screen], visible: visible).top, 871)
    }

    /// Never shown: the panel takes SwiftUI's size and keeps its top edge.
    @MainActor func testPanelSizesToContent() {
        let panel = MenuPanel(rootView: Color.clear.frame(width: 320, height: 137))
        panel.anchor = (top: 871, midX: 700)
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        panel.setContentSize(panel.contentViewController!.preferredContentSize)
        XCTAssertEqual(panel.frame.height, 137, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, 871, accuracy: 0.5)
    }

    /// Never shown: any size SwiftUI asks for keeps the anchored top edge (grows downward).
    @MainActor func testGrowsDownwardFromFixedTop() {
        let panel = MenuPanel(rootView: Color.clear)
        panel.anchor = (top: 871, midX: 700)
        for h in [100.0, 500.0, 150.0] {
            let r = panel.pinned(CGRect(x: 0, y: 0, width: 320, height: h))
            XCTAssertEqual(r.maxY, 871, accuracy: 0.5)
            XCTAssertEqual(r.height, h)
        }
    }
}

final class RadialTests: XCTestCase {
    func testShiftTap() {
        var t = ShiftTap()
        XCTAssertFalse(t.update(shift: true, others: false, at: 0))
        XCTAssertTrue(t.update(shift: false, others: false, at: 0.2), "quick press and release is a tap")
        XCTAssertFalse(t.update(shift: true, others: false, at: 1))
        XCTAssertFalse(t.update(shift: false, others: false, at: 1.5), "held too long")
        XCTAssertFalse(t.update(shift: true, others: false, at: 2))
        XCTAssertFalse(t.update(shift: true, others: true, at: 2.05))
        XCTAssertFalse(t.update(shift: false, others: false, at: 2.1), "⇧⌘ is not a tap")
        XCTAssertFalse(t.update(shift: false, others: false, at: 3), "release without press")
    }

    func testRingSplitAndSpacing() {
        let six = RadialLayout.place(count: 6)
        XCTAssertEqual(six.count, 6)
        XCTAssertEqual(six[0], CGPoint(x: 0, y: RadialLayout.innerRadius), "starts at 12 o'clock")
        for p in six { XCTAssertEqual(hypot(p.x, p.y), RadialLayout.innerRadius, accuracy: 1) }

        let twelve = RadialLayout.place(count: 12)
        XCTAssertEqual(twelve.prefix(8).filter { abs(hypot($0.x, $0.y) - RadialLayout.innerRadius) < 1 }.count, 8)
        XCTAssertEqual(twelve.suffix(4).filter { abs(hypot($0.x, $0.y) - RadialLayout.outerRadius) < 1 }.count, 4)
        XCTAssertGreaterThan(RadialLayout.extent(count: 12), RadialLayout.extent(count: 8))
    }

    func testPetalsDoNotOverlap() {
        for n in 1...20 {
            let pts = RadialLayout.place(count: n)
            for i in pts.indices { for j in pts.indices where j > i {
                XCTAssertGreaterThanOrEqual(hypot(pts[i].x - pts[j].x, pts[i].y - pts[j].y), RadialLayout.petalSize - 0.5, "n=\(n)")
            } }
        }
    }

    func testEveryActionHasUniqueShortTitle() {
        let all = Converter.actions(for: [URL(fileURLWithPath: "/a.mov")], tools: Tools(ffmpeg: URL(fileURLWithPath: "/f"), soffice: nil))
            + Converter.actions(for: [URL(fileURLWithPath: "/a.png")], tools: Tools())
        XCTAssertEqual(Set(all.map(\.shortTitle)).count, all.count)
    }
}

final class StoreTests: XCTestCase {
    func testMixerStoreRoundTrip() {
        let d = UserDefaults(suiteName: "tb-\(UUID().uuidString)")!
        let store = MixerStore(defaults: d)
        XCTAssertEqual(store.settings("a").volume, 1)
        store.save("a", volume: 0.4, muted: true)
        XCTAssertEqual(store.settings("a").volume, 0.4, accuracy: 1e-6)
        XCTAssertTrue(store.settings("a").muted)
        store.save("b", volume: 0.998, muted: false)
        XCTAssertEqual(store.settings("b").volume, 1, "legacy near-100 % values snap")
        store.save("a", volume: 1, muted: false)
        XCTAssertNil(d.dictionary(forKey: "mixer.apps")?["a"], "defaults are not stored")
    }

    @MainActor func testPrefsDefaultsAndPersist() {
        let d = UserDefaults(suiteName: "tb-\(UUID().uuidString)")!
        let p = Prefs(defaults: d)
        XCTAssertTrue(p.dockClick && p.shakeShelf && p.mixer && p.shiftRing)
        XCTAssertEqual(p.dockMode, .minimize)
        p.dockMode = .hide
        XCTAssertEqual(Prefs(defaults: d).dockMode, .hide)
    }
}
