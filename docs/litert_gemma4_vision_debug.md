# Gemma 4 LiteRT Vision Export Debug Log

## Purpose
This document records the Gemma 4 E2B LoRA to LiteRT-LM vision export work,
the runtime failures observed, the fixes applied, and the current model-quality
status. It is meant as a handoff for continuing the project or opening an
upstream issue/PR.

## Final Runtime Status
The LiteRT-LM multimodal runtime path now works. A successful smoke test showed:

```text
Creating Gemma4DataProcessor
Resize image from 2592x1944 to 912x672 which will result in 2394 patches
encoder_signature_index: 0 name: vision_2520
adapter_signature_index: 0 name: vision_adapter
RunPrefillAsync status: OK
RunDecodeAsync
```

This means the image path reaches:

```text
image file -> Gemma4DataProcessor -> vision encoder -> vision adapter -> text prefill -> decode
```

The remaining issue is model behavior/quality, not the LiteRT vision runtime.

## Main Files Changed
- `.gitignore`
  - Added rules to keep model files, datasets, logs, generated outputs, Firebase
    secrets, build artifacts, Python/Node caches, and training outputs out of
    Git.
- `scripts/convert_unsloth_lora_to_litert.py`
  - Captures `latest_export.json`.
  - Deletes stale `model.litertlm` and XNNPack cache files before export.
  - Copies successful exports to an optional capture path.
  - Supports Gemma 4 `image_text_to_text`, vision export, lightweight export,
    single-token embedder, and no-vision quantization settings.
- `scripts/convert_unsloth_lora_to_litert.sh`
  - Environment-driven wrapper around the Python converter.
  - Applies the Gemma 4 vision patch before `EXPORT_VISION_ENCODER=1` exports.
- `scripts/patch_litert_gemma4_vision_export.py`
  - Patches the active `.venv` `litert_torch` installation.
  - Registers Gemma 4 vision exportables.
  - Adds Gemma 4 metadata builder wiring.
  - Adds support for `vision_encoder_quantization_recipe=none`.
  - Patches Transformers Gemma 4 view-return problems by cloning view tensors.
- `scripts/litert_gemma4_vision_patch/vision_exportable.py`
  - Implements Gemma 4 vision encoder and adapter exportables.
  - Encoder signature: `vision_2520`.
  - Encoder inputs: `images`, `positions_xy`.
  - Encoder outputs: `features`, `mask`.
  - Adapter signature: `vision_adapter`.
  - Adapter input: `features`.
- `scripts/litert_gemma4_vision_patch/metadata_builder.py`
  - Writes Gemma 4 LiteRT-LM metadata:
    `patch_width=16`, `patch_height=16`, `max_num_patches=2520`,
    `pooling_kernel_size=3`, image/audio token strings.
- `scripts/litert_gemma4_vision_patch/export_lib_none_quantization.py`
  - Local patch snippet that lets the vision encoder stay unquantized.
- `scripts/convert_v2_vision_lora_to_litert.sh`
  - Safe converter for `v2-describe-vision-on-15ep`.
  - Writes to separate output/capture paths; does not overwrite the main model.
- `scripts/convert_no_vision_lora_to_litert_versioned.sh`
  - Safe timestamped converter for `no-vision-lora-15ep`.
  - Avoids overwriting existing model artifacts.
- `scripts/evaluate_litert_oral_models.py`
  - Runs LiteRT-LM batch evaluation against local image samples.
  - Writes timestamped JSONL and summary outputs.
  - Supports `training`, `conservative`, and `forced_choice` prompt modes.
- `docs/litert_gemma4_vision_debug.md`
  - This full debugging record.

## Artifact Paths
Current default/captured artifacts:

```text
model/gemma-4-E2B-it.litertlm
model/gemma-4-E2B-it-v2-vision.litertlm
oral_gemma_finetune_package/outputs/no-vision-lora-15ep-litert/model.litertlm
oral_gemma_finetune_package/outputs/v2-describe-vision-on-15ep-litert/model.litertlm
```

Important: earlier exports overwrote `model/gemma-4-E2B-it.litertlm`. New
versioned scripts avoid this by writing timestamped filenames.

## Export Commands
Original no-vision LoRA export, overwrites the given capture path:

```bash
PYTHON_BIN=.venv/bin/python \
EXPORT_VISION_ENCODER=1 \
VISION_QUANTIZE=none \
PREFILL_SEQ_LEN=64 \
KV_CACHE_MAX_LEN=256 \
EXPORT_THREADS=1 \
LIGHTWEIGHT_CONVERSION=1 \
SINGLE_TOKEN_EMBEDDER=1 \
CAPTURE_MODEL_PATH=model/gemma-4-E2B-it.litertlm \
./scripts/convert_unsloth_lora_to_litert.sh > convert.log 2>&1
```

