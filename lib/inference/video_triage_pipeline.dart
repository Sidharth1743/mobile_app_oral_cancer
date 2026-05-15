import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../capture/frame_selector.dart';
import '../data/local_database.dart';
import '../data/models.dart';
import 'gemma_service.dart';
import 'strict_json.dart';
import 'yolo_prefilter.dart';

const oralScreeningClassifierPrompt =
    'You are an oral screening assistant for cancer risk screening. '
    'Analyze this oral mucosal image. If there is any visible ulcer, white patch, '
    'red patch, pigmentation, irregular texture, raised area, or if the image is '
    'uncertain, choose refer_for_clinical_review. Return valid JSON only with keys '
    'category, recommendation, brief_reason, disclaimer. Categories: '
    'low_risk_or_variation or refer_for_clinical_review. Do not diagnose.';

String oralScreeningPromptForLanguage(String outputLanguage) {
  final language = outputLanguage.trim().isEmpty ? 'English' : outputLanguage;
  return '$oralScreeningClassifierPrompt '
      'Keep the JSON keys and category values exactly in English. '
      'Return recommendation, brief_reason, and disclaimer values in $language.';
}

typedef VideoTriageProgress = void Function(String message);

class VideoTriagePipeline {
  VideoTriagePipeline({
    required GemmaService gemmaService,
    required LocalDatabase database,
    required YoloPrefilter yoloPrefilter,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  }) : _gemmaService = gemmaService,
       _database = database,
       _yoloPrefilter = yoloPrefilter,
       _uuid = uuid,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final GemmaService _gemmaService;
  final LocalDatabase _database;
  final YoloPrefilter _yoloPrefilter;
  final Uuid _uuid;
  final DateTime Function() _clock;

