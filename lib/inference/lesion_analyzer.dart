import 'package:uuid/uuid.dart';

import '../data/local_database.dart';
import '../data/models.dart';
import 'gemma_service.dart';
import 'prompts.dart';
import 'strict_json.dart';

class LesionAnalyzer {
  LesionAnalyzer({
    required GemmaService gemmaService,
    required LocalDatabase database,
    PromptBuilders promptBuilders = const PromptBuilders(),
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  }) : _gemmaService = gemmaService,
       _database = database,
       _promptBuilders = promptBuilders,
       _uuid = uuid,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final GemmaService _gemmaService;
  final LocalDatabase _database;
  final PromptBuilders _promptBuilders;
  final Uuid _uuid;
  final DateTime Function() _clock;

  Future<FullAssessment> analyze({
    required ClinicalRecord clinicalRecord,
    required List<CapturedSiteFrames> capturedSites,
    required List<Map<String, Object?>> previousMeasurements,
  }) async {
    if (capturedSites.isEmpty) {
      throw ArgumentError.value(
        capturedSites,
        'capturedSites',
        'At least one captured site is required.',
      );
    }

    final siteResults = <LesionSiteResult>[];
    final thinkingParts = <String>[];
    final rawOutputs = <String>[];

    for (final site in capturedSites) {
      final prompt = _promptBuilders.siteAssessment(
        SiteAssessmentPromptInput(
          clinicalRecord: clinicalRecord,
          frames: site,
          previousMeasurements: previousMeasurements,
        ),
      );
      final response = await _inferParsed(
        GemmaRequest(prompt: prompt, imagePaths: site.framePaths),
      );
      rawOutputs.add('[site:${site.siteId}] ${response.raw}');
      thinkingParts.add(response.thinking);
      siteResults.add(_siteResultFromResponse(site, response.finalAnswer));
    }

    final hypotheses = _rankHypotheses(clinicalRecord, siteResults);
    final delta = _computeDelta(siteResults, previousMeasurements);
    final carePlan = _buildCarePlan(siteResults, hypotheses, delta);
    const citations = <String>[];
    thinkingParts.add(
      'Image-site model outputs parsed. Differential, interval change, and care plan computed by deterministic local rules.',
    );

    final assessment = FullAssessment(
      visitId: _uuid.v4(),
      patientHash: clinicalRecord.patientHash,
      createdAt: _clock(),
      siteResults: siteResults,
      hypotheses: hypotheses,
      delta: delta,
      carePlan: carePlan,
      thinking: thinkingParts
          .where((part) => part.trim().isNotEmpty)
          .join('\n\n'),
      citations: citations,
      rawModelOutputs: rawOutputs,
    );

    await _database.saveClinicalRecord(clinicalRecord);
    for (final site in capturedSites) {
      await _database.saveCapturedFrames(
        visitId: assessment.visitId,
        patientHash: clinicalRecord.patientHash,
        frames: site,
      );
    }
    await _database.saveVisit(assessment);
    return assessment;
  }

  Future<_ParsedWithRaw> _inferParsed(GemmaRequest request) async {
    final raw = await _gemmaService.infer(request);
    final parsed = parseGemmaThinking(raw.text);
    return _ParsedWithRaw(raw: raw.text, parsed: parsed);
  }

