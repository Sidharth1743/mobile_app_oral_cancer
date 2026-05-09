import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/cloud/cloud_sync_planner.dart';
import 'package:oral_cancer/consent/consent.dart';
import 'package:oral_cancer/pipeline/screening_pipeline.dart';

void main() {
  test('doctor share plan uploads ROI and mask after consent', () {
    final plan = const CloudSyncPlanner().doctorSharePlan(
      caseId: 'case-1',
      result: _result(),
      consent: _consent(const {ConsentScope.doctorShare}),
    );

    expect(plan.caseId, 'case-1');
    expect(plan.visitId, 'visit-1');
    expect(plan.uploads, hasLength(2));
    expect(plan.uploads.map((upload) => upload.kind), [
      'roiImage',
      'segmentationMask',
    ]);
    expect(
      plan.uploads.first.storagePath,
      'cases/case-1/visit-1/roi/left_buccal.jpg',
    );
    expect(
      plan.uploads.last.storagePath,
      'cases/case-1/visit-1/masks/left_buccal.png',
    );
  });

  test('doctor share plan is blocked without doctor consent', () {
    expect(
      () => const CloudSyncPlanner().doctorSharePlan(
        caseId: 'case-1',
        result: _result(),
        consent: _consent(const {ConsentScope.researchExport}),
      ),
      throwsStateError,
    );
  });
}

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