  Future<FullAssessment> analyze({
    required ClinicalRecord clinicalRecord,
    required List<String> framePaths,
    int maxGemmaImages = 5,
    String outputLanguage = 'English',
    VideoTriageProgress? onProgress,
  }) async {
    if (framePaths.isEmpty) {
      throw ArgumentError.value(framePaths, 'framePaths', 'Must not be empty.');
    }

    final pipelineStarted = DateTime.now();
    final visitId = _uuid.v4();
    debugPrint(
      '[OralCancerPipeline] analyze_start visitId=$visitId '
      'frames=${framePaths.length} maxGemmaImages=$maxGemmaImages',
    );
    final tempDir = await getTemporaryDirectory();
    final gemmaInputDir = Directory(
      '${tempDir.path}/oral_cancer/$visitId/gemma_inputs',
    );
    onProgress?.call('Running YOLO prefilter');
    final prepared =
        await YoloGemmaInputPreparer(
          yolo: _yoloPrefilter,
          confidenceThreshold: 0.25,
          cropSize: 224,
        ).prepare(
          framePaths: framePaths,
          outputDirectory: gemmaInputDir,
          maxGemmaImages: maxGemmaImages,
        );

    final hasYoloCrop = prepared.any((input) => input.selection == 'yolo_crop');
    final oralFrameScores = prepared
        .map((input) => const FrameSelector().scoreFrame(input.gemmaImagePath))
        .toList();
    final hasValidOralFrame = oralFrameScores.any(_looksLikeOralFrame);
    for (var i = 0; i < oralFrameScores.length; i++) {
      final score = oralFrameScores[i];
      debugPrint(
        '[OralCancerPipeline] oral_gate_frame index=$i '
        'selection=${prepared[i].selection} '
        'oral=${score.oralColorScore.toStringAsFixed(3)} '
        'exposure=${score.exposureScore.toStringAsFixed(3)} '
        'blur=${score.blurScore.toStringAsFixed(3)} '
        'valid=${_looksLikeOralFrame(score)}',
      );
    }
    debugPrint(
      '[OralCancerPipeline] oral_gate_summary hasYoloCrop=$hasYoloCrop '
      'hasValidOralFrame=$hasValidOralFrame prepared=${prepared.length}',
    );
    if (!hasYoloCrop && !hasValidOralFrame) {
      onProgress?.call('No valid oral mucosa frame found');
      final assessment = _recaptureAssessment(
        clinicalRecord: clinicalRecord,
        visitId: visitId,
        prepared: prepared,
        oralFrameScores: oralFrameScores,
      );
      await _persistAssessment(
        clinicalRecord: clinicalRecord,
        assessment: assessment,
        framePaths: prepared.map((item) => item.gemmaImagePath).toList(),
      );
      debugPrint(
        '[OralCancerPipeline] analyze_done result=recapture_required '
        'elapsedMs=${DateTime.now().difference(pipelineStarted).inMilliseconds}',
      );
      return assessment;
    }

    final rawOutputs = <String>[];
    final parsedResults = <Map<String, Object?>>[];
    for (var index = 0; index < prepared.length; index++) {
      final input = prepared[index];
      debugPrint(
        '[OralCancerPipeline] gemma_frame_start index=$index '
        'selection=${input.selection} image=${input.gemmaImagePath}',
      );
      onProgress?.call(
        'Running Gemma on frame ${index + 1}/${prepared.length}',
      );
      final response = await _gemmaService.infer(
        GemmaRequest(
          prompt: oralScreeningPromptForLanguage(outputLanguage),
          imagePaths: [input.gemmaImagePath],
          maxTokens: 256,
          temperature: 0,
        ),
      );
      final raw = response.text;
      rawOutputs.add('[site:video_frame_${index + 1}] $raw');
      parsedResults.add(_parseClassifierOutput(raw));
      debugPrint(
        '[OralCancerPipeline] gemma_frame_done index=$index '
        'elapsedMs=${response.elapsed.inMilliseconds} '
        'category=${parsedResults.last['category']} rawChars=${raw.length}',
      );
    }

    final shouldRefer = parsedResults.any(
      (result) => result['category'] == 'refer_for_clinical_review',
    );
    final reasons = parsedResults
        .map((result) => (result['brief_reason'] as String? ?? '').trim())
        .where((reason) => reason.isNotEmpty)
        .toList();
    final recommendations = parsedResults
        .map((result) => (result['recommendation'] as String? ?? '').trim())
        .where((recommendation) => recommendation.isNotEmpty)
        .toList();
    final selectionSummary = prepared
        .map((item) => item.selection)
        .toSet()
        .join(', ');
    final reasonSummary = reasons.isEmpty
        ? 'The screening model returned a structured triage result.'
        : reasons.join(' ');
    final patientMessage = recommendations.isNotEmpty
        ? '${recommendations.first}\n\n$reasonSummary'
        : shouldRefer
        ? 'The video screening found visible or uncertain oral mucosal findings. Please get a clinical review.'
        : 'The video screening did not find a clear high-risk visual finding. Continue routine screening and seek care if symptoms persist.';

    final assessment = FullAssessment(
      visitId: visitId,
      patientHash: clinicalRecord.patientHash,
      createdAt: _clock(),
      siteResults: [
        LesionSiteResult(
          siteId: 'video_screening',
          siteLabel: 'Video screening',
          suspicionScore: shouldRefer ? 0.9 : 0.2,
          findings: reasonSummary,
          roiImagePath: prepared.first.gemmaImagePath,
          uncertain: parsedResults.any(
            (result) =>
                ((result['brief_reason'] as String? ?? '').toLowerCase())
                    .contains('uncertain'),
          ),
        ),
      ],
      hypotheses: [
        HypothesisResult(
          label: shouldRefer
              ? 'Refer for clinical review'
              : 'Low risk or normal variation',
          probability: shouldRefer ? 0.9 : 0.2,
          rationale: reasonSummary,
        ),
      ],
      delta: const DeltaResult(
        summary: 'No prior visit comparison was used for this video triage.',
        sizeChangeMm: 0,
        concernIncreased: false,
      ),
      carePlan: CarePlan(
        action: shouldRefer ? 'urgent_referral' : 'routine_rescreen',
        patientMessage: patientMessage,
        ashaMessage: shouldRefer
            ? 'Refer this patient for clinical review. The on-device Gemma classifier flagged at least one sampled frame.'
            : 'No immediate referral was flagged by the sampled-frame classifier. Continue routine follow-up.',
        rescreenDate: _clock().add(const Duration(days: 30)),
        doctorBrief:
            'On-device video triage using YOLO prefilter/fallback and Gemma classifier. Image selection modes: $selectionSummary. $reasonSummary',
      ),
      thinking:
          'Pipeline: video frames -> YOLO TFLite prefilter -> fallback full-frame crop if needed -> Gemma classifier JSON.',
      citations: const [],
      rawModelOutputs: rawOutputs,
    );

    await _persistAssessment(
      clinicalRecord: clinicalRecord,
      assessment: assessment,
      framePaths: prepared.map((item) => item.gemmaImagePath).toList(),
    );
    debugPrint(
      '[OralCancerPipeline] analyze_done result=${shouldRefer ? 'refer' : 'low_risk'} '
      'gemmaFrames=${prepared.length} elapsedMs=${DateTime.now().difference(pipelineStarted).inMilliseconds}',
    );
    return assessment;
  }

