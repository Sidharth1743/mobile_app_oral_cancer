# Google Cloud And Firebase Plan

This document explains what must be created in Google Cloud/Firebase, how it should connect to the Flutter app, and which tests are still missing.

## Goal

The app stays offline-first.

Cloud is used only after:

1. The offline Gemma LiteRT screening result is complete.
2. The patient gives explicit consent.
3. The logged-in role is allowed to perform that action.

There must be no cloud upload, sync button, doctor package upload, ASHA upload, or research export before the local result and consent exist.

## Recommended Google Cloud Stack

Use Firebase because it is the fastest Google Cloud path for Flutter and hackathon demos.

### Firebase Authentication

Use for app login.

Roles:

- ASHA
- Doctor
- NGO/CSR
- Research
- Admin

Recommended login methods:

- ASHA: mobile number + password, or phone OTP later
- Doctor: email + password
- NGO/CSR: email + password
- Research: email + password
- Admin: email + password

For MVP, email/password is easiest to test. Mobile login can be added after the flow is stable.

### Cloud Firestore

Use for structured records:

- users
- roles
- consent records
- case metadata
- screening result summaries
- doctor package metadata
- ASHA package metadata
- research export metadata
- sync status
- audit events

Firestore supports offline persistence on Android, but our app should still keep its own SQLite queue because the project rule is explicit: upload only after result plus consent.

### Cloud Storage For Firebase

Use for files:

- ROI images
- segmentation masks
- selected frames only if required
- research export files

Do not upload raw video.

Recommended upload rule:

- Upload ROI images and masks only.
- Keep raw video local only, then delete after extraction.

### Cloud Functions For Firebase

Use for backend checks:

- Validate consent before package acceptance.
- Validate user role.
- Create doctor-readable package metadata.
- Generate research export.
- Write audit logs.
- Reject uploads that contain missing consent or wrong role.

### Firebase App Check

Use later, after the main flow works.

Purpose:

- Reduce fake app/API calls.
- Protect Firestore, Storage, and Functions.

### Cloud Logging

Use for:

- consent validation logs
- upload failure logs
- research export logs
- doctor package processing logs

### Secret Manager

Use for:

- research pseudonymization secret
- backend-only signing secrets

Do not put research HMAC secret in Flutter app for production.

## Region

Recommended region:

```text
asia-south1
```

Reason:

- Mumbai region.
- Low latency for Tamil Nadu users.
- Suitable for India-focused deployment.

Important:

- Firestore location cannot be changed after creation.
- Choose the region carefully before adding production data.

## Firebase Project Setup Steps

Current local setup:

```text
Firebase project ID: oral-cancer-e8a6e
Android app ID: 1:738123884911:android:63fdb1f48a31497d14a09a
Android package: com.example.oral_cancer
Storage bucket: oral-cancer-e8a6e.firebasestorage.app
Configured platform: android
```

Generated/configured files:

- [lib/firebase_options.dart](lib/firebase_options.dart)
- `android/app/google-services.json`

Security note:

- `android/app/google-services.json` is ignored in `.gitignore` so it is available locally but should not be published accidentally.
- `firebase_options.dart` contains Firebase app identifiers. These are not passwords, but production security must still be enforced by Firebase Auth, Security Rules, Cloud Functions, and App Check.

### 1. Create Firebase Project

Go to:

```text
https://console.firebase.google.com/
```

Create project:

```text
oral-cancer-screening
```

The exact project name can be different, but keep it simple.

### 2. Choose Billing

Upgrade to Blaze plan if Cloud Storage is required.

Reason:

- New Firebase Storage projects require Blaze for uploads.
- Google Cloud credits can cover this.

Set budget alerts immediately in Google Cloud Billing.

Recommended budget alerts:

- 25%
- 50%
- 75%
- 90%
- 100%

### 3. Add Android App

Android package name:

```text
com.example.oral_cancer
```

Download:

```text
google-services.json
```

