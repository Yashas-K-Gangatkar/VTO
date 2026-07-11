#!/usr/bin/env bash
set -euo pipefail

MODELS_DIR="${1:-$HOME/models}"
echo "Downloading IDM-VTON to: $MODELS_DIR"
mkdir -p "$MODELS_DIR"

# Download IDM-VTON model weights
echo "Downloading IDM-VTON model weights (~4GB)..."
huggingface-cli download yisol/IDM-VTON \
    --local-dir "$MODELS_DIR/idm-vton" \
    --local-dir-use-symlinks False

echo ""
echo "Done. Model at: $MODELS_DIR/idm-vton"
ls -la "$MODELS_DIR/idm-vton"
