#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT_DIR="$(cd "$ROOT_DIR/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-$PARENT_DIR/venv/bin/python3}"
PORT="${PORT:-8010}"
HOST="${HOST:-127.0.0.1}"
MODEL_PATH="${MODEL_PATH:-$ROOT_DIR/model/gemma-4-E2B-it-final.litertlm}"
BACKEND="${BACKEND:-cpu}"
INFER_MODE="${INFER_MODE:-cli}"
CLI_BIN="${CLI_BIN:-$PARENT_DIR/venv/bin/litert-lm}"
TIMEOUT_SEC="${TIMEOUT_SEC:-180}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_FILE:-$LOG_DIR/pc_litert_helper-$RUN_ID.log}"

mkdir -p "$LOG_DIR"
if [[ "${NO_PROCESS_LOG:-0}" != "1" ]]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

if [[ ! -f "$MODEL_PATH" ]]; then
  echo "Model file not found: $MODEL_PATH" >&2
  exit 1
fi

export PC_LITERT_DEFAULT_MODEL="$MODEL_PATH"
export PC_LITERT_DEFAULT_BACKEND="$BACKEND"
export PC_LITERT_PORT="$PORT"
export PC_LITERT_HOST="$HOST"
export PC_LITERT_INFER_MODE="$INFER_MODE"
export PC_LITERT_CLI_BIN="$CLI_BIN"
export PC_LITERT_TIMEOUT_SEC="$TIMEOUT_SEC"
export PYTHONUNBUFFERED=1

echo "[$(date -Iseconds)] [pc_litert_helper] starting"
echo "[$(date -Iseconds)] [pc_litert_helper] log_file=$LOG_FILE"
echo "[$(date -Iseconds)] [pc_litert_helper] model_path=$MODEL_PATH backend=$BACKEND mode=$INFER_MODE host=$HOST port=$PORT timeout=$TIMEOUT_SEC cli_bin=$CLI_BIN"
"$PYTHON_BIN" "$ROOT_DIR/scripts/pc_litert_helper.py"
