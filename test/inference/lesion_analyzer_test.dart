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

  test('runs Gemma prompts in sequence and saves complete visit', () async {
    final service = SequencedGemmaService([
      _boxed({
        'siteId': 'left_buccal',
        'siteLabel': 'Left buccal mucosa',
        'suspicionScore': 0.82,
        'findings': 'Red-white patch with irregular border.',
        'roiImagePath': 'app/frames/left-roi.jpg',
        'uncertain': false,
      }),
      _boxed({
        'hypotheses': [
          {
            'label': 'Potentially malignant oral disorder',
            'probability': 0.77,
            'rationale': 'High-risk exposure and suspicious morphology.',
          },
        ],
      }),
      _boxed({
        'summary': 'Lesion grew 4mm since last visit.',
        'sizeChangeMm': 4.0,
        'concernIncreased': true,
      }),
      _boxed({
        'action': 'see_doctor_free',
        'patientMessage': 'Visit the free doctor camp this week.',
        'ashaMessage': 'Prepare referral package.',
        'rescreenDate': '2026-05-10T00:00:00.000Z',
        'doctorBrief': 'Left buccal lesion with interval growth.',
        'citations': ['WHO oral cancer early detection guidance'],
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

    expect(service.prompts, hasLength(4));
    expect(service.prompts[0], contains('site_assessment'));
    expect(service.prompts[1], contains('rank_differentials'));
    expect(service.prompts[2], contains('interval_change'));
    expect(service.prompts[3], contains('care_plan'));
    expect(savedVisit?.carePlan.action, 'see_doctor_free');
    expect(savedVisit?.citations, ['WHO oral cancer early detection guidance']);
    expect(savedFrames.single.siteId, 'left_buccal');
  });

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

String _boxed(Map<String, Object?> json) =>
    '<think>reasoning</think>${jsonEncode(json)}';

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