Safer no-overwrite no-vision export:

```bash
./scripts/convert_no_vision_lora_to_litert_versioned.sh > convert-no-vision-versioned.log 2>&1
```

Safer no-overwrite v2 vision export:

```bash
./scripts/convert_v2_vision_lora_to_litert.sh > convert-v2-vision.log 2>&1
```

## Runtime Smoke Test
Use this to verify the exported model runs end to end:

```bash
.venv/bin/litert-lm run model/gemma-4-E2B-it.litertlm \
  --attachment assets/demo/frames/left_buccal.png \
  --prompt "Describe the oral image in one short sentence." \
  --backend cpu \
  --vision-backend cpu \
  --enable-speculative-decoding false \
  --max-num-tokens 96 \
  --temperature 0 \
  --verbose
```

The key success line is:

```text
RunPrefillAsync status: OK
```

## Errors Seen And Fixes

### 1. Missing Gemma 4 Vision Exportables
Error:

```text
ValueError: Unsupported model type: gemma4
```

Cause: public `litert_torch` could export Gemma 4 text, but had no registered
Gemma 4 vision exportables.

Fix: added `scripts/litert_gemma4_vision_patch/vision_exportable.py` and
registered it through `scripts/patch_litert_gemma4_vision_export.py`.

### 2. Vision Encoder Export Tried Unsupported Vision Path
Error:

```text
Export vision encoder models
ValueError: Unsupported model type: gemma4
```

Cause: `export_hf` had no Gemma 4 branch for vision encoder/adapter.

Fix: patched `litert_torch.generative.export_hf.model_ext.exportables` so
`model_type == "gemma4"` returns Gemma 4 vision encoder and adapter classes.

### 3. LiteRT Conversion View/Functionalization Failures
Symptom: PyTorch export/decomposition failed on view-returned tensors.

Cause: Gemma 4 attention/repeat code returned aliases/views that LiteRT export
did not accept cleanly.

Fix: patch `transformers/models/gemma4/modeling_gemma4.py` in the active venv:

```text
repeat_kv n_rep == 1 -> return hidden_states.clone()
q_proj(...).view(...) -> .view(...).clone()
k_proj(...).view(...) -> .view(...).clone()
v_proj(...).view(...) -> .view(...).clone()
```

### 4. Wrong Raw Image Encoder Assumption
Earlier attempt exported encoder input as raw NHWC image:

```text
images: (1, 672, 912, 3)
```

Runtime behavior proved this was wrong. LiteRT-LM already preprocesses image
files into patch tensors. Correct encoder input is:

```text
images: (1, 2520, 768)
positions_xy: (1, 2520, 2)
```

Fix: removed raw-image patchification from the exported encoder and accepted
patch tensors directly.

### 5. Missing Input Name
Error:

```text
Failed to find input
vision_litert_compiled_model_executor.cc:518
```

Cause: encoder exported only `images`, but LiteRT-LM Gemma 4 runtime sends both
`images` and `positions_xy`.

Fix: encoder `forward()` now accepts:

```python
forward(images, positions_xy)
```

### 6. Metadata/Signature Mismatch
Observed logs:

```text
Resize image from 2592x1944 to 912x672 which will result in 2394 patches
encoder_signature_index: 0 name: vision_2394
```

and later:

```text
encoder_signature_index: 0 name: vision_2520
```

Cause: trying to export exact resized patch signatures (`vision_2394`) conflicted
with runtime metadata and signature selection.

Fix: use fixed capacity signature:

```text
vision_2520
max_num_patches = 2520
```

The runtime fills unused patches as padding.

### 7. Adapter Input Buffer Too Small
Errors:

```text
TensorBuffer host memory buffer size is smaller than the given data size, 860160 vs 921600
967680 vs 1050624
1105920 vs 1225728
```

Cause: adapter was exported with too few feature tokens while the runtime was
estimating the number of vision tokens itself.

Attempts:

- fixed adapter capacity `280`
- fixed adapter capacity `315`
- fixed adapter capacity `360`
- dynamic adapter input shape
- fixed encoder/adapter capacity `1024`
- fixed capacity `1260`

These were not the correct root fix because the runtime count kept changing
based on missing metadata/output information.

### 8. Dynamic Adapter Output Allocation Failure
Error:

```text
Custom allocation is too small for tensor idx: 17
Failed to invoke the compiled model
```

Cause: dynamic adapter input/output exported, but LiteRT-LM custom output
allocation was sized before the dynamic output length was known.

Fix: abandoned dynamic adapter output as the primary solution.

### 9. Missing Encoder Mask
Final root cause for the moving token-count problem:

LiteRT-LM has two paths:

- if encoder output includes `mask`, count valid pooled tokens from mask;
- otherwise estimate token count from raw patch count and shrink metadata.

Our encoder exported only `features`, so LiteRT-LM guessed and requested
oversized buffers.

Fix: encoder now returns:

```python
{
  "features": pooled_features,
  "mask": pooler_mask,
}
```

Final shape contract:

```text
encoder input images       (1, 2520, 768)
encoder input positions_xy (1, 2520, 2)
encoder output features    (1, 280, 768)
encoder output mask        (1, 280)
adapter input features     (1, 280, 768)
adapter output mm_embedding
```

### 10. Model Output Repetition
Runtime worked, but `no-vision-lora-15ep` LiteRT output repeated phrases like:

```text
JSON response is JSON response...
The cropped image refers to...
```

Status: this is model/export/template behavior, not a runtime crash. The PyTorch
prediction files still show `no-vision-lora-15ep` as a strong candidate, so it
must be re-exported and compared using versioned artifacts.

## Model Quality Findings

### v2 Vision Model
Exported as:

```text
model/gemma-4-E2B-it-v2-vision.litertlm
```

Training-style prompt produced clean JSON, but initially predicted almost
everything low risk:

```text
accuracy: 0.5
recall_refer_for_clinical_review: 0.0
recall_low_risk_or_variation: 1.0
```

With conservative prompt:

```text
oral_gemma_finetune_package/outputs/litert_eval/20260509-140437/summary.json
accuracy: 0.6875
recall_refer_for_clinical_review: 1.0
recall_low_risk_or_variation: 0.375
unparsed: 0
```

With forced-choice prompt:

```text
oral_gemma_finetune_package/outputs/litert_eval/20260509-140507/summary.json
accuracy: 0.5
recall_refer_for_clinical_review: 1.0
recall_low_risk_or_variation: 0.0
unparsed: 0
```

Conclusion: `conservative` prompt is the best current prompt for screening
safety. It catches OPMD in the sampled set but over-refers low-risk images.

### no-vision-lora-15ep
This remains the intended primary checkpoint because prior balanced PyTorch
prediction files indicated it was strongest overall. However, the current
captured LiteRT export had repeated/unparsed output. It should be re-exported
using:

```bash
./scripts/convert_no_vision_lora_to_litert_versioned.sh
```

Then evaluate without overwriting existing artifacts.

## Evaluation Commands
Compare models on balanced local validation samples:

```bash
scripts/evaluate_litert_oral_models.py \
  --model model/gemma-4-E2B-it.litertlm \
  --model model/gemma-4-E2B-it-v2-vision.litertlm \
  --image-root oral_gemma_finetune_package/images/val \
  --per-class 8 \
  --max-num-tokens 256
```

Conservative prompt:

```bash
scripts/evaluate_litert_oral_models.py \
  --model model/gemma-4-E2B-it-v2-vision.litertlm \
  --image-root oral_gemma_finetune_package/images/val \
  --per-class 8 \
  --max-num-tokens 256 \
  --prompt-mode conservative
```

Forced-choice prompt:

```bash
scripts/evaluate_litert_oral_models.py \
  --model model/gemma-4-E2B-it-v2-vision.litertlm \
  --image-root oral_gemma_finetune_package/images/val \
  --per-class 8 \
  --max-num-tokens 256 \
  --prompt-mode forced_choice
```

Evaluation outputs are timestamped and do not overwrite previous runs:

```text
oral_gemma_finetune_package/outputs/litert_eval/YYYYMMDD-HHMMSS/
```

## Git And Artifact Hygiene
`.gitignore` was expanded to avoid committing:

- `model/`
- `*.litertlm`, `*.tflite`, `*.safetensors`, `*.pt`, `*.pth`, `*.bin`
- `oral_gemma_finetune_package/outputs/`
- `oral_gemma_finetune_package/images/`
- `oral_gemma_finetune_package/data/`, `data_*/`
- `node_modules/`, `.venv/`, `.dart_tool/`, `build/`
- Firebase secrets such as `android/app/google-services.json` and
  `firebase/google-services.json`
- conversion logs and emulator logs

## Current Recommendation
1. Keep `model/gemma-4-E2B-it-v2-vision.litertlm` as a backup because it runs
   cleanly and can achieve high sensitivity with conservative prompting.
2. Re-export `no-vision-lora-15ep` with the versioned no-overwrite script.
3. Evaluate the new no-vision version with all three prompt modes.
4. Select the final app model by prioritizing:
   - valid JSON rate,
   - `refer_for_clinical_review` recall,
   - then low-risk specificity.
5. Only after selecting the winner, copy that model into the app’s canonical
   model path.