  LesionSiteResult _siteResultFromResponse(
    CapturedSiteFrames site,
    String response,
  ) {
    final json = _decodeSiteResponseObject(response);
    final directJson = json['siteAssessment'] is Map
        ? Map<String, Object?>.from(json['siteAssessment'] as Map)
        : json;
    if (directJson.containsKey('suspicionScore')) {
      return LesionSiteResult.fromJson({
        ...directJson,
        'siteId': directJson['siteId'] ?? site.siteId,
        'siteLabel': directJson['siteLabel'] ?? site.siteLabel,
        'roiImagePath':
            directJson['roiImagePath'] ??
            site.roiPath ??
            (site.framePaths.isEmpty ? null : site.framePaths.first),
      });
    }

    final category = _categoryFromSiteJson(directJson);
    if (category != 'low_risk_or_variation' &&
        category != 'refer_for_clinical_review') {
      throw FormatException('Unexpected site assessment category: $category.');
    }
    final refer = category == 'refer_for_clinical_review';
    final reason = _stringValue(directJson['brief_reason']).isEmpty
        ? _stringValue(directJson['recommendation'])
        : _stringValue(directJson['brief_reason']);
    return LesionSiteResult(
      siteId: site.siteId,
      siteLabel: site.siteLabel,
      suspicionScore: refer ? 0.85 : 0.2,
      findings: reason.isEmpty
          ? (refer
                ? 'Model marked this site for clinical review.'
                : 'Model marked this site as low risk or normal variation.')
          : reason,
      roiImagePath:
          site.roiPath ??
          (site.framePaths.isEmpty ? null : site.framePaths.first),
      uncertain: false,
    );
  }

  Map<String, Object?> _decodeSiteResponseObject(String response) {
    try {
      return decodeJsonObject(response);
    } on FormatException {
      final category = _categoryFromRawText(response);
      if (category.isEmpty) {
        rethrow;
      }
      return {
        'category': category,
        'brief_reason': _fieldFromRawText(response, 'brief_reason'),
        'recommendation': category,
        'disclaimer': _fieldFromRawText(response, 'disclaimer'),
      };
    }
  }

  List<HypothesisResult> _rankHypotheses(
    ClinicalRecord clinicalRecord,
    List<LesionSiteResult> siteResults,
  ) {
    final maxScore = siteResults
        .map((site) => site.suspicionScore)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final anyUncertain = siteResults.any((site) => site.uncertain);
    final exposureBoost =
        clinicalRecord.chewsPerDay > 0 ||
        clinicalRecord.yearsUsed > 0 ||
        clinicalRecord.alcoholUse;
    if (maxScore >= 0.75) {
      return [
        HypothesisResult(
          label: 'refer_for_clinical_review',
          probability: exposureBoost ? 0.86 : 0.78,
          rationale:
              'At least one oral site was classified for clinical review by the local image model.',
        ),
      ];
    }
    if (anyUncertain) {
      return const [
        HypothesisResult(
          label: 'uncertain_findings_refer',
          probability: 0.7,
          rationale: 'One or more sites are uncertain and need manual review.',
        ),
      ];
    }
    return [
      const HypothesisResult(
        label: 'low_risk_or_variation',
        probability: 0.8,
        rationale:
            'No captured site crossed the clinical-review threshold in local image analysis.',
      ),
    ];
  }

  DeltaResult _computeDelta(
    List<LesionSiteResult> siteResults,
    List<Map<String, Object?>> previousMeasurements,
  ) {
    if (previousMeasurements.isEmpty) {
      return const DeltaResult(
        summary: 'No previous visit measurements are available for comparison.',
        sizeChangeMm: 0,
        concernIncreased: false,
      );
    }
    final currentMaxScore = siteResults
        .map((site) => site.suspicionScore)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final previousMaxScore = previousMeasurements
        .map((entry) => _doubleValue(entry['suspicionScore'] ?? entry['score']))
        .fold<double>(0, (a, b) => a > b ? a : b);
    final scoreChange = currentMaxScore - previousMaxScore;
    return DeltaResult(
      summary: scoreChange > 0.15
          ? 'Concern increased compared with the previous visit.'
          : 'No meaningful increase from previous visit score.',
      sizeChangeMm: 0,
      concernIncreased: scoreChange > 0.15,
    );
  }

