# PC Backend And Local UI

This backend is for testing the fine-tuned Gemma LoRA adapter on this PC.

It is separate from the Android LiteRT path.

## Model Paths

Base model:

```text
oral_gemma_finetune_package/model/gemma-unsloth-e2b
```

Fine-tuned LoRA adapter:

```text
oral_gemma_finetune_package/outputs/no-vision-lora-15ep
```

The adapter is not a `.litertlm` file. It is a PEFT/LoRA adapter:

```text
adapter_config.json
adapter_model.safetensors
```

## What The Backend Does

- Starts a FastAPI server on the PC.
- Checks model files.
- Loads the real Gemma base model plus the LoRA adapter.
- Accepts an uploaded oral crop image.
- Runs the real model.
- Parses only strict JSON:
  - `category`
  - `recommendation`
  - `brief_reason`
  - `disclaimer`
- Rejects malformed model output.
- Does not return a fallback result.

## Install Python Dependencies

Use the environment where CUDA, PyTorch, and Unsloth work.

From repo root:

```bash
python3 -m pip install -r oral_gemma_finetune_package/requirements.txt
```

If Python 3.13 causes PyTorch/Unsloth install problems, use a Python 3.11 or 3.12 environment for the PC backend.

## Run Lightweight Backend Tests

These tests do not load the 9.6 GB model. They test parsing, file checks, upload validation, and UI constraints.

```bash
./scripts/run_pc_backend_tests.sh
```

Equivalent:

```bash
python3 -m unittest discover -s backend/tests
```

## Start The Backend

```bash
./scripts/run_pc_backend.sh
```

Equivalent:

```bash
ORAL_GEMMA_MODEL_DIR=oral_gemma_finetune_package/outputs/no-vision-lora-15ep \
ORAL_GEMMA_BASE_MODEL_DIR=oral_gemma_finetune_package/model/gemma-unsloth-e2b \
uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Open:

```text
http://127.0.0.1:8000
```

## Merge LoRA And Prepare LiteRT Artifacts

If you want to use your fine-tuned model beyond adapter-only format, use:

```bash
./scripts/convert_unsloth_lora_to_litert.sh
```

What it does:

1. Merges the Unsloth LoRA adapter into a full 16-bit Hugging Face model directory.
2. Attempts LiteRT conversion from the merged directory.

Useful environment overrides:

```bash
MODEL_DIR=oral_gemma_finetune_package/outputs/no-vision-lora-15ep \
MERGED_DIR=oral_gemma_finetune_package/outputs/no-vision-lora-15ep-merged \
TFLITE_OUT_DIR=oral_gemma_finetune_package/outputs/no-vision-lora-15ep-litert \
./scripts/convert_unsloth_lora_to_litert.sh
```

Merge-only mode:

```bash
SKIP_CONVERT=1 ./scripts/convert_unsloth_lora_to_litert.sh
```

After merge, you can run the backend against the merged model directory:

```bash
ORAL_GEMMA_MODEL_DIR=oral_gemma_finetune_package/outputs/no-vision-lora-15ep-merged \
uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

## Run Local LiteRT Helper For Desktop App

The Flutter desktop flow can call a local helper that runs the real LiteRT model:

```bash
PYTHON_BIN=.venv/bin/python \
MODEL_PATH=model/gemma-4-E2B-it-final.litertlm \
PORT=8010 \
./scripts/run_pc_litert_helper.sh
```

Health check:

```bash
curl http://127.0.0.1:8010/health
```

Desktop Flutter run (app calls helper by default on non-Android platforms):

```bash
flutter run -d linux --dart-define=LITERT_MODEL_PATH=model/gemma-4-E2B-it-final.litertlm
```

Optional helper URL override:

```bash
flutter run -d linux \
  --dart-define=LITERT_MODEL_PATH=model/gemma-4-E2B-it-final.litertlm \
  --dart-define=PC_LITERT_HELPER_URL=http://127.0.0.1:8010
```

## API Endpoints

Status:

```bash
curl http://127.0.0.1:8000/api/status
```

Analyze:

```bash
curl -F "file=@/path/to/oral_crop.jpg" http://127.0.0.1:8000/api/analyze
```

## Android Emulator Access

If the Flutter app runs in Android Studio emulator and needs to call this PC backend:

```text
http://10.0.2.2:8000
```

Android emulator maps `10.0.2.2` to the host PC.

## Real Inference Requirements

Real inference requires:

- CUDA GPU
- PyTorch
- Unsloth
- Transformers
- FastAPI
- Uvicorn
- Pillow
- The base model files
- The LoRA adapter files

If CUDA is unavailable, `/api/status` still works, but `/api/analyze` fails clearly instead of returning a fake result.