Place it at:

```text
android/app/google-services.json
```

Do not commit real production secrets later if this repo becomes public.

### 4. Install Firebase CLI

Run:

```bash
npm install -g firebase-tools
firebase login
```

### 5. Install FlutterFire CLI

Run:

```bash
dart pub global activate flutterfire_cli
```

### 6. Configure FlutterFire

From repo root:

```bash
flutterfire configure
```

Expected result:

- `lib/firebase_options.dart` is generated.
- Android Firebase config is connected.

### 7. Add Flutter Firebase Packages

Already added locally:

```bash
flutter pub add firebase_core
flutter pub add firebase_auth
flutter pub add cloud_firestore
flutter pub add firebase_storage
flutter pub add cloud_functions
flutter pub add firebase_app_check
flutter pub add firebase_crashlytics
```

Current code initializes Firebase through [lib/cloud/firebase_bootstrap.dart](lib/cloud/firebase_bootstrap.dart).

Current implemented cloud code:

- [lib/cloud/firebase_role_auth.dart](lib/cloud/firebase_role_auth.dart)
  - email/password Firebase login
  - role profile loading from `users/{uid}`
  - disabled user rejection
- [lib/cloud/doctor_cloud_sync_service.dart](lib/cloud/doctor_cloud_sync_service.dart)
  - consent-gated doctor package upload
  - ASHA/admin upload guard
  - assigned-doctor requirement
  - ROI/mask upload to Firebase Storage
  - Firestore writes for case, private identity, consent, screening, doctor package, storage object metadata, and audit event
- [lib/cloud/cloud_paths.dart](lib/cloud/cloud_paths.dart)
  - Firestore path and Storage path generation
  - raw video/model/local DB path rejection
- [lib/cloud/cloud_payloads.dart](lib/cloud/cloud_payloads.dart)
  - case metadata payloads without direct patient identity
  - isolated private patient identity payload
- [lib/cloud/cloud_sync_planner.dart](lib/cloud/cloud_sync_planner.dart)
  - ROI/mask upload planning after `doctorShare` consent
- [lib/cloud/cloud_schema_validator.dart](lib/cloud/cloud_schema_validator.dart)
  - local schema checks for direct identity leakage, consent timing, storage object metadata, and user profile shape
- [lib/sync/sync_status.dart](lib/sync/sync_status.dart)
  - local sync status state machine
- [firestore.rules](firestore.rules)
  - role-scoped Firestore access rules
- [storage.rules](storage.rules)
  - image-only Cloud Storage access rules for ROI/mask/frame paths

## Firestore Collections

### users

Path:

```text
users/{uid}
```

Fields:

```json
{
  "uid": "firebase-auth-uid",
  "displayName": "Dr. Name",
  "mobile": "+91...",
  "email": "doctor@example.com",
  "role": "doctor",
  "district": "Madurai",
  "state": "Tamil Nadu",
  "active": true,
  "createdAt": "server timestamp",
  "updatedAt": "server timestamp"
}
```

Rules:

- User can read own profile.
- Admin can read/write all profiles.
- Role changes should be admin-only.

### cases

Path:

```text
cases/{caseId}
```

Fields:

```json
{
  "caseId": "case-id",
  "visitId": "visit-id",
  "patientHash": "local-patient-hash",
  "state": "Tamil Nadu",
  "district": "Madurai",
  "villageCode": "hashed-village-code",
  "createdByUid": "asha-uid",
  "assignedDoctorUid": "doctor-uid",
  "riskLevel": "high",
  "recommendedAction": "see_doctor_free",
  "status": "queued",
  "createdAt": "server timestamp",
  "updatedAt": "server timestamp"
}
```

Important:

- Do not create this document before consent.
- This document can be created after doctor/cloud/ASHA consent depending on selected scopes.

### patientIdentity

Path:

```text
cases/{caseId}/private/patientIdentity
```

Fields:

