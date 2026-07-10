#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Generating go.sum for all Go services..."

for dir in apps/*/; do
  if [ -f "$dir/go.mod" ]; then
    svc=$(basename "$dir")
    echo "  -> $svc"
    (cd "$dir" && go mod tidy 2>&1 | head -5)
  fi
done

echo "==> Done."
