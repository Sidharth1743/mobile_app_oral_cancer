import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/consent/consent.dart';
import 'package:oral_cancer/data/models.dart';
import 'package:oral_cancer/pipeline/screening_pipeline.dart';
import 'package:oral_cancer/research/research_export.dart';

void main() {
  test('exports de-identified research row only after research consent', () {
    final export = const ResearchExporter().export(
      identity: _identity(),
      clinicalRecord: _clinicalRecord(),
      result: _result(),
      consent: _consent(const {ConsentScope.researchExport}),
      studySecret: 'secret-a',
    );
    final encoded = jsonEncode(export);

    expect(export['studyPatientId'], hasLength(64));
    expect(export['ageBand'], '45-54');
    expect(export['pinPrefix'], '628');
    expect(encoded, isNot(contains('Meera')));
    expect(encoded, isNot(contains('9999999999')));
    expect(encoded, isNot(contains('628501')));
  });

  test(
    'research pseudonym changes with study secret and rejects missing consent',
    () {
      final exporter = const ResearchExporter();
      final first = exporter.export(
        identity: _identity(),
        clinicalRecord: _clinicalRecord(),
        result: _result(),
        consent: _consent(const {ConsentScope.researchExport}),
        studySecret: 'secret-a',
      );
      final second = exporter.export(
        identity: _identity(),
        clinicalRecord: _clinicalRecord(),
        result: _result(),
        consent: _consent(const {ConsentScope.researchExport}),
        studySecret: 'secret-b',
      );

      expect(first['studyPatientId'], isNot(second['studyPatientId']));
      expect(
        () => exporter.export(
          identity: _identity(),
          clinicalRecord: _clinicalRecord(),
          result: _result(),
          consent: _consent(const {}),
          studySecret: 'secret-a',
        ),
        throwsStateError,
      );
    },
  );

  test('exports current assessment row without direct identifiers', () {
    final export = const AssessmentResearchExporter().export(
      identity: _identity(),
      clinicalRecord: _clinicalRecord(),
      assessment: _assessment(),
      consent: _consent(const {ConsentScope.researchExport}),
      studySecret: 'secret-a',
    );
    final encoded = jsonEncode(export);

    expect(export['studyPatientId'], hasLength(64));
    expect(export['carePlanAction'], 'see_doctor_free');
    expect(export['deltaSizeChangeMm'], 4);
    expect(encoded, isNot(contains('Meera')));
    expect(encoded, isNot(contains('9999999999')));
    expect(encoded, isNot(contains('628501')));
  });

  test('assessment export rejects mismatched consent', () {
    expect(
      () => const AssessmentResearchExporter().export(
        identity: _identity(),
        clinicalRecord: _clinicalRecord(),
        assessment: _assessment(),
        consent: ConsentRecord(
          visitId: 'other-visit',
          patientHash: 'patient-hash',
          scopes: const {ConsentScope.researchExport},
          recordedAt: DateTime.utc(2026, 5, 3, 10),
          policyVersion: '2026-05',
          screeningCompletedAt: DateTime.utc(2026, 5, 3, 9),
        ),
        studySecret: 'secret-a',
      ),
      throwsStateError,
    );
  });
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

ScreeningResult _result() => ScreeningResult(
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
  differentials: const [],
  uncertainty: 0.18,
  patientSummary: 'A doctor check is needed.',
  ashaSummary: 'Prepare referral.',
  doctorSummary: 'Left buccal lesion with elevated suspicion.',
  recommendedAction: 'see_doctor_free',
  modelName: 'gemma-4-E2B-it.litertlm',
);

FullAssessment _assessment() => FullAssessment(
  visitId: 'visit-1',
  patientHash: 'patient-hash',
  createdAt: DateTime.utc(2026, 5, 3, 9),
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
  hypotheses: const [
    HypothesisResult(
      label: 'Potentially malignant oral disorder',
      probability: 0.72,
      rationale: 'Visual change and exposure history.',
    ),
  ],
  delta: const DeltaResult(
    summary: 'Lesion grew 4mm.',
    sizeChangeMm: 4,
    concernIncreased: true,
  ),
  carePlan: CarePlan(
    action: 'see_doctor_free',
    patientMessage: 'A doctor check is needed.',
    ashaMessage: 'Prepare referral.',
    doctorBrief: 'Left buccal lesion with elevated suspicion.',
    rescreenDate: DateTime.utc(2026, 5, 10),
  ),
  thinking: 'Model reasoning.',
  citations: const [],
);