```json
{
  "fullName": "Patient name",
  "dateOfBirth": "1978-02-12",
  "phone": "9999999999",
  "pinCode": "628501",
  "state": "Tamil Nadu",
  "district": "Madurai",
  "village": "Village name",
  "consentId": "consent-id",
  "createdAt": "server timestamp"
}
```

Rules:

- ASHA can read identity for cases they created or are assigned.
- Doctor can read identity only for assigned/consented cases.
- NGO/CSR cannot read.
- Research cannot read.

### consentRecords

Path:

```text
cases/{caseId}/consents/{consentId}
```

Fields:

```json
{
  "consentId": "consent-id",
  "visitId": "visit-id",
  "patientHash": "patient-hash",
  "scopes": ["doctorShare", "cloudBackup"],
  "recordedAt": "client timestamp",
  "serverRecordedAt": "server timestamp",
  "screeningCompletedAt": "client timestamp",
  "policyVersion": "2026-05",
  "ashaUid": "asha-uid"
}
```

Backend validation:

- `recordedAt` must be after `screeningCompletedAt`.
- Consent must include the scope required for the upload.
- Consent must match the same visit and patient hash.

### screeningResults

Path:

```text
cases/{caseId}/screenings/{visitId}
```

Fields:

```json
{
  "visitId": "visit-id",
  "patientHash": "patient-hash",
  "riskLevel": "high",
  "uncertainty": 0.18,
  "recommendedAction": "see_doctor_free",
  "modelName": "gemma-4-E2B-it.litertlm",
  "siteResults": [],
  "segmentation": [],
  "createdAt": "client timestamp",
  "uploadedAt": "server timestamp"
}
```

Rules:

- Created only after consent.
- ASHA and assigned doctor can read.
- NGO/CSR can read only aggregate derived data, not raw case data.
- Research can read only de-identified export, not patient identity.

### doctorPackages

Path:

```text
cases/{caseId}/doctorPackages/{packageId}
```

Fields:

```json
{
  "packageId": "doctor-visit-id",
  "visitId": "visit-id",
  "doctorUid": "doctor-uid",
  "ashaUid": "asha-uid",
  "status": "queued",
  "doctorBrief": "doctor brief",
  "imageRefs": [],
  "consentId": "consent-id",
  "createdAt": "server timestamp"
}
```

Rules:

- Requires `doctorShare` consent.
- Doctor package can include patient identity because the doctor must identify the patient.
- Access must be limited to assigned doctor, assigned ASHA, and admin.

### storageObjects

Path:

```text
cases/{caseId}/storageObjects/{objectId}
```

Fields:

```json
{
  "objectId": "object-id",
  "kind": "roiImage",
  "siteId": "left_buccal",
  "storagePath": "cases/case-id/visit-id/roi/left_buccal.jpg",
  "contentType": "image/jpeg",
  "sizeBytes": 123456,
  "createdAt": "server timestamp"
}
```

Allowed kinds:

- `roiImage`
- `segmentationMask`
- `selectedFrame`
- `researchExport`

Do not allow:

- `rawVideo`
- executable files
- APK uploads

### researchExports

Path:

```text
researchExports/{exportId}
```

Fields:

```json
{
  "exportId": "export-id",
  "createdByUid": "research-uid",
  "district": "Madurai",
  "dateRangeStart": "2026-05-01",
  "dateRangeEnd": "2026-05-31",
  "storagePath": "research/exports/export-id.json",
  "caseCount": 100,
  "status": "ready",
  "createdAt": "server timestamp"
}
```

Rules:

- Requires research role.
- Export rows must be de-identified.
- Export requires research consent for each included case.

### auditEvents

Path:

```text
auditEvents/{eventId}
```

Fields:

```json
{
  "eventId": "event-id",
  "actorUid": "uid",
  "role": "asha",
  "action": "doctor_package_uploaded",
  "caseId": "case-id",
  "visitId": "visit-id",
  "createdAt": "server timestamp",
  "result": "allowed"
}
```

