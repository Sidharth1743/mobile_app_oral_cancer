You are building oral cancer ai — an on-device oral cancer screening and care
coordination app for rural India. The entire ML inference runs locally
on the phone using Gemma 4 E4B. No patient data leaves the device
except anonymised clinical packages that sync when connectivity is
available.

=== TECH STACK ===

Frontend: Flutter (Android-first, min SDK 26)
On-device ML: Gemma 4 E4B via MediaPipe LLM Inference API (Flutter plugin)
Local DB: SQLite via sqflite package
Video processing: camera package + ffmpeg_kit_flutter for frame extraction
Image processing: opencv_dart or image package for blur/exposure scoring
Audio: record package for voice capture, Gemma 4 E4B native audio input
Backend sync (minimal): FastAPI on Railway or Render (free tier)
Push/reminders: Firebase Cloud Messaging (free tier)
Auth: none — ASHA worker PIN only, no accounts

=== PROJECT STRUCTURE ===

oral cancer ai/
lib/
main.dart
core/
pii_vault.dart -- AES-256 encrypt identity fields locally
sqlite_service.dart -- all local DB operations
sync_queue.dart -- queues cases for upload when online
connectivity_watcher.dart
features/
intake/
intake_screen.dart -- patient habit form (brand, years, freq)
intake_model.dart -- CEI score computation
capture/
video_capture_screen.dart -- 6-site guided video recording
frame_extractor.dart -- ffmpeg: extract frames from video
frame_selector.dart -- blur score + exposure → best 3 frames
inference/
gemma_service.dart -- MediaPipe LLM Inference wrapper
prompts.dart -- all Gemma 4 prompt templates
lesion_analyzer.dart -- orchestrates vision inference pipeline
ttt_adapter.dart -- test-time training: LoRA delta per patient
outputs/
patient_output.dart -- simple Tamil/Hindi spoken care plan
asha_output.dart -- clinical brief for ASHA worker
doctor_package.dart -- full clinical JSON + annotated images
tracking/
ehr_service.dart -- longitudinal record: load past visits
delta_engine.dart -- compare current vs previous lesion JSON
progress_screen.dart -- visual progress bar for patient
referral/
referral_service.dart -- PMJAY hospital lookup by district
async_doctor.dart -- package upload + voice note download
whatsapp_reminder.dart
dashboard/
asha_dashboard.dart -- ASHA worker case list + status
ngo_dashboard.dart -- aggregate outcomes for CSR reporting
models/
patient.dart
lesion_map.dart
care_plan.dart
case_package.dart
backend/
main.py -- FastAPI
routes/
cases.py -- receive doctor packages
voice_notes.py -- doctor uploads voice response
hospitals.py -- PMJAY hospital directory by district
outcomes.py -- treatment completion logging
db/
schema.sql
assets/
prompts/ -- prompt templates as .txt files
oral_sites/ -- guide overlay images for 6 capture positions

=== STEP 1: PII VAULT (build this first) ===

File: lib/core/pii_vault.dart

On patient intake, immediately split the record into two objects:

IdentityRecord (encrypted, never leaves device):

- full_name: String
- village: String
- phone: String
- abha_id: String (nullable)
- gps_coords: LatLng (nullable)

ClinicalRecord (de-identified, safe to sync):

- patient_hash: String -- SHA-256 of name+village+dob, used as FK
- age_band: String -- "30-40", "40-50" etc, never exact age
- gender: String
- district_code: String -- pincode first 3 digits only
- habit_brand: String
- habit_years: int
- habit_frequency: int -- sachets per day
- cei_score: double -- computed carcinogen exposure index
- created_at: DateTime

CEI formula:
base*score = habit_years * habit*frequency * brand_tsna_weight
brand_tsna_weight map:
"Manikchand": 1.4
"Pan Parag": 1.2  
 "Rajnigandha": 1.1
"Vimal": 1.3
"Other gutka": 1.0
"Bidi": 0.9
"Cigarette": 0.8
cei_score = min(base_score / 100.0, 1.0) -- normalized 0-1

Encrypt IdentityRecord using AES-256-GCM with a key derived from
the ASHA worker's PIN using PBKDF2. Store encrypted blob in
shared_preferences. Store ClinicalRecord in SQLite unencrypted.

