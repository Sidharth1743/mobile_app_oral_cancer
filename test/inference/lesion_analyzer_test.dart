import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/data/local_database.dart';
import 'package:oral_cancer/data/models.dart';
import 'package:oral_cancer/inference/gemma_service.dart';
import 'package:oral_cancer/inference/lesion_analyzer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LocalDatabase database;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('runs site image Gemma prompt and saves complete visit', () async {
    final service = SequencedGemmaService([
      _fenced({
        'category': 'refer_for_clinical_review',
        'recommendation': 'Refer to clinician.',
        'brief_reason': 'Irregular red-white area requires clinical review.',
        'disclaimer': 'Screening support only.',
      }),
    ]);
    final analyzer = LesionAnalyzer(
      gemmaService: service,
      database: database,
      clock: () => DateTime.utc(2026, 5, 3, 10),
    );

    final assessment = await analyzer.analyze(
      clinicalRecord: _clinicalRecord(),
      capturedSites: [
        CapturedSiteFrames(
          siteId: 'left_buccal',
          siteLabel: 'Left buccal mucosa',
          framePaths: const ['app/frames/left-1.jpg'],
          roiPath: 'app/frames/left-roi.jpg',
          createdAt: DateTime.utc(2026, 5, 3, 9),
        ),
      ],
      previousMeasurements: const [
        {'siteId': 'left_buccal', 'largestDiameterMm': 9.0},
      ],
    );

    final savedVisit = await database.visitById(assessment.visitId);
    final savedFrames = await database.capturedFramesForVisit(
      assessment.visitId,
    );

    expect(service.prompts, hasLength(1));
    expect(service.prompts[0], contains('site_assessment'));
    expect(savedVisit?.carePlan.action, 'see_doctor_free');
    expect(savedVisit?.citations, isEmpty);
    expect(savedVisit?.siteResults.single.suspicionScore, 0.85);
    expect(savedVisit?.siteResults.single.findings, contains('Irregular'));
    expect(savedVisit?.hypotheses.single.label, 'refer_for_clinical_review');
    expect(savedFrames.single.siteId, 'left_buccal');
  });

  test(
    'accepts LiteRT site output with category in recommendation field',
    () async {
      final service = SequencedGemmaService([
        _fenced({
          'site': 'left_buccal',
          'recommendation': 'refer_for_clinical_review',
          'brief_reason': 'Visible mucosal change should be reviewed.',
          'disclaimer': 'Screening support only.',
        }),
      ]);
      final analyzer = LesionAnalyzer(
        gemmaService: service,
        database: database,
        clock: () => DateTime.utc(2026, 5, 3, 10),
      );

      final assessment = await analyzer.analyze(
        clinicalRecord: _clinicalRecord(),
        capturedSites: [
          CapturedSiteFrames(
            siteId: 'left_buccal',
            siteLabel: 'Left buccal mucosa',
            framePaths: const ['app/frames/left-1.jpg'],
            createdAt: DateTime.utc(2026, 5, 3, 9),
          ),
        ],
        previousMeasurements: const [],
      );

      expect(assessment.siteResults.single.suspicionScore, 0.85);
      expect(assessment.carePlan.action, 'see_doctor_free');
    },
  );

  test(
    'recovers allowed category from truncated escaped LiteRT JSON',
    () async {
      final service = SequencedGemmaService([
        r'''```json
{"result":"{\"category\":\"low_risk_or_variation\",\"recommendation\":\"No immediate concern noted.\",\"brief_reason\":\"Normal anatomical variation.\",\"disclaimer\":\"Screening only.\",\"image\":\"[image''',
      ]);
      final analyzer = LesionAnalyzer(
        gemmaService: service,
        database: database,
        clock: () => DateTime.utc(2026, 5, 3, 10),
      );

      final assessment = await analyzer.analyze(
        clinicalRecord: _clinicalRecord(),
        capturedSites: [
          CapturedSiteFrames(
            siteId: 'left_buccal',
            siteLabel: 'Left buccal mucosa',
            framePaths: const ['app/frames/left-1.jpg'],
            createdAt: DateTime.utc(2026, 5, 3, 9),
          ),
        ],
        previousMeasurements: const [],
      );

      expect(assessment.siteResults.single.suspicionScore, 0.2);
      expect(
        assessment.siteResults.single.findings,
        'Normal anatomical variation.',
      );
      expect(assessment.carePlan.action, 'rescreen');
    },
  );

  test(
    'recovers low-risk category from explicit no-concern observation',
    () async {
      final service = SequencedGemmaService([
        r'''```json
{"site":"oral_mucosal","observation":"The mucosa appears healthy, smooth and uniform, with no evidence of ulceration, white patches, redness, pigmentation, or areas of concern. The texture is''',
      ]);
      final analyzer = LesionAnalyzer(
        gemmaService: service,
        database: database,
        clock: () => DateTime.utc(2026, 5, 3, 10),
      );

      final assessment = await analyzer.analyze(
        clinicalRecord: _clinicalRecord(),
        capturedSites: [
          CapturedSiteFrames(
            siteId: 'left_buccal',
            siteLabel: 'Left buccal mucosa',
            framePaths: const ['app/frames/left-1.jpg'],
            createdAt: DateTime.utc(2026, 5, 3, 9),
          ),
        ],
        previousMeasurements: const [],
      );

      expect(assessment.siteResults.single.suspicionScore, 0.2);
      expect(assessment.carePlan.action, 'rescreen');
    },
  );

  test('rejects empty capture list before calling Gemma', () async {
    final service = SequencedGemmaService([]);
    final analyzer = LesionAnalyzer(gemmaService: service, database: database);

    expect(
      () => analyzer.analyze(
        clinicalRecord: _clinicalRecord(),
        capturedSites: const [],
        previousMeasurements: const [],
      ),
      throwsArgumentError,
    );
    expect(service.prompts, isEmpty);
  });
}

String _fenced(Map<String, Object?> json) =>
    '<think>reasoning</think>```json\n${jsonEncode(json)}\n```';

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

class SequencedGemmaService implements GemmaService {
  SequencedGemmaService(this._responses);

  final List<String> _responses;
  final List<String> prompts = [];

  @override
  Future<GemmaRawResponse> infer(GemmaRequest request) async {
    prompts.add(request.prompt);
    if (prompts.length > _responses.length) {
      throw StateError('No test response for prompt ${prompts.length}.');
    }
    return GemmaRawResponse(
      text: _responses[prompts.length - 1],
      modelName: 'test-gemma',
      elapsed: Duration.zero,
    );
  }
}
