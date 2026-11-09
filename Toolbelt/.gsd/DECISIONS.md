# DECISIONS.md — ADR log

## ADR-001: Feature scope from user quiz (2026-11-09)
- **Ledge:** shake-to-shelf + basic shelf only.
- **Click2Minimize:** Dock click minimizes; option to hide instead.
- **Fader:** volume sliders, mute, level meters, remembered volumes (all).
- **Convertino:** image convert/compress/resize; video/audio + documents.
- **Rationale:** consolidate only used features; Ledge image actions and Convertino image features overlap → one conversion engine.

## ADR-002: Conversions are shelf actions (2026-11-09)
Right-click on shelf items, output back to shelf. No separate radial menu / gesture. One drag surface.

## ADR-003: Media dependencies (2026-11-09)
AVFoundation natively (MP4/MOV/M4A, remove audio, shrink). `ffmpeg` and `soffice` used only when found on disk; their actions are hidden otherwise. Nothing bundled.

## ADR-004: Platform + location (2026-11-09)
macOS 14.2+ (process taps). App lives at `appwork/Toolbelt/`, xcodegen + ad-hoc signing like Ledge. No third-party packages (global hotkeys not needed in scope).

## ADR-005: Dock hit-testing via AX at pointer (2026-11-09)
Reuse the user's Click2Minimize 3.0 approach: `AXUIElementCopyElementAtPosition` on mouse-down near the Dock edge; no AppleScript cache, no Automation permission.

## ADR-006: Audio taps on demand (2026-11-09)
A process tap mutes the original stream and re-renders it with gain, adding latency. Create taps only for apps with volume ≠ 100% / muted, or while the popover is open for meters; tear down otherwise.
