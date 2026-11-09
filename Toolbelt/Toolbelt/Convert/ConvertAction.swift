import Foundation
import UniformTypeIdentifiers

enum ImageFormat: String, CaseIterable {
    case jpeg, png, heic, tiff
    var type: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .tiff: .tiff
        }
    }
    var ext: String { self == .jpeg ? "jpg" : (type.preferredFilenameExtension ?? rawValue) }
    var isLossy: Bool { self == .jpeg || self == .heic }
}

enum ResizeSpec: Hashable {
    case half
    case fit(Int)
}

enum VideoTarget: String, CaseIterable {
    case mp4, mov, shrink1080, shrink720
}

enum FFTarget: String, CaseIterable {
    case mp4, webm, gif, mp3, wav
    var ext: String { rawValue }
    var isAudio: Bool { self == .mp3 || self == .wav }
    var args: [String] {
        switch self {
        case .mp4: ["-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-c:a", "aac", "-movflags", "+faststart"]
        case .webm: ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "33", "-c:a", "libopus"]
        case .gif: ["-vf", "fps=12,scale=640:-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse", "-loop", "0", "-an"]
        case .mp3: ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case .wav: ["-vn", "-c:a", "pcm_s16le"]
        }
    }
}

enum FileKind: Equatable {
    case image, video, audio, document, other

    static let documentExtensions: Set<String> = ["doc", "docx", "odt", "rtf", "ppt", "pptx", "odp", "xls", "xlsx", "ods", "pages", "key", "numbers"]
    static let extraVideoExtensions: Set<String> = ["mkv", "webm", "avi", "flv", "wmv", "mpg", "mpeg", "ts"]

    static func of(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if documentExtensions.contains(ext) { return .document }
        if extraVideoExtensions.contains(ext) { return .video }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return .other
    }
}

enum ConvertAction: Hashable, Identifiable {
    case convertImage(ImageFormat)
    case compress
    case resize(ResizeSpec)
    case video(VideoTarget)
    case removeAudio
    case extractAudio
    case ffmpeg(FFTarget)
    case toPDF

    var id: String { title }

    var title: String {
        switch self {
        case .convertImage(let f): "Convert to \(f.rawValue.uppercased())"
        case .compress: "Compress"
        case .resize(.half): "Resize 50%"
        case .resize(.fit(let px)): "Fit in \(px) px"
        case .video(.mp4): "Convert to MP4"
        case .video(.mov): "Convert to MOV"
        case .video(.shrink1080): "Shrink to 1080p"
        case .video(.shrink720): "Shrink to 720p"
        case .removeAudio: "Remove Audio"
        case .extractAudio: "Extract Audio (M4A)"
        case .ffmpeg(let t): "\(t.rawValue.uppercased()) (ffmpeg)"
        case .toPDF: "Convert to PDF"
        }
    }

    var group: String {
        switch self {
        case .convertImage, .compress, .resize: "Image"
        case .video, .removeAudio: "Video"
        case .extractAudio: "Audio"
        case .ffmpeg(let t): t.isAudio ? "Audio" : "Video"
        case .toPDF: "Document"
        }
    }

    struct Group { let title: String; let actions: [ConvertAction] }

    static func grouped(_ actions: [ConvertAction]) -> [Group] {
        var order: [String] = []
        var map: [String: [ConvertAction]] = [:]
        for a in actions {
            if map[a.group] == nil { order.append(a.group) }
            map[a.group, default: []].append(a)
        }
        return order.map { Group(title: $0, actions: map[$0]!) }
    }
}

/// Optional external converters, found on disk; never bundled.
struct Tools: Equatable {
    var ffmpeg: URL?
    var soffice: URL?

    static func detect(path: String = ProcessInfo.processInfo.environment["PATH"] ?? "") -> Tools {
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin"] + path.split(separator: ":").map(String.init)
        func find(_ name: String, extra: [String] = []) -> URL? {
            (extra + dirs.map { "\($0)/\(name)" })
                .first { FileManager.default.isExecutableFile(atPath: $0) }
                .map(URL.init(fileURLWithPath:))
        }
        return Tools(ffmpeg: find("ffmpeg"),
                     soffice: find("soffice", extra: ["/Applications/LibreOffice.app/Contents/MacOS/soffice"]))
    }
}
