---
phase: 5
plan: 1
completed_at: 2026-11-09T22:00:00Z
status: complete
---

# Summary: DMG + perf

## Results
- `scripts/build_dmg.sh` → `dist/Toolbelt.dmg` (universal arm64+x86_64, ad-hoc, 2.0 MB app). `hdiutil verify`: VALID. Release build: 0 compiler warnings.

## Performance (Release build, idle, 60 s sampled with top/vmmap)

| App | Physical footprint | CPU | Idle wakeups / 5 s |
|-----|-------------------|-----|---------|
| **Toolbelt** (all 4 features) | **12.6 MB** | **0.0 %** | **0** |
| Ledge | 14.6 MB | 0.0 % | 8 |
| Click2Minimize | 18.9 MB | 0.0 % | 1 |
| Fader | 20.0 MB | 0.7 % | 386 |
| Convertino | 77.7 MB | 0.1 % | 886 |
| **Originals combined** | **131 MB** | **0.8 %** | **1281** |

GPU/energy: `top` power column 0.0 at idle; no window or layer renders while the popover and shelf are closed.

## Deviations Applied
- Footprint: popover SwiftUI graph built on first open (13.7 → 12.6 MB idle, wakeups 1 → 0).
- Hot path: Dock defaults cached instead of opened per click.

## Footprint design (why it stays idle)
- No timers or polling at idle. Dock: one event tap (mouse down/up), AX query only for clicks in the Dock band. Shelf: drag monitor does work only during a content drag. Mixer: Core Audio property listeners; taps only for apps ≠100 %/muted; 20 Hz meter timer only while popover open.

## Not measured
- Active-path cost (live taps, meters, conversions): needs consent + audio playback; measure with `sudo powermetrics --samplers cpu_power,gpu_power -i 1000` while using it.
