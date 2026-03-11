#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT_DIR/VERSION")"
APP_NAME="OpenClaw Manager Native"
PRODUCT_NAME="OpenClawManagerNative"
ICON_BASENAME="OpenClawManager"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_BUILD_ROOT="$ROOT_DIR/.build/app"
RELEASE_DIR="$ROOT_DIR/release"
APP_DIR="$APP_BUILD_ROOT/$APP_NAME.app"
RELEASE_APP_DIR="$RELEASE_DIR/$APP_NAME.app"
FALLBACK_RELEASE_APP_DIR="$RELEASE_DIR/$APP_NAME-latest.app"
EXECUTABLE_SOURCE="$BUILD_DIR/$PRODUCT_NAME"
EXECUTABLE_TARGET="$APP_DIR/Contents/MacOS/$PRODUCT_NAME"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
SCRIPTS_DIR="$RESOURCES_DIR/scripts"
RUNTIME_SOURCE="$ROOT_DIR/vendor/runtime"
APP_ENTITLEMENTS="$ROOT_DIR/assets/OpenClawManager.entitlements"

resolve_codesign_identity() {
  if [ -n "${OPENCLAW_CODESIGN_IDENTITY:-}" ]; then
    printf '%s\n' "$OPENCLAW_CODESIGN_IDENTITY"
    return
  fi

  local identity
  identity="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"
  if [ -n "$identity" ]; then
    printf '%s\n' "$identity"
    return
  fi

  printf '%s\n' '-'
}

codesign_file() {
  local identity="$1"
  local target="$2"
  local entitlements="${3:-}"

  local -a args=(--force --sign "$identity")
  if [ "$identity" != '-' ]; then
    args+=(--timestamp --options runtime)
  fi
  if [ -n "$entitlements" ]; then
    args+=(--entitlements "$entitlements")
  fi
  args+=("$target")

  codesign "${args[@]}"
}

sign_app_bundle() {
  local identity="$1"

  xattr -cr "$APP_DIR"

  while IFS= read -r file_path; do
    [ -z "$file_path" ] && continue
    case "$file_path" in
      "$EXECUTABLE_TARGET")
        continue
        ;;
      *)
        codesign_file "$identity" "$file_path"
        ;;
    esac
  done < <(
    find "$APP_DIR/Contents" -type f | while IFS= read -r candidate; do
      if file "$candidate" | grep -q 'Mach-O'; then
        printf '%s\n' "$candidate"
      fi
    done | sort
  )

  codesign_file "$identity" "$APP_DIR" "$APP_ENTITLEMENTS"
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
}

sync_release_app_bundle() {
  mkdir -p "$RELEASE_DIR"

  if rm -rf "$RELEASE_APP_DIR" 2>/dev/null; then
    cp -R "$APP_DIR" "$RELEASE_APP_DIR"
    echo "原生 app 已同步到 release: $RELEASE_APP_DIR"
    return
  fi

  rm -rf "$FALLBACK_RELEASE_APP_DIR"
  cp -R "$APP_DIR" "$FALLBACK_RELEASE_APP_DIR"
  echo "无法覆盖 release 中已有的 app，已输出到: $FALLBACK_RELEASE_APP_DIR"
}

bash "$ROOT_DIR/scripts/build-icon.sh"
bash "$ROOT_DIR/scripts/sync-runtime.sh"

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$RESOURCES_DIR" "$SCRIPTS_DIR"

cp "$EXECUTABLE_SOURCE" "$EXECUTABLE_TARGET"
chmod +x "$EXECUTABLE_TARGET"
cp "$ROOT_DIR/assets/$ICON_BASENAME.icns" "$RESOURCES_DIR/$ICON_BASENAME.icns"
rsync -a --delete "$RUNTIME_SOURCE/" "$RESOURCES_DIR/runtime/"
for script_name in install-watchdog.sh uninstall-watchdog.sh watchdog-status.sh; do
  cp "$ROOT_DIR/scripts/$script_name" "$SCRIPTS_DIR/$script_name"
done
chmod 755 "$SCRIPTS_DIR"/*.sh

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_BASENAME.icns</string>
  <key>CFBundleIconName</key>
  <string>$ICON_BASENAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.zhuanz.openclawmanagernative</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

SIGN_IDENTITY="$(resolve_codesign_identity)"
SIGN_MODE='ad-hoc'
if [ "$SIGN_IDENTITY" != '-' ]; then
  SIGN_MODE='developer-id'
fi

sign_app_bundle "$SIGN_IDENTITY"
sync_release_app_bundle

echo "原生 app 已生成: $APP_DIR"
echo "签名模式: $SIGN_MODE"
echo "签名身份: $SIGN_IDENTITY"
