import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/dashboard/dashboard_models.dart';
import 'package:oral_cancer/data/models.dart';
import 'package:oral_cancer/pipeline/screening_pipeline.dart';

void main() {
  test('builds aggregate NGO CSR metrics without patient identity', () {
    final metrics = DashboardMetrics.fromResults(
      [
        _result('a', 'high', 0.2),
        _result('b', 'urgent', 0.4),
        _result('c', 'low', 0.1),
      ],
      villageCodeByPatientHash: const {'a': 'v1', 'b': 'v1', 'c': 'v2'},
    );
    final encoded = jsonEncode(metrics.toJson());

    expect(metrics.totalScreenings, 3);
    expect(metrics.highRiskCount, 2);
    expect(metrics.urgentCount, 1);
    expect(metrics.averageUncertainty, closeTo(0.233, 0.001));
    expect(metrics.byVillageCode, {'v1': 2, 'v2': 1});
    expect(encoded, isNot(contains('fullName')));
    expect(encoded, isNot(contains('phone')));
  });
}

ScreeningResult _result(String patientHash, String risk, double uncertainty) =>
    ScreeningResult(
      visitId: 'visit-$patientHash',
      patientHash: patientHash,
      createdAt: DateTime.utc(2026, 5, 3),
      riskLevel: risk,
      siteResults: const [
        LesionSiteResult(
          siteId: 'left_buccal',
          siteLabel: 'Left buccal mucosa',
          suspicionScore: 0.7,
          findings: 'Finding.',
          roiImagePath: null,
          uncertain: false,
        ),
      ],
      segmentation: const [],
      differentials: const [],
      uncertainty: uncertainty,
      patientSummary: 'Summary.',
      ashaSummary: 'ASHA.',
      doctorSummary: 'Doctor.',
      recommendedAction: 'rescreen',
      modelName: 'gemma-4-E2B-it.litertlm',
    );
