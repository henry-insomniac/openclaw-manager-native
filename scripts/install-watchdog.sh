#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_SUPPORT_DIR="$HOME/Library/Application Support/OpenClaw Manager Native/watchdog"
WATCHDOG_BIN_SRC="$ROOT_DIR/runtime/openclaw-watchdog"
WATCHDOG_BIN_DST="$APP_SUPPORT_DIR/openclaw-watchdog"
PLIST_PATH="$HOME/Library/LaunchAgents/ai.openclaw.watchdog.plist"
UID_NUM="$(id -u)"
PATH_VALUE="${PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
OPENCLAW_ROOT="${OPENCLAW_WATCHDOG_OPENCLAW_ROOT:-$HOME}"
OPENCLAW_STATE_DIR_PATH="${OPENCLAW_STATE_DIR:-$OPENCLAW_ROOT/.openclaw}"
LOG_DIR="${OPENCLAW_WATCHDOG_LOG_DIR:-$OPENCLAW_STATE_DIR_PATH/logs}"

if [ ! -x "$WATCHDOG_BIN_SRC" ]; then
  echo "未找到 Go watchdog 二进制: $WATCHDOG_BIN_SRC" >&2
  exit 1
fi

mkdir -p "$APP_SUPPORT_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"
cp "$WATCHDOG_BIN_SRC" "$WATCHDOG_BIN_DST"
chmod 755 "$WATCHDOG_BIN_DST"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>ai.openclaw.watchdog</string>
    <key>ProgramArguments</key>
    <array>
      <string>$WATCHDOG_BIN_DST</string>
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
"$WATCHDOG_BIN_DST" --once --check-only || true

echo "watchdog installed"
echo "binary: $WATCHDOG_BIN_DST"
echo "openclaw state: $OPENCLAW_STATE_DIR_PATH"
echo "plist: $PLIST_PATH"
echo "log: $LOG_DIR/watchdog.log"
