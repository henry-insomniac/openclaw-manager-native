#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT_DIR/VERSION")"
APP_NAME="OpenClaw Manager Native"
RELEASE_DIR="$ROOT_DIR/release"
APP_DIR="$ROOT_DIR/.build/app/$APP_NAME.app"
PKG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-arm64.pkg"
PKG_SCRIPTS_DIR="$ROOT_DIR/.build/pkg-scripts"

resolve_installer_identity() {
  if [ -n "${OPENCLAW_INSTALLER_SIGN_IDENTITY:-}" ]; then
    printf '%s\n' "$OPENCLAW_INSTALLER_SIGN_IDENTITY"
    return
  fi

  local identity
  identity="$(security find-identity -v -p basic 2>/dev/null | sed -n 's/.*"\(Developer ID Installer:.*\)"/\1/p' | head -n 1)"
  if [ -n "$identity" ]; then
    printf '%s\n' "$identity"
    return
  fi

  printf '%s\n' '-'
}

bash "$ROOT_DIR/scripts/build-app.sh"

SIGN_IDENTITY="$(resolve_installer_identity)"
PKG_MODE='unsigned'
rm -f "$PKG_PATH"
rm -rf "$PKG_SCRIPTS_DIR"
mkdir -p "$PKG_SCRIPTS_DIR"

cat > "$PKG_SCRIPTS_DIR/postinstall" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

APP_PATH="/Applications/OpenClaw Manager Native.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [ -d "$APP_PATH" ]; then
  touch "$APP_PATH" || true
  touch /Applications || true
  if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$APP_PATH" >/dev/null 2>&1 || true
  fi
fi
EOF

chmod 755 "$PKG_SCRIPTS_DIR/postinstall"

PKGBUILD_ARGS=(
  --component "$APP_DIR"
  --install-location /Applications
  --identifier com.zhuanz.openclawmanagernative.pkg
  --scripts "$PKG_SCRIPTS_DIR"
  --version "$VERSION"
)

if [ "$SIGN_IDENTITY" != '-' ]; then
  PKGBUILD_ARGS+=(--sign "$SIGN_IDENTITY")
  PKG_MODE='developer-id-installer'
fi

pkgbuild "${PKGBUILD_ARGS[@]}" "$PKG_PATH" >/dev/null

echo "原生 app pkg 已生成: $PKG_PATH"
echo "安装包签名模式: $PKG_MODE"
echo "安装包签名身份: $SIGN_IDENTITY"
