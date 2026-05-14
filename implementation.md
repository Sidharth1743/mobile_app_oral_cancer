# Implementation Status

This document tracks what has been implemented in the Flutter MVP so far and what is still left to build.

## Current Rule Set

- The core offline AI workflow is the center of the project:
  `video -> frames/images -> Gemma 4 LiteRT -> segmentation -> screening result`.
- The AI/segmentation pipeline must be real. No mock Gemma result or fallback result should be added without explicit permission.
- Patient identity stays on the device by default.
- Identity can be shared to doctor, ASHA, or cloud only after:
  1. The offline Gemma result is completed.
  2. The patient gives explicit consent.
- The offline local model may receive patient identity because it runs on-device.
- There is no audio, no TTS, no voice note, and no doctor audio workflow in this project.
- `architecture.svg` still contains voice-note/spoken-care-plan labels, but those are intentionally excluded by the latest project rule above.
- Connectivity and sync must not appear before the offline result is ready.
- Connectivity checks happen only after result plus consent:
  - automatically every 90 seconds
  - manually when the user taps a connect/check button
- Doctor packages should include patient personal information after doctor-share consent.
- ASHA workers can see patient personal information.
- NGO/CSR dashboard must be aggregate-only and must not expose patient identity.
- Research export must be consent-gated and de-identified.

## Implemented Modules

### 1. Flutter Android App Foundation

Implemented:

- Flutter project scaffolded at repo root as `oral_cancer`.
- Android build configuration exists.
- Android-first app flow exists in [lib/main.dart](lib/main.dart).
- LiteRT model path defaults to:
  `/sdcard/Android/data/com.example.oral_cancer/files/models/gemma-4-E2B-it.litertlm`
- Local model push script exists at [scripts/push_model_to_phone.sh](scripts/push_model_to_phone.sh).

Test coverage:

- App smoke test checks the intake screen workflow fields.

### 2. PII Vault And De-identification

Implemented:

- Patient identity model:
  - name
  - village
  - date of birth
  - phone
  - PIN code
- Identity is encrypted locally using the ASHA PIN.
- Clinical record is de-identified before SQLite storage.
- Patient hash is generated from normalized identity.
- Exact age is converted into an age band.
- PIN code is reduced to prefix only.
- Village is converted into a village code.
- CEI calculation exists for tobacco exposure.

Files:

- [lib/core/pii_vault.dart](lib/core/pii_vault.dart)
- [lib/core/deidentification.dart](lib/core/deidentification.dart)
- [lib/data/models.dart](lib/data/models.dart)

Test coverage:

- PII encryption/decryption round trip.
- Wrong PIN failure.
- Stored vault values do not contain plaintext PII.
- PIN policy.
- Patient hash normalization.
- Age-band and PIN-prefix de-identification.
- CEI brand weights and clamp behavior.

### 3. Local SQLite Storage

Implemented:

- SQLite database wrapper.
- Tables for:
  - clinical records
  - captured frames
  - visits
  - consents
  - sync queue
- CRUD helpers for clinical records, captured frames, visits, consents, and queued sync payloads.

Files:

- [lib/data/local_database.dart](lib/data/local_database.dart)

Test coverage:

- Database create/open.
- Clinical record save/read.
- Captured frame save/read.
- Visit save/read.
- Consent save/read.
- Sync queue enqueue/read.

### 4. Real Video Capture And Frame Pipeline

Implemented:

- Six-site oral capture structure.
- Camera-based video capture screen.
- FFmpeg-based frame extraction from video.
- Frame scoring and selection using the Dart `image` package.
- Raw video deletion path exists after extraction.

Files:

- [lib/capture/oral_sites.dart](lib/capture/oral_sites.dart)
- [lib/capture/frame_extractor.dart](lib/capture/frame_extractor.dart)
- [lib/capture/frame_selector.dart](lib/capture/frame_selector.dart)

Test coverage:

- Frame selector score ordering.
- Empty/undecodable frame rejection.

Still needs real-device verification:

- Record video on Android phone.
- Extract frames.
- Confirm raw video deletion.
- Confirm selected images are stored under app-private internal storage.

### 5. LiteRT Gemma Service Boundary

Implemented:

- Dart service interface for Gemma inference.
- Android Kotlin method channel for LiteRT-LM inference.
- Local model path passed from Flutter into Android.
- Image paths and prompt are sent into the LiteRT engine.
- Generated text is returned back to Flutter.

Files:

