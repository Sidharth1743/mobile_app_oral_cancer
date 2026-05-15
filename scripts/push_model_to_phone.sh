#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_ID="${PACKAGE_ID:-com.example.oral_cancer}"
PHONE_MODEL_DIR="${PHONE_MODEL_DIR:-files/models}"
PHONE_TMP_DIR="${PHONE_TMP_DIR:-/data/local/tmp/oral_cancer_models}"
LEGACY_PHONE_MODEL_DIR="${LEGACY_PHONE_MODEL_DIR:-/sdcard/Android/data/$PACKAGE_ID/files/models}"
APK_PATH="${APK_PATH:-$ROOT_DIR/build/app/outputs/flutter-apk/app-debug.apk}"
INSTALL_APK="${INSTALL_APK:-1}"

LOCAL_GEMMA="${LOCAL_GEMMA:-$ROOT_DIR/model/model.litertlm}"
PHONE_GEMMA="${PHONE_GEMMA:-$PHONE_MODEL_DIR/gemma-4-E2B-it-final.litertlm}"

LOCAL_YOLO="${LOCAL_YOLO:-$ROOT_DIR/model/yolo11n_lesion_best_640_int8.tflite}"
PHONE_YOLO="${PHONE_YOLO:-$PHONE_MODEL_DIR/yolo11n_lesion_best_640_int8.tflite}"

require_device() {
  if ! command -v adb >/dev/null 2>&1; then
    echo "adb is not installed or not in PATH." >&2
    exit 1
  fi

  local devices
  devices="$(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')"
  if [[ -z "$devices" ]]; then
    echo "No authorized Android device found." >&2
    echo "Connect the phone, enable USB debugging, accept the prompt, then run: adb devices" >&2
    exit 1
  fi
}

app_file_size() {
  adb shell "run-as '$PACKAGE_ID' stat -c %s '$1' 2>/dev/null || echo 0" | tr -d '\r'
}

device_file_size() {
  adb shell "stat -c %s '$1' 2>/dev/null || echo 0" | tr -d '\r'
}

stage_if_needed() {
  local local_path="$1"
  local app_path="$2"
  local label="$3"

  if [[ ! -f "$local_path" ]]; then
    echo "Missing local $label model: $local_path" >&2
    exit 1
  fi

  local local_size
  local remote_size
  local_size="$(stat -c %s "$local_path")"
  remote_size="$(app_file_size "$app_path")"

  if [[ "$remote_size" == "$local_size" ]]; then
    echo "[$label] already staged in app storage: $app_path ($remote_size bytes)"
    return
  fi

  local file_name
  local tmp_path
  local legacy_path
  local legacy_size
  file_name="$(basename "$app_path")"
  tmp_path="$PHONE_TMP_DIR/$file_name"
  legacy_path="$LEGACY_PHONE_MODEL_DIR/$file_name"

  if [[ "$remote_size" != "0" ]]; then
    echo "[$label] remote size mismatch: $remote_size != $local_size; replacing"
    adb shell "run-as '$PACKAGE_ID' rm -f '$app_path'"
  else
    echo "[$label] missing in app storage; pushing"
  fi

  legacy_size="$(device_file_size "$legacy_path")"
  if [[ "$legacy_size" == "$local_size" ]]; then
    echo "[$label] copying existing staged file from: $legacy_path"
    adb shell "run-as '$PACKAGE_ID' mkdir -p '$PHONE_MODEL_DIR'"
    adb shell "run-as '$PACKAGE_ID' cp '$legacy_path' '$app_path'"
    return
  fi

  adb shell "mkdir -p '$PHONE_TMP_DIR'"
  adb push "$local_path" "$tmp_path"
  adb shell "chmod 644 '$tmp_path'"
  adb shell "run-as '$PACKAGE_ID' mkdir -p '$PHONE_MODEL_DIR'"
  adb shell "run-as '$PACKAGE_ID' cp '$tmp_path' '$app_path'"
  adb shell "rm -f '$tmp_path'"
}

require_device

if [[ "$INSTALL_APK" == "1" ]]; then
  if [[ -f "$APK_PATH" ]]; then
    echo "[APK] installing: $APK_PATH"
    adb install -r "$APK_PATH"
  else
    echo "[APK] not found: $APK_PATH"
    echo "[APK] build it first with: flutter build apk --debug"
  fi
fi

adb shell "run-as '$PACKAGE_ID' mkdir -p '$PHONE_MODEL_DIR'"
stage_if_needed "$LOCAL_YOLO" "$PHONE_YOLO" "YOLO"
stage_if_needed "$LOCAL_GEMMA" "$PHONE_GEMMA" "Gemma"

echo "Model directory ready inside app storage: /data/user/0/$PACKAGE_ID/$PHONE_MODEL_DIR"
