import SwiftUI
import UniformTypeIdentifiers

struct PopoverView: View {
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var mixer = MixerModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if prefs.mixer { mixerSection; Divider() }
            if !permissions.accessibility, prefs.needsAccessibility {
                notice("Dock, mouse and ⌘⇥ features need Accessibility access.", button: "Open Settings") { permissions.promptAccessibility() }
            }

            Toggle("Dock click", isOn: $prefs.dockClick)
            if prefs.dockClick {
                Picker("Action", selection: $prefs.dockMode) {
                    ForEach(DockMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Shake to open shelf", isOn: $prefs.shakeShelf)
            if prefs.shakeShelf {
                Picker("Sensitivity", selection: $prefs.shakeSensitivity) {
                    ForEach(ShakeSensitivity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Toggle("Tap ⇧ while dragging: convert ring", isOn: $prefs.shiftRing)
            Divider()
            inputSection
            Toggle("Per-app volume", isOn: $prefs.mixer)
            Toggle("Launch at login", isOn: Binding(get: { permissions.launchAtLogin },
                                                    set: { permissions.setLaunchAtLogin($0) }))
            Divider()
            HStack {
                Button("Show Shelf") { ShelfController.shared.show(at: NSEvent.mouseLocation) }
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .toggleStyle(.switch)
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder private var inputSection: some View {
        Toggle("⌘⇥ vertical app switcher", isOn: $prefs.switcher)
        Toggle("Middle-click Dock icon quits app", isOn: $prefs.dockMiddleQuit)
        Toggle("Middle-drag moves windows", isOn: $prefs.middleDragMove)
        Picker("Trackpad middle click", selection: $prefs.trackpadMiddle) {
            ForEach(TrackpadMiddle.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        Text(Trackpad.systemThreeFingerDrag && prefs.trackpadMiddle != .off
             ? "Three Finger Drag is on in Accessibility settings, so three-finger presses stay drags; light taps still work in Lighter."
             : prefs.trackpadMiddle.detail)
            .font(.caption).foregroundStyle(.secondary)
        HStack {
            Toggle("Finder Dock icon opens", isOn: $prefs.finderOpensApp)
            Spacer()
            Button(prefs.finderAppPath.isEmpty ? "Choose…"
                   : FileManager.default.displayName(atPath: prefs.finderAppPath).replacingOccurrences(of: ".app", with: "")) {
                chooseFinderApp()
            }
            .controlSize(.small)
        }
    }

    private func chooseFinderApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an app to open when clicking Finder's Dock icon"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            prefs.finderAppPath = url.path
            prefs.finderOpensApp = true
        }
    }

    @ViewBuilder private var mixerSection: some View {
        Text("Volume").font(.headline)
        if permissions.audio == .denied {
            notice("Allow System Audio Recording to change app volumes.", button: "Open Settings") { permissions.openAudioSettings() }
        } else if let error = mixer.lastError {
            Text(error).font(.caption).foregroundStyle(.secondary)
        }
        if mixer.apps.isEmpty {
            Text("Nothing is playing").foregroundStyle(.secondary)
        }
        MixerList(apps: mixer.apps, levels: mixer.levels)
    }

    private func notice(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(text).font(.caption)
            Spacer()
            Button(button, action: action).controlSize(.small)
        }
    }
}

/// Rows of per-app controls; a fixed-height scroller past `maxRows`, so many audio apps can't
/// push the menu off screen.
struct MixerList: View {
    static let rowHeight: CGFloat = 46
    static let maxRows = 6
    let apps: [MixerApp]
    let levels: [String: Float]

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(apps) { app in
                    MixerRow(app: app, level: levels[app.id] ?? 0).frame(height: Self.rowHeight - 6)
                }
            }
        }
        .scrollDisabled(apps.count <= Self.maxRows)
        .frame(height: CGFloat(min(apps.count, Self.maxRows)) * Self.rowHeight)
    }
}

private struct MixerRow: View {
    let app: MixerApp
    let level: Float

    var body: some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.caption).lineLimit(1)
                Slider(value: Binding(get: { Double(app.volume) },
                                      set: { MixerModel.shared.setVolume(app.id, Float($0)) }), in: 0...1.5)
                    .controlSize(.small)
                GeometryReader { geo in
                    Capsule().fill(.quaternary)
                        .overlay(alignment: .leading) {
                            Capsule().fill(level > 0.9 ? Color.orange : Color.green)
                                .frame(width: geo.size.width * CGFloat(app.muted ? 0 : level))
                        }
                }
                .frame(height: 3)
            }
            Text("\(Int((app.volume * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(width: 38, alignment: .trailing)
            Button { MixerModel.shared.toggleMute(app.id) } label: {
                Image(systemName: app.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help(app.muted ? "Unmute" : "Mute")
        }
    }
}
