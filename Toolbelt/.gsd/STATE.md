---
updated: 2026-11-10T12:00:00Z
---

# Project State

## Current Position

**Milestone:** v1.0
**Phase:** 8 - Input features (C2M + WheelClick) (executed)
**Status:** built; 42 tests pass; awaiting hand test R5
**Plan:** —

## Last Action

Phase 8: one shared InputTap (replaces DockClick's tap), vertical ⌘⇥ switcher, Finder Dock icon → chosen app, Dock middle-click quits, middle-drag moves windows, trackpad middle click Standard (three-finger press) / Lighter (+ light tap). Release build has zero warnings; dist/Toolbelt.dmg rebuilt.

## Next Steps

1. Hand test R5: install the new DMG, re-grant Accessibility, try ⌘⇥ / Finder icon / middle-click Dock / middle-drag / three-finger press + tap
2. Re-measure idle (0 % CPU, 0 wakeups, MB) with the new build
3. Push or merge feat/toolbelt when the user asks
4. Optional: measure active-path perf (mixer taps, meters) with `sudo powermetrics`

## Active Decisions

| Decision | Choice | Made | Affects |
|----------|--------|------|---------|
| Scope | ADR-001 | 2026-11-09 | all |
| Popover built lazily | first open | 2026-11-09 | perf |

## Blockers

None.

## Concerns

- Mixer taps not exercised headless (needs System Audio Recording consent + playing audio).
- Native ⌘⇥ is disabled via private `CGSSetSymbolicHotKeyEnabled` while the switcher is on; a crash leaves it off until Toolbelt relaunches (restored at launch/quit).
- MultitouchSupport is private and loaded at runtime; a macOS change could break the trackpad middle click (fails soft: feature does nothing).
- Uses private `TCCAccessPreflight` (dlsym, optional) and `responsibility_get_pid_responsible_for_pid`; fine for personal use, not App Store.

## Session Context

App at `appwork/Toolbelt`. Build: `scripts/build_dmg.sh`. Tests: `xcodebuild -project Toolbelt.xcodeproj -scheme Toolbelt -derivedDataPath build/dd test` (run `xcodegen generate` after adding files).
