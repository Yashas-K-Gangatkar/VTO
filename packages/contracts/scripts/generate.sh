#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CONTRACTS_DIR="$REPO_ROOT/packages/contracts"
echo "==> Validating OpenAPI spec..."
cd "$CONTRACTS_DIR"
pnpm validate
echo "==> Generating TypeScript client..."
pnpm gen:typescript
echo "==> Generating Go client..."
if ! command -v oapi-codegen &>/dev/null; then
  go install github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@latest
fi
pnpm gen:go
echo "==> Generating Python client..."
pnpm gen:python
echo "==> Codegen complete."
