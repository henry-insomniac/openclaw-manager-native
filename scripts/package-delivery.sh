#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT_DIR/VERSION")"
APP_NAME="OpenClaw Manager Native"
RELEASE_DIR="$ROOT_DIR/release"
DELIVERY_DIR="$RELEASE_DIR/OpenClawManagerNative-delivery"
DELIVERY_ZIP="$RELEASE_DIR/OpenClawManagerNative-delivery.zip"
VERSIONED_DELIVERY_ZIP="$RELEASE_DIR/OpenClawManagerNative-$VERSION-delivery.zip"
APP_ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-arm64-mac.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-arm64.dmg"
PKG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-arm64.pkg"
CHECKSUMS_PATH="$RELEASE_DIR/OpenClawManagerNative-$VERSION-SHA256SUMS.txt"
OPENCLAW_RELEASE_TIMESTAMP="${OPENCLAW_RELEASE_TIMESTAMP:-$(date '+%Y%m%d-%H%M%S')}"
export OPENCLAW_RELEASE_TIMESTAMP
TIMESTAMPED_DMG_PATH="$RELEASE_DIR/OpenClawManagerNative-$VERSION-$OPENCLAW_RELEASE_TIMESTAMP-arm64.dmg"

if [ -n "${OPENCLAW_NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  bash "$ROOT_DIR/scripts/notarize-app.sh"
else
  bash "$ROOT_DIR/scripts/package-app.sh"
fi

bash "$ROOT_DIR/scripts/package-dmg.sh"
bash "$ROOT_DIR/scripts/package-pkg.sh"

if [ ! -f "$APP_ZIP_PATH" ]; then
  echo "未找到原生 app zip: $APP_ZIP_PATH" >&2
  exit 1
fi
if [ ! -f "$DMG_PATH" ]; then
  echo "未找到原生 app dmg: $DMG_PATH" >&2
  exit 1
fi
if [ ! -f "$TIMESTAMPED_DMG_PATH" ]; then
  echo "未找到时间戳 dmg: $TIMESTAMPED_DMG_PATH" >&2
  exit 1
fi
if [ ! -f "$PKG_PATH" ]; then
  echo "未找到原生 app pkg: $PKG_PATH" >&2
  exit 1
fi

cp -f "$APP_ZIP_PATH" "$RELEASE_DIR/OpenClawManagerNative-latest-arm64.zip"
cp -f "$DMG_PATH" "$RELEASE_DIR/OpenClawManagerNative-latest-arm64.dmg"
cp -f "$PKG_PATH" "$RELEASE_DIR/OpenClawManagerNative-latest-arm64.pkg"

rm -rf "$DELIVERY_DIR"
mkdir -p "$DELIVERY_DIR"

cp "$APP_ZIP_PATH" "$DELIVERY_DIR/"
cp "$DMG_PATH" "$DELIVERY_DIR/"
cp "$TIMESTAMPED_DMG_PATH" "$DELIVERY_DIR/"
cp "$PKG_PATH" "$DELIVERY_DIR/"
cp "$ROOT_DIR/README.md" "$DELIVERY_DIR/"
cp "$ROOT_DIR/INSTALL.md" "$DELIVERY_DIR/"
cp "$ROOT_DIR/QUICKSTART.md" "$DELIVERY_DIR/"
cp "$ROOT_DIR/USAGE.md" "$DELIVERY_DIR/"

rm -f "$CHECKSUMS_PATH"
(
  cd "$RELEASE_DIR"
  shasum -a 256 \
    "$(basename "$APP_ZIP_PATH")" \
    "$(basename "$DMG_PATH")" \
    "$(basename "$TIMESTAMPED_DMG_PATH")" \
    "$(basename "$PKG_PATH")" > "$(basename "$CHECKSUMS_PATH")"
)
cp "$CHECKSUMS_PATH" "$DELIVERY_DIR/"

rm -f "$DELIVERY_ZIP"
(
  cd "$RELEASE_DIR"
  zip -qry -X "$DELIVERY_ZIP" "$(basename "$DELIVERY_DIR")"
)

cp -f "$DELIVERY_ZIP" "$VERSIONED_DELIVERY_ZIP"
cp -f "$DELIVERY_ZIP" "$RELEASE_DIR/OpenClawManagerNative-latest-delivery.zip"
cp -f "$CHECKSUMS_PATH" "$RELEASE_DIR/OpenClawManagerNative-latest-SHA256SUMS.txt"

echo "原生版交付包已生成: $DELIVERY_ZIP"
echo "版本交付包已生成: $VERSIONED_DELIVERY_ZIP"
echo "本次时间戳 dmg: $TIMESTAMPED_DMG_PATH"
echo "SHA256 清单: $CHECKSUMS_PATH"
