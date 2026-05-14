import 'dart:convert';

import '../data/models.dart';

class SiteAssessmentPromptInput {
  const SiteAssessmentPromptInput({
    required this.clinicalRecord,
    required this.frames,
    required this.previousMeasurements,
  });

  final ClinicalRecord clinicalRecord;
  final CapturedSiteFrames frames;
  final List<Map<String, Object?>> previousMeasurements;
}

class DifferentialPromptInput {
  const DifferentialPromptInput({
    required this.clinicalRecord,
    required this.siteResults,
  });

  final ClinicalRecord clinicalRecord;
  final List<LesionSiteResult> siteResults;
}

class CarePlanPromptInput {
  const CarePlanPromptInput({
    required this.clinicalRecord,
    required this.siteResults,
    required this.hypotheses,
    required this.delta,
  });

  final ClinicalRecord clinicalRecord;
  final List<LesionSiteResult> siteResults;
  final List<HypothesisResult> hypotheses;
  final DeltaResult delta;
}

class DeltaPromptInput {
  const DeltaPromptInput({
    required this.currentSiteResults,
    required this.previousMeasurements,
  });

  final List<LesionSiteResult> currentSiteResults;
  final List<Map<String, Object?>> previousMeasurements;
}

class PromptBuilders {
  const PromptBuilders();

  String siteAssessment(SiteAssessmentPromptInput input) {
    final payload = {
      'task': 'site_assessment',
      'siteId': input.frames.siteId,
      'siteLabel': input.frames.siteLabel,
      'requiredJsonFields': [
        'category',
        'recommendation',
        'brief_reason',
        'disclaimer',
      ],
      'categories': ['low_risk_or_variation', 'refer_for_clinical_review'],
    };
    return _compactPrompt(
      role: 'Analyze this cropped oral mucosal image.',
      payload: payload,
      outputRule:
          'Choose exactly one category. If visible ulcer, white patch, red patch, pigmentation, irregular texture, raised area, or uncertainty exists, choose refer_for_clinical_review. Return only one compact JSON object with category, recommendation, brief_reason, disclaimer. Do not add observation/image/result keys. Do not diagnose.',
    );
  }

  String differentials(DifferentialPromptInput input) {
    final payload = {
      'task': 'rank_differentials',
      'risk': {
        'ageBand': input.clinicalRecord.ageBand,
        'gender': input.clinicalRecord.gender,
        'chewsPerDay': input.clinicalRecord.chewsPerDay,
        'yearsUsed': input.clinicalRecord.yearsUsed,
        'alcoholUse': input.clinicalRecord.alcoholUse,
        'cei': input.clinicalRecord.cei,
      },
      'sites': input.siteResults
          .map(
            (site) => {
              'siteId': site.siteId,
              'score': site.suspicionScore,
              'uncertain': site.uncertain,
            },
          )
          .toList(),
      'requiredJsonFields': ['hypotheses'],
    };
    return _compactPrompt(
      role: 'Rank likely differentials.',
      payload: payload,
      outputRule: 'Return JSON only. hypotheses sorted by probability desc.',
    );
  }

  String carePlan(CarePlanPromptInput input) {
    final payload = {
      'task': 'care_plan',
      'risk': {
        'ageBand': input.clinicalRecord.ageBand,
        'gender': input.clinicalRecord.gender,
        'chewsPerDay': input.clinicalRecord.chewsPerDay,
        'yearsUsed': input.clinicalRecord.yearsUsed,
        'alcoholUse': input.clinicalRecord.alcoholUse,
        'cei': input.clinicalRecord.cei,
      },
      'sites': input.siteResults
          .map(
            (site) => {
              'siteId': site.siteId,
              'score': site.suspicionScore,
              'uncertain': site.uncertain,
            },
          )
          .toList(),
      'hypotheses': input.hypotheses
          .take(3)
          .map(
            (hypothesis) => {
              'label': hypothesis.label,
              'probability': hypothesis.probability,
            },
          )
          .toList(),
      'delta': {
        'sizeChangeMm': input.delta.sizeChangeMm,
        'concernIncreased': input.delta.concernIncreased,
      },
      'allowedActions': [
        'reassure',
        'rescreen',
        'see_doctor_free',
        'urgent_referral',
      ],
      'requiredJsonFields': [
        'action',
        'patientMessage',
        'ashaMessage',
        'rescreenDate',
        'doctorBrief',
      ],
    };
    return _compactPrompt(
      role: 'Create care plan.',
      payload: payload,
      outputRule: 'Return JSON only. Messages concise. No identity fields.',
    );
  }

  String delta(DeltaPromptInput input) {
    final payload = {
      'task': 'interval_change',
      'sites': input.currentSiteResults
          .map(
            (site) => {
              'siteId': site.siteId,
              'score': site.suspicionScore,
              'uncertain': site.uncertain,
            },
          )
          .toList(),
      'previous': input.previousMeasurements
          .map(
            (entry) => {
              'siteId': entry['siteId'],
              'sizeMm': entry['sizeMm'],
              'score': entry['suspicionScore'],
            },
          )
          .toList(),
      'requiredJsonFields': ['summary', 'sizeChangeMm', 'concernIncreased'],
    };
    return _compactPrompt(
      role: 'Compare interval change.',
      payload: payload,
      outputRule: 'Return JSON only.',
    );
  }

  String _compactPrompt({
    required String role,
    required Map<String, Object?> payload,
    required String outputRule,
  }) {
    return [
      'You are oral screening assistant.',
      role,
      'Use payload only.',
      'No identity data.',
      outputRule,
      jsonEncode(payload),
    ].join('\n\n');
  }
}
