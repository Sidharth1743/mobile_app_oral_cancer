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
      'site': input.frames.toJson(),
      'clinicalRecord': input.clinicalRecord.toJson(),
      'previousMeasurements': input.previousMeasurements,
      'requiredJsonFields': [
        'siteId',
        'siteLabel',
        'suspicionScore',
        'findings',
        'roiImagePath',
        'uncertain',
      ],
    };
    return _prompt(
      role:
          'Assess one oral cavity site from selected frames and de-identified risk data.',
      payload: payload,
      outputRule: 'Return one strict JSON object matching requiredJsonFields.',
    );
  }

  String differentials(DifferentialPromptInput input) {
    final payload = {
      'task': 'rank_differentials',
      'clinicalRecord': input.clinicalRecord.toJson(),
      'siteResults': input.siteResults.map((site) => site.toJson()).toList(),
      'requiredJsonFields': ['hypotheses'],
    };
    return _prompt(
      role:
          'Rank oral lesion differential hypotheses using de-identified data only.',
      payload: payload,
      outputRule:
          'Return strict JSON with hypotheses sorted by probability descending.',
    );
  }

  String carePlan(CarePlanPromptInput input) {
    final payload = {
      'task': 'care_plan',
      'clinicalRecord': input.clinicalRecord.toJson(),
      'siteResults': input.siteResults.map((site) => site.toJson()).toList(),
      'hypotheses': input.hypotheses
          .map((hypothesis) => hypothesis.toJson())
          .toList(),
      'delta': input.delta.toJson(),
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
    return _prompt(
      role:
          'Create patient, ASHA, and doctor outputs for an oral cancer screening visit.',
      payload: payload,
      outputRule:
          'Return strict JSON for the care plan. Do not include identity fields.',
    );
  }

  String delta(DeltaPromptInput input) {
    final payload = {
      'task': 'interval_change',
      'currentSiteResults': input.currentSiteResults
          .map((site) => site.toJson())
          .toList(),
      'previousMeasurements': input.previousMeasurements,
      'requiredJsonFields': ['summary', 'sizeChangeMm', 'concernIncreased'],
    };
    return _prompt(
      role:
          'Compare current screening findings with previous de-identified measurements.',
      payload: payload,
      outputRule: 'Return strict JSON describing interval change.',
    );
  }

  String _prompt({
    required String role,
    required Map<String, Object?> payload,
    required String outputRule,
  }) {
    return [
      'You are an on-device oral cancer screening assistant for an ASHA workflow.',
      role,
      'Use only the de-identified JSON payload below.',
      'Never request, infer, or emit patient name, phone number, exact DOB, or full PIN code.',
      outputRule,
      jsonEncode(payload),
    ].join('\n\n');
  }
}
