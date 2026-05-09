import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/consent/consent.dart';
import 'package:oral_cancer/pipeline/screening_pipeline.dart';
import 'package:oral_cancer/sync/connectivity_policy.dart';

void main() {
  test('does not check connectivity before result and consent', () {
    final now = DateTime.utc(2026, 5, 3, 10);
    const policy = ConnectivityPolicy();

    expect(
      policy.shouldCheck(
        now: now,
        lastCheckedAt: null,
        result: null,
        consent: null,
      ),
      isFalse,
    );
    expect(
      policy.shouldCheck(
        now: now,
        lastCheckedAt: null,
        result: _result(),
        consent: _consent(const {}),
      ),
      isFalse,
    );
  });

  test('checks every 90 seconds or manually after consent', () {
    final now = DateTime.utc(2026, 5, 3, 10);
    const policy = ConnectivityPolicy();
    final result = _result();
    final consent = _consent(const {ConsentScope.doctorShare});

    expect(
      policy.shouldCheck(
        now: now,
        lastCheckedAt: now.subtract(const Duration(seconds: 89)),
        result: result,
        consent: consent,
      ),
      isFalse,
    );
    expect(
      policy.shouldCheck(
        now: now,
        lastCheckedAt: now.subtract(const Duration(seconds: 90)),
        result: result,
        consent: consent,
      ),
      isTrue,
    );
    expect(
      policy.shouldCheck(
        now: now,
        lastCheckedAt: now.subtract(const Duration(seconds: 1)),
        result: result,
        consent: consent,
        manual: true,
      ),
      isTrue,
    );
  });
}

ConsentRecord _consent(Set<ConsentScope> scopes) => ConsentRecord(
  visitId: 'visit-1',
  patientHash: 'patient-hash',
  scopes: scopes,
  recordedAt: DateTime.utc(2026, 5, 3, 9, 1),
  policyVersion: '2026-05',
  screeningCompletedAt: DateTime.utc(2026, 5, 3, 9),
);

ScreeningResult _result() => ScreeningResult(
  visitId: 'visit-1',
  patientHash: 'patient-hash',
  createdAt: DateTime.utc(2026, 5, 3, 9),
  riskLevel: 'low',
  siteResults: const [],
  segmentation: const [],
  differentials: const [],
  uncertainty: 0.1,
  patientSummary: 'No immediate concern.',
  ashaSummary: 'Rescreen later.',
  doctorSummary: 'No doctor package required.',
  recommendedAction: 'rescreen',
  modelName: 'gemma-4-E2B-it.litertlm',
);
