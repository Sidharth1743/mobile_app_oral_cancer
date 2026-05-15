#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ID="${PACKAGE_ID:-com.example.oral_cancer}"
PHONE_MODEL_DIR="${PHONE_MODEL_DIR:-/sdcard/Android/data/$PACKAGE_ID/files/models}"

LOCAL_GEMMA="${LOCAL_GEMMA:-/home/sach/gemma/organized_artifacts/models/MAIN_ours_text_ours_vision/model.litertlm}"
PHONE_GEMMA="${PHONE_GEMMA:-$PHONE_MODEL_DIR/gemma-4-E2B-it-final.litertlm}"

LOCAL_YOLO="${LOCAL_YOLO:-/home/sach/gemma/organized_artifacts/yolo_prefilter/YOLO11n_lesion_cropper_best_mobile_exports/yolo11n_lesion_best_640_int8.tflite}"
PHONE_YOLO="${PHONE_YOLO:-$PHONE_MODEL_DIR/yolo11n_lesion_best_640_int8.tflite}"

device_size() {
  adb shell "stat -c %s '$1' 2>/dev/null || echo 0" | tr -d '\r'
}

stage_if_needed() {
  local local_path="$1"
  local phone_path="$2"
  local label="$3"

  if [[ ! -f "$local_path" ]]; then
    echo "Missing local $label model: $local_path" >&2
    exit 1
  fi

  local local_size
  local remote_size
  local_size="$(stat -c %s "$local_path")"
  remote_size="$(device_size "$phone_path")"

  if [[ "$remote_size" == "$local_size" ]]; then
    echo "[$label] already staged: $phone_path ($remote_size bytes)"
    return
  fi

  if [[ "$remote_size" != "0" ]]; then
    echo "[$label] remote size mismatch: $remote_size != $local_size; replacing"
    adb shell "rm -f '$phone_path'"
  else
    echo "[$label] missing on device; pushing"
  fi
  adb push "$local_path" "$phone_path"
}

adb shell "mkdir -p '$PHONE_MODEL_DIR'"
stage_if_needed "$LOCAL_YOLO" "$PHONE_YOLO" "YOLO"
stage_if_needed "$LOCAL_GEMMA" "$PHONE_GEMMA" "Gemma"

echo "Model directory ready: $PHONE_MODEL_DIR"
