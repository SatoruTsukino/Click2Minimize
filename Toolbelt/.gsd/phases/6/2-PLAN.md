---
phase: 6
plan: 2
wave: 1
gap_closure: true
---

# Plan 6.2: Gap closure (round 2)

## Objective
Fix R2.7 (restarted app not listed), R2.8 (slow listing), R2.10 (steady 0.1 % CPU).

<task type="auto">
  <name>Reliable process listing</name>
  <files>Toolbelt/Mixer/MixerModel.swift</files>
  <action>Probe showed `kAudioProcessPropertyIsRunningOutput` never notifies; `IsRunning` ('pir?') and `Devices` ('pdv#') do. Watch those, re-read IsRunningOutput on change.</action>
  <verify>scratch probe: afplay -v 0 → pir?/pdv# callbacks at 70 ms, runOut=1</verify>
  <done>New/restarted apps listed without reopening Toolbelt</done>
</task>

<task type="auto">
  <name>Per-click cost</name>
  <files>Toolbelt/Dock/DockClick.swift, Toolbelt/Shelf/DragMonitor.swift</files>
  <action>Dock band from tilesize/magnification/largesize + 24 px (was 220 px). Drag pasteboard read only during the first 30 drag events, never on mouse-down.</action>
  <verify>DockDecisionTests.testDockBand; top sample</verify>
  <done>Clicks outside the Dock cost no AX/pasteboard IPC</done>
</task>
