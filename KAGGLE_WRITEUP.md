# Oral Gemma Sachiv: On-Device Oral Cancer Screening with Gemma 4 Vision

**Subtitle:** A field-ready Android app that fine-tunes Gemma 4 E2B-it for oral lesion triage, runs inference fully offline via LiteRT-LM, and syncs consent-gated clinical data to Firebase when connectivity returns.

**Suggested track:** Gemma 4 in Your App (Mobile / Edge AI)

---

## Problem and motivation

Oral cancer is a leading cause of cancer mortality in India, yet many high-risk patients are first seen by community health workers (ASHA) in villages with unreliable connectivity. Screening must work **without the cloud**, respect **patient privacy**, and still let doctors and researchers access structured outcomes when consent allows.

**Oral Gemma Sachiv** (Sachiv = secretary/assistant in Hindi) is an Android-first screening assistant that captures oral video, runs **Gemma 4 vision inference on the phone**, and produces a structured triage result (refer, low risk, or recapture) that ASHA workers can act on immediately.

---

## System architecture

The system has four layers:

1. **On-device inference (offline core)** — Flutter UI → FFmpeg frame extraction → YOLOv11n lesion prefilter (TFLite INT8) → Gemma 4 E2B-it classifier (LiteRT-LM, ~3.1 GB) → strict JSON parsing → local SQLite.
2. **Privacy and consent** — PII encrypted locally with ASHA PIN; de-identified exports for research; four-scope consent gate (doctor, ASHA, cloud backup, research).
3. **Cloud sync (online, optional)** — Firebase Auth (role-based), Firestore case documents, Cloud Storage for ROI images, Cloud Functions for research validation.
4. **Training and export (PC/GPU)** — Unsloth QLoRA fine-tuning on `google/gemma-4-E2B-it`, conversion to `.litertlm`, evaluation, and `adb` deployment to device private storage.

```
Patient intake → Video capture → Frame extract → YOLO crop → Gemma JSON classify
      → Result + consent → SQLite queue → (when online) Firebase → Role dashboards
```

**Attached assets (required for eligibility):**
- Architecture diagram (high-level flow)
- Demo video (end-to-end screening on a physical device)
- Screenshots: intake, inference progress, result, consent, staff login
- Link to fine-tuned model card / Hugging Face artifact (`gemma-4-E2B-it-final.litertlm`)

---

## How we use Gemma 4 specifically

We use **Gemma 4 E2B-it** as a **vision-language classifier**, not a open-ended chatbot. This matches the clinical need: bounded outputs, auditable JSON, and predictable latency on mid-range phones.

### Fine-tuning

- **Base model:** `google/gemma-4-E2B-it` via Unsloth (`FastVisionModel`, `UnslothVisionDataCollator`, `gemma-4` chat template).
- **Task:** Binary clinical triage — `low_risk_or_variation` vs `refer_for_clinical_review` on cropped oral mucosa images, plus `recapture_required` at inference time for bad frames.
- **Method:** QLoRA (r=32, α=64) with **vision layers trainable**; 20 epochs with early stopping and a **clinical selection callback** that maximizes refer recall while requiring minimum macro-F1 (0.45) so we do not sacrifice overall quality for sensitivity alone.
- **Export:** LoRA merged and converted to **LiteRT-LM** (`.litertlm`) for on-device deployment with the official `litertlm-android` runtime.

### On-device inference pipeline

1. **Video → frames:** FFmpeg extracts candidate frames from a short oral cavity video.
2. **YOLO prefilter:** A 6 MB INT8 YOLOv11n model detects lesion-like regions; crops are resized to 224×224 for Gemma. If YOLO finds nothing, the pipeline falls back to quality-scored full frames (blur, exposure, oral-color gate).
3. **Gemma calls (sequential):** Up to five crops are sent **one at a time** through a Kotlin `MethodChannel` to a cached LiteRT-LM `Engine` (GPU backend preferred). Each call uses a fixed classifier prompt requiring JSON with `category`, `recommendation`, `brief_reason`, and `disclaimer`. Temperature is 0; max tokens 256.
4. **Aggregation:** If any frame is `refer_for_clinical_review`, the visit is referred. If all frames are `recapture_required`, the user is asked to recapture. Otherwise the result is low risk.
5. **Release:** After inference, the Gemma engine and YOLO interpreter are explicitly closed, and the camera controller is disposed to reduce peak RAM.

Gemma is also wired for **regional language output** (English, Hindi, Tamil, Kannada, Malayalam): JSON keys stay in English; patient-facing strings are localized via prompt instruction.

