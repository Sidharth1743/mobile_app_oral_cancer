# Oral Gemma Fine-tuning Package

This package contains a portable training dataset for instruction fine-tuning a vision-language model on cropped oral mucosal lesion images.

## What This Dataset Is

The dataset is a binary oral screening dataset built from lesion-focused oral image crops.
Each example pairs one cropped oral mucosal image with an instruction-following JSON answer.
The task is not diagnosis. The task is to map an oral image crop to a safe binary screening response.

Target categories:

- `low_risk_or_variation`
- `refer_for_clinical_review`

The JSON responses are designed for conservative screening-style output, including recommendation, brief reasoning, and a non-diagnostic disclaimer.

## Dataset Contents

Total records: 364

Split summary:

- `train`: 244 records, category counts = {'low_risk_or_variation': 142, 'refer_for_clinical_review': 102}
- `val`: 55 records, category counts = {'refer_for_clinical_review': 18, 'low_risk_or_variation': 37}
- `test`: 65 records, category counts = {'low_risk_or_variation': 22, 'refer_for_clinical_review': 43}

## File Layout

- `data/train.jsonl`
- `data/val.jsonl`
- `data/test.jsonl`
- `images/train/...`
- `images/val/...`
- `images/test/...`

## JSONL Format

Each JSONL row contains:

- `image`: relative path to the packaged image file
- `messages`: chat-style training example with user and assistant turns
- `metadata`: split, source class, binary category, crop path, and detector confidence

The image paths were rewritten to be relative so the package can be moved to another machine without preserving the original local directory structure.

## Source Semantics

- `source_class` keeps the original upstream subtype such as `opmd` or `variation_from_normal`.
- `binary_category` is the training target used for safe binary screening.
- The task framing is screening support only and explicitly non-diagnostic.

## Expected Training Task

Input:
an oral mucosal crop and a short instruction asking for JSON only.

Output:
a JSON object with category, recommendation, brief_reason, and disclaimer.

## Usage Notes

- Paths are relative inside this package, so training scripts should load the JSONL files from `data/` and resolve image paths relative to the package root.
- This package includes only the dataset. The model weights are not included.
- If you use a training script, confirm that it does not assume old absolute paths like `/content/drive/...`.
- The training script defaults to the local Unsloth checkpoint at `model/gemma-unsloth-e2b`.
- The `litert-community/gemma-4-E2B-it-litert-lm` download is for LiteRT-LM inference/deployment. Its `.litertlm` file is not a trainable Unsloth/Transformers checkpoint. For Unsloth fine-tuning, use the Unsloth checkpoint `unsloth/gemma-4-E2B-it`.
- To train from Hugging Face instead of the local checkpoint, run `python3 train_gemma4_e2b.py --model-dir missing --allow-hub-fallback`.
- The training script follows Unsloth's Gemma 4 vision format: image first, text instruction second, `FastVisionModel`, `UnslothVisionDataCollator`, and the `gemma-4` chat template.
- Training logs to Weights & Biases by default. First run `wandb login`, then start training with `python3 train_gemma4_e2b.py --wandb-run-name my-run`. Use `--no-wandb` to disable logging.
- W&B will show the essential fine-tuning curves: train loss, validation loss, learning rate, gradient norm, epoch/step progress, GPU memory curves, and optional gradient/parameter histograms controlled by `--wandb-watch gradients|all|false`.
- Each training run now saves to a fresh timestamped directory under `outputs/` by default. Pass `--output-dir path/to/run --overwrite-output-dir` only when you intentionally want to reuse an existing directory.
- Early stopping on validation loss is enabled by default with `--early-stopping-patience 4 --early-stopping-threshold 0.01`. Disable it with `--no-early-stopping`.
- Generation-based clinical validation is enabled by default every 50 optimizer steps. It logs `clinical_val/refer_recall`, `clinical_val/macro_f1`, low-risk metrics, and confusion counts to W&B, then saves the best clinical adapter to `outputs/<run>/best_clinical/` by maximizing referral recall with macro-F1 as the tie-breaker. Tune with `--clinical-eval-steps`, `--clinical-min-macro-f1`, `--clinical-eval-max-samples`, `--clinical-max-new-tokens`, or disable with `--no-clinical-eval`.
- After training, benchmark the newest saved LoRA or checkpoint on the test split with `python3 benchmark_gemma4_e2b.py`. To compare checkpoints directly, pass paths like `--adapter-dir outputs/my-run/checkpoint-600`.
- Benchmark validation with `python3 benchmark_gemma4_e2b.py --split val --adapter-dir outputs/my-run`, or benchmark all splits with `python3 benchmark_gemma4_e2b.py --all-splits --adapter-dir outputs/my-run`.
- Benchmark the non-fine-tuned local base model with `python3 benchmark_gemma4_e2b.py --base-model`.

## Suggested Training Environment

- The current training script used by the package creator is optimized conservatively for limited VRAM and 4-bit QLoRA.
- On an RTX 3090, the current script configuration should run, but it is conservative rather than performance-oriented.

## Local UI

- The local review UI uses `outputs/no-vision-lora-15ep` by default.
- Start it on this PC with `uvicorn main:app --host 127.0.0.1 --port 8000`.
- Open `http://127.0.0.1:8000`.
- To use a different adapter, set `ORAL_GEMMA_MODEL_DIR=/path/to/adapter` before starting the server.
