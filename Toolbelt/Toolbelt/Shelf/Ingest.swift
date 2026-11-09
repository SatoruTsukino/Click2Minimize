import AppKit
import UniformTypeIdentifiers

/// Turns pasteboard content into file URLs. Raw image and text data is written to the app's temp folder.
enum Ingest {
    static let readableTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, .URL, .png, .tiff, .string,
        NSPasteboard.PasteboardType(UTType.fileURL.identifier),
        NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData"),
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
    ] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    static func canRead(_ pb: NSPasteboard) -> Bool {
        guard let types = pb.types else { return false }
        return types.contains(where: readableTypes.contains)
    }

    /// Root for everything the shelf creates (dropped data, promised files, conversion output).
    /// Each file gets its own subfolder so it keeps a clean name; all of it is deleted once used.
    static var tempFolder: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Toolbelt/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A new, empty folder inside `tempFolder`.
    static func newSlot() -> URL {
        let url = tempFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func isTemporary(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(tempFolder.standardizedFileURL.path + "/")
    }

    /// Deletes the shelf's own temporary files among `urls` (never anything else), after `delay`
    /// seconds so an app that reads a dropped file lazily still finds it.
    static func discard(_ urls: [URL], after delay: TimeInterval = 0) {
        let temps = urls.filter(isTemporary)
        guard !temps.isEmpty else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            let fm = FileManager.default
            for url in temps {
                try? fm.removeItem(at: url)
                let parent = url.deletingLastPathComponent()
                if parent.standardizedFileURL != tempFolder.standardizedFileURL,
                   (try? fm.contentsOfDirectory(atPath: parent.path))?.isEmpty ?? false {
                    try? fm.removeItem(at: parent)
                }
            }
        }
    }

    /// Removes leftovers from earlier runs.
    static func purge() {
        try? FileManager.default.removeItem(at: tempFolder)
    }

    /// Synchronous part of a drop: real files, then image data, then text. File promises are
    /// resolved asynchronously through `promises`. Data without a file is written to `folder`,
    /// or to a new temp slot.
    static func read(_ pb: NSPasteboard, folder: URL? = nil) -> [URL] {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls
        }
        if let data = pb.data(forType: .png) {
            return write(data, name: "Image.png", folder: folder ?? newSlot()).map { [$0] } ?? []
        }
        if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return write(png, name: "Image.png", folder: folder ?? newSlot()).map { [$0] } ?? []
        }
        if let text = pb.string(forType: .string), !text.isEmpty {
            return write(Data(text.utf8), name: "Text.txt", folder: folder ?? newSlot()).map { [$0] } ?? []
        }
        return []
    }

    static func promises(_ pb: NSPasteboard) -> [NSFilePromiseReceiver] {
        (pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver]) ?? []
    }

    static func write(_ data: Data, name: String, folder: URL) -> URL? {
        let url = uniqueURL(in: folder, name: name)
        return (try? data.write(to: url)) != nil ? url : nil
    }

    /// `name`, or `name 2`, `name 3`… so nothing is overwritten.
    static func uniqueURL(in folder: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var url = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }
}
