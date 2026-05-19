# Oral Gemma Sachiv — Release notes

Offline-first Android oral cancer screening: YOLO lesion prefilter, on-device Gemma 4 E2B-it (LiteRT-LM), voice intake, and optional Firebase sync.

**Package:** `com.example.oral_cancer`  
**Min Android:** API 26 (Android 8.0), **arm64-v8a**  
**App version:** 1.0.0 (build 1)

---

## What is in the APK

| Included | Not included (install separately) |
|----------|-----------------------------------|
| Flutter app, YOLO + LiteRT native code | Gemma LiteRT model (~3 GB) |
| Firebase client (Auth / Firestore) | YOLO TFLite weights (~few MB) |
| UI, screening flow, debug capture hooks | Training data |

The APK alone will open the app, but **screening, voice extract, and translation need models** staged on the phone (see below).

---

## 1. Install the APK

**From GitHub Release**

1. Download `app-release.apk` (or `oral-gemma-sachiv-v1.0.0.apk`) from this release.
2. On the phone: allow install from unknown sources if prompted.
3. Open **Oral Cancer** / **oral_cancer** from the app drawer.

**From PC (USB)**

```bash
adb install -r app-release.apk
```

---

## 2. Prepare model files on your PC (copy to these paths)

Clone or unzip this repository, then place files under the app folder:

**Base folder (copy/paste path on Linux):**

```text
/home/YOUR_USER/path/to/oral-gemma-sachiv/mobile_app_oral_cancer/
```

**Required local files before running the push script:**

| Model | Copy your file to this path on PC |
|-------|----------------------------------|
| **Gemma (LiteRT-LM)** | `mobile_app_oral_cancer/model/model.litertlm` |
| **YOLO (TFLite int8)** | `mobile_app_oral_cancer/model/yolo11n_lesion_best_640_int8.tflite` |

**Example — if your Gemma export is named differently:**

```bash
cd /path/to/oral-gemma-sachiv/mobile_app_oral_cancer

mkdir -p model

# Gemma: copy OR symlink your .litertlm file to the name the script expects
cp /path/to/your/gemma-4-E2B-it-final.litertlm model/model.litertlm

# YOLO
cp /path/to/your/yolo11n_lesion_best_640_int8.tflite model/
```

**Or point the script at your files without renaming (see §3 environment variables).**

Typical Gemma source names from this project (use whichever you built):

- `model/gemma-4-E2B-it-final.litertlm`
- `model/gemma-4-E2B-it-v2-vision.litertlm`

The phone will always receive Gemma as:

```text
files/models/gemma-4-E2B-it-final.litertlm
```

---

## 3. Push models to the phone (recommended script)

**Requirements**

- USB debugging enabled on the phone
- `adb` installed on PC
- Phone shows as `device` in `adb devices`

**One-command setup (install APK + push both models):**

```bash
cd /path/to/oral-gemma-sachiv/mobile_app_oral_cancer

# Build release APK first if needed:
# flutter build apk --release

chmod +x scripts/push_model_to_phone.sh

# Installs debug APK by default; for release-only push, set INSTALL_APK=0
INSTALL_APK=0 APK_PATH=build/app/outputs/flutter-apk/app-release.apk \
  ./scripts/push_model_to_phone.sh
```

**Push models only (APK already installed):**

```bash
cd /path/to/oral-gemma-sachiv/mobile_app_oral_cancer
INSTALL_APK=0 ./scripts/push_model_to_phone.sh
```

**Custom local paths (copy/paste and edit):**

```bash
cd /path/to/oral-gemma-sachiv/mobile_app_oral_cancer

export LOCAL_GEMMA="/full/path/to/your/gemma-4-E2B-it-final.litertlm"
export LOCAL_YOLO="/full/path/to/your/yolo11n_lesion_best_640_int8.tflite"
export INSTALL_APK=0

./scripts/push_model_to_phone.sh
```

**Success line:**

```text
Model directory ready inside app storage: /data/user/0/com.example.oral_cancer/files/models
```

---

## 4. Where models live on the phone (copy/paste reference)

