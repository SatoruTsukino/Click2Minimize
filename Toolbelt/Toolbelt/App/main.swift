import AppKit

/// Unit tests use the app as TEST_HOST. Skip all UI and system hooks then, so tests stay headless.
let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
