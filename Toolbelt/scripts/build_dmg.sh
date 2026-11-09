#!/bin/bash
# Builds a universal Release Toolbelt.app, ad-hoc signs it and writes dist/Toolbelt.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
rm -rf build/release dist
xcodebuild -project Toolbelt.xcodeproj -scheme Toolbelt -configuration Release \
  -derivedDataPath build/release -destination "generic/platform=macOS" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build | grep -E "warning:|error:|BUILD" || true
APP=build/release/Build/Products/Release/Toolbelt.app
[ -d "$APP" ] || { echo "build failed"; exit 1; }
codesign --force --deep -s - "$APP"
mkdir -p dist/stage
cp -R "$APP" dist/stage/
ln -s /Applications dist/stage/Applications
hdiutil create -volname Toolbelt -srcfolder dist/stage -ov -format UDZO dist/Toolbelt.dmg >/dev/null
rm -rf dist/stage
echo "wrote dist/Toolbelt.dmg"
