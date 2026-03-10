#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_SUPPORT_DIR="$HOME/Library/Application Support/OpenClaw Manager Native/watchdog"
SCRIPT_SRC="$ROOT_DIR/scripts/openclaw-watchdog.mjs"
SCRIPT_DST="$APP_SUPPORT_DIR/openclaw-watchdog.mjs"
PLIST_PATH="$HOME/Library/LaunchAgents/ai.openclaw.watchdog.plist"
UID_NUM="$(id -u)"
PATH_VALUE="${PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
OPENCLAW_ROOT="${OPENCLAW_WATCHDOG_OPENCLAW_ROOT:-$HOME}"
OPENCLAW_STATE_DIR_PATH="${OPENCLAW_STATE_DIR:-$OPENCLAW_ROOT/.openclaw}"
LOG_DIR="${OPENCLAW_WATCHDOG_LOG_DIR:-$OPENCLAW_STATE_DIR_PATH/logs}"

resolve_node() {
  if [ -n "${OPENCLAW_WATCHDOG_NODE:-}" ] && [ -x "${OPENCLAW_WATCHDOG_NODE}" ]; then
    printf '%s' "$OPENCLAW_WATCHDOG_NODE"
    return 0
  fi

  for candidate in \
    "$ROOT_DIR/runtime/node_modules/node/bin/node" \
    "/Applications/OpenClaw Manager Native.app/Contents/Resources/runtime/node_modules/node/bin/node" \
    "$ROOT_DIR/release/OpenClaw Manager Native.app/Contents/Resources/runtime/node_modules/node/bin/node"; do
    if [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  if command -v node >/dev/null 2>&1; then
    command -v node
    return 0
  fi

  return 1
}

NODE_BIN="$(resolve_node || true)"
if [ -z "$NODE_BIN" ]; then
  echo "未找到可用的 node，可通过 OPENCLAW_WATCHDOG_NODE 指定" >&2
  exit 1
fi

mkdir -p "$APP_SUPPORT_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"
cp "$SCRIPT_SRC" "$SCRIPT_DST"
chmod 755 "$SCRIPT_DST"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>ai.openclaw.watchdog</string>
    <key>ProgramArguments</key>
    <array>
      <string>$NODE_BIN</string>
      <string>$SCRIPT_DST</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>$HOME</string>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/watchdog.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/watchdog.err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
      <key>HOME</key>
      <string>$HOME</string>
      <key>PATH</key>
      <string>$PATH_VALUE</string>
      <key>OPENCLAW_STATE_DIR</key>
      <string>$OPENCLAW_STATE_DIR_PATH</string>
    </dict>
    <key>ProcessType</key>
    <string>Background</string>
  </dict>
</plist>
EOF

plutil -lint "$PLIST_PATH" >/dev/null
launchctl bootout "gui/$UID_NUM" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST_PATH"
launchctl kickstart -k "gui/$UID_NUM/ai.openclaw.watchdog"
sleep 2
"$NODE_BIN" "$SCRIPT_DST" --once --check-only || true

echo "watchdog installed"
echo "node: $NODE_BIN"
echo "openclaw state: $OPENCLAW_STATE_DIR_PATH"
echo "script: $SCRIPT_DST"
echo "plist: $PLIST_PATH"
echo "log: $LOG_DIR/watchdog.log"
