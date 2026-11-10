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

## Measurement after fix (installed 6398b37, Accessibility granted, multitouch running)
- top 30 × 1 s: avg 0.07 %, max 0.2 %, 15/30 samples 0.0 %, 0 idle wakeups/s, 14 MB (was 16 wakeups/s, 42 MB)

## R6 retest
- R6.1 ✗ "window isnt getting grabbed": root cause, a pressed three-finger drag moves no pointer, so no drag events reached the middle-drag code. Fix: while a three-finger press is held, the multitouch centroid drives the pointer (detached and warped) and posts middle-drag events (`Trackpad.beginFollow`); the pointer is reattached on release and on quit.
- R6.2 ✗ "0.5% top when moving mouse": while any finger is on the trackpad, the private multitouch framework delivers ~90 frames/s; Toolbelt's own per-frame work is now allocation- and IPC-free. Remaining cost is the framework's frame delivery, inherent while the trackpad middle click is on (Off = 0 frames).