Use for:

- consent recorded
- package uploaded
- upload rejected
- research export generated
- identity viewed

## Cloud Storage Paths

Recommended paths:

```text
cases/{caseId}/{visitId}/roi/{siteId}.jpg
cases/{caseId}/{visitId}/masks/{siteId}.png
cases/{caseId}/{visitId}/frames/{siteId}_{index}.jpg
research/exports/{exportId}.json
```

Do not upload:

```text
raw videos
model files
PIN vault files
local SQLite database
```

## Security Rules Direction

Rules must enforce:

- Auth required.
- Role required.
- Consent required for uploads.
- Doctor reads only assigned cases.
- ASHA reads only created/assigned cases.
- NGO/CSR reads only aggregate documents.
- Research reads only de-identified export documents.
- Patient identity is never readable by NGO/CSR or research role.

For MVP, we can start with strict rules and use Cloud Functions for sensitive writes.

Preferred approach:

- Flutter writes request to a local queue.
- Flutter uploads through callable Cloud Function.
- Cloud Function checks:
  - auth
  - role
  - consent
  - package shape
  - file metadata
- Cloud Function creates Firestore documents.

## Cloud Sync Flow

### Doctor Share Flow

1. Offline screening completes.
2. Patient sees result.
3. Consent screen appears.
4. Patient selects doctor share.
5. App creates local consent record.
6. App queues doctor package locally.
7. Connectivity policy allows check.
8. App uploads ROI and mask to Cloud Storage.
9. App calls Cloud Function to create doctor package.
10. Cloud Function validates consent and role.
11. Firestore case/package documents are created.
12. Local sync queue marks item as synced.

### Research Export Flow

1. Offline screening completes.
2. Patient gives research consent.
3. De-identified row is generated.
4. Research row is queued.
5. Cloud Function validates consent.
6. Row is stored in research dataset collection or export file.
7. No direct identity fields are uploaded.

### NGO/CSR Dashboard Flow

1. Cases are uploaded after consent.
2. Cloud Function creates aggregate counters.
3. NGO/CSR user reads aggregate documents only.
4. No names, phone numbers, DOB, exact PIN, or exact village should appear.

## What You Need To Provide

Before implementation, provide:

```text
Firebase project ID:
Google Cloud billing enabled: yes/no
Firestore location:
Storage bucket name:
Android package name:
Login method for ASHA:
Login method for doctor/admin:
Do we upload selected frames or only ROI + mask:
Who assigns doctor to case:
Do research exports include district-level data:
```

Recommended answers:

```text
Firestore location: asia-south1
Android package name: com.example.oral_cancer
ASHA login: mobile + password for MVP
Doctor/admin login: email + password
Upload: ROI + mask only
Doctor assignment: ASHA selects doctor from approved list
Research export: district-level only, no exact village
```

## Missing Test Cases

The current local tests cover many offline modules. The tests below are still needed when cloud code is implemented.

### Firebase Initialization Tests

- App initializes Firebase before cloud services are used.
- App can run without cloud initialization during pure offline screening tests.
- Missing `google-services.json` gives a clear setup error in cloud build mode.
- Firebase project ID is read from generated config.

### Authentication Tests

- ASHA can log in with valid credentials.
- ASHA login fails with wrong password.
- Doctor can log in with valid credentials.
- NGO/CSR can log in but cannot open patient identity screen.
- Research user can log in but cannot open patient identity screen.
- Disabled user cannot log in.
- Unknown role is rejected.
- Role is loaded from Firestore profile after Firebase Auth login.
- Local role cache is cleared on logout.
- Expired auth session forces re-login before upload.

### Role Permission Tests

- ASHA can create a consented case.
- ASHA can view patient identity for cases they created.
- ASHA cannot view unrelated district cases.
- Doctor can view assigned consented cases.
- Doctor cannot view unassigned cases.
- NGO/CSR can view aggregate dashboard only.
- NGO/CSR cannot read `patientIdentity`.
- Research can create export only from consented de-identified rows.
- Admin can manage user roles.
- Non-admin cannot change another user's role.

