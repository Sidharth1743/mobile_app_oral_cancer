#!/usr/bin/env bash
# Pull YOLO debug artifacts (boxes, annotated frames, Gemma crops) to this PC.
#
# Prerequisite: debug build (flutter run), complete a video screening analyze.
#
# Each frame folder contains:
#   source.jpg           - original extracted frame
#   annotated_boxes.jpg  - frame with YOLO boxes drawn
#   gemma_input.jpg      - 224x224 image sent to Gemma
#   meta.json            - box coordinates and confidence
#
# Usage:
#   ./scripts/pull_yolo_debug_outputs.sh
#   ./scripts/pull_yolo_debug_outputs.sh /path/to/save

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_ID="${PACKAGE_ID:-com.example.oral_cancer}"
DEST_DIR="${1:-$ROOT_DIR/debug_captures/yolo_outputs}"
PHONE_REL="files/debug/yolo_outputs"
PHONE_EXTERNAL="/sdcard/Android/data/$PACKAGE_ID/files/debug/yolo_outputs"

require_device() {
  if ! command -v adb >/dev/null 2>&1; then
    echo "adb is not installed or not in PATH." >&2
    exit 1
  fi
  if ! adb devices | awk 'NR > 1 && $2 == "device" {found=1} END {exit !found}'; then
    echo "No authorized Android device. Connect USB, enable debugging, run: adb devices" >&2
    exit 1
  fi
}

pull_tree() {
  local src="$1"
  if adb shell "test -d '$src'" 2>/dev/null; then
    mkdir -p "$DEST_DIR"
    echo "[pull] adb pull $src"
    adb pull "$src/." "$DEST_DIR"
    return 0
  fi
  return 1
}

pull_via_run_as() {
  local listing
  listing="$(adb shell "run-as '$PACKAGE_ID' ls '$PHONE_REL' 2>/dev/null" | tr -d '\r' || true)"
  if [[ -z "$listing" ]]; then
    return 1
  fi
  mkdir -p "$DEST_DIR"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    [[ "$name" == "." || "$name" == ".." ]] && continue
    if [[ "$name" == LATEST.txt || "$name" == manifest.json ]]; then
      adb exec-out "run-as '$PACKAGE_ID' cat '$PHONE_REL/$name'" >"$DEST_DIR/$name" || true
      continue
    fi
    local session_listing
    session_listing="$(adb shell "run-as '$PACKAGE_ID' ls '$PHONE_REL/$name' 2>/dev/null" | tr -d '\r' || true)"
    mkdir -p "$DEST_DIR/$name"
    while IFS= read -r frame; do
      [[ -z "$frame" ]] && continue
      [[ "$frame" == "." || "$frame" == ".." ]] && continue
      mkdir -p "$DEST_DIR/$name/$frame"
      local files
      files="$(adb shell "run-as '$PACKAGE_ID' ls '$PHONE_REL/$name/$frame' 2>/dev/null" | tr -d '\r' || true)"
      while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ "$file" == "." || "$file" == ".." ]] && continue
        echo "[pull] $name/$frame/$file"
        adb exec-out "run-as '$PACKAGE_ID' cat '$PHONE_REL/$name/$frame/$file'" \
          >"$DEST_DIR/$name/$frame/$file"
      done <<<"$files"
    done <<<"$session_listing"
    if [[ -f "$DEST_DIR/$name/manifest.json" ]]; then
      :
    else
      adb exec-out "run-as '$PACKAGE_ID' cat '$PHONE_REL/$name/manifest.json'" \
        >"$DEST_DIR/$name/manifest.json" 2>/dev/null || true
    fi
  done <<<"$listing"
  return 0
}

require_device

if pull_tree "$PHONE_EXTERNAL"; then
  :
elif pull_via_run_as; then
  :
else
  echo "No YOLO debug captures found." >&2
  echo "1. flutter run (debug) on phone" >&2
  echo "2. Record/upload video and tap Analyze" >&2
  echo "3. Re-run this script" >&2
  exit 1
fi

echo ""
echo "YOLO captures saved under: $DEST_DIR"
find "$DEST_DIR" -name 'meta.json' 2>/dev/null | head -10
echo ""
echo "Open annotated_boxes.jpg to review detections."
