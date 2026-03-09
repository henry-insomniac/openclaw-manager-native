#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT_DIR/VERSION")"
APP_NAME="OpenClaw Manager Native"
RELEASE_DIR="$ROOT_DIR/release"
APP_DIR="$RELEASE_DIR/$APP_NAME.app"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-arm64.dmg"
STAGING_DIR="$RELEASE_DIR/.dmg-staging"

bash "$ROOT_DIR/scripts/build-app.sh"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$ROOT_DIR/INSTALL.md" "$STAGING_DIR/INSTALL.md"
cp "$ROOT_DIR/ALPHA-TEST.md" "$STAGING_DIR/ALPHA-TEST.md"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "原生 app dmg 已生成: $DMG_PATH"
