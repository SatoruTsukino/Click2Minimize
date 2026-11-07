<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/hero-banner-dark.svg" />
    <img src="assets/hero-banner.svg" alt="Click2Minimize" width="100%" />
  </picture>
</p>

<p align="center">
  <a href="https://github.com/hatimhtm/Click2Minimize/releases/latest"><img src="https://img.shields.io/github/v/release/hatimhtm/Click2Minimize?style=flat-square&label=DOWNLOAD&labelColor=14151A&color=2E4FD6" alt="Latest release" /></a>
  <img src="https://img.shields.io/badge/macOS-14.0+-2E4FD6?style=flat-square&logo=apple&logoColor=white&labelColor=14151A&color=2E4FD6" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-5-2E4FD6?style=flat-square&logo=swift&logoColor=white&labelColor=14151A&color=2E4FD6" alt="Swift 5" />
  <img src="https://img.shields.io/badge/Xcode-16-2E4FD6?style=flat-square&logo=xcode&logoColor=white&labelColor=14151A&color=2E4FD6" alt="Xcode 16" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/LICENSE-POLYFORM_NC-2E4FD6?style=flat-square&labelColor=14151A&color=2E4FD6" alt="PolyForm Noncommercial" /></a>
</p>

<p align="center">
  <em><strong>Click an app's dock icon to minimize its windows, and a lot more.</strong> Click2Minimize is a free Swift menu-bar utility that adds the window, Dock and gesture behaviour macOS leaves out: minimize, close, fill, snap, move and resize windows without aiming at tiny buttons, plus an enhanced app switcher and a window overview that includes minimized windows. Every feature is free: no license key, no trial, no telemetry. Free to use personally, not for commercial reuse (see <a href="LICENSE">LICENSE</a>).</em>
</p>

## What it does

The original behaviour is on by default: click the Dock icon of the app you're already using and its windows minimize. Click again to bring them back, like the Windows taskbar. Everything else is off until you turn it on in Settings, one feature at a time.

| Area | Features |
|---|---|
| **Dock** | Click a focused app's icon to minimize all windows, minimize the front one, cycle windows, or hide the app · hand focus to the previous app after the last window goes · double-click an icon to hide other apps · middle-click an icon to quit · hover an icon for App Exposé · replace Finder's icon with another app · lock the Dock to the main display · Dock Fidget: slide from the trackpad's bottom edge to run the pointer along the Dock with a haptic tick per icon · instant auto-hide · minimize into app icon |
| **Minimize** | Right-drag down · hold right, click left · 3-finger swipe down |
| **Close & quit** | Triple right-click · middle-click near any button matching a keyword (no aiming) · middle-click to dismiss notification banners · middle-click a window in Mission Control or App Exposé to close it · middle-click an app in the Dock, the switcher or Stage Manager to quit it |
| **Full screen & fill** | Right-drag up · double right-click to fill (and restore) · hold left, click right · double-click the camera area |
| **Move & resize** | Middle-drag anywhere · light 3-finger press, then move without pressure · middle-button + scroll · pinch during the 3-finger drag · animated moves (respects Reduce Motion) |
| **Snap & warp** | Right-drag to halves, quarters or maximize with a live preview · double right-click a title bar, or 2-finger double-click at the top of the trackpad, to move to the next display |
| **App switcher** | Replace ⌘⇥ · hold right and scroll · 3-finger swipe up · pinned apps · keep quit apps · type a letter to jump · per-app show/hide hotkeys · per-app auto-quit after idling |
| **Window overview & stash** | A grid of every window including minimized and hidden ones (4-finger swipe, double-click a screen edge, or right + side button) · middle-click to close · stash hides everything and brings it back |
| **Shortcut gestures** | Right-drag circles and shakes, 2-finger rotation, wheel tilt: each runs a window action, Mission Control, a desktop switch, a keyboard shortcut or a Shortcuts.app shortcut |
| **Universal** | Back / forward everywhere via 3-finger swipe or mouse side buttons, with per-app overrides · fn + swipe/scroll to jump to top or bottom · modifier + swipe/scroll as arrow keys · 3-finger click as middle click · trackpad-edge slide for volume and for the brightness of the display under the pointer, external monitors included |
| **Control** | Exclude apps from gestures · pause in macOS Game Mode · palm rejection · back up and restore settings · restart shortcut · hide the menu-bar icon |
| **macOS settings** | Native three-finger drag · hand 3- or 4-finger swipes over from macOS in one click · alert volume · shortcuts to scroll speed |

