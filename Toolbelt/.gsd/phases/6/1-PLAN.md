---
phase: 6
plan: 1
wave: 1
gap_closure: true
---

# Plan 6.1: Hand-test gap closure

## Objective
Close hand-test round 1: failures 6.4 (app not re-listed, menu stalled, echo) and 7.1 (idle spikes), plus notes 4.1/4.2/4.4 (shelf layout, temp files), 6.1 (slow listing), 6.2 (snap).

## Tasks

<task type="auto">
  <name>Single instance + tap engine off main</name>
  <files>Toolbelt/App/AppDelegate.swift, Toolbelt/Mixer/TapEngine.swift, Toolbelt/Mixer/MixerModel.swift, Toolbelt/Mixer/AppTap.swift</files>
  <action>Second launch reopens the first and quits. All HAL tap work on a serial queue; tap state freed only in deinit. Quit releases taps synchronously.</action>
  <verify>open twice → pgrep shows one instance</verify>
  <done>One instance; no HAL calls on main</done>
</task>

<task type="auto">
  <name>Snap + idle CPU</name>
  <files>Toolbelt/Mixer/MixerModel.swift, Toolbelt/Shelf/DragMonitor.swift</files>
  <action>Snap ±4 % to 100 % on set and on read. Drag pasteboard probed for the first 30 drag events only.</action>
  <verify>SnapTests, StoreTests; top idle sample</verify>
  <done>Idle 0.0 % CPU, 0 wakeups</done>
</task>

<task type="auto">
  <name>Shelf layouts + temp lifecycle</name>
  <files>Toolbelt/Shelf/*.swift, Toolbelt/Convert/Converter.swift</files>
  <action>Stack/Grid/List; single item fills; AppKit drag source removes dropped-out items; temp slots per file; discard after 60 s; purge at launch; conversions to temp.</action>
  <verify>IngestTests.testDiscardOnlyDeletesTempFiles, testDataDropsGetOwnSlot; ConverterTests</verify>
  <done>Only temp files ever deleted; source folders untouched</done>
</task>
