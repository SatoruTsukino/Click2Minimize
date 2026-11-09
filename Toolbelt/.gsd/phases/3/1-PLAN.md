---
phase: 3
plan: 1
wave: 2
gap_closure: false
---

# Plan 3.1: Shake shelf

## Objective
Floating non-activating shelf opened by shaking a content drag; drop in, drag out, Quick Look, remove.

## Context
- /Users/jsph/Ledge/Ledge/Activation/ShakeDetector.swift, DragMonitor.swift (user's MIT code)

## Tasks

<task type="auto">
  <name>Shake detection</name>
  <files>Toolbelt/Toolbelt/Shelf/ShakeDetector.swift, Toolbelt/Toolbelt/Shelf/DragMonitor.swift</files>
  <action>Port ShakeDetector (pure, tested). Global+local NSEvent monitors; content drag = drag pasteboard changeCount changed since mouse-down.</action>
  <verify>xcodebuild test -only-testing:ToolbeltTests/ShakeDetectorTests</verify>
  <done>Zig-zag path triggers; straight path does not</done>
</task>

<task type="auto">
  <name>Shelf panel</name>
  <files>Toolbelt/Toolbelt/Shelf/Shelf*.swift</files>
  <action>
    NSPanel (.nonactivatingPanel, canJoinAllSpaces, fullScreenAuxiliary), SwiftUI grid of items; drop destination (files, images, text → temp files); drag out single (onDrag) / all (header via NSDraggingSession); Quick Look (QLPreviewPanel); context menu.
  </action>
  <verify>xcodebuild test -only-testing:ToolbeltTests/IngestTests</verify>
  <done>Ingest writes text/image data to temp files</done>
</task>
