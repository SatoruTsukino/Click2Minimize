# REQUIREMENTS.md

Status values: `Pending` → `Built` (code done, unit-tested where logic is testable) → `Verified` (passed user hand test) → `Complete` (verified and committed).

## Format
| ID | Requirement | Source | Status |
|----|-------------|--------|--------|
| SHELL-01 | Menu bar–only accessory app (`LSUIElement`), one status item with a popover containing the mixer, toggles and Quit | SPEC goal 1–4 | Verified |
| SHELL-02 | Permission status for Accessibility and Audio Capture with buttons that open the matching System Settings pane | SPEC constraints | Verified |
| SHELL-03 | Launch at login toggle via `SMAppService.mainApp` | SPEC users | Verified |
| SHELL-04 | Each feature (Dock click, Shake shelf, Mixer) can be turned on/off; settings persist in `UserDefaults` | SPEC goal 5 | Verified |
| DOCK-01 | Clicking the Dock icon of the active, unhidden app minimizes all its visible windows (AX `kAXMinimizedAttribute`); the click is swallowed | SPEC goal 1 | Verified |
| DOCK-02 | Mode choice: Minimize windows or Hide app | SPEC goal 1 | Verified |
| DOCK-03 | Pass-through when app is not active, is fullscreen, item is not an app (Trash, folders, Launchpad), or app has no visible windows | SPEC goal 1 | Verified |
| DOCK-04 | Dock items hit-tested live through AX at the pointer (no AppleScript, no cache) | SPEC goal 5 | Verified |
| SHLF-01 | Shaking the pointer while dragging content (drag pasteboard changed) opens a floating, non-activating shelf under the pointer, on all Spaces | SPEC goal 2 | Verified |
| SHLF-02 | Dropping files, images and text adds them; raw image/text data is saved as files in an app temp folder | SPEC goal 2 | Verified |
| SHLF-03 | Dragging out drags all items (from the shelf header) or a single item; close button empties/closes the shelf | SPEC goal 2 | Verified |
| SHLF-04 | Space bar / context menu Quick Look; context menu Show in Finder, Remove | SPEC goal 2 | Verified |
| CONV-01 | Image actions on selected/all image items: Convert to JPEG/PNG/HEIC/TIFF, Compress (quality), Resize (50% or fit-to max px) via ImageIO, EXIF orientation honoured | SPEC goal 3 | Verified |
| CONV-02 | Video actions via AVFoundation: Convert to MP4 / MOV, Shrink (1080p/720p presets), Remove audio, Extract audio to M4A | SPEC goal 3 | Verified |
| CONV-03 | If `ffmpeg` is found (`/opt/homebrew/bin`, `/usr/local/bin`, PATH): extra targets MP3, WAV, WEBM, GIF for media items | SPEC goal 3 | Verified |
| CONV-04 | If `soffice` (LibreOffice) is found: documents (doc/docx/odt/rtf/ppt/pptx/xls/xlsx) → PDF | SPEC goal 3 | Built (untested: LibreOffice not installed) |
| CONV-05 | Conversions run off the main thread, results are added to the shelf from a temp folder (originals' folders untouched), errors shown as an alert-free inline shelf message | SPEC goal 3, 5 | Verified |
| MIX-01 | Popover lists processes currently producing audio (Core Audio process object list, `IsRunningOutput`), with app name and icon | SPEC goal 4 | Verified |
| MIX-02 | Per-app volume slider 0–150% applied through a process tap + aggregate device (tap muted when tapped, re-rendered with gain) | SPEC goal 4 | Verified |
| MIX-03 | Per-app mute toggle | SPEC goal 4 | Verified |
| MIX-04 | Live peak level meter per app while the popover is open | SPEC goal 4 | Verified |
| MIX-05 | Volume/mute persisted per bundle ID and re-applied when the app starts producing audio again | SPEC goal 4 | Verified |
| MIX-06 | Taps exist only for apps at ≠100% or muted, or while the popover shows meters; default output device change rebuilds taps | SPEC goal 5 | Verified |
| SHELL-05 | Single instance: a second launch reopens the running copy's menu and quits (two copies double-tap audio → echo) | Hand test 6.4 | Verified |
| SHLF-05 | Layouts: Stack (default; one click selects all, one drag takes all), Grid, List; a single item fills the shelf | Hand test 4.1, 4.4 | Verified |
| SHLF-06 | Everything the shelf creates lives in a temp folder; items dragged out leave the shelf, their temp files deleted after 60 s; temp purged at launch | Hand test 4.1 | Verified |
| MIX-07 | Volume snaps to 100 % within ±4 % (also for stored values), so near-normal apps need no tap | Hand test 6.2, 7.1 | Verified |
| MIX-08 | All tap create/destroy runs on a background queue; menu never stalls | Hand test 6.1, 6.4 | Verified |
| MIX-09 | Listing follows processes via `IsRunning` + `Devices` listeners (`IsRunningOutput` never notifies), so restarted/new apps appear without reopening Toolbelt | Hand test R2.7, R2.8 | Verified |
| DOCK-05 | Dock pre-filter band = Dock tile size (or magnified size) + 24 px, so other clicks never cost an AX query; clicks cost no pasteboard IPC | Hand test R2.10 | Verified |
| MIX-10 | Mixer list scrolls past 6 apps so the menu never grows off screen | Hand test R3.3; MixerListTests (headless layout: 2→92 pt, 6/20→276 pt) | Verified |
| MIX-11 | Process owner (PID → app) cached per audio object; listener storms coalesced 250 ms; unchanged refresh does no UI/tap work | R3.4 measurement | Verified |
| SHELL-06 | Menu is a top-pinned panel (below the icon, or top-right under the menu bar when the icon is hidden); it grows downward and closes on click-away/Esc | User report: menu crawls up | Built |
| PACK-01 | `xcodegen` project, Release build with zero warnings, unit tests pass headless | SPEC success | Verified |
| PACK-02 | `scripts/build_dmg.sh` writes `dist/Toolbelt.dmg`, ad-hoc signed | SPEC success | Verified |

## Traceability
| Phase | Requirements |
|-------|--------------|
| 1 Foundation | SHELL-01..04, PACK-01 |
| 2 Dock click | DOCK-01..04 |
| 3 Shelf + convert | SHLF-01..04, CONV-01..05 |
| 4 Mixer | MIX-01..06 |
| 5 Package | PACK-02 |
| 6 Hand-test gaps | SHELL-05, SHLF-05, SHLF-06, MIX-07, MIX-08, MIX-09, MIX-10, MIX-11, DOCK-05 |