=== STEP 2: VIDEO CAPTURE + FRAME SELECTION ===

File: lib/features/capture/video_capture_screen.dart
File: lib/features/capture/frame_extractor.dart
File: lib/features/capture/frame_selector.dart

UI: Show a guide overlay image of the oral site position.
Label each of the 6 sites in the ASHA worker's language:

1. buccal_left -- "Left inner cheek"
2. buccal_right -- "Right inner cheek"
3. tongue_top -- "Top of tongue"
4. tongue_bottom -- "Under tongue"
5. floor_mouth -- "Under tongue, floor"
6. palate -- "Roof of mouth"

For each site:

- Show guide overlay (semi-transparent positioning diagram)
- Record video for 4 seconds using camera package
- After recording, run frame*extractor.dart:
  ffmpeg command: extract 1 frame per 0.5 seconds = 8 frames per video
  ffmpeg_kit_flutter: FFmpegKit.execute(
  '-i $videoPath -vf fps=2 $outputDir/frame*%03d.jpg -y'
  )
- Run frame_selector.dart on the 8 frames:
  For each frame compute:
  blur_score: Laplacian variance using opencv_dart
  -- load image as grayscale Mat
  -- apply Laplacian filter
  -- compute variance of result
  -- frames with variance < 100 are blurry, reject
  exposure_score: mean pixel value of center crop
  -- reject if mean < 30 (too dark) or mean > 220 (overexposed)
  face_region_confidence: check if bottom-third of image
  has expected oral cavity color range (pinkish-red hues)
  Select top 2-3 frames by combined score
- Delete the raw video immediately after frame extraction
- Store selected frames as JPEG in app's private directory
- Record in SQLite: site, frame_paths, capture_timestamp, patient_hash

=== STEP 3: GEMMA 4 SERVICE ===

File: lib/features/inference/gemma_service.dart

Use MediaPipe LLM Inference API for Flutter.
Model: gemma-4-e4b-it (download on first launch, ~3GB, cache in app dir)

The service exposes one method:
Future<String> infer({
required String systemPrompt,
required String userPrompt,
List<String>? imagePaths, -- base64 encode images before sending
bool useThinkingMode = true,
})

Thinking mode: prepend to system prompt:
"Think through this step by step inside <think></think> tags
before giving your final answer."

Parse response: extract content after </think> as the final answer.
Keep the <think> block separately for the doctor package.

=== STEP 4: PROMPT TEMPLATES ===

File: lib/features/inference/prompts.dart

PROMPT 1 — LESION ANALYSIS (per oral site):

System:
"""
You are a clinical oral oncologist analyzing images for an ASHA
community health worker in rural India. The patient is a {age_band}
{gender} who has used {habit_brand} for {habit_years} years at
{habit_frequency} sachets per day. Their Carcinogen Exposure Index
is {cei_score}/1.0.

Think through your analysis inside <think></think> tags.

Return ONLY a valid JSON object with this exact structure:
{
"site": "{site_name}",
"lesion_detected": true/false,
"lesion_type": "normal" | "homogeneous_leukoplakia" |
"non_homogeneous_leukoplakia" | "erythroplakia" |
"osmf" | "ulcer" | "traumatic_keratosis" |
"leukoedema" | "other",
"area_mm2_estimate": number or null,
"color_deviation": "none" | "mild_white" | "heavy_white" |
"red_component" | "mixed",
"texture": "smooth" | "granular" | "nodular" | "ulcerated",
"border": "well_defined" | "irregular" | "diffuse",
"roi_description": "1-2 sentence description of which image region
drove this finding and why",
"field_risk_state": "intact" | "stressed" | "early_condemned" |
"condemned",
"confidence": number between 0 and 1
}
"""

User: [attach image(s) for this site]
"Analyze this oral cavity image. Return only the JSON."

PROMPT 2 — HYPOTHESIS + UNCERTAINTY GENERATION:

