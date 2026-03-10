#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT_DIR/VERSION")"
APP_NAME="OpenClaw Manager Native"
RELEASE_DIR="$ROOT_DIR/release"
APP_DIR="$ROOT_DIR/.build/app/$APP_NAME.app"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-arm64.dmg"
RELEASE_TIMESTAMP="${OPENCLAW_RELEASE_TIMESTAMP:-$(date '+%Y%m%d-%H%M%S')}"
TIMESTAMPED_DMG_PATH="$RELEASE_DIR/OpenClawManagerNative-$VERSION-$RELEASE_TIMESTAMP-arm64.dmg"
STAGING_DIR="$RELEASE_DIR/.dmg-staging"

bash "$ROOT_DIR/scripts/build-app.sh"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$ROOT_DIR/INSTALL.md" "$STAGING_DIR/INSTALL.md"
cp "$ROOT_DIR/QUICKSTART.md" "$STAGING_DIR/QUICKSTART.md"

rm -f "$DMG_PATH" "$TIMESTAMPED_DMG_PATH"
hdiutil create   -volname "$APP_NAME"   -srcfolder "$STAGING_DIR"   -ov   -format UDZO   "$DMG_PATH" >/dev/null
cp -f "$DMG_PATH" "$TIMESTAMPED_DMG_PATH"

rm -rf "$STAGING_DIR"

echo "原生 app dmg 已生成: $DMG_PATH"
echo "时间戳 dmg 已生成: $TIMESTAMPED_DMG_PATH"
