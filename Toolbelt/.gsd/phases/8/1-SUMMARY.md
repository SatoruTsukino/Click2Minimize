---
phase: 8
plan: 1
completed_at: 2026-11-10T00:00:00Z
status: complete
---

# Summary: Shared input tap, middle button, trackpad middle click

## Results
- **Tasks:** 3/3 · **Verification:** passed (42 tests, Release build with zero warnings) · GUI awaiting hand test R5

## Files Changed
| File | Change |
|---|---|
| Toolbelt/Input/InputTap.swift | Created: one tap, pure `mask(for:)`, rebuilt on feature change, passes `Synth.marker` events |
| Toolbelt/Input/Synth.swift | Created: middle-event builder, `post` (features see it) vs `replay` (marked, apps only) |
| Toolbelt/Input/MiddleButton.swift | Created: Dock quit, switcher row quit, middle-drag (4 pt threshold) with replay of plain clicks, trackpad press conversion, tap click |
| Toolbelt/Input/WindowMover.swift | Created: ported from C2M; background coalesced AX writes |
| Toolbelt/Input/Trackpad.swift | Created: MultitouchSupport (dlopen), `TapDetector`, per-frame work on the callback thread |
| Toolbelt/Dock/DockClick.swift | Private tap removed; `handleDown` called by InputTap; `finderAlternate` and `quitApp` added |
| Toolbelt/Dock/AX.swift | `window(at:)`, `position`, `setPosition` |

## Verification
| Check | Status | Evidence |
|---|---|---|
| Mask has only the needed events | ✅ | InputTapTests.testMaskCoversOnlyEnabledFeatures |
| Drag threshold | ✅ | InputTapTests.testDragThreshold |
| Tap: fires; hold, move, press, 2 and 4 fingers don't | ✅ | TapDetectorTests (6) |
| DockDecision regression | ✅ | DockDecisionTests |
| Live idle sample | ⏳ | Not measured: the new build needs Accessibility re-granted (new ad-hoc signature) and the /Applications copy is running |
| GUI | ⏳ | hand test R5 |
