import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/consent/consent.dart';
import 'package:oral_cancer/data/local_database.dart';
import 'package:oral_cancer/data/models.dart';
import 'package:oral_cancer/output/doctor_package.dart';
import 'package:oral_cancer/pipeline/screening_pipeline.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LocalDatabase database;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'builds anonymized doctor package with reasoning and image references',
    () {
      final package = const DoctorPackageBuilder().build(_assessment());
      final encoded = jsonEncode(package.toJson());

      expect(package.visitId, 'visit-1');
      expect(package.patientHash, 'patient-hash');
      expect(package.reasoning, contains('risk exposure'));
      expect(package.imageReferences, ['app/frames/left-roi.jpg']);
      expect(encoded, isNot(contains('fullName')));
      expect(encoded, isNot(contains('phone')));
      expect(encoded, isNot(contains('dateOfBirth')));
      expect(encoded, isNot(contains('pinCode')));
    },
  );

  test('queues anonymized package in sync queue', () async {
    final queued = await const DoctorPackageBuilder().queue(
      database: database,
      assessment: _assessment(),
    );
    final items = await database.queuedSyncItems();

    expect(queued.kind, 'doctor_package');
    expect(items.single.payload['visitId'], 'visit-1');
    expect(jsonEncode(items.single.payload), isNot(contains('phone')));
  });

  test('builds identified doctor package only after doctor consent', () {
    final package = const IdentifiedDoctorPackageBuilder().build(
      identity: _identity(),
      clinicalRecord: _clinicalRecord(),
      result: _screeningResult(),
      consent: _consent(const {ConsentScope.doctorShare}),
    );

    expect(package['patient'], isA<Map<String, Object?>>());
    expect(jsonEncode(package), contains('Meera Kumar'));
    expect(jsonEncode(package), contains('9999999999'));
    expect(package['doctorBrief'], contains('Left buccal'));
  });

  test('rejects identified doctor package without consent', () {
    expect(
      () => const IdentifiedDoctorPackageBuilder().build(
        identity: _identity(),
        clinicalRecord: _clinicalRecord(),
        result: _screeningResult(),
        consent: _consent(const {}),
      ),
      throwsStateError,
    );
  });

  test(
    'queues identified assessment package with assigned doctor after consent',
    () async {
      final queued = await const IdentifiedAssessmentDoctorPackageBuilder()
          .queue(
            database: database,
            identity: _identity(),
            clinicalRecord: _clinicalRecord(),
            assessment: _assessment(),
            consent: _consent(const {ConsentScope.doctorShare}),
            assignedDoctorUid: 'doctor-uid-1',
          );
      final items = await database.queuedSyncItems();

      expect(queued.kind, 'identified_assessment_doctor_package');
      expect(items.single.payload['assignedDoctorUid'], 'doctor-uid-1');
      expect(jsonEncode(items.single.payload), contains('Meera Kumar'));
      expect(jsonEncode(items.single.payload), contains('9999999999'));
    },
  );

  test('identified assessment package requires assigned doctor', () {
    expect(
      () => const IdentifiedAssessmentDoctorPackageBuilder().build(
        identity: _identity(),
        clinicalRecord: _clinicalRecord(),
        assessment: _assessment(),
        consent: _consent(const {ConsentScope.doctorShare}),
        assignedDoctorUid: '',
      ),
      throwsArgumentError,
    );
  });
}

FullAssessment _assessment() {
  return FullAssessment(
    visitId: 'visit-1',
    patientHash: 'patient-hash',
    createdAt: DateTime.utc(2026, 5, 3),
    siteResults: const [
      LesionSiteResult(
        siteId: 'left_buccal',
        siteLabel: 'Left buccal mucosa',
        suspicionScore: 0.86,
        findings: 'Red-white patch with growth.',
        roiImagePath: 'app/frames/left-roi.jpg',
        uncertain: false,
      ),
    ],
    hypotheses: const [
      HypothesisResult(
        label: 'Potentially malignant oral disorder',
        probability: 0.74,
        rationale: 'Suspicious appearance and risk exposure.',
      ),
    ],
    delta: const DeltaResult(
      summary: 'Lesion grew 4mm.',
      sizeChangeMm: 4,
      concernIncreased: true,
    ),
    carePlan: CarePlan(
      action: 'see_doctor_free',
      patientMessage: 'Visit the free doctor camp this week.',
      ashaMessage: 'Prepare referral package.',
      rescreenDate: DateTime.utc(2026, 5, 10),
      doctorBrief: 'Left buccal lesion with interval growth.',
    ),
    thinking: 'Model considered risk exposure and visual findings.',
    citations: const ['WHO oral cancer early detection guidance'],
  );
}

IdentityRecord _identity() => IdentityRecord(
  fullName: 'Meera Kumar',
  village: 'Kovilpatti',
  dateOfBirth: DateTime.utc(1978, 2, 12),
  phone: '9999999999',
  pinCode: '628501',
);

ClinicalRecord _clinicalRecord() => ClinicalRecord(
  id: 'clinical-1',
  patientHash: 'patient-hash',
  ageBand: '45-54',
  pinPrefix: '628',
  villageCode: 'kovilpatti',
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

ScreeningResult _screeningResult() => ScreeningResult(
  visitId: 'visit-1',
  patientHash: 'patient-hash',
  createdAt: DateTime.utc(2026, 5, 3, 9),
  riskLevel: 'high',
  siteResults: const [
    LesionSiteResult(
      siteId: 'left_buccal',
      siteLabel: 'Left buccal mucosa',
      suspicionScore: 0.82,
      findings: 'Irregular red-white patch.',
      roiImagePath: 'app/roi/left.jpg',
      uncertain: false,
    ),
  ],
  segmentation: const [
    SegmentationArtifact(
      siteId: 'left_buccal',
      roiImagePath: 'app/roi/left.jpg',
      maskPath: 'app/masks/left.png',
      lesionSizeMm: 9,
    ),
  ],
  differentials: const [
    HypothesisResult(
      label: 'Potentially malignant oral disorder',
      probability: 0.72,
      rationale: 'Visual change and exposure history.',
    ),
  ],
  uncertainty: 0.18,
  patientSummary: 'A doctor check is needed.',
  ashaSummary: 'Prepare referral.',
  doctorSummary: 'Left buccal lesion with elevated suspicion.',
  recommendedAction: 'see_doctor_free',
  modelName: 'gemma-4-E2B-it.litertlm',
);
