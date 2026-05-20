# ORCA-G4

**OR**al **C**ancer screening with **G**emma **4** — Android app for offline oral mucosal screening using on-device **YOLO** lesion prefiltering and **Gemma 4 E2B-it** (LiteRT-LM). Built for community health workflows (e.g. ASHA): capture video, review YOLO crops, run Gemma triage, then optionally sync consent-gated data to Firebase.

| | |
|---|---|
| **Demo** | [YouTube walkthrough](https://www.youtube.com/watch?v=ZtOtu5DVxAM) |
| **Platform** | Android (arm64-v8a), API 26+ |
| **Package** | `com.example.oral_cancer` |
| **Stack** | Flutter · LiteRT-LM · TFLite · Firebase · SQLite |

> **Not a medical device.** Screening support only; clinical review is required.

---

## Features

- **Video screening** — extract frames → YOLO boxes → review frames in-app → Gemma classification per frame
- **On-device inference** — no cloud required for analysis (~3 GB Gemma + YOLO staged on phone)
- **Voice intake** — speak patient details; Gemma extracts fields you can edit and translate locally
- **Offline-first** — SQLite queue; sync when online and consented
- **Role views** — ASHA, doctor, research, NGO dashboards (Firebase Auth + Firestore)
- **Privacy** — local PII vault; de-identified exports; four-scope consent

---

## How it works

```
Intake → Video → FFmpeg frames → YOLO detect/crop → [Review frames] → Gemma (per frame)
    → Result + consent → Local DB → (optional) Firebase sync
```

Models are **not bundled in the APK**. Download or build weights, then push once via USB (see below).

---

## Models

| Artifact | Hugging Face | Use |
|----------|--------------|-----|
| **LiteRT (on-device)** | https://huggingface.co/sach3v/Gemma-4-e2b-custom-oral_cancer | Copy as `model/model.litertlm` → push to phone |
| **QLoRA adapter (training)** | [Sidharth1743/orcal-cancer-gemma-4-e2b-finetuned](https://huggingface.co/Sidharth1743/orcal-cancer-gemma-4-e2b-finetuned) | Fine-tuned on `unsloth/gemma-4-E2B-it`; merge & convert to LiteRT for deployment |
| **YOLO** | https://huggingface.co/sach3v/Gemma-4-e2b-custom-oral_cancer/blob/main/yolo11n_lesion_best_640_int8.tflite | `yolo11n_lesion_best_640_int8.tflite` (project-trained; see [RELEASE_NOTES.md](RELEASE_NOTES.md)) |

The adapter targets conservative screening (`low_risk_or_variation`, `refer_for_clinical_review`) with structured JSON output. For Android, use the **LiteRT** bundle above (or export your own via `scripts/convert_unsloth_lora_to_litert.py`).

---

## Requirements

- Flutter SDK (Dart 3.10+)
- Android device or emulator (physical device recommended for Gemma/YOLO)
- `adb` for model deployment
- **PC:** Gemma `.litertlm` (~3 GB) from [HF LiteRT repo](https://huggingface.co/Sidharth1743/gemma-4-E2B-it-litertlm) and YOLO `.tflite` (see [Release notes](RELEASE_NOTES.md))
- **Optional:** Firebase project with `google-services.json` (included for demo project)

---

## Quick start

### 1. Clone and install

```bash
cd mobile_app_oral_cancer
flutter pub get
```

### 2. Stage models on the phone

Place files on your PC:

```text
model/model.litertlm
model/yolo11n_lesion_best_640_int8.tflite
```

Connect the phone (USB debugging), then:

```bash
chmod +x scripts/push_model_to_phone.sh
INSTALL_APK=0 ./scripts/push_model_to_phone.sh
```

Custom paths: set `LOCAL_GEMMA` and `LOCAL_YOLO` (documented in [RELEASE_NOTES.md](RELEASE_NOTES.md)).

### 3. Run the app

```bash
flutter run
# or
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

---

## Project layout

```text
lib/                    # Flutter app (intake, capture, inference, sync, UI)
android/                # LiteRT-LM + YOLO native channels
scripts/                # Model push, LiteRT convert, debug pull helpers
oral_gemma_finetune_package/   # Dataset + Unsloth training (train_gemma4_e2b.py)
functions/              # Firebase Cloud Functions (optional)
firebase-emulator-tests/
test/
RELEASE_NOTES.md        # APK install, model paths, GitHub release
```

| Path | Purpose |
|------|---------|
| `lib/inference/` | Video triage, YOLO prefilter, Gemma services |
| `lib/debug/` | Debug capture of raw Gemma / YOLO outputs |
| `lib/cloud/` | Firestore sync, role home data |
| `oral_gemma_finetune_package/train_gemma4_e2b.py` | Fine-tune Gemma 4 on oral crops |
| `scripts/convert_unsloth_lora_to_litert.py` | Export LoRA → `.litertlm` for Android |

---

## Scripts (common)

| Script | Use |
|--------|-----|
| `scripts/push_model_to_phone.sh` | Push Gemma + YOLO into app storage |
| `scripts/pull_debug_captures.sh` | Pull Gemma raw + YOLO debug artifacts to PC |
| `scripts/pull_raw_model_outputs.sh` | Gemma text captures only |
| `scripts/pull_yolo_debug_outputs.sh` | Annotated frames + crops |

Debug captures require a **debug** build (`flutter run`).

---

## Firebase (optional)

Works without billing for local screening. For full cloud sync (Storage, Functions), use a **Blaze** plan with active billing. Spark plan may block Storage uploads; the app can still write Firestore-only when configured.

```bash
firebase deploy --only firestore:rules,storage
# functions require Blaze
```

---

## Fine-tuning

Published adapter: [orcal-cancer-gemma-4-e2b-finetuned](https://huggingface.co/Sidharth1743/orcal-cancer-gemma-4-e2b-finetuned). Training scripts live in [`oral_gemma_finetune_package/`](oral_gemma_finetune_package/README.md):

```bash
cd oral_gemma_finetune_package
python3 train_gemma4_e2b.py
```

Export to LiteRT ([published bundle](https://huggingface.co/Sidharth1743/gemma-4-E2B-it-litertlm) or your own) — see `scripts/convert_unsloth_lora_to_litert.sh` and [docs/final_litert_model.md](docs/final_litert_model.md).

---

## Build & test

```bash
flutter analyze
flutter test
flutter build apk --release
```

Release APK: `build/app/outputs/flutter-apk/app-release.apk`  
Full release checklist: [RELEASE_NOTES.md](RELEASE_NOTES.md)

---

## More documentation

- [Demo video](https://www.youtube.com/watch?v=ZtOtu5DVxAM) — app walkthrough on YouTube
- [RELEASE_NOTES.md](RELEASE_NOTES.md) — install, model paths, manual `adb` copy
- [KAGGLE_WRITEUP.md](KAGGLE_WRITEUP.md) — architecture and design rationale
- [implementation.md](implementation.md) — detailed implementation notes
- [PC_BACKEND.md](PC_BACKEND.md) — desktop LiteRT helper for Linux dev

---

## License

Model weights (Gemma, YOLO) follow their respective licenses. Application code: see repository license file if present.
