#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_ROOT="${MANAGER_SOURCE_ROOT:-$ROOT_DIR/../codex-pool-management}"
RUNTIME_DIR="$ROOT_DIR/vendor/runtime"

mkdir -p "$RUNTIME_DIR"

cat > "$RUNTIME_DIR/package.json" <<'EOF'
{
  "name": "openclaw-manager-native-runtime",
  "private": true,
  "type": "module",
  "dependencies": {
    "@fastify/cors": "^10.1.0",
    "dotenv": "^17.2.2",
    "fastify": "^5.3.3",
    "luxon": "^3.7.0",
    "node": "22.22.1",
    "pg": "^8.17.2",
    "zod": "^4.3.5"
  }
}
EOF

echo "同步源项目: $SOURCE_ROOT"
(
  cd "$SOURCE_ROOT"
  npm run build
)

(
  cd "$RUNTIME_DIR"
  npm install --omit=dev --no-fund --no-audit
)

mkdir -p "$RUNTIME_DIR/apps/api" "$RUNTIME_DIR/apps/web"
rsync -a --delete "$SOURCE_ROOT/apps/api/dist/" "$RUNTIME_DIR/apps/api/dist/"
rsync -a --delete "$SOURCE_ROOT/apps/web/dist/" "$RUNTIME_DIR/apps/web/dist/"
cp "$ROOT_DIR/runtime/ui-server.mjs" "$RUNTIME_DIR/ui-server.mjs"

echo "runtime 已同步到: $RUNTIME_DIR"

