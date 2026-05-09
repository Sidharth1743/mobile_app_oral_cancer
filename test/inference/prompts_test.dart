import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/data/models.dart';
import 'package:oral_cancer/inference/prompts.dart';

void main() {
  const builders = PromptBuilders();

  test('site prompt contains required fields and no identity fields', () {
    final prompt = builders.siteAssessment(
      SiteAssessmentPromptInput(
        clinicalRecord: _clinicalRecord(),
        frames: CapturedSiteFrames(
          siteId: 'left_buccal',
          siteLabel: 'Left buccal mucosa',
          framePaths: const ['app/frames/left-1.jpg'],
          roiPath: 'app/frames/left-roi.jpg',
          createdAt: DateTime.utc(2026, 5, 3),
        ),
        previousMeasurements: const [
          {'siteId': 'left_buccal', 'largestDiameterMm': 9.0},
        ],
      ),
    );

    final payload = _payloadFromPrompt(prompt);

    expect(prompt, contains('site_assessment'));
    expect(prompt, contains('suspicionScore'));
    expect(payload['task'], 'site_assessment');
    final clinicalRecord = Map<String, Object?>.from(
      payload['clinicalRecord'] as Map,
    );
    expect(clinicalRecord, isNot(contains('fullName')));
    expect(clinicalRecord, isNot(contains('phone')));
    expect(clinicalRecord, isNot(contains('dateOfBirth')));
  });

  test('differential, delta, and care-plan prompts are strict JSON tasks', () {
    final siteResults = [
      const LesionSiteResult(
        siteId: 'left_buccal',
        siteLabel: 'Left buccal mucosa',
        suspicionScore: 0.86,
        findings: 'Red-white patch with interval growth.',
        roiImagePath: 'app/frames/left-roi.jpg',
        uncertain: false,
      ),
    ];
    final hypotheses = [
      const HypothesisResult(
        label: 'Potentially malignant oral disorder',
        probability: 0.74,
        rationale: 'High-risk exposure and lesion morphology.',
      ),
    ];
    final delta = const DeltaResult(
      summary: 'Lesion grew 4mm.',
      sizeChangeMm: 4,
      concernIncreased: true,
    );

    final differentialPrompt = builders.differentials(
      DifferentialPromptInput(
        clinicalRecord: _clinicalRecord(),
        siteResults: siteResults,
      ),
    );
    final deltaPrompt = builders.delta(
      DeltaPromptInput(
        currentSiteResults: siteResults,
        previousMeasurements: const [
          {'siteId': 'left_buccal', 'largestDiameterMm': 9.0},
        ],
      ),
    );
    final carePlanPrompt = builders.carePlan(
      CarePlanPromptInput(
        clinicalRecord: _clinicalRecord(),
        siteResults: siteResults,
        hypotheses: hypotheses,
        delta: delta,
      ),
    );

    expect(
      _payloadFromPrompt(differentialPrompt)['task'],
      'rank_differentials',
    );
    expect(_payloadFromPrompt(deltaPrompt)['task'], 'interval_change');
    expect(_payloadFromPrompt(carePlanPrompt)['task'], 'care_plan');
    expect(carePlanPrompt, contains('Do not include identity fields'));
    expect(carePlanPrompt, contains('see_doctor_free'));
  });
}

Map<String, Object?> _payloadFromPrompt(String prompt) {
  final payloadText = prompt.split('\n\n').last;
  return Map<String, Object?>.from(jsonDecode(payloadText) as Map);
}

ClinicalRecord _clinicalRecord() {
  return ClinicalRecord(
    id: 'clinical-1',
    patientHash: 'patient-hash',
    ageBand: '48-57',
    pinPrefix: '600',
    villageCode: 'abc123def456',
    gender: 'female',
    tobaccoBrand: 'Hans',
    chewsPerDay: 8,
    yearsUsed: 20,
    alcoholUse: false,
    cei: 0.27,
    createdAt: DateTime.utc(2026, 5, 3),
  );
}