- [lib/inference/gemma_service.dart](lib/inference/gemma_service.dart)
- [lib/inference/litert_gemma_service.dart](lib/inference/litert_gemma_service.dart)
- [android/app/src/main/kotlin/com/example/oral_cancer/MainActivity.kt](android/app/src/main/kotlin/com/example/oral_cancer/MainActivity.kt)

Important:

- This is not a mock path.
- If the model is missing or inference fails, it should surface as an error.
- No fallback result should be added without permission.

Still needs:

- Real phone run with the pushed `.litertlm` model.
- Confirm LiteRT logs show model load and inference.
- Confirm model output JSON parses correctly.

### 5B. PC Fine-tuned LoRA Backend

Implemented:

- FastAPI backend for local PC testing.
- Clean local web UI for model status, image upload, strict JSON result, and file checks.
- Backend core module:
  - [backend/core.py](backend/core.py)
- Runtime module:
  - [backend/runtime.py](backend/runtime.py)
- FastAPI app:
  - [backend/main.py](backend/main.py)
- UI files:
  - [backend/ui/index.html](backend/ui/index.html)
  - [backend/ui/styles.css](backend/ui/styles.css)
  - [backend/ui/app.js](backend/ui/app.js)
- PC guide:
  - [PC_BACKEND.md](PC_BACKEND.md)

Important:

- This backend uses the real LoRA adapter and base model.
- It does not create mock model outputs.
- If CUDA/model dependencies are missing, inference fails clearly.

Test coverage:

- strict JSON parsing
- invalid category rejection
- missing field rejection
- upload validation
- model file inspection
- CleanUI banned-pattern checks
- loading/content/empty UI state checks

### 6. Screening Pipeline Contract

Implemented:

- A real interface contract for Sachiv's core AI pipeline integration.
- `ScreeningInput` includes:
  - visit ID
  - identity
  - de-identified clinical record
  - video paths by oral site
  - previous EHR visits
- `ScreeningResult` includes:
  - patient hash
  - risk level
  - site results
  - segmentation artifacts
  - differentials
  - uncertainty
  - patient summary
  - ASHA summary
  - doctor summary
  - recommended action
  - model name
- `SegmentationArtifact` includes:
  - site ID
  - ROI image path
  - mask path
  - lesion size in mm

Files:

- [lib/pipeline/screening_pipeline.dart](lib/pipeline/screening_pipeline.dart)

Test coverage:

- Screening input JSON round trip.
- Identity is preserved for local offline model context.
- Video paths are preserved.
- Screening result carries Gemma and segmentation result fields.

### 7. EHR Visit History And Delta Checking

Implemented:

- EHR visit model.
- EHR site measurement model.
- Delta calculator comparing current screening result with previous visits.
- Detects:
  - lesion size change
  - concern increase
  - repeated high-risk site
- Ten EHR JSON output fixtures were added for test coverage.

Files:

- [lib/ehr/ehr_models.dart](lib/ehr/ehr_models.dart)
- [test/fixtures/ehr/](test/fixtures/ehr/)

Test coverage:

- Loads 10 EHR JSON files.
- Confirms lesion grew 4 mm compared with the latest previous visit.
- Confirms repeated high-risk site detection.

### 8. Consent Model

Implemented:

- Consent scopes:
  - doctor share
  - ASHA share
  - cloud backup
  - research export
- Consent record stores:
  - visit ID
  - patient hash
  - scopes
  - recorded time
  - policy version
  - screening completed time
- Consent is rejected if it is recorded before the offline screening result.

Files:

- [lib/consent/consent.dart](lib/consent/consent.dart)
- [lib/ui/screens/consent_screen.dart](lib/ui/screens/consent_screen.dart)
- [lib/sync/post_result_share_queue.dart](lib/sync/post_result_share_queue.dart)

Test coverage:

- No online sharing by default.
- Reject consent before result.
- Serialize/deserialize consent scopes.
- Consent UI saves selected scopes after a result.
- Selected post-result share scopes are queued locally.
- Mismatched consent/result pairs are rejected.

### 9. Doctor Package Sharing

Implemented:

- Existing anonymized local doctor package builder remains.
- New identified doctor package builder was added.
- Identified doctor package requires doctor-share consent.
- Identified doctor package includes:
  - patient full name
  - date of birth
  - phone
  - village
  - PIN code
  - clinical record
  - screening result
  - doctor brief
  - image references
  - consent record
