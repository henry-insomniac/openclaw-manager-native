#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/vendor/runtime"
DAEMON_PATH="$RUNTIME_DIR/openclaw-manager-daemon"
WATCHDOG_PATH="$RUNTIME_DIR/openclaw-watchdog"

rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"

echo "编译 Go runtime..."
(
  cd "$ROOT_DIR"
  GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -o "$DAEMON_PATH" ./cmd/openclaw-manager-daemon
  GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -o "$WATCHDOG_PATH" ./cmd/openclaw-watchdog
)

chmod 755 "$DAEMON_PATH"
chmod 755 "$WATCHDOG_PATH"

echo "Go runtime 已同步到: $DAEMON_PATH"
echo "Go watchdog 已同步到: $WATCHDOG_PATH"
