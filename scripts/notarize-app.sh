#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT_DIR/VERSION")"
APP_NAME="OpenClaw Manager Native"
RELEASE_DIR="$ROOT_DIR/release"
APP_DIR="$RELEASE_DIR/$APP_NAME.app"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-arm64-mac.zip"
KEYCHAIN_PROFILE="${OPENCLAW_NOTARY_KEYCHAIN_PROFILE:-}"

if [ -z "$KEYCHAIN_PROFILE" ]; then
  echo "缺少 OPENCLAW_NOTARY_KEYCHAIN_PROFILE，先执行: xcrun notarytool store-credentials ..." >&2
  exit 1
fi

bash "$ROOT_DIR/scripts/package-app.sh"

xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$APP_DIR"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "原生 app 已完成公证并重新封装: $ZIP_PATH"