- Package is rejected when doctor-share consent is missing.
- Identified assessment package queue requires an assigned doctor UID.
- Doctor package UI unlocks identity from the on-device PII vault using ASHA PIN.

Files:

- [lib/output/doctor_package.dart](lib/output/doctor_package.dart)
- [lib/ui/screens/doctor_package_screen.dart](lib/ui/screens/doctor_package_screen.dart)

Test coverage:

- Anonymized package still excludes PII.
- Identified package includes PII after consent.
- Identified package rejects missing consent.
- Identified assessment package queues after consent and assigned doctor.
- Missing assigned doctor is rejected.

### 10. Connectivity Policy

Implemented:

- Connectivity check policy.
- No connectivity check before screening result.
- No connectivity check without consent.
- Automatic check interval is 90 seconds.
- Manual check is allowed after result plus consent.

Files:

- [lib/sync/connectivity_policy.dart](lib/sync/connectivity_policy.dart)
- [lib/ui/screens/sync_queue_screen.dart](lib/ui/screens/sync_queue_screen.dart)
- [lib/sync/sync_worker.dart](lib/sync/sync_worker.dart)
- [lib/cloud/assessment_cloud_sync_service.dart](lib/cloud/assessment_cloud_sync_service.dart)
- [lib/cloud/research_cloud_sync_service.dart](lib/cloud/research_cloud_sync_service.dart)

Test coverage:

- Before result: no check.
- Result without consent: no check.
- 89 seconds: no automatic check.
- 90 seconds: automatic check allowed.
- Manual check after consent: allowed.
- Sync queue UI empty/content states.
- Sync worker marks success as synced.
- Sync worker marks failures with retryable error state.
- Sync queue records attempt count, updated timestamp, and last error.

### 11. Role Login And Permissions

Implemented:

- Role model:
  - ASHA
  - doctor
  - NGO/CSR
  - research
  - admin
- Local username/mobile style login model.
- Salted password hashing.
- Role permission boundaries:
  - ASHA and doctor can see patient identity.
  - NGO/CSR can see aggregate dashboard only.
  - Research role can export research dataset.

Files:

- [lib/auth/role_auth.dart](lib/auth/role_auth.dart)
- [lib/cloud/role_home_repository.dart](lib/cloud/role_home_repository.dart)
- [lib/ui/screens/role_login_screen.dart](lib/ui/screens/role_login_screen.dart)
- [lib/ui/screens/role_home_screen.dart](lib/ui/screens/role_home_screen.dart)
- [lib/ui/screens/operations_screen.dart](lib/ui/screens/operations_screen.dart)

Test coverage:

- Login success.
- Login failure.
- Password hash does not contain plaintext password.
- Role visibility boundaries.
- Role login UI calls the Firebase sign-in boundary and renders the returned role profile.
- Doctor home reads assigned Firestore cases.
- ASHA home reads ASHA-created Firestore cases.
- Research home reads Firestore research export summaries.

### 12. NGO/CSR Dashboard Data

Implemented:

- Aggregate dashboard metrics:
  - total screenings
  - high-risk count
  - urgent count
  - average uncertainty
  - count by village code
- No patient identity fields are included.

Files:

- [lib/dashboard/dashboard_models.dart](lib/dashboard/dashboard_models.dart)
- [lib/ui/screens/ngo_dashboard_screen.dart](lib/ui/screens/ngo_dashboard_screen.dart)

Test coverage:

- Aggregate counts.
- Average uncertainty.
- Village-code grouping.
- Output does not contain name or phone.
- Dashboard UI renders aggregate metrics and no direct identity.

### 13. Research Dataset Export

Implemented:

- Consent-gated research export.
- Uses HMAC-SHA256 study pseudonymization.
- Different study secrets produce different pseudonyms.
- Export excludes direct PII.
- Export includes:
  - study patient ID
  - visit ID
  - age band
  - PIN prefix
  - village code
  - gender
  - CEI
  - risk level
  - uncertainty
  - recommended action
  - model name
  - limited site result fields
  - lesion size measurements

Files:

- [lib/research/research_export.dart](lib/research/research_export.dart)
- [lib/research/research_export_file.dart](lib/research/research_export_file.dart)
- [lib/ui/screens/research_export_screen.dart](lib/ui/screens/research_export_screen.dart)

Test coverage:

- Export allowed only with research consent.
- Direct identity excluded.
- Pseudonym length and stability.
- Different secrets produce different pseudonyms.
- Current-assessment export excludes direct identity.
- Export JSON file is written to local app storage.

