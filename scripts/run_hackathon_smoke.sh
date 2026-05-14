#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_FILE:-$LOG_DIR/hackathon_smoke-$RUN_ID.log}"

mkdir -p "$LOG_DIR"
if [[ "${NO_PROCESS_LOG:-0}" != "1" ]]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

echo "[$(date -Iseconds)] [smoke] start"
echo "[$(date -Iseconds)] [smoke] log_file=$LOG_FILE"

echo "[smoke] PC backend tests"
./scripts/run_pc_backend_tests.sh

if command -v npm >/dev/null 2>&1; then
  echo "[smoke] Cloud Functions validation tests"
  npm run test:functions

  echo "[smoke] Firebase rules emulator tests"
  npm run test:rules
else
  echo "[smoke] npm not found in PATH; skipping functions/rules smoke tests."
fi

echo "[smoke] Done."
echo "[$(date -Iseconds)] [smoke] end"
