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

## ADR-007: Radial convert ring (2026-11-09)
Convertino-style ring added alongside the shelf actions (it doesn't replace ADR-002). Tap Shift during a content drag to toggle it. Every action is shown: 8 on the inner ring, the rest on an outer ring. Results go to the shelf (temp), not beside the original. Its key monitor exists only during content drags.

## ADR-008: Input features from Click2Minimize and WheelClick (2026-11-10)
- **Added (user request):** a vertical ⌘⇥ app switcher, Finder's Dock icon opening another app, middle-clicking a Dock icon to quit the app, and middle-dragging to move the window under the pointer (all ported from the user's Click2Minimize 3.0 code). Also a trackpad middle click with two sensitivities, matching WheelClick's free gestures: **Standard** is a three-finger physical press (WheelClick's "Three-Finger Click"); **Lighter** is also a light three-finger tap with no press (WheelClick's "Three-Finger Tap").
- **One event tap:** a single `InputTap` replaces DockClick's private tap. Its event mask is rebuilt from the enabled features, so keyboard events are tapped only while the switcher is on, and drag events only while the trackpad middle click is on. Events Ledge synthesizes carry a marker and pass straight through.
- **Native ⌘⇥:** turned off with the private `CGSSetSymbolicHotKeyEnabled(1/2)` only while the switcher is on. It is turned back on when the switcher is switched off and when Toolbelt quits. A crash leaves it off until Toolbelt runs again, which restores the setting at launch.
- **Trackpad:** the private MultitouchSupport framework (loaded at runtime with dlopen) runs only while the trackpad middle click is on. Tap detection runs on its callback thread; the main thread is woken only for an actual tap. Standard mode is suspended while macOS Three Finger Drag is on, as in WheelClick.
