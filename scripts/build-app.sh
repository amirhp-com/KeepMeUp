#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="KeepMeUp"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

cd "$ROOT"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cd "$ROOT"
codesign --force --deep --options runtime --entitlements Resources/KeepMeUp.entitlements --sign "${SIGN_IDENTITY:--}" "$APP"

cd "$DIST"
rm -f "$APP_NAME.zip"
ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip"

if [ -f "${KEEPMEUP_KEY:-$HOME/.config/keepmeup/ed25519.key}" ]; then
    swift "$ROOT/scripts/release-key.swift" sign "$DIST/$APP_NAME.zip"
fi

echo "Built $APP"
lipo -info "$APP/Contents/MacOS/$APP_NAME"