  CarePlan _buildCarePlan(
    List<LesionSiteResult> siteResults,
    List<HypothesisResult> hypotheses,
    DeltaResult delta,
  ) {
    final maxScore = siteResults
        .map((site) => site.suspicionScore)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final reviewNeeded =
        maxScore >= 0.75 ||
        delta.concernIncreased ||
        hypotheses.any((item) => item.label.contains('refer'));
    final rescreenDate = _clock().add(Duration(days: reviewNeeded ? 14 : 90));
    if (!reviewNeeded) {
      return CarePlan(
        action: 'rescreen',
        patientMessage:
            'No urgent warning sign was found today. Please return for the next screening visit.',
        ashaMessage:
            'Schedule routine rescreening and advise the patient to return earlier if symptoms appear.',
        rescreenDate: rescreenDate,
        doctorBrief:
            'Local image screening did not cross the clinical-review threshold.',
      );
    }
    return CarePlan(
      action: 'see_doctor_free',
      patientMessage:
          'Please visit the free doctor review. This screening result needs clinical checking.',
      ashaMessage:
          'Prepare the doctor package and help the patient attend clinical review.',
      rescreenDate: rescreenDate,
      doctorBrief:
          'At least one oral site crossed the local screening threshold for clinical review.',
    );
  }

  String _stringValue(Object? value) => value is String ? value.trim() : '';

  String _categoryFromSiteJson(Map<String, Object?> json) {
    final category = _stringValue(json['category']).toLowerCase();
    if (category.isNotEmpty) {
      return category;
    }
    final recommendation = _stringValue(json['recommendation']).toLowerCase();
    if (recommendation == 'low_risk_or_variation' ||
        recommendation == 'refer_for_clinical_review') {
      return recommendation;
    }
    if (recommendation.contains('refer_for_clinical_review') ||
        recommendation.contains('refer') ||
        recommendation.contains('review')) {
      return 'refer_for_clinical_review';
    }
    if (recommendation.contains('low_risk_or_variation') ||
        recommendation.contains('low risk') ||
        recommendation.contains('no immediate concern')) {
      return 'low_risk_or_variation';
    }
    return '';
  }

  String _categoryFromRawText(String source) {
    final normalized = source.toLowerCase();
    final match = RegExp(
      r'\\?"(?:category|recommendation)\\?"\s*:\s*\\?"(low_risk_or_variation|refer_for_clinical_review)\\?"',
      caseSensitive: false,
    ).firstMatch(source);
    final exact = match?.group(1)?.toLowerCase();
    if (exact != null) {
      return exact;
    }
    if (normalized.contains('refer for clinical review') ||
        normalized.contains('warrants further clinical') ||
        normalized.contains('requires clinical') ||
        normalized.contains('area of concern')) {
      return 'refer_for_clinical_review';
    }
    final lowRiskSignals = [
      'no significant concern',
      'no immediate concern',
      'no concern noted',
      'no evidence of ulceration',
      'no evidence of',
      'no discernible irregularities',
      'healthy',
      'smooth and uniform',
    ];
    final hasLowRiskSignal = lowRiskSignals.any(normalized.contains);
    final hasReviewSignal =
        normalized.contains('clinical review') ||
        normalized.contains('warrants') ||
        normalized.contains('requires');
    if (hasLowRiskSignal && !hasReviewSignal) {
      return 'low_risk_or_variation';
    }
    return '';
  }

  String _fieldFromRawText(String source, String field) {
    final escaped = RegExp.escape(field);
    final match = RegExp(
      '\\\\?"$escaped\\\\?"\\s*:\\s*\\\\?"([^"\\\\]*)',
      caseSensitive: false,
    ).firstMatch(source);
    return match?.group(1)?.trim() ?? '';
  }

  double _doubleValue(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value);
      if (match != null) {
        return double.parse(match.group(0)!);
      }
    }
    return 0;
  }
}

class _ParsedWithRaw {
  _ParsedWithRaw({required this.raw, required GemmaParsedResponse parsed})
    : thinking = parsed.thinking,
      finalAnswer = parsed.finalAnswer;

  final String raw;
  final String thinking;
  final String finalAnswer;
}
