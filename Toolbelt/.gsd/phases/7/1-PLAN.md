---
phase: 7
plan: 1
wave: 1
gap_closure: false
---

# Plan 7.1: Radial convert ring (Shift during drag)

## Objective
While dragging files, tap Shift to open a ring of conversion petals around the pointer; dropping on a petal converts and shows the result in the shelf. All actions are shown: up to 8 on the inner ring, the rest on an outer ring. A "Shelf" petal adds the files to the shelf as they are.

## Context
- .gsd/DECISIONS.md (ADR-007)
- Toolbelt/Shelf/DragMonitor.swift, Toolbelt/Convert/*.swift, Toolbelt/Shelf/ShelfModel.swift

## Tasks

<task type="auto">
  <name>Pure logic</name>
  <files>Toolbelt/Radial/RadialLayout.swift</files>
  <action>`ShiftTap`: Shift down→up within 0.35 s, no other modifier, counts as a tap. `RadialLayout.place(count:)`: inner ring ≤ 8 at r = 92, rest on the outer ring at r = 168, evenly spaced from 12 o'clock. `ConvertAction.shortTitle` for petals.</action>
  <verify>xcodebuild test -only-testing:ToolbeltTests/RadialTests</verify>
  <done>Tap rules, ring split and spacing, unique short titles</done>
</task>

<task type="auto">
  <name>Ring panel</name>
  <files>Toolbelt/Radial/RadialController.swift</files>
  <action>Borderless, transparent, non-activating panel centred on the pointer; one AppKit PetalView per action registered for file URLs (highlight on hover); a centre Cancel petal; drop → `ShelfController.show` + `ShelfModel.run`. The ring closes on drop, on a second Shift tap, or when the drag ends. Actions come from the drag pasteboard's file URLs.
  AVOID: monitors at idle. USE: flagsChanged monitor installed only while a content drag is in progress.</action>
  <verify>build; hand test</verify>
  <done>Ring opens/closes as specified; no idle cost</done>
</task>

<task type="auto">
  <name>Wiring</name>
  <files>Toolbelt/Shelf/DragMonitor.swift, Toolbelt/App/Prefs.swift, Toolbelt/App/PopoverView.swift</files>
  <action>DragMonitor notifies the ring when a content drag starts or ends (mouse-up monitor, no IPC). Pref "Shift opens convert ring", on by default.</action>
  <verify>PrefsTests; idle top sample</verify>
  <done>Toggle persists; idle remains 0 %</done>
</task>
