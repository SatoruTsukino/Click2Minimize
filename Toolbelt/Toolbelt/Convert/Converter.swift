import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ConvertError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// One conversion engine for the shelf: ImageIO for images, AVFoundation for media, and
/// `ffmpeg` / `soffice` when installed. Runs off the main actor.
enum Converter {
    /// Actions that apply to every URL in `urls`.
    static func actions(for urls: [URL], tools: Tools) -> [ConvertAction] {
        let kinds = Set(urls.map(FileKind.of))
        guard kinds.count == 1, let kind = kinds.first else { return [] }
        var out: [ConvertAction] = []
        switch kind {
        case .image:
            out = ImageFormat.allCases.map(ConvertAction.convertImage) + [.compress, .resize(.half), .resize(.fit(2048)), .resize(.fit(1024))]
        case .video:
            out = VideoTarget.allCases.map(ConvertAction.video) + [.removeAudio, .extractAudio]
            if tools.ffmpeg != nil { out += FFTarget.allCases.map(ConvertAction.ffmpeg) }
        case .audio:
            out = [.extractAudio]
            if tools.ffmpeg != nil { out += [.ffmpeg(.mp3), .ffmpeg(.wav)] }
        case .document:
            if tools.soffice != nil { out = [.toPDF] }
        case .other:
            break
        }
        return out
    }

    /// Converts each URL, returning the new files (see `output(for:name:)`).
    static func run(_ action: ConvertAction, on urls: [URL], tools: Tools = .detect()) async throws -> [URL] {
        var outputs: [URL] = []
        for url in urls {
            outputs.append(try await convert(url, action, tools))
        }
        return outputs
    }

    private static func convert(_ url: URL, _ action: ConvertAction, _ tools: Tools) async throws -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        switch action {
        case .convertImage(let format):
            return try ImageOps.write(url, format: format, quality: 0.9, maxPixels: nil,
                                      to: output(for: url, name: "\(base).\(format.ext)"))
        case .compress:
            let format = ImageOps.compressedFormat(for: url)
            return try ImageOps.write(url, format: format, quality: 0.6, maxPixels: nil,
                                      to: output(for: url, name: "\(base) (compressed).\(format.ext)"))
        case .resize(let spec):
            let format = ImageOps.sameFormat(for: url)
            let label = if case .fit(let px) = spec { "\(px)px" } else { "50%" }
            return try ImageOps.resize(url, spec: spec, format: format,
                                       to: output(for: url, name: "\(base) (\(label)).\(format.ext)"))
        case .video(let target):
            let (preset, type, ext): (String, AVFileType, String) = switch target {
            case .mp4: (AVAssetExportPresetHighestQuality, .mp4, "mp4")
            case .mov: (AVAssetExportPresetHighestQuality, .mov, "mov")
            case .shrink1080: (AVAssetExportPreset1920x1080, .mp4, "mp4")
            case .shrink720: (AVAssetExportPreset1280x720, .mp4, "mp4")
            }
            let suffix = target == .shrink1080 ? " (1080p)" : target == .shrink720 ? " (720p)" : ""
            return try await MediaOps.export(AVURLAsset(url: url), preset: preset, type: type,
                                             to: output(for: url, name: "\(base)\(suffix).\(ext)"))
        case .removeAudio:
            let ext = url.pathExtension.lowercased() == "mp4" ? "mp4" : "mov"
            return try await MediaOps.removeAudio(url, type: ext == "mp4" ? .mp4 : .mov,
                                                  to: output(for: url, name: "\(base) (no audio).\(ext)"))
        case .extractAudio:
            return try await MediaOps.export(AVURLAsset(url: url), preset: AVAssetExportPresetAppleM4A, type: .m4a,
                                             to: output(for: url, name: "\(base).m4a"))
        case .ffmpeg(let target):
            guard let ffmpeg = tools.ffmpeg else { throw ConvertError("ffmpeg is not installed") }
            let out = output(for: url, name: "\(base).\(target.ext)")
            try await External.run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", url.path] + target.args + [out.path])
            return out
        case .toPDF:
            guard let soffice = tools.soffice else { throw ConvertError("LibreOffice is not installed") }
            // soffice names the output itself; convert into a private folder, then move to a unique name.
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("Toolbelt/soffice-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            try await External.run(soffice, ["--headless", "--convert-to", "pdf", "--outdir", scratch.path, url.path])
            guard let produced = try FileManager.default.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil).first else {
                throw ConvertError("LibreOffice produced no PDF")
            }
            let out = output(for: url, name: "\(base).pdf")
            try FileManager.default.moveItem(at: produced, to: out)
            return out
        }
    }

    /// Output file in its own temp slot: it lands on the shelf, keeps a clean name, and is
    /// deleted once dragged out or removed. Originals and their folders are never touched.
    static func output(for source: URL, name: String) -> URL {
        Ingest.newSlot().appendingPathComponent(name)
    }
}

