---
phase: 7
plan: 1
completed_at: 2026-11-09T23:58:00Z
status: complete
---

# Summary: Radial convert ring

## Results
- **Tasks:** 3/3 · **Verification:** passed (30 tests, 1 skipped: ffmpeg absent) · GUI awaiting hand test

## Files Changed
| File | Change |
|---|---|
| Toolbelt/Radial/RadialLayout.swift | Created: `ShiftTap`, ring placement, `shortTitle` |
| Toolbelt/Radial/RadialController.swift | Created: monitors scoped to the drag, `RingPanel`, `PetalView` drop targets |
| Toolbelt/Shelf/DragMonitor.swift | Notifies the ring when a drag starts or ends; shake gated by its pref |
| Toolbelt/App/{Prefs,PopoverView,AppDelegate}.swift | `shiftRing` pref (default on); drag monitor runs if either feature is on |

## Verification
| Check | Status | Evidence |
|---|---|---|
| Shift tap rules | ✅ | RadialTests.testShiftTap |
| Ring split, spacing, no overlap (1–20 petals) | ✅ | RadialTests |
| Unique petal labels | ✅ | RadialTests.testEveryActionHasUniqueShortTitle |
| Idle cost | ✅ | 13/13 samples 0.0 %, 0 wakeups, 0.01 s CPU / 60 s, 14.2 MB |
| GUI | ⏳ | hand test R4 |
