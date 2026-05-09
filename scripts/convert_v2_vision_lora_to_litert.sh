#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL_DIR="$ROOT_DIR/oral_gemma_finetune_package/outputs/v2-describe-vision-on-15ep" \
MERGED_DIR="$ROOT_DIR/oral_gemma_finetune_package/outputs/v2-describe-vision-on-15ep-merged" \
TFLITE_OUT_DIR="$ROOT_DIR/oral_gemma_finetune_package/outputs/v2-describe-vision-on-15ep-litert" \
CAPTURE_MODEL_PATH="$ROOT_DIR/model/gemma-4-E2B-it-v2-vision.litertlm" \
EXPORT_VISION_ENCODER=1 \
VISION_QUANTIZE=none \
PREFILL_SEQ_LEN="${PREFILL_SEQ_LEN:-64}" \
KV_CACHE_MAX_LEN="${KV_CACHE_MAX_LEN:-256}" \
EXPORT_THREADS="${EXPORT_THREADS:-1}" \
LIGHTWEIGHT_CONVERSION=1 \
SINGLE_TOKEN_EMBEDDER=1 \
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}" \
"$ROOT_DIR/scripts/convert_unsloth_lora_to_litert.sh"