System:
"""
You are a clinical oral oncologist. You have received lesion analysis
results from {num_sites} oral sites.

Think through differentials inside <think></think> tags.

Return ONLY a valid JSON object:
{
"differentials": [
{
"diagnosis": string,
"probability": number 0-1,
"supporting_evidence": [list of strings],
"ruling_out_test": string or null
}
],
"uncertainty_level": "low" | "moderate" | "high",
"uncertainty_reason": string,
"overall_risk": "no_concern" | "monitor" | "refer_elective" |
"refer_urgent",
"most_concerning_site": string,
"rag_citations": ["WHO Oral Cancer Classification 2022",
"ICMR Guidelines 2019", ...]
}

Uncertainty rules:

- high: top differential probability < 0.55
- moderate: top differential probability 0.55-0.75
- low: top differential probability > 0.75

If uncertainty is high, overall_risk must be at least refer_elective.
"""

User: "Here are the per-site analysis results: {json_array_of_site_results}
Patient profile: {clinical_record_json}
Return only the JSON."

PROMPT 3 — CARE PLAN GENERATION (3 versions):

System:
"""
You are generating a personalized care plan for three different
audiences. Be culturally sensitive. Never use the word 'cancer'
in the patient version unless the risk is refer_urgent.

Return ONLY a valid JSON object:
{
"patient_version": {
"language": "tamil" | "hindi" | "marathi" | "telugu" | "english",
"spoken_text": "2-3 sentence plain language explanation in the
patient's language. Non-scary. Honest. Actionable.",
"key_message": "one sentence they must remember",
"action": "nothing_now" | "come_back_30_days" | "see_doctor_free"
},
"asha_version": {
"clinical_summary": string,
"action_required": string,
"rescreen_in_days": number,
"cessation_counseling_needed": boolean
},
"doctor_version": {
"clinical_brief": "3-4 sentence clinical summary with findings",
"key_concerns": [list of strings],
"recommended_workup": string,
"urgency": "routine" | "within_2_weeks" | "within_48_hours"
},
"predicted_trajectory": {
"six_month_lesion_probability": number 0-1,
"if_cessation_probability": number 0-1,
"trajectory_curve_points": [[0,current_risk],[90,p90],[180,p180]]
}
}
"""

User: "Patient: {clinical_record_json}
Lesion findings: {lesion_map_json}
Hypothesis assessment: {hypothesis_json}
Longitudinal history: {ehr_history_json or 'No previous visits'}
Generate the care plan."

PROMPT 4 — PROGRESS DELTA (returning patients only):

System:
"""
You are comparing two oral screening visits for the same patient.
Return ONLY a valid JSON object:
{
"site_deltas": [
{
"site": string,
"size_change": "regressed" | "stable" | "grew_slightly" |
"grew_significantly",
"color_change": "improved" | "stable" | "worsened",
"texture_change": "improved" | "stable" | "worsened",
"new_lesion": boolean
}
],
"composite_trajectory": "regressing" | "stable" |
"slow_progression" | "rapid_progression",
"habit_compliance_assessment": string,
"patient_bar_color": "green" | "yellow" | "orange" | "red",
"patient_message": "1 sentence in patient language about progress"
}
"""

User: "Previous visit ({days_ago} days ago): {previous_lesion_json}
Current visit: {current_lesion_json}
Habit change reported: {habit_change}
Generate the delta."

=== STEP 5: LESION ANALYZER ORCHESTRATOR ===

File: lib/features/inference/lesion_analyzer.dart

Method: Future<FullAssessment> analyze(String patientHash)

Steps:

1. Load clinical record from SQLite for patientHash
2. Load captured frame paths for current visit from SQLite
3. Load previous visit lesion_map_json from SQLite if exists
4. For each of 6 sites:
   a. Get frame paths for that site
   b. Run PROMPT 1 with those images + patient profile
   c. Parse JSON response → LesionSiteResult object
   d. Store in list
5. Run PROMPT 2 with all 6 LesionSiteResult JSONs → HypothesisResult
6. If previous visit exists: run PROMPT 4 → DeltaResult
7. Run PROMPT 3 with all results → CarePlan
8. Save everything to SQLite under current visit record
9. Return FullAssessment object containing all of the above

=== STEP 6: OUTPUT SCREENS ===

File: lib/features/outputs/patient_output.dart

Show patient-facing output:

- Big colored circle (green/yellow/orange/red) based on patient_bar_color
- Single large text: care_plan.patient_version.key_message
- Below: care_plan.patient_version.spoken_text
- TTS button: use flutter_tts package to read spoken_text aloud
  in patient's language
