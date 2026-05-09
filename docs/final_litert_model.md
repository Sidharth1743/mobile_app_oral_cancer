# Final LiteRT Model Selection

## Selected Model
Use the backup vision export as the current final LiteRT model:

```text
model/gemma-4-E2B-it-v2-vision.litertlm
```

A local symlink was created for clarity:

```text
model/gemma-4-E2B-it-final.litertlm -> gemma-4-E2B-it-v2-vision.litertlm
```

The model directory is ignored by Git, so this symlink/model file is local only.

## Why This Model
The re-exported `no-vision-lora-15ep` model still produced degenerate repeated
text in LiteRT-LM, for example repeated `assistant` and malformed
`risk_from_review` phrases. It is not usable as the app model in its current
LiteRT export.

The `v2-describe-vision-on-15ep` export runs cleanly through the Gemma 4 LiteRT
vision path and returns valid JSON. With the conservative screening prompt it
achieved:

```text
accuracy: 0.6875
recall_refer_for_clinical_review: 1.0
recall_low_risk_or_variation: 0.375
unparsed: 0
```

This over-refers, but it is safer for a screening MVP than missing OPMD cases.

## Inference Command

```bash
.venv/bin/litert-lm run model/gemma-4-E2B-it-final.litertlm \
  --attachment oral_gemma_finetune_package/images/val/opmd_SMITA00018_W_LB_crop0_conf0.57.jpg \
  --prompt "You are an oral screening assistant for cancer risk screening. Analyze this cropped oral mucosal image. If there is any visible ulcer, white patch, red patch, pigmentation, irregular texture, raised area, or if the image is uncertain, choose refer_for_clinical_review. Return valid JSON only with keys category, recommendation, brief_reason, disclaimer. Categories: low_risk_or_variation or refer_for_clinical_review. Do not diagnose." \
  --backend cpu \
  --vision-backend cpu \
  --enable-speculative-decoding false \
  --max-num-tokens 256 \
  --temperature 0
```

## Push To Phone

```bash
MODEL_NAME=gemma-4-E2B-it-final.litertlm ./scripts/push_model_to_phone.sh
```

If the Android app expects `gemma-4-E2B-it.litertlm`, either update the app
model filename setting or copy the final model to that name deliberately after
selection.
