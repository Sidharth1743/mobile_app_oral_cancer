#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_NAME="${MODEL_NAME:-gemma-4-E2B-it.litertlm}"
LOCAL_MODEL="$PROJECT_ROOT/model/$MODEL_NAME"
PACKAGE_ID="com.example.oral_cancer"
PHONE_MODEL_DIR="/sdcard/Android/data/$PACKAGE_ID/files/models"
PHONE_MODEL_PATH="$PHONE_MODEL_DIR/$MODEL_NAME"

if [[ ! -f "$LOCAL_MODEL" ]]; then
  echo "Missing local model: $LOCAL_MODEL" >&2
  exit 1
fi

adb shell "mkdir -p '$PHONE_MODEL_DIR'"
adb push "$LOCAL_MODEL" "$PHONE_MODEL_PATH"

echo "$PHONE_MODEL_PATH"
