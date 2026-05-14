#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_FILE:-$LOG_DIR/mobile_demo_flow-$RUN_ID.log}"

mkdir -p "$LOG_DIR"
if [[ "${NO_PROCESS_LOG:-0}" != "1" ]]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

MODEL_PATH_ON_PHONE="/sdcard/Android/data/com.example.oral_cancer/files/models/gemma-4-E2B-it-final.litertlm"
echo "[$(date -Iseconds)] [mobile_demo] log_file=$LOG_FILE"

echo "1) Build debug APK"
echo "   flutter build apk --debug"

echo "2) Install APK"
echo "   adb install -r build/app/outputs/flutter-apk/app-debug.apk"

echo "3) Push model file"
echo "   adb push model/gemma-4-E2B-it-final.litertlm ${MODEL_PATH_ON_PHONE}"

echo "4) Run app"
echo "   flutter run -d <device-id> --dart-define=LITERT_MODEL_PATH=${MODEL_PATH_ON_PHONE}"

echo "5) Observe logs"
echo "   adb logcat | rg \"OralCancerLiteRT|flutter|ffmpeg\""

echo
echo "Manual demo checks:"
echo "- Intake -> Capture (6 sites) -> Analyze"
echo "- Result screen renders"
echo "- Consent recorded after result"
echo "- Doctor package/research queue entries created"
echo "- Optional sync from queue after consent"
echo "[$(date -Iseconds)] [mobile_demo] checklist printed"
