import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/cloud/cloud_payloads.dart';
import 'package:oral_cancer/consent/consent.dart';
import 'package:oral_cancer/data/models.dart';
import 'package:oral_cancer/pipeline/screening_pipeline.dart';

void main() {
  test('case metadata excludes direct patient identity', () {
    final payload = const CloudCasePayloadBuilder().buildCaseMetadata(
      caseId: 'case-1',
      createdByUid: 'asha-1',
      state: 'Tamil Nadu',
      district: 'Madurai',
      clinicalRecord: _clinicalRecord(),
      result: _result(),
      consent: _consent(const {ConsentScope.doctorShare}),
      assignedDoctorUid: 'doctor-1',
    );
    final encoded = jsonEncode(payload);

    expect(payload['district'], 'Madurai');
    expect(payload['riskLevel'], 'high');
    expect(encoded, isNot(contains('Meera')));
    expect(encoded, isNot(contains('9999999999')));
    expect(encoded, isNot(contains('1978-02-12')));
    expect(encoded, isNot(contains('628501')));
  });

  test('patient identity payload is isolated to private document', () {
    final payload = const CloudCasePayloadBuilder().buildPatientIdentity(
      identity: _identity(),
      consent: _consent(const {ConsentScope.doctorShare}),
      consentId: 'consent-1',
    );

    expect(payload['fullName'], 'Meera Kumar');
    expect(payload['district'], 'Madurai');
    expect(payload['consentId'], 'consent-1');
  });

  test('cloud payload rejects consent mismatched to result', () {
    final badConsent = ConsentRecord(
      visitId: 'other-visit',
      patientHash: 'patient-hash',
      scopes: const {ConsentScope.doctorShare},
      recordedAt: DateTime.utc(2026, 5, 3, 10),
      policyVersion: '2026-05',
      screeningCompletedAt: DateTime.utc(2026, 5, 3, 9),
    );

    expect(
      () => const CloudCasePayloadBuilder().buildScreeningResult(
        result: _result(),
        consent: badConsent,
      ),
      throwsStateError,
    );
  });
}

IdentityRecord _identity() => IdentityRecord(
  fullName: 'Meera Kumar',
  village: 'Melur',
  dateOfBirth: DateTime.utc(1978, 2, 12),
  phone: '9999999999',
  pinCode: '625106',
  state: 'Tamil Nadu',
  district: 'Madurai',
);

ClinicalRecord _clinicalRecord() => ClinicalRecord(
  id: 'clinical-1',
  patientHash: 'patient-hash',
  ageBand: '45-54',
  pinPrefix: '625',
  villageCode: 'melur-code',
  gender: 'female',
  tobaccoBrand: 'Hans',
  chewsPerDay: 6,
  yearsUsed: 12,
  alcoholUse: false,
  cei: 0.62,
  createdAt: DateTime.utc(2026, 5, 3),
);

ConsentRecord _consent(Set<ConsentScope> scopes) => ConsentRecord(
  visitId: 'visit-1',
  patientHash: 'patient-hash',
  scopes: scopes,
  recordedAt: DateTime.utc(2026, 5, 3, 10),
  policyVersion: '2026-05',
  screeningCompletedAt: DateTime.utc(2026, 5, 3, 9),
);

ScreeningResult _result() => ScreeningResult(
  visitId: 'visit-1',
  patientHash: 'patient-hash',
  createdAt: DateTime.utc(2026, 5, 3, 9),
  riskLevel: 'high',
  siteResults: const [],
  segmentation: const [
    SegmentationArtifact(
      siteId: 'left_buccal',
      roiImagePath: 'app/roi/left.jpg',
      maskPath: 'app/masks/left.png',
      lesionSizeMm: 9,
    ),
  ],
  differentials: const [],
  uncertainty: 0.18,
  patientSummary: 'A doctor check is needed.',
  ashaSummary: 'Prepare referral.',
  doctorSummary: 'Left buccal lesion.',
  recommendedAction: 'see_doctor_free',
  modelName: 'gemma-4-E2B-it.litertlm',
);
