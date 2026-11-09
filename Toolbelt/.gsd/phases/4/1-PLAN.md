---
phase: 4
plan: 1
wave: 2
gap_closure: false
---

# Plan 4.1: Audio engine + mixer UI

## Objective
Per-app volume (0–150%), mute, meters, persistence using Core Audio process taps.

## Tasks

<task type="auto">
  <name>Process list</name>
  <files>Toolbelt/Toolbelt/Mixer/AudioProcesses.swift</files>
  <action>kAudioHardwarePropertyProcessObjectList + per-process listeners on kAudioProcessPropertyIsRunningOutput; map PID → NSRunningApplication (walk to responsible app via bundle ID; helper processes like "WebContent" grouped by bundle ID prefix).</action>
  <verify>build</verify>
  <done>List updates on property change, no polling</done>
</task>

<task type="auto">
  <name>Tap + gain</name>
  <files>Toolbelt/Toolbelt/Mixer/AppTap.swift, Toolbelt/Toolbelt/Mixer/Gain.swift</files>
  <action>
    CATapDescription(stereoMixdownOfProcesses:) muteBehavior .mutedWhenTapped, private; AudioHardwareCreateProcessTap; private aggregate device (main sub-device = default output, tap list = tap); IOProc copies input→output × gain, computes peak (atomic). Rebuild on default output change.
    Pure `Gain.apply(buffer:gain:) -> peak` unit tested.
  </action>
  <verify>xcodebuild test -only-testing:ToolbeltTests/GainTests</verify>
  <done>Gain/peak math tested; taps created only per ADR-006</done>
</task>

<task type="auto">
  <name>Mixer UI + persistence</name>
  <files>Toolbelt/Toolbelt/Mixer/MixerModel.swift, Toolbelt/Toolbelt/App/PopoverView.swift</files>
  <action>Row per app: icon, name, slider, mute, meter (30 Hz timer only while popover visible). Store [bundleID: {volume, muted}].</action>
  <verify>xcodebuild test -only-testing:ToolbeltTests/MixerStoreTests</verify>
  <done>Store round-trips</done>
</task>
