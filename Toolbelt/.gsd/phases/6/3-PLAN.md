---
phase: 6
plan: 3
wave: 1
gap_closure: true
---

# Plan 6.3: Active-use CPU, mixer list height, menu placement

<task type="auto">
  <name>Cache process owners</name>
  <files>Toolbelt/Mixer/MixerModel.swift</files>
  <action>Resolve PID → owning app once per audio object; coalesce listener storms to 250 ms; skip UI/tap work when unchanged.</action>
  <verify>ps CPU time over 120 s of normal use</verify>
  <done>≤ 0.05 % average</done>
</task>

<task type="auto">
  <name>Bounded menu</name>
  <files>Toolbelt/App/PopoverView.swift, Toolbelt/App/MenuPanel.swift, Toolbelt/App/AppDelegate.swift</files>
  <action>Mixer list scrolls past 6 rows. Replace NSPopover with a top-pinned panel (below the icon, or top-right under the menu bar when the icon is hidden) that grows downward.</action>
  <verify>MixerListTests, MenuPanelTests</verify>
  <done>Menu never grows off screen</done>
</task>
