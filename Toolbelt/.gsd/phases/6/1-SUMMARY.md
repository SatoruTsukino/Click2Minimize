---
phase: 6
plan: 1
completed_at: 2026-11-09T23:00:00Z
status: complete
---

# Summary: Hand-test gap closure

## Results
- **Tasks:** 3/3 · **Commits:** 0 (uncommitted) · **Verification:** passed (22 tests, 1 skipped: ffmpeg absent)

## Root causes
| Finding | Cause | Fix |
|---|---|---|
| 6.4 app not re-listed, menu dead, echo | Two Toolbelt instances (both tapping → echo); HAL tap create/destroy on main thread stalled the menu and the refresh | Single-instance guard; `TapEngine` serial queue |
| 6.1 slow to list | Same main-thread tap work after each refresh | `TapEngine` |
| 7.1 idle spikes | Stored volumes 99.8 % / 101.2 % kept taps rendering permanently; drag monitor read the drag pasteboard (IPC) on every drag event | Snap on set and read; probe only first 30 drag events |
| 4.1/4.2/4.4 | UX requests | Stack/Grid/List; single item fills; drag-out removes items; temp lifecycle |
| 6.2 | UX request | ±4 % snap |

## Verification
| Check | Status | Evidence |
|---|---|---|
| Unit tests | ✅ | 22 executed, 0 failures |
| Single instance | ✅ | `open` twice → one PID |
| Idle, menu closed | ✅ | 14.3 MB, 0.0 % CPU, 0 wakeups / 5 s (60 s) |
| Menu open with audio playing | ℹ️ | ~0.1–1.5 % CPU, 37 MB: meters tap every playing app (by design, only while open) |
| GUI | ⏳ | round-2 retest |

## Notes
- Fader still running alongside Toolbelt also taps audio → echo. Quit Fader during tests.
