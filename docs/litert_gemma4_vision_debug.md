# Gemma 4 LiteRT Vision Export Debug Log

## Goal
Export the fine-tuned Gemma 4 E2B model from
`oral_gemma_finetune_package/outputs/no-vision-lora-15ep-merged` into a
LiteRT-LM bundle at `model/gemma-4-E2B-it.litertlm` that supports image + text
inference through `litert-lm`.

## What Was Implemented
- Added a local Gemma 4 vision export patch under
  `scripts/litert_gemma4_vision_patch/`.
- Added `scripts/patch_litert_gemma4_vision_export.py` to patch the active
  `litert_torch` install before export.
- Registered Gemma 4 vision encoder and adapter exportables in LiteRT-Torch.
- Added Gemma 4 LiteRT-LM metadata generation with:
  - image token strings
  - patch size `16`
  - max patches `2520`
  - pooling kernel size `3`
- Patched Transformers Gemma 4 view-return issues by cloning tensors before
  LiteRT export.
- Fixed the first runtime failure by changing encoder input names to the
  LiteRT-LM contract:
  - `images`
  - `positions_xy`
- Fixed raw-image confusion: LiteRT-LM already preprocesses images into patch
  tensors, so the encoder must accept patch tensors shaped
  `(1, 2520, 768)`, not raw NHWC images.
- Tried static and dynamic adapter capacities to handle runtime token counts.

## Observed Runtime Failures
1. `Failed to find input`
   - Cause: encoder exported `images` only, but LiteRT-LM sends `images` and
     `positions_xy`.
   - Status: fixed.

2. `TensorBuffer host memory buffer size is smaller...`
   - `860160 vs 921600`: adapter input was `280` tokens, runtime sent `300`.
   - `967680 vs 1050624`: adapter input was `315`, runtime sent `342`.
   - `1105920 vs 1225728`: adapter input/output handling still moved with the
     sample capacity.
   - `3145728 vs 3677184`: current encoder output buffer is `1024` tokens, but
     runtime expects `1197` tokens for a `2394` patch image.

## Current Understanding
Gemma 4 vision preprocessing keeps aspect ratio and uses patch tokens. Public
docs say Gemma 4 supports configurable soft-token budgets such as `280`, with
pooling size `3`. For the demo image, LiteRT-LM resizes `2592x1944` to
`912x672`, producing `2394` patch tokens. The runtime then expects a larger
encoder feature buffer than our patched exporter produced.

The latest error shows:

```text
3145728 / 4 / 768 = 1024
3677184 / 4 / 768 = 1197
1197 = 2394 / 2
```

So the LiteRT-LM runtime is currently trying to copy `1197` encoder feature
tokens, while our encoder output buffer is capped at `1024`.

## Correct Fix
The LiteRT-LM vision executor has two paths:

- If the encoder exports a `mask` output, the runtime counts valid pooled
  tokens from that mask.
- If there is no `mask`, the runtime guesses token count from
  `patch_num_shrink_factor`.

Our patched encoder did not export `mask`, so the runtime guessed counts from
the raw patch count and kept asking for larger adapter buffers. The correct
shape contract is:

- encoder input `images`: `(1, 2520, 768)`
- encoder input `positions_xy`: `(1, 2520, 2)`
- encoder output `features`: `(1, 280, 768)`
- encoder output `mask`: `(1, 280)`
- adapter input `features`: `(1, 280, 768)`

The encoder must build `padding_positions` from `positions_xy == -1`, run the
Gemma 4 pooler, and return both pooled features and the pooler mask. This lets
LiteRT-LM send only the valid pooled tokens to the adapter.

## Validation Commands
The runtime export path is fixed. If generation quality is poor with
`no-vision-lora-15ep`, convert the better vision-trained adapter instead:

```bash
./scripts/convert_v2_vision_lora_to_litert.sh > convert-v2-vision.log 2>&1
```

This writes:

- merged HF model:
  `oral_gemma_finetune_package/outputs/v2-describe-vision-on-15ep-merged`
- LiteRT export:
  `oral_gemma_finetune_package/outputs/v2-describe-vision-on-15ep-litert/model.litertlm`
- captured app/test model:
  `model/gemma-4-E2B-it-v2-vision.litertlm`

It does not overwrite `model/gemma-4-E2B-it.litertlm`.

Export:

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

Smoke test:

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