  bool _looksLikeOralFrame(FrameScore score) =>
      score.oralColorScore >= 0.18 &&
      score.exposureScore >= 0.45 &&
      score.blurScore >= 0.05;

  FullAssessment _recaptureAssessment({
    required ClinicalRecord clinicalRecord,
    required String visitId,
    required List<GemmaInputFrame> prepared,
    required List<FrameScore> oralFrameScores,
  }) {
    final createdAt = _clock();
    final scoreSummary = oralFrameScores
        .map(
          (score) =>
              'oral=${score.oralColorScore.toStringAsFixed(2)}, '
              'exposure=${score.exposureScore.toStringAsFixed(2)}, '
              'blur=${score.blurScore.toStringAsFixed(2)}',
        )
        .join('; ');
    return FullAssessment(
      visitId: visitId,
      patientHash: clinicalRecord.patientHash,
      createdAt: createdAt,
      siteResults: [
        LesionSiteResult(
          siteId: 'video_screening',
          siteLabel: 'Video screening',
          suspicionScore: 0,
          findings:
              'No valid oral mucosa frame was detected. Please recapture the video with the oral cavity clearly visible.',
          roiImagePath: prepared.isEmpty ? null : prepared.first.gemmaImagePath,
          uncertain: true,
        ),
      ],
      hypotheses: const [
        HypothesisResult(
          label: 'No valid oral mucosa frame',
          probability: 1,
          rationale:
              'The sampled frames did not pass the oral-frame validity gate, so Gemma was not run.',
        ),
      ],
      delta: const DeltaResult(
        summary: 'No prior visit comparison was used for this video triage.',
        sizeChangeMm: 0,
        concernIncreased: false,
      ),
      carePlan: CarePlan(
        action: 'recapture_required',
        patientMessage:
            'No valid oral cavity view was detected. Please recapture the video with the mouth open and oral mucosa clearly visible.',
        ashaMessage:
            'Recapture required. The app did not detect a usable oral mucosa frame, so clinical triage was not performed.',
        rescreenDate: createdAt,
        doctorBrief:
            'Video rejected before Gemma inference. YOLO found no crop and fallback frames failed oral-frame validation. Scores: $scoreSummary',
      ),
      thinking:
          'Pipeline stopped before Gemma: no YOLO crop and no fallback frame passed oral-mucosa validity checks.',
      citations: const [],
      rawModelOutputs: [
        '[site:video_screening] {"category":"recapture_required","recommendation":"recapture_required","brief_reason":"No valid oral mucosa frame was detected, so Gemma inference was skipped.","disclaimer":"This is an input-quality gate, not a diagnosis."}',
      ],
    );
  }

  Future<void> _persistAssessment({
    required ClinicalRecord clinicalRecord,
    required FullAssessment assessment,
    required List<String> framePaths,
  }) async {
    await _database.saveClinicalRecord(clinicalRecord);
    await _database.saveCapturedFrames(
      visitId: assessment.visitId,
      patientHash: clinicalRecord.patientHash,
      frames: CapturedSiteFrames(
        siteId: 'video_screening',
        siteLabel: 'Video screening',
        framePaths: framePaths,
        roiPath: framePaths.isEmpty ? null : framePaths.first,
        createdAt: assessment.createdAt,
      ),
    );
    await _database.saveVisit(assessment);
  }

  Map<String, Object?> _parseClassifierOutput(String raw) {
    try {
      final parsed = decodeJsonObject(raw);
      final category = parsed['category'];
      if (category == 'low_risk_or_variation' ||
          category == 'refer_for_clinical_review') {
        return parsed;
      }
    } catch (_) {
      // Invalid medical triage output should fail safe to review.
    }
    return {
      'category': 'refer_for_clinical_review',
      'recommendation': 'refer_for_clinical_review',
      'brief_reason':
          'The model output could not be parsed reliably, so this screening should be reviewed clinically.',
      'disclaimer':
          'This analysis is not a diagnosis and must be reviewed by a qualified clinician.',
    };
  }
}
