#!/usr/bin/env bash

set -euo pipefail

OPENCLAW_ROOT="${OPENCLAW_WATCHDOG_OPENCLAW_ROOT:-$HOME}"
OPENCLAW_STATE_DIR_PATH="${OPENCLAW_STATE_DIR:-$OPENCLAW_ROOT/.openclaw}"
STATE_PATH="$HOME/Library/Application Support/OpenClaw Manager Native/watchdog/state.json"
LOG_PATH="$OPENCLAW_STATE_DIR_PATH/logs/watchdog.log"
ERR_LOG_PATH="$OPENCLAW_STATE_DIR_PATH/logs/watchdog.err.log"
PLIST_PATH="$HOME/Library/LaunchAgents/ai.openclaw.watchdog.plist"

printf '%s\n' '--- launchctl ---'
launchctl list | grep -E 'ai\.openclaw\.watchdog|ai\.openclaw\.gateway' || true
printf '%s\n' '--- configured openclaw state dir ---'
printf '%s\n' "$OPENCLAW_STATE_DIR_PATH"
printf '%s\n' '--- plist ---'
[ -f "$PLIST_PATH" ] && sed -n '1,240p' "$PLIST_PATH" || echo '(missing)'
printf '%s\n' '--- state ---'
[ -f "$STATE_PATH" ] && sed -n '1,240p' "$STATE_PATH" || echo '(missing)'
printf '%s\n' '--- watchdog.log tail ---'
[ -f "$LOG_PATH" ] && tail -n 60 "$LOG_PATH" || echo '(missing)'
printf '%s\n' '--- watchdog.err.log tail ---'
[ -f "$ERR_LOG_PATH" ] && tail -n 60 "$ERR_LOG_PATH" || echo '(missing)'