After the script runs, files are in **app-private storage** (not visible in a normal file manager without root):

| File on device | Full path (reference) |
|----------------|------------------------|
| Gemma | `/data/user/0/com.example.oral_cancer/files/models/gemma-4-E2B-it-final.litertlm` |
| YOLO | `/data/user/0/com.example.oral_cancer/files/models/yolo11n_lesion_best_640_int8.tflite` |

**Legacy / visible path (older installs; script may copy from here):**

```text
/sdcard/Android/data/com.example.oral_cancer/files/models/
```

The app resolves models in this order: app `files/models/` → external app storage → legacy `/sdcard/...` path.

---

## 5. Manual copy via adb (without the script)

Use this if you prefer explicit `adb` steps or the script fails.

```bash
PACKAGE=com.example.oral_cancer
TMP=/data/local/tmp/oral_cancer_models

# 1) Push to temporary folder on phone
adb shell mkdir -p "$TMP"
adb push model/model.litertlm "$TMP/gemma-4-E2B-it-final.litertlm"
adb push model/yolo11n_lesion_best_640_int8.tflite "$TMP/yolo11n_lesion_best_640_int8.tflite"

# 2) Copy into app-private storage (app must be installed once)
adb shell "run-as $PACKAGE mkdir -p files/models"
adb shell "run-as $PACKAGE cp $TMP/gemma-4-E2B-it-final.litertlm files/models/gemma-4-E2B-it-final.litertlm"
adb shell "run-as $PACKAGE cp $TMP/yolo11n_lesion_best_640_int8.tflite files/models/yolo11n_lesion_best_640_int8.tflite"

# 3) Cleanup temp
adb shell rm -f "$TMP/gemma-4-E2B-it-final.litertlm" "$TMP/yolo11n_lesion_best_640_int8.tflite"
```

Verify sizes:

```bash
adb shell "run-as $PACKAGE ls -l files/models/"
```

---

## 6. Verify in the app

1. Open the app → complete intake → **record or upload video** → **Analyze**.
2. You should see **YOLO frame review** (boxes per frame), then **Run Gemma analysis**.
3. If you see `MODEL_NOT_FOUND` or missing model errors, re-run §3 or §5.

**Pull debug captures to PC (optional, debug builds only):**

```bash
./scripts/pull_debug_captures.sh
# Saves under: mobile_app_oral_cancer/debug_captures/
```

---

## 7. Firebase (optional)

- **Spark (free):** Auth, Firestore rules, local screening — sync may skip Cloud Storage (HTTP 402).
- **Blaze:** Cloud Functions, Storage for ROI images — requires active billing.

Configure `google-services.json` before building if you use your own Firebase project.

---

## 8. Build this release yourself

```bash
cd mobile_app_oral_cancer
flutter pub get
flutter build apk --release
```

**Output APK path on PC:**

```text
mobile_app_oral_cancer/build/app/outputs/flutter-apk/app-release.apk
```

---

## 9. Publish this release on GitHub

```bash
cd /path/to/oral-gemma-sachiv
git tag v1.0.0
git push origin v1.0.0

gh release create v1.0.0 \
  mobile_app_oral_cancer/build/app/outputs/flutter-apk/app-release.apk \
  --title "Oral Gemma Sachiv v1.0.0" \
  --notes-file mobile_app_oral_cancer/RELEASE_NOTES.md
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `adb: no devices` | Enable USB debugging; accept RSA prompt; `adb devices` |
| `Missing local Gemma model` | Copy file to `model/model.litertlm` or set `LOCAL_GEMMA=...` |
| `MODEL_NOT_FOUND` in app | Re-run `push_model_to_phone.sh`; confirm `run-as` works (app installed) |
| Speech / Gemma very slow | Expected on-device; first Gemma load is slowest |
| NGO / doctor home empty | Complete consent → doctor package → research export → ASHA **Sync now** |

---

## License / models

Gemma and YOLO weights are subject to their original licenses and your export terms. Do not commit multi-GB model files to public git; distribute via release assets, Drive, or internal storage.
