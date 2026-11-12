# Toolbelt

One menu bar app replacing Ledge (shake shelf), Click2Minimize (Dock click), Fader (per-app volume) and Convertino (conversion). macOS 14.2+.

- **Dock click** — click the frontmost app's Dock icon to minimize its windows or hide it. Needs Accessibility.
- **Shake shelf** — shake while dragging to open a floating shelf. Drop in, drag out (one or all), Space for Quick Look.
- **Convert** — right-click shelf items: images (JPEG/PNG/HEIC/TIFF, compress, resize), video (MP4/MOV, 1080p/720p, remove audio, extract M4A). With `brew install ffmpeg`: MP3/WAV/WEBP/GIF/MP4. With LibreOffice: documents → PDF.
- **Volume** — per-app slider (0–150 %), mute, meter; remembered per app. Needs System Audio Recording.

Idle: ~13 MB, 0 % CPU, no wakeups.

```bash
./scripts/build_dmg.sh        # → dist/Toolbelt.dmg
xcodegen generate && xcodebuild -project Toolbelt.xcodeproj -scheme Toolbelt -derivedDataPath build/dd test
```

Planning: `.gsd/`.
