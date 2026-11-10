---
phase: 8
plan: 2
wave: 2
gap_closure: false
---

# Plan 8.2: App switcher, Finder alternate, UI

## Objective
Add a vertical ⌘⇥ switcher and Finder-icon-opens-app, with popover controls for all phase 8 features.

## Context
- Plan 8.1 output (InputTap)
- /Users/jsph/Click2Minimize/Click2Minimize/AppSwitcher.swift (reference; pins, per-app hotkeys and auto-quit are out of scope)

## Tasks

<task type="auto">
  <name>Switcher model</name>
  <files>Toolbelt/Input/AppSwitcher.swift</files>
  <action>Keep an MRU history from `didActivateApplication`. Write `AppSwitcher.order(running:history:)` and `initialSelection(front:delta:)` as pure functions. Handle keys: ⌘⇥ / ⌘⇧⇥ / arrows / Tab / Esc / Return / ⌘Q / ⌘H / letter jump; releasing ⌘ commits. Commit unhides and activates the app, restoring a window if all are minimized. Native ⌘⇥ is disabled while on and restored on off/quit/launch.</action>
  <verify>SwitcherTests</verify>
  <done>SWCH-01, SWCH-02</done>
</task>

<task type="auto">
  <name>Switcher panel</name>
  <files>Toolbelt/Input/AppSwitcher.swift</files>
  <action>Write a borderless non-activating panel, built lazily, centred on the screen under the pointer. Rows show icon and name, with a hidden badge. Clicking a row picks it, clicking outside cancels, and middle-click quits the row.</action>
  <verify>build; hand test</verify>
  <done>Panel matches SWCH-01</done>
</task>

<task type="auto">
  <name>Finder alternate + popover UI + wiring</name>
  <files>Toolbelt/Dock/DockClick.swift, Toolbelt/App/Prefs.swift, Toolbelt/App/PopoverView.swift, Toolbelt/App/AppDelegate.swift</files>
  <action>Clicking Finder's Dock icon opens the chosen app when that is on. Add prefs: switcher, finderOpensApp + finderAppPath, dockMiddleQuit, middleDragMove, trackpadMiddle. Add a popover "Mouse & keyboard" section. The Accessibility notice covers every feature that needs it. applyPrefs updates InputTap, Trackpad and AppSwitcher; terminate restores native ⌘⇥.</action>
  <verify>PrefsTests; idle sample (0 % CPU, 0 wakeups)</verify>
  <done>DOCK-06; every control persists</done>
</task>