## How it works

```
 CGEvent tap (mouse, scroll, keys) ──┐
                                     ├──▶ EventRouter ──▶ Dock · WindowOps · AppSwitcher · Overview · Actions
 MultitouchSupport (raw touches) ────┘        │
                                              └── held clicks are replayed when no gesture happens
```

- **One event tap** at `cghidEventTap` routes every mouse, scroll and key event. Each button has its own state machine; a press that turns out not to be a gesture is replayed, so normal clicks and context menus keep working.
- **Dock items are hit-tested live** through Accessibility at the pointer. That is correct with magnification, auto-hide and multiple displays, and needs no Automation (AppleScript) permission any more.
- **Window control** uses the Accessibility API (`AXMinimized`, `AXFullScreen`, position and size, the close button's press action), never simulated clicks on title-bar buttons.
- **Trackpad gestures** read raw contacts from the private `MultitouchSupport` framework, loaded at runtime and only started while a trackpad feature is on.
- **Window overview thumbnails** use ScreenCaptureKit when Screen Recording is granted. Windows are snapshotted just before Click2Minimize minimizes them, because minimized windows can't be captured later. Without the permission the overview shows app icons.
- **Undocumented macOS interfaces**, all resolved at runtime so a missing one disables a feature instead of breaking launch:

  | Interface | Used for |
  |---|---|
  | `MultitouchSupport` | raw trackpad contacts |
  | `CGSSetSymbolicHotKeyEnabled` | handing ⌘⇥ to the app switcher |
  | `CoreDockSendNotification` | Mission Control, App Exposé, Show Desktop, Launchpad |
  | `_AXUIElementGetWindow` | window ids for thumbnails and fill / restore |
  | `DisplayServices` | brightness of built-in and Apple displays |
  | `IOAVService` DDC/CI | brightness of other external monitors (Apple silicon), with gamma dimming as a fallback |
  | `OSDManager` | the native brightness HUD |
  | `com.apple.system.game_mode_status_changed` | Game Mode pause |
  | `activateSettings -u` | applying trackpad gesture settings live |
- **Gesture maths** (lines, circles, shakes, snap zones, display mapping, version checks) lives in a pure Swift file covered by `./test_logic.sh`.

## Highlights

| | |
|---|---|
| **Free, all of it** | No license, trial or paywall. The commercial Click2Minimize 3.x sells most of these features; here they are free |
| **No window** | Menu-bar accessory app (`LSUIElement`); the icon can be hidden, and launching the app again opens Settings |
| **No telemetry** | Zero network calls except the GitHub releases check |
| **One permission** | Accessibility. Screen Recording is optional and only adds thumbnails |
| **Opt-in everything** | Only the original click-to-minimize is on by default |
| **Universal binary** | arm64 + x86_64; ad-hoc signed DMG |
| **Source-available** | PolyForm Noncommercial 1.0.0 |

## 3.0: what changed from 2.1

- **New**: feature parity with the commercial Click2Minimize 3.x (Dock, window controls, snapping, app switcher, window overview and stash, shortcut gestures, universal navigation, trackpad gestures, backup and restore), reimplemented from scratch and free.
- **Changed**: Dock detection moved from an AppleScript query of System Events to live Accessibility hit-testing. The Automation permission and the per-app name map hack are gone.
- **Changed**: no relaunch after granting Accessibility. The app starts working as soon as access is granted.
- **Changed**: Settings rebuilt as a sidebar window with one page per area.
- **Fixed**: the update check never offered updates, because `v`-prefixed tags parsed as version 0. Install now stages the new app and swaps it in atomically, instead of deleting the old one first.
- **New**: Game Mode pause, external-monitor brightness over DDC with the native HUD, Dock Fidget on the trackpad, close-from-Mission-Control, quit-from-Stage-Manager, light-press 3-finger window drag, native trackpad settings, animated window moves, restart shortcut, snap cancel (Esc or left tap).
- **Requires**: macOS 14 (for ScreenCaptureKit window snapshots).

## 2.1: what changed from 2.0

- **Fixed**: `isActiveAppFullscreen()` was inspecting Click2Minimize's own `NSWindow`s: always returned false. Rewritten to read `AXFullScreen` on the frontmost app via Accessibility.
- **Fixed**: dock-item ignore-list was `"Launchpad||Trash||Downloads".contains(name)`: substring match, would catch "TrashCan" or any app with "Trash" in the name. Replaced with proper `Set` membership.
- **Fixed**: dock-update debounce was firing every event and only suppressing later ones inside the 0.5s window: it never actually coalesced bursts. Rewritten with `DispatchWorkItem` trailing-edge debounce at 300ms.
- **Improved**: all `print()` calls migrated to `os.Logger` with privacy modifiers. Release builds no longer write to stdout.
- **Improved**: launch-at-login is now an opt-in toggle in Settings instead of unconditional. Existing installs that were auto-registered stay registered until toggled off.
- **Improved**: settings sheet redesigned (launch-at-login row, cleaner spacing, footnote anchored).
- **Improved**: deprecated `NSWorkspace.launchApplication(_:)` swapped for `openApplication(at:configuration:completionHandler:)`.
- **Bumped**: marketing version → 2.1 to align the in-app version with the GitHub release tag (was 1.4 in-plist while the latest release was already tagged v2.0).

## Install

1. Grab the latest `.dmg` from [Releases](../../releases/latest).
2. Open it, drag `Click2Minimize.app` into `/Applications`.
3. Launch it. You'll be prompted for **Accessibility** permission: open System Settings → Privacy & Security → Accessibility and toggle Click2Minimize on. It starts working right away.
4. Optional: grant **Screen Recording** from Settings › General to get window thumbnails in the window overview.
5. Some gestures overlap macOS trackpad gestures (3- and 4-finger swipes). Turn those off in System Settings › Trackpad › More Gestures before enabling the Click2Minimize versions.

The DMG is ad-hoc signed, so the first launch will need a right-click → Open to get past Gatekeeper.

## Build from source

```bash
git clone https://github.com/hatimhtm/Click2Minimize.git
cd Click2Minimize

# Release build into ./build
xcodebuild -scheme Click2Minimize -configuration Release -derivedDataPath build

# Or build the full DMG in ./dist
./build_dmg.sh

# Logic tests (gesture maths) and build-script tests
./test_logic.sh
./test_build_dmg.sh
```

Requires Xcode 16+. Targets macOS 14.0+.

## License

[PolyForm Noncommercial 1.0.0](LICENSE). In plain English:

- **Allowed**: reading, learning, personal use, hobby use, non-profit / educational / research use, forking to improve, distributing your fork under the same license.
- **Not allowed**: shipping it inside a paid product, selling support for it, embedding it in commercial software, any commercial use.

If you want a commercial license, [open an issue](../../issues) or [book a call](https://cal.com/hatimelhassak/engineering-discovery).

---

<p align="center">
  <a href="https://hatimelhassak.is-a.dev">Portfolio</a> ·
  <a href="https://cal.com/hatimelhassak/engineering-discovery">Book a call</a> ·
  <a href="https://www.linkedin.com/in/hatim-elhassak/">LinkedIn</a> ·
  <a href="mailto:hatimelhassak.official@gmail.com">Email</a> ·
  <a href="https://buymeacoffee.com/hatimelhassak">Buy me a coffee</a>
</p>