### 14. Audio Removed

Implemented:

- Removed TTS import and speak button from the UI.
- Removed audio dependencies from `pubspec.yaml`.

Removed packages:

- `flutter_tts`
- `audioplayers`

Verification:

- Search found no remaining audio/TTS references in `lib/`, `test/`, or `pubspec.yaml`.

### 15. Cloud Functions And Secret Manager

Implemented:

- Firebase Functions source configured at [functions](functions).
- Callable `submitDoctorPackage` validates doctor-share consent and writes:
  - case metadata
  - private patient identity
  - consent
  - assessment
  - doctor package metadata
  - audit event
- Callable `submitResearchExport` validates research consent and uses Secret Manager secret:
  `research-pseudonym-secret`
- Server-side validation rejects direct identity in public assessment/research payloads.

Files:

- [functions/index.mjs](functions/index.mjs)
- [functions/src/validation.mjs](functions/src/validation.mjs)
- [functions/package.json](functions/package.json)

Test coverage:

- Doctor package consent validation.
- Public payload direct-identity rejection.
- Research consent validation.
- Secret-based HMAC stability/change behavior.

### 16. Local Translation

Implemented:

- Local Gemma translation service.
- Strict JSON response contract.
- Patient result screen can open local translation screen.
- Translation screen runs through LiteRT model path; no cloud translation and no fallback.

Files:

- [lib/translation/local_translation_service.dart](lib/translation/local_translation_service.dart)
- [lib/ui/screens/local_translation_screen.dart](lib/ui/screens/local_translation_screen.dart)

Test coverage:

- Translation JSON parses into typed result.
- Empty text is rejected before model call.

### 17. Treatment Completion Loop

Implemented:

- Treatment timeline model.
- Local SQLite treatment timeline storage.
- Treatment tracking screen.
- Firestore rules allow assigned ASHA/doctor/admin treatment event access.

Files:

- [lib/treatment/treatment_tracking.dart](lib/treatment/treatment_tracking.dart)
- [lib/ui/screens/treatment_tracking_screen.dart](lib/ui/screens/treatment_tracking_screen.dart)

Test coverage:

- Timeline reaches completed after ordered events.
- Immediate completion after referral is rejected.
- Treatment timeline saves/loads locally.
- Firebase rules allow assigned doctor treatment event creation.

## Verification Completed

Completed successfully:

```bash
dart format lib test
flutter pub get
flutter analyze
flutter test
python3 -m py_compile backend/core.py backend/runtime.py backend/main.py
./scripts/run_pc_backend_tests.sh
npm run test:functions
JAVA_HOME=/home/sidharth/Downloads/android-studio/jbr PATH=/home/sidharth/Downloads/android-studio/jbr/bin:$PATH npm run test:rules
flutter build apk --debug
```

Results:

- `flutter analyze`: no issues found.
- `flutter test`: all tests passed.
- backend unit tests: 7 passed.
- Cloud Functions validation tests: passed.
- Firebase emulator rule tests: 7 passed.
- Android debug APK built at `build/app/outputs/flutter-apk/app-debug.apk`.

## What Is Left To Build

### A. Finish Real Offline AI Pipeline Integration

Owner can be Sachiv or this project, but the contract is ready.

Still needed:

- Connect real `video -> frame extraction -> selected frames -> LiteRT Gemma -> segmentation -> ScreeningResult`.
- Ensure segmentation output produces:
  - ROI image
  - mask image
  - lesion size in mm
  - site ID
- Ensure Gemma output produces strict JSON matching `ScreeningResult`.
- Add parser tests using real saved model output samples.
- Add real-device integration test flow.

### B. Real Android Phone Testing

Still needed:

- Install debug APK on phone.
- Push model into app-specific internal shared storage path:
  `/sdcard/Android/data/com.example.oral_cancer/files/models/`
- Record all six oral-site videos.
- Run analyze.
- Capture logs for:
  - camera recording
  - FFmpeg extraction
  - LiteRT model load
  - LiteRT inference
  - JSON parsing
  - result save

### C. Live Cloud Sync Worker

Implemented:

- Local sync worker processes pending queued upload payloads.
- Queue tracks:
  - queued
  - uploading
  - synced
  - failed
- Queue tracks attempt count and last error.
- Complete identified doctor package payloads can upload through Firebase sync service.
- Research export payloads route through Cloud Functions.

Still needed:

