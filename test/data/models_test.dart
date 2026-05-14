import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/data/models.dart';

void main() {
  test('full assessment round trips through JSON', () {
    final assessment = FullAssessment(
      visitId: 'visit-1',
      patientHash: 'hash-123',
      createdAt: DateTime.utc(2026, 5, 3),
      siteResults: const [
        LesionSiteResult(
          siteId: 'left_buccal',
          siteLabel: 'Left buccal mucosa',
          suspicionScore: 0.82,
          findings: 'Irregular red-white patch with induration concern.',
          roiImagePath: 'assets/demo/frames/left_buccal.png',
          uncertain: false,
        ),
      ],
      hypotheses: const [
        HypothesisResult(
          label: 'Potentially malignant oral disorder',
          probability: 0.71,
          rationale:
              'High-risk habit history and persistent lesion appearance.',
        ),
      ],
      delta: const DeltaResult(
        summary: 'Lesion grew 4mm since previous visit.',
        sizeChangeMm: 4,
        concernIncreased: true,
      ),
      carePlan: CarePlan(
        action: 'see_doctor_free',
        patientMessage: 'Please visit the free doctor camp this week.',
        ashaMessage: 'Prioritize referral and prepare anonymized package.',
        rescreenDate: DateTime.utc(2026, 5, 10),
        doctorBrief: 'Suspicious left buccal lesion; referral recommended.',
      ),
      thinking: 'Model considered site findings, history, and interval growth.',
      citations: const ['WHO oral potentially malignant disorders guidance'],
    );

    final encoded = assessment.toJsonString();
    final decoded = FullAssessment.fromJsonString(encoded);

    expect(decoded.visitId, assessment.visitId);
    expect(decoded.siteResults.single.siteId, 'left_buccal');
    expect(decoded.hypotheses.single.probability, 0.71);
    expect(decoded.delta.sizeChangeMm, 4);
    expect(decoded.carePlan.action, 'see_doctor_free');
    expect(jsonDecode(encoded), isA<Map<String, Object?>>());
  });

  test('clinical record keeps only de-identified fields', () {
    final record = ClinicalRecord(
      id: 'clinical-1',
      patientHash: 'sha256-hash',
      ageBand: '45-54',
      pinPrefix: '600',
      villageCode: 'village-a',
      gender: 'female',
      tobaccoBrand: 'Hans',
      chewsPerDay: 6,
      yearsUsed: 12,
      alcoholUse: false,
      cei: 0.67,
      createdAt: DateTime.utc(2026, 5, 3),
      coords: const GeoCoords(latitude: 13.08, longitude: 80.27),
    );

    final json = record.toJson();

    expect(json, isNot(contains('fullName')));
    expect(json, isNot(contains('phone')));
    expect(json, isNot(contains('dateOfBirth')));
    expect(json['pinPrefix'], '600');
    expect(ClinicalRecord.fromJson(json).coords?.latitude, 13.08);
  });

  test('model result parsers coerce common LiteRT JSON scalar variants', () {
    final site = LesionSiteResult.fromJson({
      'siteId': 'left_buccal',
      'siteLabel': 'Left buccal mucosa',
      'suspicionScore': '0.82',
      'findings': 'Visible white patch.',
      'roiImagePath': 'roi.jpg',
      'uncertain': 'false',
    });
    final delta = DeltaResult.fromJson({
      'summary': 'Change noted.',
      'sizeChangeMm': '2.5mm',
      'concernIncreased': 'true',
    });

    expect(site.suspicionScore, 0.82);
    expect(site.uncertain, isFalse);
    expect(delta.sizeChangeMm, 2.5);
    expect(delta.concernIncreased, isTrue);
  });
}
