import Cocoa
import os.log

private let log = Logger(subsystem: "com.idemfactor.Click2Minimize", category: "update")

/// Checks GitHub releases and installs a newer DMG into /Applications.
enum Updater {
    static let repo = "hatimhtm/Click2Minimize"
    private static var latestURL: URL { URL(string: "https://api.github.com/repos/\(repo)/releases/latest")! }
    private static var releasesPage: URL { URL(string: "https://github.com/\(repo)/releases")! }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let assets: [Asset]
    }

    /// `interactive` reports "up to date" and errors; the launch check stays silent.
    static func check(interactive: Bool) {
        URLSession.shared.dataTask(with: latestURL) { data, _, error in
            let release = data.flatMap { try? JSONDecoder().decode(Release.self, from: $0) }
            DispatchQueue.main.async {
                guard let release else {
                    log.error("update check failed: \(error?.localizedDescription ?? "bad response", privacy: .public)")
                    if interactive { alert("Couldn't check for updates", "Please try again later.") }
                    return
                }
                if GestureMath.isNewerVersion(release.tag_name, than: currentVersion) {
                    offer(release)
                } else if interactive {
                    alert("You're up to date", "You are using the latest version v\(currentVersion).")
                }
            }
        }.resume()
    }

    private static func offer(_ release: Release) {
        let a = NSAlert()
        a.messageText = "Update Available"
        a.informativeText = "Version \(release.tag_name) is available. You have v\(currentVersion). Would you like to update?"
        a.addButton(withTitle: "Update")
        a.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        guard let dmg = release.assets.first(where: { $0.name.hasSuffix(".dmg") })?.browser_download_url else {
            NSWorkspace.shared.open(releasesPage)
            return
        }
        install(from: dmg)
    }

    private static func install(from url: URL) {
        URLSession.shared.downloadTask(with: url) { file, _, error in
            guard let file else {
                log.error("download failed: \(error?.localizedDescription ?? "?", privacy: .public)")
                DispatchQueue.main.async { NSWorkspace.shared.open(releasesPage) }
                return
            }
            let mount = FileManager.default.temporaryDirectory.appendingPathComponent("c2m-update-\(UUID().uuidString)")
            let ok = run("/usr/bin/hdiutil", ["attach", file.path, "-nobrowse", "-quiet", "-mountpoint", mount.path])
            defer { if ok { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"]) } }
            let source = mount.appendingPathComponent("Click2Minimize.app")
            let destination = URL(fileURLWithPath: "/Applications/Click2Minimize.app")
            do {
                guard ok, FileManager.default.fileExists(atPath: source.path) else { throw CocoaError(.fileNoSuchFile) }
                let staged = FileManager.default.temporaryDirectory.appendingPathComponent("Click2Minimize-\(UUID().uuidString).app")
                try FileManager.default.copyItem(at: source, to: staged)
                // Swap only after the new copy is complete, so a failure leaves the old app intact.
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
                } else {
                    try FileManager.default.moveItem(at: staged, to: destination)
                }
                DispatchQueue.main.async { relaunch(destination) }
            } catch {
                log.error("install failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { NSWorkspace.shared.open(releasesPage) }
            }
        }.resume()
    }

    private static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private static func relaunch(_ app: URL) {
        alert("Update Installed", "Click2Minimize has been updated and will now relaunch.")
        relaunchApp(at: app)
    }

    static func relaunchApp(at app: URL = Bundle.main.bundleURL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
