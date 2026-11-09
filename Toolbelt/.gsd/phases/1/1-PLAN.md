---
phase: 1
plan: 1
wave: 1
gap_closure: false
---

# Plan 1.1: Project + app shell

## Objective
Generated Xcode project and a menu bar accessory app with a popover, persisted feature toggles, permission status and launch at login. Test target must not start the app's UI.

## Context
- .gsd/SPEC.md
- /Users/jsph/Ledge/project.yml (pattern)

## Tasks

<task type="auto">
  <name>xcodegen project</name>
  <files>Toolbelt/project.yml, Toolbelt/Toolbelt/Info.plist, Toolbelt/Toolbelt/Toolbelt.entitlements</files>
  <action>
    App target (macOS 14.2, LSUIElement, NSAudioCaptureUsageDescription, ad-hoc), unit test target with TEST_HOST.
    AVOID: hardened runtime/sandbox because event taps + AX need unsandboxed.
  </action>
  <verify>xcodegen generate</verify>
  <done>Toolbelt.xcodeproj generated</done>
</task>

<task type="auto">
  <name>App shell</name>
  <files>Toolbelt/Toolbelt/App/*.swift</files>
  <action>
    NSStatusItem + NSPopover hosting SwiftUI PopoverView; Prefs (UserDefaults); Permissions (AXIsProcessTrusted, audio TCC preflight); LoginItem (SMAppService).
    Startup guard: skip feature start when XCTestConfigurationFilePath is set.
  </action>
  <verify>xcodebuild -scheme Toolbelt build</verify>
  <done>Build succeeds, zero warnings</done>
</task>

## Must-Haves
- [ ] SHELL-01..04 built
- [ ] Tests run without UI

## Success Criteria
- [ ] All tasks verified passing
