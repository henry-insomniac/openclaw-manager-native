#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/assets"
SVG_PATH="$ASSETS_DIR/OpenClawManager.svg"
PREVIEW_PNG="$ASSETS_DIR/OpenClawManager.svg.png"
MASTER_PNG="$ASSETS_DIR/OpenClawManager-1024.png"
ICONSET_DIR="$ASSETS_DIR/OpenClawManager.iconset"
ICNS_PATH="$ASSETS_DIR/OpenClawManager.icns"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

if qlmanage -t -s 1024 -o "$ASSETS_DIR" "$SVG_PATH" >/dev/null 2>&1 && [ -f "$PREVIEW_PNG" ]; then
  mv "$PREVIEW_PNG" "$MASTER_PNG"
elif [ -f "$ICNS_PATH" ]; then
  echo "跳过图标重建，继续使用现有 icns: $ICNS_PATH"
  exit 0
elif [ -f "$MASTER_PNG" ]; then
  echo "复用现有主图: $MASTER_PNG"
else
  echo "无法生成图标：qlmanage 不可用，且缺少现有主图/图标缓存" >&2
  exit 1
fi

create_icon() {
  local size="$1"
  local name="$2"
  sips -z "$size" "$size" "$MASTER_PNG" --out "$ICONSET_DIR/$name" >/dev/null
}

create_icon 16 icon_16x16.png
create_icon 32 icon_16x16@2x.png
create_icon 32 icon_32x32.png
create_icon 64 icon_32x32@2x.png
create_icon 128 icon_128x128.png
create_icon 256 icon_128x128@2x.png
create_icon 256 icon_256x256.png
create_icon 512 icon_256x256@2x.png
create_icon 512 icon_512x512.png
cp "$MASTER_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns -o "$ICNS_PATH" "$ICONSET_DIR"

echo "图标已生成: $ICNS_PATH"
