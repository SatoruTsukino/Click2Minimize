---
phase: 8
plan: 2
completed_at: 2026-11-10T00:00:00Z
status: complete
---

# Summary: App switcher, Finder alternate, UI

## Results
- **Tasks:** 3/3 · **Verification:** passed (SwitcherTests, prefs persistence) · GUI awaiting hand test R5

## Files Changed
| File | Change |
|---|---|
| Toolbelt/Input/AppSwitcher.swift | Created: MRU history, pure `order`/`initialSelection`, keys (⌘⇥ ⌘⇧⇥ arrows Esc Return ⌘Q ⌘H letters), release-⌘ commit, click/middle-click rows, restore minimized window, native ⌘⇥ toggle, lazy panel |
| Toolbelt/App/Prefs.swift | switcher, finderOpensApp, finderAppPath, dockMiddleQuit, middleDragMove, trackpadMiddle; `needsAccessibility`, `inputFeatures` |
| Toolbelt/App/PopoverView.swift | "Mouse & keyboard" controls, Finder app chooser, Three Finger Drag note, broader Accessibility notice |
| Toolbelt/App/AppDelegate.swift | applyPrefs drives InputTap / AppSwitcher / Trackpad; quit restores native ⌘⇥ |

## Decisions
- Pins, per-app hotkeys and auto-quit from C2M's switcher are left out (not requested).
- Defaults: switcher, Dock middle-quit and middle-drag on; trackpad Standard; Finder alternate off until an app is chosen.

## Verification
| Check | Status | Evidence |
|---|---|---|
| MRU order, dead apps dropped | ✅ | SwitcherTests.testOrderIsMostRecentFirstThenLaunchOrder |
| ⌘⇥ / ⌘⇧⇥ start positions | ✅ | SwitcherTests.testInitialSelectionLikeCommandTab |
| Finder alternate rule | ✅ | InputTapTests.testFinderAlternate |
| Prefs defaults + persistence | ✅ | SwitcherTests.testInputPrefsDefaultsAndPersist |
| GUI | ⏳ | hand test R5 |
