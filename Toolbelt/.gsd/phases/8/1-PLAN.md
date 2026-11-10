---
phase: 8
plan: 1
wave: 1
gap_closure: false
---

# Plan 8.1: Shared input tap, middle button, trackpad middle click

## Objective
Replace DockClick's private event tap with one shared `InputTap`, then add Dock middle-click to quit, middle-drag to move windows, and the trackpad middle click (Standard / Lighter) on top of it.

## Context
- .gsd/DECISIONS.md (ADR-005, ADR-008)
- Toolbelt/Dock/DockClick.swift, Toolbelt/Dock/AX.swift
- /Users/jsph/Click2Minimize/Click2Minimize/{EventRouter,WindowOps,Trackpad,Input}.swift (reference)

## Tasks

<task type="auto">
  <name>InputTap + Synth</name>
  <files>Toolbelt/Input/InputTap.swift, Toolbelt/Input/Synth.swift, Toolbelt/Dock/DockClick.swift</files>
  <action>Write `InputTap.Features` → `mask(for:)` (pure). One `.cgSessionEventTap` / `.headInsertEventTap` / `.defaultTap`, rebuilt when the features change and absent when none are on. Re-enable it after a timeout. Dispatch events to DockClick, MiddleButton and AppSwitcher, and pass through events carrying `Synth.marker`. DockClick keeps its hit-testing and decision table but loses its own tap.
  AVOID: two taps for the same events; keyboard events in the mask while the switcher is off.</action>
  <verify>InputTests.testMask; DockDecisionTests still pass</verify>
  <done>Mask contains exactly the events the enabled features need</done>
</task>

<task type="auto">
  <name>Middle button + window mover</name>
  <files>Toolbelt/Input/MiddleButton.swift, Toolbelt/Input/WindowMover.swift, Toolbelt/Dock/AX.swift</files>
  <action>On middle down: if the switcher is visible, quit the row under the pointer. If it is a Dock app icon (not Finder) and Dock quit is on, terminate the app. If middle-drag is on, hold the event: past 4 pt of movement, start WindowMover on `AX.window(at:)`; on release with no drag, replay the held down/up with the marker. WindowMover is ported from C2M: it records the origin once, applies offsets, and drains only the latest position on a background queue.</action>
  <verify>InputTests.testDragThreshold; build</verify>
  <done>DOCK-07, MIDL-01</done>
</task>

<task type="auto">
  <name>Trackpad middle click</name>
  <files>Toolbelt/Input/Trackpad.swift</files>
  <action>Load MultitouchSupport with dlopen and start it only while the mode is not Off. The callback thread keeps the finger count under a lock and runs the pure `TapDetector`: a three-finger tap is shorter than 0.25 s, travels less than 0.03 (normalized), and has no button pressed. In Lighter mode a tap posts a middle down/up at the pointer. In Standard and Lighter, a left-down with 3 fingers becomes a middle down/drag/up. Standard is suspended while `TrackpadThreeFingerDrag` is on.</action>
  <verify>TrackpadTests (tap fires; hold, move, two-finger and press don't)</verify>
  <done>MIDL-02, MIDL-03</done>
</task>
