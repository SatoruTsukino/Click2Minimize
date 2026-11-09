# SPEC.md — Project Specification

> **Status**: `FINALIZED`

## Vision
Toolbelt is one lightweight macOS menu bar app that replaces four separate utilities the user runs every day: Ledge (drag shelf), Click2Minimize (Dock click behaviour), Fader (per-app volume) and Convertino (file conversion). It keeps only the features the user actually uses, shares one process, one permission set and one settings surface, and stays idle-cheap: no polling, no timers while nothing is happening.

## Goals
1. **Dock click** — Clicking the Dock icon of the frontmost app minimizes its windows, or hides the app (user choice). Fullscreen apps pass through.
2. **Shake shelf** — Shaking the pointer while dragging content opens a small floating shelf; items can be dropped in, dragged back out, Quick Looked, and removed.
3. **Convert from the shelf** — Right-click shelf items to convert/compress/resize images (ImageIO), convert video/audio (AVFoundation), and, when installed, use `ffmpeg` / `soffice` for extra formats. Output goes back into the shelf.
4. **Per-app mixer** — A menu bar popover lists apps producing audio with a volume slider, mute toggle and live level meter each; volumes persist per bundle ID.
5. **Performance** — Idle CPU ≈ 0%, no polling loops; audio work only for apps whose volume ≠ 100% or are muted, or while the popover is open (meters).

## Non-Goals (Out of Scope)
- Ledge: edge docking, notch drop, screenshots, folder monitoring, S3 upload, custom scripts, Shortcuts/Alfred, multiple named/pinned shelves.
- Click2Minimize: per-app exclude list, trackpad gestures, window overview, other Dock tweaks.
- Convertino: PDF merge/split/compress, QR, hashes, background removal, watch folders, recipes, CLI, data formats (JSON/YAML/CSV).
- App Store distribution or sandboxing (Accessibility + event taps rule it out).
- Auto-update.

## Users
The single owner of this Mac, running it at login, interacting through the menu bar icon, Dock clicks and drag-and-drop.

## Constraints
- macOS 14.2+ (Core Audio process taps), Swift 5 + SwiftUI/AppKit, `xcodegen` project, ad-hoc signed, no third-party packages.
- Accessibility permission (event tap + AX window control); Audio Capture permission (process taps).
- `ffmpeg` / `soffice` are optional: only used if found on disk, never bundled.
- Headless verification only: unit tests must not launch UI (guard app startup when `XCTestConfigurationFilePath` is set).
- Clean-room: no code from third-party apps; may reuse the user's own Ledge (MIT) and Click2Minimize 3.0 code.

## Success Criteria
- [ ] `xcodebuild` Release build succeeds with zero warnings; unit tests pass headless.
- [ ] Every v1 requirement in REQUIREMENTS.md is Built (code + test where logic is testable).
- [ ] DMG produced by `scripts/build_dmg.sh`.
- [ ] Hand test by the user confirms Dock click, shelf, conversions and mixer (GUI features stay "Built" until then).

---

*Last updated: 2026-11-09*