- Wire periodic/background execution into the Android app lifecycle.
- Add retry/backoff timing around failed uploads.
- Add end-to-end emulator test for actual queued upload success/failure with Firebase SDK instances.

### D. Full Role Homes

Implemented:

- Doctor home reads assigned Firestore cases.
- ASHA home reads ASHA-created Firestore cases.
- Research home reads Firestore export summaries.
- Role login can open the role-specific home.

Still needed:

- Add detailed case pages for doctor and ASHA.
- Add live local pending queue summary in ASHA home.
- Add role-specific automatic navigation immediately after login.

### F. Google Cloud Sync Implementation

Currently only local queue/policy exists.

Firebase Android setup is now configured locally:

- Project ID: `oral-cancer-e8a6e`
- Android package: `com.example.oral_cancer`
- Generated options: [lib/firebase_options.dart](lib/firebase_options.dart)
- Local `android/app/google-services.json` is present and ignored from git.
- Firebase initialization wrapper: [lib/cloud/firebase_bootstrap.dart](lib/cloud/firebase_bootstrap.dart)
- Real Firebase role auth/profile service:
  - [lib/cloud/firebase_role_auth.dart](lib/cloud/firebase_role_auth.dart)
- Cloud payload/path planning code:
  - [lib/cloud/cloud_paths.dart](lib/cloud/cloud_paths.dart)
  - [lib/cloud/cloud_payloads.dart](lib/cloud/cloud_payloads.dart)
  - [lib/cloud/cloud_sync_planner.dart](lib/cloud/cloud_sync_planner.dart)
- Real consent-gated doctor package cloud service:
  - [lib/cloud/doctor_cloud_sync_service.dart](lib/cloud/doctor_cloud_sync_service.dart)
- Cloud schema validator:
  - [lib/cloud/cloud_schema_validator.dart](lib/cloud/cloud_schema_validator.dart)
- Sync state machine:
  - [lib/sync/sync_status.dart](lib/sync/sync_status.dart)
- Firebase Security Rules:
  - [firestore.rules](firestore.rules)
  - [storage.rules](storage.rules)

Implemented cloud behavior:

- Email/password Firebase login service.
- Firestore role profile loading from `users/{uid}`.
- Disabled profiles are rejected.
- Doctor package upload requires ASHA/admin role.
- Doctor package upload requires `doctorShare` consent.
- Doctor package upload requires an assigned doctor UID.
- ROI and segmentation mask files are uploaded to Cloud Storage.
- Raw videos, local DB files, and model files are rejected by upload path validation.
- Firestore documents are written for:
  - case metadata
  - private patient identity
  - consent record
  - screening result
  - doctor package metadata
  - storage object metadata
  - audit event
- Firestore rules restrict:
  - patient identity to assigned ASHA, assigned doctor, and admin
  - NGO/CSR to aggregate dashboard documents
  - research role to research export metadata
  - public case documents from carrying direct identity keys
- Storage rules restrict:
  - ROI uploads to JPEG
  - mask uploads to PNG
  - file size under 10 MB
  - no broad raw-video upload path
- Sync state now enforces valid transitions:
  - queued -> uploading -> synced
  - uploading -> failed -> uploading retry

Still needed:

- Build role login UI screens.
- Deploy and emulator-test Firestore security rules.
- Deploy and emulator-test Storage security rules.
- Decide whether to move doctor package write behind Cloud Functions for backend-side consent validation.
- Retry queued items.
- Mark sync status:
  - queued
  - uploading
  - synced
  - failed
- Add tests for upload success/failure/retry.

### G. Cloud Consent Storage

Still needed:

- Send consent record with shared package.
- Make cloud reject uploads without matching consent.
- Add server-side consent audit trail.

### H. Live NGO/CSR Dashboard Data

Aggregate dashboard UI and model tests are implemented.

Still needed:

- Load aggregate dashboard documents from Firestore.
- Add date/district filters when live aggregate data exists.
- Keep Firebase rules enforcing aggregate-only access.

### I. Research Export Upload

Implemented:

- Research export UI and local JSON file generation.
- Research exports queue with consent and patient hash.
- Cloud Function validates research consent and uses Secret Manager pseudonym secret.

Still needed:

- Create the real `research-pseudonym-secret` in Google Secret Manager.
- Deploy functions and grant Secret Manager access to the Cloud Functions service account.
- Add CSV export if required by the final dataset repo.

### J. Translation

Implemented:

