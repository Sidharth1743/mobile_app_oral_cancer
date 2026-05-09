#!/usr/bin/env bash
set -euo pipefail

export ORAL_GEMMA_MODEL_DIR="${ORAL_GEMMA_MODEL_DIR:-oral_gemma_finetune_package/outputs/no-vision-lora-15ep-merged}"
export ORAL_GEMMA_BASE_MODEL_DIR="${ORAL_GEMMA_BASE_MODEL_DIR:-oral_gemma_finetune_package/model/gemma-unsloth-e2b}"

uvicorn backend.main:app --host 127.0.0.1 --port 8000
