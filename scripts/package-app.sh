#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT_DIR/VERSION")"
APP_NAME="OpenClaw Manager Native"
RELEASE_DIR="$ROOT_DIR/release"
APP_DIR="$RELEASE_DIR/$APP_NAME.app"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-arm64-mac.zip"

bash "$ROOT_DIR/scripts/build-app.sh"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "原生 app zip 已生成: $ZIP_PATH"