A fuller multi-site pipeline (`LesionAnalyzer` with site assessment, differential ranking, care plan, and delta prompts) is implemented for future 6-site capture; the hackathon demo path uses the streamlined **video triage pipeline** above.

---

## Technical choices and why they were right

| Choice | Rationale |
|--------|-----------|
| **Gemma 4 E2B-it (2B class)** | Strong vision-language quality with a model size that can run on-device after LiteRT export; E2B balances accuracy and deployability vs larger variants. |
| **LiteRT-LM on Android** | Official Google edge runtime for Gemma 4; avoids shipping PyTorch/TF on mobile; enables GPU inference via `EngineConfig`. |
| **YOLO before Gemma** | Reduces irrelevant pixels sent to a 3 GB VLM; improves latency and focuses Gemma on lesion-adjacent mucosa. |
| **Structured JSON outputs** | Clinical workflows need machine-readable triage, not prose; `strict_json.dart` parses model text defensively. |
| **Models outside APK** | `.litertlm` and `.tflite` are pushed to app-private storage via `adb run-as`, keeping APK small and allowing model updates without rebuild. |
| **SQLite + sync queue** | Offline-first: screening never blocks on network; uploads are consent-scoped and processed **sequentially** (FIFO) to avoid memory spikes and simplify failure handling. |
| **Firebase for roles only** | Auth + Firestore + Storage for ASHA/doctor/NGO/research dashboards; inference does not depend on cloud. |
| **PII vault + consent gate** | Regulatory alignment: identity stays encrypted locally; cloud paths receive only what the patient agreed to share. |

---

## Challenges we overcame

**1. Running a 3 GB vision model on a phone**  
Peak memory exceeded 3 GB PSS with camera preview + Gemma + YOLO active. We fixed this by releasing the camera before analysis, closing native engines after each pipeline stage, and staging models in `/data/user/0/.../files/models/` (not world-readable `/sdcard`).

**2. Model path and permissions**  
Hardcoded SD-card paths failed under scoped storage. `MobileModelPaths` resolves internal support directory, external app dir, then legacy fallbacks; `push_model_to_phone.sh` uses `adb push` + `run-as cp` for correct permissions.

**3. Reliable structured output**  
Vision LLMs sometimes emit extra keys or markdown. We constrain prompts (“Return only one compact JSON object”), forbid diagnosis language, and parse with defensive JSON extraction before mapping to `FullAssessment`.

**4. Offline-to-online handoff**  
Consent saves enqueue share requests locally (`doctor_share_request`, `cloud_backup_request`, etc.). `LocalSyncWorker` drains the queue **sequentially**: mark uploading → upload → mark synced/failed. Doctor package upload runs ROI `putFile` loops sequentially, then a single Firestore batch commit. Research export uses one Cloud Function callable per row. *Note:* automatic background sync on connectivity restore is designed (`ConnectivityPolicy`, 90s interval) and tested; wiring it to app lifecycle is the next integration step—manual/screen-triggered paths work today.

**5. Training → deployment gap**  
Unsloth trains Hugging Face checkpoints; phones need LiteRT. We scripted LoRA merge, LiteRT export patches, and `evaluate_litert_oral_models.py` so the same clinical labels are validated before device push.

---

## What the demo proves

The video demo shows real engineering, not a mock UI:

- Patient intake with village/state selection and encrypted identity
- Live video capture and on-device analysis progress (“Running YOLO…”, “Running Gemma on frame N/M”)
- Structured result with care plan messages for patient and ASHA
- Consent toggles and local sync queue visibility
- Staff login (Firebase Auth) and role home for operational follow-up

Judges can verify: Gemma 4 is **fine-tuned for our domain**, **exported to LiteRT**, **invoked from Kotlin**, and **drives clinical triage JSON** that persists locally and can sync to Firebase.

---

## Future work

- Background sync on connectivity restore (`connectivity_plus` + `LocalSyncWorker`)
- Full 6-site oral cavity protocol with per-site Gemma prompts (`PromptBuilders` / `LesionAnalyzer`)
- Smaller or stronger-quantized LiteRT build for low-RAM devices
- App Check and release signing for production ASHA rollout

---

## Team and repository

Built for the **Kaggle Gemma Sprint 2025**. Code, training scripts, Firebase rules, and deployment tooling are in the project repository. The fine-tuned LiteRT artifact and YOLO weights are deployed separately to device storage due to size.

**Word count:** ~1,480
