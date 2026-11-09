---
updated: 2026-11-09T22:00:00Z
---

# Project State

## Current Position

**Milestone:** v1.0
**Phase:** 6 - Hand-test gap closure (executed)
**Status:** verifying — waiting on round-3 retest
**Plan:** —

## Last Action

R3.4 measured during normal use: 0.23 % avg → 0.04 % avg (0.05 s CPU / 120 s) after caching process owners (plan 6.3). 22 tests pass. MIX-10 verified headless (MixerListTests); 23 tests pass.

## Next Steps

1. User checks SHELL-06 (menu grows downward)
2. Commit `Toolbelt/`
3. Optional: measure active-path perf (mixer taps, meters) with `sudo powermetrics`

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
