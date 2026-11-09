---
phase: 2
plan: 1
wave: 2
gap_closure: false
---

# Plan 2.1: Dock click controller

## Objective
Swallow left mouse-down on the Dock icon of the active app and minimize its windows or hide it.

## Context
- /Users/jsph/Click2Minimize/Click2Minimize/Dock.swift, AX.swift (user's own approach)

## Tasks

<task type="auto">
  <name>AX helpers + Dock hit test</name>
  <files>Toolbelt/Toolbelt/Dock/AX.swift, Toolbelt/Toolbelt/Dock/DockClick.swift</files>
  <action>
    CGEvent tap (leftMouseDown) → if pointer within Dock band of its screen → AXUIElementCopyElementAtPosition, walk up to *DockItem → resolve NSRunningApplication by AXURL.
    Decision fn `DockClick.decide(isApp:isActive:isHidden:isFullscreen:visibleWindows:mode:)` pure + unit tested.
    Re-enable tap on tapDisabledByTimeout. AX messaging timeout 0.25s.
    AVOID: AppleScript dock queries because they're slow and need Automation permission.
  </action>
  <verify>xcodebuild test -only-testing:ToolbeltTests/DockDecisionTests</verify>
  <done>Decision table tests pass</done>
</task>

## Must-Haves
- [ ] DOCK-01..04 built