enum ImageOps {
    static func source(_ url: URL) throws -> CGImageSource {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 else {
            throw ConvertError("Not a readable image")
        }
        return src
    }

    static func sourceType(_ url: URL) -> UTType? {
        (try? source(url)).flatMap { CGImageSourceGetType($0) as String? }.flatMap(UTType.init)
    }

    static func sameFormat(for url: URL) -> ImageFormat {
        guard let t = sourceType(url) else { return .png }
        return ImageFormat.allCases.first { t.conforms(to: $0.type) } ?? .png
    }

    /// Lossy formats stay as they are; everything else becomes JPEG.
    static func compressedFormat(for url: URL) -> ImageFormat {
        let f = sameFormat(for: url)
        return f.isLossy ? f : .jpeg
    }

    /// Decodes with EXIF orientation applied, optionally downscaled so the long side is ≤ `maxPixels`.
    static func image(_ src: CGImageSource, maxPixels: Int?) throws -> CGImage {
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixels ?? Int.max, max(w, h, 1)),
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw ConvertError("Could not decode the image")
        }
        return img
    }

    static func write(_ url: URL, format: ImageFormat, quality: Double, maxPixels: Int?, to out: URL) throws -> URL {
        let img = try image(source(url), maxPixels: maxPixels)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw ConvertError("\(format.rawValue.uppercased()) cannot be written")
        }
        var props: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if format.isLossy { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: out)
            throw ConvertError("Could not write the image")
        }
        return out
    }

    static func resize(_ url: URL, spec: ResizeSpec, format: ImageFormat, to out: URL) throws -> URL {
        let src = try source(url)
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let longSide = max(props?[kCGImagePropertyPixelWidth] as? Int ?? 0, props?[kCGImagePropertyPixelHeight] as? Int ?? 0)
        let target = switch spec {
        case .half: max(1, longSide / 2)
        case .fit(let px): min(px, max(longSide, 1)) // never upscale
        }
        return try write(url, format: format, quality: 0.9, maxPixels: target, to: out)
    }
}

enum MediaOps {
    static func export(_ asset: AVAsset, preset: String, type: AVFileType, to out: URL) async throws -> URL {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConvertError("This file can't be exported with AVFoundation")
        }
        if #available(macOS 15, *) {
            try await session.export(to: out, as: type)
        } else {
            session.outputURL = out
            session.outputFileType = type
            await session.export()
            if session.status != .completed {
                throw session.error ?? ConvertError("Export failed")
            }
        }
        return out
    }

    static func removeAudio(_ url: URL, type: AVFileType, to out: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else { throw ConvertError("No video track") }
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        guard let dst = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ConvertError("Could not build the video")
        }
        try dst.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        dst.preferredTransform = try await track.load(.preferredTransform)
        return try await export(composition, preset: AVAssetExportPresetPassthrough, type: type, to: out)
    }
}

enum External {
    /// Runs a tool with an argument array (no shell). stderr goes to a file so a chatty tool can't block on a full pipe.
    static func run(_ tool: URL, _ args: [String]) async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("Toolbelt-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: log) }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let p = Process()
        p.executableURL = tool
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = handle
        let status: Int32 = try await withCheckedThrowingContinuation { cont in
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
        guard status == 0 else {
            let text = (try? String(contentsOf: log, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ConvertError(text.isEmpty ? "\(tool.lastPathComponent) exited with \(status)" : String(text.suffix(200)))
        }
    }
}
