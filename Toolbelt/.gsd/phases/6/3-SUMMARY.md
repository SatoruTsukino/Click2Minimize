---
phase: 6
plan: 3
completed_at: 2026-11-09T23:35:00Z
status: complete
---

# Summary: Active-use CPU (R3.4)

## Evidence
`sample` (15 s, normal use): `MixerModel.refresh` 71 ms — IsRunning/Devices listener storms (browser) re-resolved PID + owning app for ~33 processes every refresh. AX 22 ms from Dock clicks (expected).

## Fix
- Owner per process object cached (PID immutable per object); refresh = 1 HAL read per process.
- Coalesce 100 → 250 ms; unchanged refresh returns before UI/tap work.
- Mixer list capped at 6 rows (R3.3 note, MIX-10).

## Verification
| Check | Before | After |
|---|---|---|
| CPU, 120 s normal use | 0.28 s (0.23 %) | 0.05 s (0.04 %) |
| `top` 5 s samples at 0.0 % | 1/25 | 19/25 |
| Wakeups | 0 | 0 |
| Footprint | 14.1 MB | 14.1 MB |
| Unit tests | — | 22, 0 failures, 1 skipped |
