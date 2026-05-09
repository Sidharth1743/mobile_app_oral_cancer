import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/consent/consent.dart';

void main() {
  test('defaults to no online sharing when no scopes are present', () {
    final consent = ConsentRecord(
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      scopes: const {},
      recordedAt: DateTime.utc(2026, 5, 3, 10),
      policyVersion: '2026-05',
      screeningCompletedAt: DateTime.utc(2026, 5, 3, 9),
    );

    expect(consent.hasAnyOnlineScope, isFalse);
    expect(consent.doctorShare, isFalse);
  });

  test('rejects consent recorded before the offline result exists', () {
    final consent = ConsentRecord(
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      scopes: const {ConsentScope.doctorShare},
      recordedAt: DateTime.utc(2026, 5, 3, 8),
      policyVersion: '2026-05',
      screeningCompletedAt: DateTime.utc(2026, 5, 3, 9),
    );

    expect(consent.validatePostResult, throwsStateError);
  });

  test('serializes explicit consent scopes', () {
    final consent = ConsentRecord(
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      scopes: const {ConsentScope.doctorShare, ConsentScope.cloudBackup},
      recordedAt: DateTime.utc(2026, 5, 3, 10),
      policyVersion: '2026-05',
      screeningCompletedAt: DateTime.utc(2026, 5, 3, 9),
    );

    final decoded = ConsentRecord.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(consent.toJson())) as Map,
      ),
    );

    expect(decoded.doctorShare, isTrue);
    expect(decoded.cloudBackup, isTrue);
    expect(decoded.researchExport, isFalse);
  });
}