### Consent Gate Tests

- Cloud upload is blocked before screening result exists.
- Cloud upload is blocked when consent is missing.
- Doctor package upload is blocked without `doctorShare`.
- ASHA package upload is blocked without `ashaShare`.
- Cloud backup upload is blocked without `cloudBackup`.
- Research export is blocked without `researchExport`.
- Consent before screening result is rejected.
- Consent with wrong patient hash is rejected.
- Consent with wrong visit ID is rejected.
- Consent scope cannot be silently expanded after recording.
- Revoked consent blocks future uploads.
- Revoked consent does not delete audit history.

### Sync Queue Tests

- Queue item is created after consent.
- Queue item is not created before consent.
- Queue item stores only allowed payload fields.
- Queue item retries after network failure.
- Queue item does not retry before 90-second policy allows it.
- Manual sync works after result plus consent.
- Manual sync is blocked before consent.
- Successful upload marks queue item as synced.
- Failed upload records reason.
- App restart preserves unsynced queue items.
- Duplicate queue item for same package is not uploaded twice.

### Firestore Write Tests

- Case document is created only after consent.
- Case document contains district and risk summary.
- Case document does not contain full name or phone.
- Patient identity is stored only in private subdocument.
- Screening result document matches local `ScreeningResult`.
- Doctor package metadata references consent ID.
- Upload status moves from queued to synced.
- Server timestamp is added.
- Client timestamp is preserved.
- Invalid schema is rejected.

### Firestore Read Tests

- ASHA reads own cases.
- Doctor reads assigned cases.
- Doctor does not read unassigned cases.
- NGO/CSR reads aggregate collection only.
- Research reads export metadata only.
- Offline cached Firestore data does not show unauthorized documents after logout.
- Re-login as different role clears previous role data.

### Cloud Storage Upload Tests

- ROI image uploads to correct path.
- Mask image uploads to correct path.
- Selected frame upload is allowed only if enabled.
- Raw video upload is rejected.
- Model file upload is rejected.
- SQLite database upload is rejected.
- PII vault file upload is rejected.
- Upload metadata includes case ID, visit ID, site ID, and content type.
- Wrong content type is rejected.
- Oversized file is rejected.
- Upload failure leaves local queue item pending.
- Upload success stores storage object metadata in Firestore.

### Cloud Function Tests

- Function rejects unauthenticated call.
- Function rejects wrong role.
- Function rejects missing consent.
- Function rejects mismatched patient hash.
- Function rejects mismatched visit ID.
- Function creates doctor package after valid consent.
- Function writes audit event for allowed upload.
- Function writes audit event for rejected upload.
- Function is idempotent for duplicate package upload.
- Function does not expose patient identity in logs.
- Function validates Storage object paths.
- Function rejects raw video paths.

### Doctor Package Tests

- Identified doctor package includes patient identity after consent.
- Doctor package includes ROI and mask references.
- Doctor package does not include raw video.
- Doctor package cannot be created without assigned doctor.
- Doctor package cannot be opened by NGO/CSR.
- Doctor package cannot be opened by research role.
- Doctor package is readable by assigned doctor.
- Doctor package is readable by assigned ASHA.
- Doctor package audit event is created when opened.

### ASHA Workflow Tests

- ASHA can complete intake offline.
- ASHA can see patient identity locally.
- ASHA can select district from Tamil Nadu list.
- ASHA can record consent after result.
- ASHA can queue doctor package.
- ASHA can manually retry sync.
- ASHA sees sync status after consent only.
- ASHA does not see cloud controls before result.

### NGO/CSR Dashboard Tests

