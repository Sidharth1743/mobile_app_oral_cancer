#!/usr/bin/env bash
# Pull all debug captures (Gemma raw + YOLO) from phone to PC.

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/pull_raw_model_outputs.sh" "$ROOT_DIR/debug_captures/raw_outputs"
"$ROOT_DIR/scripts/pull_yolo_debug_outputs.sh" "$ROOT_DIR/debug_captures/yolo_outputs"

echo ""
echo "All debug captures under: $ROOT_DIR/debug_captures/"
