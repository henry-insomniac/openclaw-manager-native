#!/usr/bin/env bash

set -euo pipefail

PLIST_PATH="$HOME/Library/LaunchAgents/ai.openclaw.watchdog.plist"
APP_SUPPORT_DIR="$HOME/Library/Application Support/OpenClaw Manager Native/watchdog"
UID_NUM="$(id -u)"

launchctl bootout "gui/$UID_NUM" "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"
rm -rf "$APP_SUPPORT_DIR"

echo 'watchdog uninstalled'
