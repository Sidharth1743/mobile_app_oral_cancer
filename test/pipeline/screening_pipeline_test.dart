import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/data/models.dart';
import 'package:oral_cancer/ehr/ehr_models.dart';
import 'package:oral_cancer/pipeline/screening_pipeline.dart';

void main() {
  test(
    'screening input preserves identity for local offline model context',
    () {
      final input = ScreeningInput(
        visitId: 'visit-1',
        identity: _identity(),
        clinicalRecord: _clinicalRecord(),
        videoPathsBySite: const {
          'left_buccal': '/data/user/0/app/videos/left.mp4',
          'tongue': '/data/user/0/app/videos/tongue.mp4',
        },
        previousVisits: [
          EhrVisit(
            visitId: 'ehr-1',
            patientHash: 'patient-hash',
            createdAt: DateTime.utc(2026, 4, 1),
            siteMeasurements: [
              EhrSiteMeasurement(
                siteId: 'left_buccal',
                siteLabel: 'Left buccal mucosa',
                lesionSizeMm: 5,
                riskLevel: 'medium',
                recordedAt: DateTime.utc(2026, 4, 1),
              ),
            ],
            doctorSummary: 'Earlier lesion measured.',
          ),
        ],
      );

      final decoded = ScreeningInput.fromJson(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(input.toJson())) as Map,
        ),
      );

      expect(decoded.identity.fullName, 'Meera Kumar');
      expect(decoded.videoPathsBySite['left_buccal'], endsWith('left.mp4'));
      expect(
        decoded.previousVisits.single.siteMeasurements.single.lesionSizeMm,
        5,
      );
    },
  );

  test(
    'screening result contract carries segmentation and Gemma result fields',
    () {
      final result = _screeningResult();
      final decoded = ScreeningResult.fromJson(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(result.toJson())) as Map,
        ),
      );

      expect(decoded.modelName, 'gemma-4-E2B-it.litertlm');
      expect(decoded.segmentation.single.maskPath, 'app/masks/left.png');
      expect(decoded.differentials.single.label, contains('malignant'));
      expect(decoded.recommendedAction, 'see_doctor_free');
    },
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

ScreeningResult _screeningResult() => ScreeningResult(
  visitId: 'visit-1',
  patientHash: 'patient-hash',
  createdAt: DateTime.utc(2026, 5, 3),
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
