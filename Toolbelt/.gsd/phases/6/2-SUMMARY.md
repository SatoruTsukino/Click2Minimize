---
phase: 6
plan: 2
completed_at: 2026-11-09T23:20:00Z
status: complete
---

# Summary: Gap closure (round 2)

## Root causes
| Finding | Evidence | Fix |
|---|---|---|
| R2.7 restarted app not listed, R2.8 slow | Probe: new afplay process listed with IsRunningOutput 0, then 1 with no IsRunningOutput callback; wildcard listener showed `pir?` + `pdv#` at +70 ms | Watch IsRunning + Devices |
| R2.10 steady 0.1 % | `sample`: AX IPC (`_AXXMIGCopyAttributeValue`) from the event-tap Source1 for clicks in the 220 px band; drag-pasteboard IPC on every mouse-down | Band from Dock settings; no IPC on mouse-down |

## Verification
| Check | Status | Evidence |
|---|---|---|
| Unit tests | ✅ | 22 executed, 0 failures, 1 skipped (ffmpeg) |
| Idle (menu closed) | ✅ | 14.3 MB; 11/13 samples 0.0 %, 2/13 0.3 % during user input; 0 wakeups; 0.47 s CPU in 140 s incl. launch |
| GUI | ⏳ | round-3 retest |
