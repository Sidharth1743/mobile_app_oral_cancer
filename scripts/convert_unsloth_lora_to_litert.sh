#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

MODEL_DIR="${MODEL_DIR:-$ROOT_DIR/oral_gemma_finetune_package/outputs/no-vision-lora-15ep}"
MERGED_DIR="${MERGED_DIR:-$ROOT_DIR/oral_gemma_finetune_package/outputs/no-vision-lora-15ep-merged}"
TFLITE_OUT_DIR="${TFLITE_OUT_DIR:-$ROOT_DIR/oral_gemma_finetune_package/outputs/no-vision-lora-15ep-litert}"
OUTPUT_NAME_PREFIX="${OUTPUT_NAME_PREFIX:-gemma4-oc}"
PREFILL_SEQ_LEN="${PREFILL_SEQ_LEN:-256}"
KV_CACHE_MAX_LEN="${KV_CACHE_MAX_LEN:-1024}"
QUANTIZE="${QUANTIZE:-dynamic_wi4_afp32}"
EXPORT_TASK="${EXPORT_TASK:-text_generation}"
EXPORT_VISION_ENCODER="${EXPORT_VISION_ENCODER:-0}"
VISION_QUANTIZE="${VISION_QUANTIZE:-none}"
EXPORT_THREADS="${EXPORT_THREADS:-2}"
LIGHTWEIGHT_CONVERSION="${LIGHTWEIGHT_CONVERSION:-0}"
SINGLE_TOKEN_EMBEDDER="${SINGLE_TOKEN_EMBEDDER:-1}"
CAPTURE_MODEL_PATH="${CAPTURE_MODEL_PATH:-}"

# Set SKIP_CONVERT=1 to only create merged HF model.
SKIP_CONVERT="${SKIP_CONVERT:-0}"
# Set FORCE_MERGE=1 to rebuild the merged HF model. By default, reuse it.
FORCE_MERGE="${FORCE_MERGE:-0}"
SKIP_MERGE_ARGS=()
if [[ "$FORCE_MERGE" != "1" && -f "$MERGED_DIR/config.json" ]]; then
  SKIP_MERGE_ARGS=(--skip-merge)
fi
LIGHTWEIGHT_ARGS=()
if [[ "$LIGHTWEIGHT_CONVERSION" == "1" ]]; then
  LIGHTWEIGHT_ARGS=(--experimental-lightweight-conversion)
fi
SINGLE_TOKEN_ARGS=()
if [[ "$SINGLE_TOKEN_EMBEDDER" == "1" ]]; then
  SINGLE_TOKEN_ARGS=(--single-token-embedder)
fi
CAPTURE_ARGS=()
if [[ -n "$CAPTURE_MODEL_PATH" ]]; then
  CAPTURE_ARGS=(--capture-model-path "$CAPTURE_MODEL_PATH")
fi
VISION_ARGS=()
if [[ "$EXPORT_VISION_ENCODER" == "1" ]]; then
  EXPORT_TASK="image_text_to_text"
  VISION_ARGS=(--export-vision-encoder --vision-quantize "$VISION_QUANTIZE")
  "$PYTHON_BIN" "$ROOT_DIR/scripts/patch_litert_gemma4_vision_export.py"
fi

if [[ "$SKIP_CONVERT" == "1" ]]; then
  "$PYTHON_BIN" "$ROOT_DIR/scripts/convert_unsloth_lora_to_litert.py" \
    --model-dir "$MODEL_DIR" \
    --merged-dir "$MERGED_DIR" \
    "${SKIP_MERGE_ARGS[@]}" \
    --skip-convert
else
  "$PYTHON_BIN" "$ROOT_DIR/scripts/convert_unsloth_lora_to_litert.py" \
    --model-dir "$MODEL_DIR" \
    --merged-dir "$MERGED_DIR" \
    --tflite-out-dir "$TFLITE_OUT_DIR" \
    --output-name-prefix "$OUTPUT_NAME_PREFIX" \
    --export-task "$EXPORT_TASK" \
    --prefill-seq-len "$PREFILL_SEQ_LEN" \
    --kv-cache-max-len "$KV_CACHE_MAX_LEN" \
    --export-threads "$EXPORT_THREADS" \
    "${LIGHTWEIGHT_ARGS[@]}" \
    "${SINGLE_TOKEN_ARGS[@]}" \
    "${VISION_ARGS[@]}" \
    "${CAPTURE_ARGS[@]}" \
    "${SKIP_MERGE_ARGS[@]}" \
    --quantize "$QUANTIZE"
fi