- If action == "see_doctor_free": show button "Book free appointment"
  that triggers referral_service.dart

File: lib/features/outputs/asha_output.dart

ASHA worker view (password-gated — requires PIN entry):

- Clinical summary text
- Uncertainty badge (LOW/MODERATE/HIGH with color)
- Top 3 differentials with probabilities as a simple bar chart
- ROI: for each flagged site, show the best frame with a
  colored rectangle drawn around the bbox coordinates from lesion JSON
- Rescreen date
- Action required (bold, large)
- Button: "Prepare doctor package" → doctor_package.dart

File: lib/features/outputs/doctor_package.dart

Creates the case package for async doctor review:

- Anonymised ClinicalRecord (no PII)
- All lesion frames with ROI bounding boxes annotated (draw rects in Flutter)
- Full JSON: lesion_map, hypothesis, uncertainty, trajectory
- The <think> reasoning chain from Gemma 4 (clinical reasoning)
- RAG citations list
- CarePlan doctor_version
  Package this as a JSON file + image attachments
  Store in sync_queue for upload

=== STEP 7: LONGITUDINAL EHR ===

File: lib/features/tracking/ehr_service.dart

SQLite schema for visits table:
CREATE TABLE visits (
id TEXT PRIMARY KEY,
patient_hash TEXT,
visit_date TEXT,
lesion_map_json TEXT,
hypothesis_json TEXT,
care_plan_json TEXT,
delta_json TEXT,
doctor_response_text TEXT,
doctor_response_audio_path TEXT,
outcome TEXT,
synced INTEGER DEFAULT 0
)

Method: List<Visit> getVisitHistory(String patientHash)
Returns all past visits sorted by date ascending.

Method: Visit? getLastVisit(String patientHash)
Returns most recent visit or null.

When loading history for Gemma 4 context (PROMPT 3 and 4):
Serialize last 3 visits as compact JSON array.
If patient has ABHA ID (stored in IdentityVault) and device is online:
Make API call to ABDM sandbox to fetch external records.
Parse and append to history context.

=== STEP 8: CONNECTIVITY + SYNC ===

File: lib/core/connectivity_watcher.dart
File: lib/core/sync_queue.dart

connectivity_watcher: uses connectivity_plus package
Watches for network state changes.
When network becomes available: trigger sync_queue.processQueue()

sync_queue:
Queue stored in SQLite table:
CREATE TABLE sync_queue (
id TEXT PRIMARY KEY,
type TEXT, -- "case_package" | "outcome" | "dataset_consent"
payload_path TEXT,
created_at TEXT,
attempts INTEGER DEFAULT 0,
synced INTEGER DEFAULT 0
)

processQueue():
For each unsynced item:
POST to FastAPI backend
On 200: mark synced=1
On failure: increment attempts, retry up to 3 times
After 3 failures: mark as failed, alert ASHA worker

=== STEP 9: ASYNC DOCTOR LOOP ===

File: lib/features/referral/async_doctor.dart

Upload: when case_package syncs to backend, doctor receives
push notification via FCM.

Download: on every sync, check GET /voice_notes/{patient_hash}
If new voice note exists: download mp3 to private app dir
Update visit record: doctor_response_audio_path

Playback screen:
Show doctor's name, credentials, timestamp
Large play button
Waveform visualization (audioplayers package)
Below audio: doctor's text summary if provided

=== STEP 10: REFERRAL SERVICE ===

File: lib/features/referral/referral_service.dart

Hospital lookup: GET /hospitals?district_code={code}
Returns: List of PMJAY-empanelled cancer hospitals
Each hospital: name, address, distance_km, phone, pmjay_id

Show to ASHA worker: sorted by distance
Show to patient (simplified): hospital name + "Free under PMJAY"

Appointment booking: POST /appointments
Body: { patient_hash, hospital_pmjay_id, preferred_date,
urgency, case_package_id }
Returns: appointment_id, confirmed_date, instructions

WhatsApp reminder (24h before):
Use WhatsApp Business API (free tier: 1000 messages/month)
Message template (pre-approved):
"Kal {time} baje {hospital_name} mein appointment hai.
PMJAY card saath lena. Treatment bilkul free.
Agar nahi aa sakte: {asha_phone}"

=== BACKEND (FastAPI) ===

File: backend/main.py