- Dashboard counts total screenings.
- Dashboard counts high-risk cases.
- Dashboard counts urgent cases.
- Dashboard groups by district.
- Dashboard groups by month.
- Dashboard excludes full name.
- Dashboard excludes phone.
- Dashboard excludes DOB.
- Dashboard excludes exact PIN.
- Dashboard excludes exact village.
- NGO/CSR cannot drill into patient identity.

### Research Export Tests

- Export includes only consented rows.
- Export excludes non-consented rows.
- Export uses backend HMAC pseudonymization.
- Same patient gets stable pseudonym within same study.
- Different study secret gives different pseudonym.
- Export excludes full name.
- Export excludes phone.
- Export excludes DOB.
- Export excludes exact PIN.
- Export excludes raw image paths if not approved.
- Export includes age band, district, risk level, site result, lesion size.
- Export file is written to Cloud Storage.
- Export metadata is written to Firestore.
- Research role can download export.
- ASHA/doctor/NGO cannot download research export unless allowed.

### Offline/Online Transition Tests

- App completes screening with no internet.
- App does not show sync before result.
- App does not show sync before consent.
- App detects connectivity after consent.
- App auto-checks every 90 seconds.
- App manual check works after consent.
- Network loss during upload keeps item queued.
- Network restore resumes upload.
- App restart during upload does not duplicate package.
- Local SQLite remains source of truth until upload success.

### Security Rules Tests

- Unauthenticated user cannot read cases.
- Unauthenticated user cannot write cases.
- ASHA cannot read all cases globally.
- Doctor cannot list all cases globally.
- NGO/CSR cannot read private patient identity subdocuments.
- Research cannot read private patient identity subdocuments.
- Only admin can create/change role profiles.
- Storage write requires auth.
- Storage write requires allowed path.
- Storage write rejects raw video.
- Storage read requires correct role.

Initial emulator examples were added in [firebase-emulator-tests/rules_examples.test.mjs](firebase-emulator-tests/rules_examples.test.mjs):

- ASHA can read private identity for her own case.
- NGO/CSR cannot read private patient identity.
- Raw video upload to Cloud Storage is denied.
- Assigned doctor can read private identity.
- Unassigned doctor cannot read private identity.
- ASHA can upload ROI JPEG.
- ASHA cannot upload ROI with wrong content type.
- Public case metadata with direct identity fields is rejected.

Run them with:

```bash
npm install
npm run test:rules
```

Dependency note:

- `firebase-tools` is intentionally not kept as a local `devDependency`.
- The test script uses the globally installed `firebase` CLI.
- This keeps the project `npm audit` clean while still allowing emulator tests to run.

### Privacy Regression Tests

- JSON sent to NGO dashboard does not contain identity fields.
- JSON sent to research export does not contain identity fields.
- Logs do not contain full name.
- Logs do not contain phone.
- Logs do not contain PIN code.
- Error messages do not leak patient identity.
- Cloud Function rejected payload logs only case ID and reason.

### Cost And Abuse Tests

- Large upload is rejected before consuming too much bandwidth.
- Duplicate upload is idempotent.
- Retry backoff prevents tight upload loops.
- App Check missing token is rejected once App Check is enabled.
- Rate limit is applied to callable functions.
- Storage paths cannot be overwritten by another user.

## Implementation Order

Recommended order:

1. Create Firebase project and configure FlutterFire.
2. Add Firebase initialization only.
3. Add Auth login and role profile loading.
4. Add consent-gated cloud interfaces, but keep upload disabled until tests pass.
5. Add Firestore case metadata upload.
6. Add Storage ROI/mask upload.
7. Add Cloud Function consent validation.
8. Add doctor package upload.
9. Add NGO/CSR aggregate dashboard.
10. Add research export.
11. Add App Check.
12. Add stricter security rules and emulator tests.

## Do Not Build Yet

Do not build these until the above is stable:

- public dashboards
- automatic doctor assignment
- hospital EHR integration
- SMS/WhatsApp notifications
- production analytics
- cloud model inference

The hackathon story should remain:

```text
offline screening first, cloud sharing only with consent
```
