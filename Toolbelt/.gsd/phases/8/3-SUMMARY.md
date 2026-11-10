---
phase: 8
plan: 3
completed_at: 2026-11-10T09:00:00Z
status: complete
gap_closure: true
---

# Summary: Hand-test R5 gaps

## Results
- R5: 10/12 pass. Failures: R5.7 (wants tactile confirmation on window grab), R5.12 (idle 0.1–0.5 % CPU).
- **Tasks:** 2/2 · **Verification:** 42 tests pass · retest R6.1–R6.2

## Changes
| File | Change |
|---|---|
| Toolbelt/Input/MiddleButton.swift | Haptic `.alignment` tick when a middle-drag grabs a window (user chose "normal click + haptic tick") |
| Toolbelt/Input/Trackpad.swift | Callback (~90 Hz while touched) no longer allocates an array or calls `CGEventSource.buttonState` (IPC); allocation-free `TapDetector.frame(count:cx:cy:)` |
| Toolbelt/Input/InputTap.swift | Feeds left button state to the trackpad (`noteButton`) |

## Measurement before fix (running R5 build, user idle)
- top 16 × 1 s: 0.0–0.3 % CPU, 16 idle wakeups/s, 42 MB
- sample: main thread almost idle; the few busy samples are AppKit answering external Accessibility queries (Raycast running); multitouch thread receiving frames
- After-fix numbers need the new build installed (new ad-hoc signature ⇒ re-grant Accessibility)
