import 'dart:convert';

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
      thinkingParts.add(response.thinking);
      siteResults.add(
        LesionSiteResult.fromJson(decodeJsonObject(response.finalAnswer)),
      );
    }

    final differentialResponse = await _inferParsed(
      GemmaRequest(
        prompt: _promptBuilders.differentials(
          DifferentialPromptInput(
            clinicalRecord: clinicalRecord,
            siteResults: siteResults,
          ),
        ),
      ),
    );
    thinkingParts.add(differentialResponse.thinking);
    final differentialJson = decodeJsonObject(differentialResponse.finalAnswer);
    final hypotheses = decodeJsonObjectList(
      differentialJson['hypotheses'],
      'hypotheses',
    ).map(HypothesisResult.fromJson).toList();

    final deltaResponse = await _inferParsed(
      GemmaRequest(
        prompt: _promptBuilders.delta(
          DeltaPromptInput(
            currentSiteResults: siteResults,
            previousMeasurements: previousMeasurements,
          ),
        ),
      ),
    );
    thinkingParts.add(deltaResponse.thinking);
    final delta = DeltaResult.fromJson(
      decodeJsonObject(deltaResponse.finalAnswer),
    );

    final carePlanResponse = await _inferParsed(
      GemmaRequest(
        prompt: _promptBuilders.carePlan(
          CarePlanPromptInput(
            clinicalRecord: clinicalRecord,
            siteResults: siteResults,
            hypotheses: hypotheses,
            delta: delta,
          ),
        ),
      ),
    );
    thinkingParts.add(carePlanResponse.thinking);
    final carePlan = CarePlan.fromJson(
      decodeJsonObject(carePlanResponse.finalAnswer),
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
      citations: _citationsFromCarePlanResponse(carePlanResponse.finalAnswer),
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

  Future<GemmaParsedResponse> _inferParsed(GemmaRequest request) async {
    final raw = await _gemmaService.infer(request);
    return parseGemmaThinking(raw.text);
  }

  List<String> _citationsFromCarePlanResponse(String response) {
    final decoded = jsonDecode(response);
    if (decoded is! Map || decoded['citations'] == null) {
      return const [];
    }
    final citations = decoded['citations'];
    if (citations is! List) {
      throw const FormatException(
        'citations must be a JSON array when present.',
      );
    }
    return List<String>.from(citations);
  }
}
