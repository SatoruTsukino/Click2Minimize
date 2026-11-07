import ApplicationServices
import Cocoa

/// Finds and presses buttons near the pointer so tiny targets need no aiming.
enum ButtonFinder {
    private static var keywords: [String] {
        Pref.closeButtonKeywords.string.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    private static func label(_ el: AXUIElement) -> String {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute]
            .compactMap { AX.get(el, $0) as String? }.joined(separator: " ").lowercased()
    }

    /// Presses the closest button whose label matches a keyword, within the configured distance.
    static func pressNearbyButton(at p: CGPoint) -> Bool {
        let words = keywords
        guard !words.isEmpty, var root = AX.element(at: p) else { return false }
        if AX.pid(root) == ProcessInfo.processInfo.processIdentifier { return false }
        // Climb a few levels so siblings of the clicked element are searched too.
        for _ in 0..<max(1, Pref.closeButtonSearchDepth.int) {
            guard let parent = AX.parent(root), AX.role(parent) != kAXApplicationRole else { break }
            root = parent
        }
        let maxDistance = CGFloat(Pref.closeButtonMaxDistance.double)
        var best: (AXUIElement, CGFloat)?
        var queue = [root], visited = 0
        while !queue.isEmpty, visited < 400 {
            let el = queue.removeFirst()
            visited += 1
            if AX.role(el) == kAXButtonRole, let f = AX.frame(el) {
                let d = hypot(f.midX - p.x, f.midY - p.y)
                let text = label(el) + (AX.subrole(el) == kAXCloseButtonSubrole ? " close" : "")
                if d <= maxDistance, words.contains(where: text.contains), d < (best?.1 ?? .infinity) {
                    best = (el, d)
                }
            }
            queue.append(contentsOf: AX.children(el))
        }
        guard let button = best?.0 else { return false }
        return AX.perform(button, kAXPressAction)
    }

    /// Dismisses the notification banner under the pointer.
    static func dismissNotification(at p: CGPoint) -> Bool {
        guard var el = AX.element(at: p),
              let app = NSRunningApplication(processIdentifier: AX.pid(el)),
              app.bundleIdentifier == "com.apple.notificationcenterui" else { return false }
        for _ in 0..<10 {
            // Banners expose "Close" / "Clear" as custom actions ("Name:Close\nTarget:…").
            if let action = AX.actions(el).first(where: { $0.contains("Close") || $0.contains("Clear") }) {
                return AX.perform(el, action)
            }
            guard let parent = AX.parent(el) else { break }
            el = parent
        }
        return false
    }
}
