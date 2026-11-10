---
updated: 2026-11-10T02:10:00Z
---

# Project State

## Current Position

**Milestone:** v1.0
**Phase:** 7 - Radial convert ring (executed)
**Status:** verified — R4 7/7 pass; committed
**Plan:** —

## Last Action

Phase 7: Shift-tap convert ring built (ADR-007). 30 tests pass. Idle unchanged: 0.0 %, 0 wakeups, 0.01 s CPU / 60 s, 14.2 MB. Hand test R4 passed 7/7 (RING-01..04, SHELL-06 Verified). Phase 7 committed on feat/toolbelt.

## Next Steps

1. Push or merge feat/toolbelt when the user asks
2. Optional: measure active-path perf (mixer taps, meters) with `sudo powermetrics`

## Active Decisions

| Decision | Choice | Made | Affects |
|----------|--------|------|---------|
| Scope | ADR-001 | 2026-11-09 | all |
| Popover built lazily | first open | 2026-11-09 | perf |

## Blockers

None.

## Concerns

- Mixer taps not exercised headless (needs System Audio Recording consent + playing audio).
- Uses private `TCCAccessPreflight` (dlsym, optional) and `responsibility_get_pid_responsible_for_pid`; fine for personal use, not App Store.

## Session Context

App at `appwork/Toolbelt`. Build: `scripts/build_dmg.sh`. Tests: `xcodebuild -project Toolbelt.xcodeproj -scheme Toolbelt -derivedDataPath build/dd test` (run `xcodegen generate` after adding files).
