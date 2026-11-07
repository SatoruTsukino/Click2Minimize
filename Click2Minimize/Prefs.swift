import Foundation
import SwiftUI

/// Every user setting, its storage key and its default. Engine code reads
/// values through these accessors; SwiftUI binds the same keys via @AppStorage.
enum Pref: String, CaseIterable {
    // General
    case clickToMinimize = "ClickToMinimizeEnabled"   // key kept from 1.x/2.x installs
    case launchAtLogin = "LaunchAtLoginEnabled"       // key kept from 2.x installs
    case showInMenuBar
    case pauseInGameMode
    case excludedApps                // [String] bundle IDs that skip gestures
    case palmThreshold               // max touch major axis treated as a fingertip

    // Dock
    case dockClickAction             // DockClickAction raw value
    case concedeFocusOnMinimize
    case doubleClickToHideOthers
    case middleClickToTerminate
    case forceKillOnTerminate
    case finderAlternateEnabled
    case finderAlternatePath
    case hoverToExpose
    case lockDockToMainScreen
    case dockFidget

    // Window controls
    case rightDragDownToMinimize
    case rightLeftClickToMinimize
    case threeFingerSwipeDownToMinimize
    case tripleRightClickToClose
    case middleClickCloseButton
    case closeButtonKeywords
    case closeButtonMaxDistance
    case rightDragUpToFullscreen
    case doubleRightClickToFill
    case leftRightClickAction        // WindowToggle raw value
    case doubleClickNotchToFullscreen
    case middleDragToMove
    case threeFingerDragToMove
    case middleScrollToResize
    case threeFingerPinchToResize
    case rightDragToSnap
    case doubleRightClickTitleToNextDisplay
    case twoFingerTopDoubleClickToNextDisplay
    case exitFullscreenBeforeGestures
    case suppressContextMenus
    case middleClickDismissNotifications

    // App switcher and overview
    case switcherCmdTab
    case switcherRightScroll
    case switcherThreeFingerSwipe
    case switcherMaxRows
    case switcherKeepTerminated
    case switcherReverseScroll
    case pinnedApps                  // [String] bundle IDs, ordered
    case appShortcuts                // JSON [bundleID: KeyShortcut]
    case appAutoQuitMinutes          // JSON [bundleID: Int]
    case overviewFourFinger
    case overviewScreenEdge
    case overviewRightSideButtons

    // Shortcut gestures (JSON GestureAction)
    case drawCircleClockwise, drawCircleCounterClockwise, drawShakeHorizontal, drawShakeVertical
    case rotateClockwise, rotateCounterClockwise
    case tiltLeft, tiltRight

    // Universal
    case universalNavigation
    case navigationOverrides         // JSON [bundleID: NavigationOverride]
    case inPageScrolling
    case modifierArrowKeys
    case threeFingerClickToMiddle
    case edgeSlide

    var defaultValue: Any? {
        switch self {
        case .clickToMinimize, .showInMenuBar, .exitFullscreenBeforeGestures: return true
        case .palmThreshold: return 14.0
        case .dockClickAction: return DockClickAction.minimizeAll.rawValue
        case .closeButtonKeywords: return "close, dismiss, ×, ✕"
        case .closeButtonMaxDistance: return 80.0
        case .leftRightClickAction: return WindowToggle.none.rawValue
        case .switcherMaxRows: return 10
        case .finderAlternatePath: return ""
        case .excludedApps, .pinnedApps: return [String]()
        default:
            if Pref.codableKeys.contains(self) { return nil }
            return false
        }
    }

    static let codableKeys: Set<Pref> = [
        .appShortcuts, .appAutoQuitMinutes, .navigationOverrides,
        .drawCircleClockwise, .drawCircleCounterClockwise, .drawShakeHorizontal, .drawShakeVertical,
        .rotateClockwise, .rotateCounterClockwise, .tiltLeft, .tiltRight,
    ]

    static func registerDefaults() {
        var d: [String: Any] = [:]
        for p in allCases { if let v = p.defaultValue { d[p.rawValue] = v } }
        UserDefaults.standard.register(defaults: d)
    }

    var bool: Bool { UserDefaults.standard.bool(forKey: rawValue) }
    var int: Int { UserDefaults.standard.integer(forKey: rawValue) }
    var double: Double { UserDefaults.standard.double(forKey: rawValue) }
    var string: String { UserDefaults.standard.string(forKey: rawValue) ?? "" }
    var strings: [String] { UserDefaults.standard.stringArray(forKey: rawValue) ?? [] }

    func set(_ value: Any?) { UserDefaults.standard.set(value, forKey: rawValue) }

    func decoded<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = UserDefaults.standard.data(forKey: rawValue) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func encode<T: Encodable>(_ value: T) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: rawValue)
    }

    var action: GestureAction { decoded(GestureAction.self) ?? GestureAction() }
}

enum DockClickAction: String, CaseIterable, Identifiable {
    case minimizeAll, minimizeFront, cycleWindows, hideApp
    var id: String { rawValue }
    var title: String {
        switch self {
        case .minimizeAll: return "Minimize all of its windows"
        case .minimizeFront: return "Minimize its front window"
        case .cycleWindows: return "Cycle through its windows"
        case .hideApp: return "Hide the app"
        }
    }
}

enum WindowToggle: String, CaseIterable, Identifiable {
    case none, fill, fullscreen
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Off"
        case .fill: return "Fill screen"
        case .fullscreen: return "Full screen"
        }
    }
}

/// SwiftUI binding for a JSON-encoded preference.
@propertyWrapper
struct CodablePref<T: Codable>: DynamicProperty {
    @AppStorage private var data: Data
    private let fallback: T

    init(_ pref: Pref, default fallback: T) {
        _data = AppStorage(wrappedValue: Data(), pref.rawValue)
        self.fallback = fallback
    }

    var wrappedValue: T {
        get { (try? JSONDecoder().decode(T.self, from: data)) ?? fallback }
        nonmutating set { data = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var projectedValue: Binding<T> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

/// Export / import of the app's preferences domain.
enum SettingsBackup {
    static var domain: String { Bundle.main.bundleIdentifier ?? "com.idemfactor.Click2Minimize" }
    static let knownKeys = Set(Pref.allCases.map(\.rawValue))

    static func export(to url: URL) throws {
        let values = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        let ours = values.filter { knownKeys.contains($0.key) }
        let data = try PropertyListSerialization.data(fromPropertyList: ours, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    enum RestoreError: LocalizedError {
        case invalid, empty
        var errorDescription: String? {
            switch self {
            case .invalid: return "The selected file is not a valid Click2Minimize settings backup."
            case .empty: return "The selected file did not contain any restorable settings."
            }
        }
    }

    /// Validates and applies a backup. Unknown keys are ignored.
    static func restore(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw RestoreError.invalid
        }
        let ours = dict.filter { knownKeys.contains($0.key) }
        guard !ours.isEmpty else { throw RestoreError.empty }
        for (k, v) in ours { UserDefaults.standard.set(v, forKey: k) }
    }
}
