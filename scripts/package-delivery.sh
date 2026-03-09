#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
DELIVERY_DIR="$RELEASE_DIR/OpenClawManagerNative-delivery"
DELIVERY_ZIP="$RELEASE_DIR/OpenClawManagerNative-delivery.zip"

if [ -n "${OPENCLAW_NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  bash "$ROOT_DIR/scripts/notarize-app.sh"
else
  bash "$ROOT_DIR/scripts/package-app.sh"
fi

bash "$ROOT_DIR/scripts/package-dmg.sh"

APP_ZIP_PATH="$(find "$RELEASE_DIR" -maxdepth 1 -type f -name '*-mac.zip' | sort | tail -n 1)"
DMG_PATH="$(find "$RELEASE_DIR" -maxdepth 1 -type f -name '*.dmg' | sort | tail -n 1)"
if [ -z "$APP_ZIP_PATH" ]; then
  echo "未找到原生 app zip" >&2
  exit 1
fi
if [ -z "$DMG_PATH" ]; then
  echo "未找到原生 app dmg" >&2
  exit 1
fi

cp "$APP_ZIP_PATH" "$RELEASE_DIR/OpenClawManagerNative-latest-arm64.zip"
cp "$DMG_PATH" "$RELEASE_DIR/OpenClawManagerNative-latest-arm64.dmg"

rm -rf "$DELIVERY_DIR"
mkdir -p "$DELIVERY_DIR"

cp "$APP_ZIP_PATH" "$DELIVERY_DIR/"
cp "$DMG_PATH" "$DELIVERY_DIR/"
cp "$ROOT_DIR/README.md" "$DELIVERY_DIR/"
cp "$ROOT_DIR/INSTALL.md" "$DELIVERY_DIR/"
cp "$ROOT_DIR/ALPHA-TEST.md" "$DELIVERY_DIR/"

rm -f "$DELIVERY_ZIP"
(
  cd "$RELEASE_DIR"
  zip -qry -X "$DELIVERY_ZIP" "$(basename "$DELIVERY_DIR")"
)

cp "$DELIVERY_ZIP" "$RELEASE_DIR/OpenClawManagerNative-latest-delivery.zip"

echo "原生版交付包已生成: $DELIVERY_ZIP"
