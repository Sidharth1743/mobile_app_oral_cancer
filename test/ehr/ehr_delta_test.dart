import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/data/models.dart';
import 'package:oral_cancer/ehr/ehr_models.dart';
import 'package:oral_cancer/pipeline/screening_pipeline.dart';

void main() {
  test('loads ten EHR JSON visit outputs', () {
    final visits = _loadVisits();

    expect(visits, hasLength(10));
    expect(visits.map((visit) => visit.visitId).toSet(), hasLength(10));
    expect(
      visits.every((visit) => visit.patientHash == 'patient-hash'),
      isTrue,
    );
  });

  test('reports lesion growth and repeated high risk site', () {
    final report = const EhrDeltaCalculator().compare(
      current: _currentResult(),
      previousVisits: _loadVisits(),
    );

    final left = report.siteDeltas.singleWhere(
      (delta) => delta.siteId == 'left_buccal',
    );
    expect(left.previousSizeMm, 5);
    expect(left.currentSizeMm, 9);
    expect(left.sizeChangeMm, 4);
    expect(left.concernIncreased, isTrue);
    expect(report.repeatedHighRiskSite, isTrue);
    expect(report.summary, contains('4.0mm'));
  });
}

List<EhrVisit> _loadVisits() {
  return List.generate(10, (index) {
    final number = (index + 1).toString().padLeft(2, '0');
    final file = File('test/fixtures/ehr/visit_$number.json');
    return EhrVisit.fromJson(
      Map<String, Object?>.from(jsonDecode(file.readAsStringSync()) as Map),
    );
  });
}

ScreeningResult _currentResult() => ScreeningResult(
  visitId: 'current-visit',
  patientHash: 'patient-hash',
  createdAt: DateTime.utc(2026, 5, 3),
  riskLevel: 'high',
  siteResults: const [
    LesionSiteResult(
      siteId: 'left_buccal',
      siteLabel: 'Left buccal mucosa',
      suspicionScore: 0.84,
      findings: 'Irregular red-white patch.',
      roiImagePath: 'app/roi/current-left.jpg',
      uncertain: false,
    ),
  ],
  segmentation: const [
    SegmentationArtifact(
      siteId: 'left_buccal',
      roiImagePath: 'app/roi/current-left.jpg',
      maskPath: 'app/masks/current-left.png',
      lesionSizeMm: 9,
    ),
  ],
  differentials: const [
    HypothesisResult(
      label: 'Potentially malignant oral disorder',
      probability: 0.75,
      rationale: 'High suspicion and growth.',
    ),
  ],
  uncertainty: 0.2,
  patientSummary: 'A doctor check is needed.',
  ashaSummary: 'Refer to doctor.',
  doctorSummary: 'Interval growth in left buccal lesion.',
  recommendedAction: 'see_doctor_free',
  modelName: 'gemma-4-E2B-it.litertlm',
);