Routes:
POST /cases -- receive doctor package (JSON + images as multipart)
GET /cases/{id} -- doctor retrieves case for review
POST /voice_notes -- doctor uploads voice response (mp3)
GET /voice_notes/{patient_hash} -- check for new voice notes
GET /hospitals -- PMJAY hospital directory by district_code
POST /appointments -- book referral appointment
POST /outcomes -- log treatment completion (from doctor/NGO)
GET /ngo_dashboard -- aggregate stats for CSR reporting

Database: PostgreSQL (free tier on Supabase)
All case data anonymised at receipt (patient_hash only, no PII)
Voice notes stored in Supabase Storage bucket

=== NGO / CSR DASHBOARD ===

File: lib/features/dashboard/ngo_dashboard.dart
(Web view embedded in app, or separate Flutter web build)

Shows for a given district/sponsor:

- Total screenings this month
- Risk distribution (no_concern / monitor / refer_elective / refer_urgent)
- Referral completion rate
- Treatment outcome rate
- Top risk villages (by district_code cluster)
- Brand prevalence in high-risk cases

Data comes from GET /ngo_dashboard?sponsor_id={id}&district={code}

=== DATASET CONTRIBUTION ===

With explicit patient consent (shown on intake screen, in local language):

- De-identified clinical record + lesion images (no face, no PII)
- Doctor's confirmed diagnosis (if available)
- Outcome (if logged)
  Added to sync_queue with type "dataset_consent"
  Backend: POST /dataset -- stores in separate Supabase bucket
  Will be released as open dataset for oral cancer AI research

=== DEMO REQUIREMENTS ===

Build a demo mode that works without a real Gemma 4 model download.
Demo mode: use pre-computed JSON responses stored in assets/demo/
so judges can see the full flow without waiting for model inference.

Demo patient profile:
Name: Murugan (displayed in demo only)
Age: 41, Male, Nagpur district
Brand: Manikchand, 14 years, 4/day
CEI: 0.78
Has one previous visit 45 days ago (stored in assets/demo/prev_visit.json)

Demo flow:

1. Intake screen (pre-filled with demo data)
2. Video capture (skip actual recording in demo, use assets/demo/frames/)
3. Show Gemma 4 "analyzing..." spinner for 3 seconds
4. Load demo results from assets/demo/assessment.json
5. Show patient output: yellow circle, Tamil spoken text, TTS plays
6. Show ASHA output: moderate uncertainty, 2 differentials, ROI overlay
7. Show progress: "lesion grew 4mm since last visit" — orange bar
8. Show doctor package: annotated image + clinical brief
9. Connectivity: "syncing..." → "Doctor notified"
10. Play demo doctor voice note from assets/demo/doctor_response.mp3

=== LOCALIZATION ===

Support 5 languages using Flutter's intl package:

- Tamil (ta)
- Hindi (hi)
- Marathi (mr)
- Telugu (te)
- English (en) -- fallback

All patient-facing strings in ARB files: lib/l10n/app_ta.arb etc.
All clinical strings (ASHA + doctor facing) in English only.
TTS language codes: ta-IN, hi-IN, mr-IN, te-IN

=== BUILD + RUN ===

flutter pub get
flutter run --flavor demo -- runs demo mode, no model needed
flutter run --flavor prod -- requires Gemma 4 E4B download on first run

Target device: Android 8.0+, arm64
Min RAM: 4GB (Gemma 4 E4B requirement)
Storage: ~4GB for model + ~500MB app data

=== WHAT TO BUILD FIRST (in order) ===

1. PII vault + SQLite schema
2. Video capture + frame extraction (test with sample oral images)
3. Gemma 4 service wrapper (test with a simple text prompt first)
4. PROMPT 1 lesion analysis on a single site
5. PROMPT 2 hypothesis generation
6. PROMPT 3 care plan (3 versions)
7. Patient output screen with TTS
8. ASHA output screen with ROI overlay
9. Demo mode with pre-computed responses
10. Longitudinal EHR + PROMPT 4 delta
11. Connectivity + sync queue
12. Backend FastAPI (minimal — just cases + voice notes)
13. Async doctor loop
14. NGO dashboard
15. Referral service

Build 1-9 first. That is the hackathon MVP.
10-15 are the full product — implement as time allows.
