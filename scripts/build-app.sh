#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="KeepMeUp"
DIST="$ROOT/dist"
STAGE="$DIST/app.noindex"
APP="$STAGE/$APP_NAME.app"

cd "$ROOT"

if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCHS=(--arch arm64 --arch x86_64)
else
    ARCHS=(--arch arm64)
fi

swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/$APP_NAME"

rm -rf "$APP" "$DIST/$APP_NAME.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$DIST/$APP_NAME.app" >/dev/null 2>&1 || true
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cd "$ROOT"
if [ -z "${SIGN_IDENTITY:-}" ] && security find-certificate -c "KeepMeUp Release" >/dev/null 2>&1; then
    SIGN_IDENTITY="KeepMeUp Release"
fi
codesign --force --deep --options runtime --entitlements Resources/KeepMeUp.entitlements --sign "${SIGN_IDENTITY:--}" "$APP"

rm -f "$DIST/$APP_NAME.zip"
ditto -c -k --keepParent "$APP" "$DIST/$APP_NAME.zip"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" >/dev/null 2>&1 || true

if [ -f "${KEEPMEUP_KEY:-$HOME/.config/keepmeup/ed25519.key}" ]; then
    swift "$ROOT/scripts/release-key.swift" sign "$DIST/$APP_NAME.zip"
fi

echo "Built $APP"
lipo -info "$APP/Contents/MacOS/$APP_NAME"
