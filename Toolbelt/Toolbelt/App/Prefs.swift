import Foundation

enum DockMode: String, CaseIterable, Identifiable {
    case minimize, hide
    var id: String { rawValue }
    var title: String { self == .minimize ? "Minimize windows" : "Hide app" }
}

enum ShakeSensitivity: String, CaseIterable, Identifiable {
    case normal, high, highest
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Persisted user settings. Feature toggles call `onChange` so the app can start or stop the hook.
@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()

    private let defaults: UserDefaults
    var onChange: (() -> Void)?

    @Published var dockClick: Bool { didSet { save(dockClick, "dockClick") } }
    @Published var dockMode: DockMode { didSet { save(dockMode.rawValue, "dockMode") } }
    @Published var shakeShelf: Bool { didSet { save(shakeShelf, "shakeShelf") } }
    @Published var shakeSensitivity: ShakeSensitivity { didSet { save(shakeSensitivity.rawValue, "shakeSensitivity") } }
    @Published var mixer: Bool { didSet { save(mixer, "mixer") } }
    @Published var shiftRing: Bool { didSet { save(shiftRing, "shiftRing") } }
    @Published var switcher: Bool { didSet { save(switcher, "switcher") } }
    @Published var finderOpensApp: Bool { didSet { save(finderOpensApp, "finderOpensApp") } }
    @Published var finderAppPath: String { didSet { save(finderAppPath, "finderAppPath") } }
    @Published var dockMiddleQuit: Bool { didSet { save(dockMiddleQuit, "dockMiddleQuit") } }
    @Published var middleDragMove: Bool { didSet { save(middleDragMove, "middleDragMove") } }
    @Published var trackpadMiddle: TrackpadMiddle { didSet { save(trackpadMiddle.rawValue, "trackpadMiddle") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["dockClick": true, "shakeShelf": true, "mixer": true, "shiftRing": true,
                                     "switcher": true, "dockMiddleQuit": true, "middleDragMove": true])
        dockClick = defaults.bool(forKey: "dockClick")
        dockMode = DockMode(rawValue: defaults.string(forKey: "dockMode") ?? "") ?? .minimize
        shakeShelf = defaults.bool(forKey: "shakeShelf")
        shakeSensitivity = ShakeSensitivity(rawValue: defaults.string(forKey: "shakeSensitivity") ?? "") ?? .normal
        mixer = defaults.bool(forKey: "mixer")
        shiftRing = defaults.bool(forKey: "shiftRing")
        switcher = defaults.bool(forKey: "switcher")
        finderOpensApp = defaults.bool(forKey: "finderOpensApp")
        finderAppPath = defaults.string(forKey: "finderAppPath") ?? ""
        dockMiddleQuit = defaults.bool(forKey: "dockMiddleQuit")
        middleDragMove = defaults.bool(forKey: "middleDragMove")
        trackpadMiddle = TrackpadMiddle(rawValue: defaults.string(forKey: "trackpadMiddle") ?? "") ?? .standard
    }

    /// Features that need Accessibility (they run on the shared input tap).
    var needsAccessibility: Bool {
        dockClick || finderOpensApp || switcher || dockMiddleQuit || middleDragMove || trackpadMiddle != .off
    }

    var inputFeatures: InputTap.Features {
        InputTap.Features(dockClick: dockClick || (finderOpensApp && !finderAppPath.isEmpty),
                          middle: dockMiddleQuit || middleDragMove,
                          trackpadPress: trackpadMiddle != .off,
                          switcher: switcher)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }
}
