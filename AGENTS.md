# Repository Guidelines

## Project Structure & Module Organization
This repo is a Flutter-first Android app with supporting services at the root. Primary app code lives in `lib/`, grouped by feature (`auth/`, `cloud/`, `inference/`, `research/`, `sync/`, `ui/`, etc.). Assets are in `assets/`, including demo fixtures and location data. Tests live in `test/` for Dart, `firebase-emulator-tests/` for Firebase rules, and `functions/test/` for Cloud Functions. The local PC backend is in `backend/`. Keep `oral_gemma_finetune_package/` for model and training artifacts only; do not add app code there.

## Build, Test, and Development Commands
- `flutter pub get` installs Dart dependencies.
- `flutter analyze` checks static analysis and lint rules.
- `flutter test` runs the full Dart test suite.
- `flutter build apk --debug` builds the Android APK for device testing.
- `./scripts/run_pc_backend.sh` starts the local backend.
- `./scripts/run_pc_backend_tests.sh` runs backend unit tests.
- `npm run test:rules` runs Firebase emulator rules tests.
- `npm run test:functions` runs Cloud Functions validation tests.

## Coding Style & Naming Conventions
Use Dart’s standard 2-space indentation and keep files formatted with `dart format`. Prefer small, single-purpose widgets and feature-based filenames such as `doctor_package_screen.dart` or `sync_worker.dart`. Dart tests should end in `_test.dart`; Node tests should end in `.test.mjs`. Keep JSON fixtures and assets descriptive, for example `assets/demo/prev_visit.json`.

## Testing Guidelines
Prefer deterministic tests that cover business logic, data validation, and workflow boundaries. Flutter tests use `flutter_test`, backend tests use Python `unittest`, and Firebase tests run against emulators. Add or update tests whenever you change intake, de-identification, sync, inference prompts, or export behavior. Use clear test names like `rejects_future_dob` or `builds_doctor_package_without_identity`.

## Commit & Pull Request Guidelines
There is no established commit history yet, so use short imperative commits such as `add sync queue tests` or `fix firebase rule checks`. Pull requests should summarize the change, list validation commands run, and include screenshots or APK notes for UI work. Link the related issue or task when available.

## Security & Configuration Tips
Do not commit secrets, device-specific paths, or generated build output. Keep Firebase and cloud configuration in the documented root files (`firebase.json`, `firestore.rules`, `storage.rules`, `functions/`). When in doubt, preserve offline behavior and avoid placing code inside model output directories.
