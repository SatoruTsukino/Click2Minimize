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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["dockClick": true, "shakeShelf": true, "mixer": true])
        dockClick = defaults.bool(forKey: "dockClick")
        dockMode = DockMode(rawValue: defaults.string(forKey: "dockMode") ?? "") ?? .minimize
        shakeShelf = defaults.bool(forKey: "shakeShelf")
        shakeSensitivity = ShakeSensitivity(rawValue: defaults.string(forKey: "shakeSensitivity") ?? "") ?? .normal
        mixer = defaults.bool(forKey: "mixer")
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }
}
