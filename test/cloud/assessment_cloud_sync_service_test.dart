import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/cloud/assessment_cloud_sync_service.dart';
import 'package:oral_cancer/consent/consent.dart';
import 'package:oral_cancer/data/models.dart';

void main() {
  test(
    'identified assessment cloud payload parses and validates consistency',
    () {
      final payload = _payload();

      final parsed = IdentifiedAssessmentCloudPayload.fromJson(payload);

      expect(parsed.identity.fullName, 'Meera Kumar');
      expect(parsed.assignedDoctorUid, 'doctor-1');
      expect(parsed.assessment.visitId, 'visit-1');
    },
  );

  test('identified assessment cloud payload rejects missing doctor uid', () {
    final payload = {..._payload(), 'assignedDoctorUid': ''};

    expect(
      () => IdentifiedAssessmentCloudPayload.fromJson(payload),
      throwsStateError,
    );
  });
}

Map<String, Object?> _payload() => {
  'assignedDoctorUid': 'doctor-1',
  'patient': _identity().toJson(),
  'clinical': _clinicalRecord().toJson(),
  'assessment': _assessment().toJson(),
  'consent': _consent().toJson(),
};

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

ConsentRecord _consent() => ConsentRecord(
  visitId: 'visit-1',
  patientHash: 'patient-hash',
  scopes: const {ConsentScope.doctorShare},
  recordedAt: DateTime.utc(2026, 5, 3, 10),
  policyVersion: '2026-05',
  screeningCompletedAt: DateTime.utc(2026, 5, 3, 9),
);

FullAssessment _assessment() => FullAssessment(
  visitId: 'visit-1',
  patientHash: 'patient-hash',
  createdAt: DateTime.utc(2026, 5, 3, 9),
  siteResults: const [],
  hypotheses: const [],
  delta: const DeltaResult(
    summary: 'No earlier measurement.',
    sizeChangeMm: 0,
    concernIncreased: false,
  ),
  carePlan: CarePlan(
    action: 'see_doctor_free',
    patientMessage: 'Doctor check needed.',
    ashaMessage: 'Prepare referral.',
    rescreenDate: DateTime.utc(2026, 5, 10),
    doctorBrief: 'Review needed.',
  ),
  thinking: '',
  citations: const [],
);
