#!/usr/bin/env bash
# Pull Gemma raw debug captures from a USB-connected phone to this PC.
#
# Prerequisite: run the app in debug mode (flutter run) and complete at least
# one Gemma inference (screening analyze, voice extract, or translate).
#
# Usage:
#   ./scripts/pull_raw_model_outputs.sh
#   ./scripts/pull_raw_model_outputs.sh /path/to/save

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_ID="${PACKAGE_ID:-com.example.oral_cancer}"
DEST_DIR="${1:-$ROOT_DIR/debug_captures/raw_outputs}"
PHONE_REL="files/debug/raw_outputs"
PHONE_EXTERNAL="/sdcard/Android/data/$PACKAGE_ID/files/debug/raw_outputs"

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
    local dest="$DEST_DIR/$name"
    echo "[pull] run-as $PHONE_REL/$name"
    adb exec-out "run-as '$PACKAGE_ID' cat '$PHONE_REL/$name'" >"$dest"
  done <<<"$listing"
  return 0
}

pull_via_external() {
  if ! adb shell "test -d '$PHONE_EXTERNAL'" 2>/dev/null; then
    return 1
  fi
  mkdir -p "$DEST_DIR"
  echo "[pull] adb pull $PHONE_EXTERNAL"
  adb pull "$PHONE_EXTERNAL/." "$DEST_DIR"
  return 0
}

require_device

if pull_via_external; then
  :
elif pull_via_run_as; then
  :
else
  echo "No captures found on device." >&2
  echo "1. flutter run (debug build) on the phone" >&2
  echo "2. Run screening / voice extract / translate once" >&2
  echo "3. Re-run this script" >&2
  exit 1
fi

echo ""
echo "Captures saved under: $DEST_DIR"
if [[ -f "$DEST_DIR/manifest.json" ]]; then
  echo "Manifest: $DEST_DIR/manifest.json"
fi
if [[ -f "$DEST_DIR/LATEST.txt" ]]; then
  cat "$DEST_DIR/LATEST.txt"
fi
ls -lt "$DEST_DIR" | head -15
