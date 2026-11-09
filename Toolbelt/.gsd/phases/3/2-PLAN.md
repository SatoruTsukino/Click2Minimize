---
phase: 3
plan: 2
wave: 3
gap_closure: false
---

# Plan 3.2: Conversion engine + shelf actions

## Objective
One `Converter` used by shelf context menu: images (ImageIO), video/audio (AVFoundation), optional ffmpeg/soffice.

## Tasks

<task type="auto">
  <name>Converter</name>
  <files>Toolbelt/Toolbelt/Convert/*.swift</files>
  <action>
    `ConvertAction` enum; `available(for: [URL], tools:)` filters by UTType + tool presence; `run(_:on:) async throws -> [URL]`.
    Image: re-encode / quality / resize with EXIF orientation (port Ledge ImageOps).
    Media: AVAssetExportSession presets (MP4/MOV/M4A/720p/1080p), remove audio via AVMutableComposition.
    ffmpeg/soffice: Process with argument arrays (no shell), output to unique file beside temp output folder.
    AVOID: shell string interpolation because filenames may contain quotes.
  </action>
  <verify>xcodebuild test -only-testing:ToolbeltTests/ConverterTests</verify>
  <done>PNG→JPEG, resize 50%, compress produce valid images; action availability correct per type/tool</done>
</task>
