---
phase: 5
plan: 1
wave: 4
gap_closure: false
---

# Plan 5.1: DMG + README

<task type="auto">
  <name>DMG script</name>
  <files>Toolbelt/scripts/build_dmg.sh, Toolbelt/README.md</files>
  <action>xcodegen → Release universal build → codesign -s - → hdiutil UDZO to dist/Toolbelt.dmg.</action>
  <verify>bash scripts/build_dmg.sh; hdiutil verify dist/Toolbelt.dmg</verify>
  <done>dist/Toolbelt.dmg verifies</done>
</task>