- Local Gemma translation service and screen.
- No cloud translation.
- Patient-facing summaries can be translated after result using the LiteRT model path.

Still needed:

- Run on phone with the actual `.litertlm` model.
- Add tests with real saved translation outputs from the final model.

### K. App UI

Implemented:

- Material 3 app shell with screening, operations, and queue tabs.
- Shared app theme and small reusable UI components.
- Result screen routes to consent before sharing.
- Consent screen.
- Role login screen.
- ASHA summary and progress screen.
- Doctor package queue screen.
- Sync queue screen.
- NGO/CSR aggregate dashboard screen.
- Research export screen.

Still needed:

- Real-device visual pass after Android install.
- Doctor/ASHA/research role homes backed by live Firestore data.
- Final copy/localization pass for patient-facing strings.

### M. Tamil Nadu Intake

Implemented:

- Tamil Nadu district data is bundled as a local app asset.
- The app can load all 38 Tamil Nadu districts offline.
- Intake now has:
  - state dropdown
  - district dropdown
  - date-of-birth picker instead of typed DOB text
- Identity record now stores state and district.

Files:

- [assets/locations/india_states_districts.json](assets/locations/india_states_districts.json)
- [lib/location/indian_locations.dart](lib/location/indian_locations.dart)
- [lib/intake/date_of_birth.dart](lib/intake/date_of_birth.dart)

Test coverage:

- Tamil Nadu district asset loads 38 districts.
- Unknown/non-selected state returns no districts.
- DOB picker stores a valid selected date.
- Future DOB is rejected.

### L. Full Build Verification

Still needed:

```bash
flutter build apk --debug
```

Then:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
flutter run -d <device-id>
adb logcat | grep -E "OralCancerLiteRT|flutter|ffmpeg"
```

## Current Test Areas

The current test suite covers:

- app smoke
- frame selection
- de-identification
- PII vault
- SQLite database
- data model parsing
- demo fixture parsing
- Gemma service parsing
- lesion analyzer path
- prompt builders
- doctor package
- screening pipeline contract
- EHR delta calculation
- consent rules
- consent UI and post-result share queue
- role login and permissions
- role login UI
- Firestore-backed ASHA/doctor/research role homes
- connectivity timing
- sync queue UI
- live local sync worker
- NGO/CSR aggregate dashboard data
- NGO/CSR aggregate dashboard UI
- research export
- research export file writing
- Cloud Functions validation and Secret Manager HMAC behavior
- local Gemma translation contract
- treatment completion loop
- identified assessment doctor package queue
- CleanUI UI pattern checks

## Next Recommended Step

Run the full Android phone workflow with the local `.litertlm` model:

1. Install the debug APK.
2. Confirm six video captures save under app-private internal storage.
3. Confirm FFmpeg extracts selected frames and deletes raw video.
4. Confirm LiteRT Gemma returns strict JSON.
5. Confirm result -> consent -> doctor package queue -> sync queue works on device.

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

.venv/bin/litert-lm run model/gemma-4-E2B-it.litertlm \
 --attachment assets/demo/frames/left_buccal.png \
 --prompt "Describe the oral image in one short sentence." \
 --backend cpu \
 --vision-backend cpu \
 --enable-speculative-decoding false \
 --max-num-tokens 96 \
 --temperature 0 \
 --verbose

MODEL_DIR=oral_gemma_finetune_package/outputs/no-vision-lora-15ep \
 MERGED_DIR=oral_gemma_finetune_package/outputs/no-vision-lora-15ep-merged \
 TFLITE_OUT_DIR=oral_gemma_finetune_package/outputs/no-vision-lora-15ep-litert-rerun-$(date +%Y%m%d-%H%M%S) \
  CAPTURE_MODEL_PATH=model/gemma-4-E2B-it-no-vision-$(date +%Y%m%d-%H%M%S).litertlm \
 PYTHON_BIN=.venv/bin/python \
 EXPORT_VISION_ENCODER=1 \
 VISION_QUANTIZE=none \
 PREFILL_SEQ_LEN=64 \
 KV_CACHE_MAX_LEN=256 \
 EXPORT_THREADS=1 \
 LIGHTWEIGHT_CONVERSION=1 \
 SINGLE_TOKEN_EMBEDDER=1 \
 ./scripts/convert_unsloth_lora_to_litert.sh > convert-no-vision-rerun.log 2>&1

watch -n 2 'free -h; echo; tail -n 20 convert.log'
