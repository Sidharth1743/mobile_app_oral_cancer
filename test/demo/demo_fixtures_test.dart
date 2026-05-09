import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/demo/demo_fixtures.dart';

void main() {
  test('parses assessment and previous visit fixtures from asset files', () {
    final fixtures = DemoFixtures.fromJsonStrings(
      assessmentJson: File(DemoFixtures.assessmentAsset).readAsStringSync(),
      previousVisitJson: File(
        DemoFixtures.previousVisitAsset,
      ).readAsStringSync(),
    );

    expect(fixtures.assessment.visitId, 'demo-visit-2026-05-03');
    expect(fixtures.previousVisit.visitId, 'demo-visit-2026-04-03');
    expect(fixtures.assessment.delta.sizeChangeMm, 4.0);
    expect(fixtures.assessment.carePlan.action, 'see_doctor_free');
    expect(
      fixtures.assessment.siteResults.map((site) => site.roiImagePath),
      everyElement(isNotNull),
    );
  });

  test('fixture frame paths point to real dataset-derived asset files', () {
    final fixtures = DemoFixtures.fromJsonStrings(
      assessmentJson: File(DemoFixtures.assessmentAsset).readAsStringSync(),
      previousVisitJson: File(
        DemoFixtures.previousVisitAsset,
      ).readAsStringSync(),
    );

    for (final site in fixtures.assessment.siteResults) {
      final roiImagePath = site.roiImagePath;
      expect(roiImagePath, isNotNull);
      expect(
        File(roiImagePath!).existsSync(),
        isTrue,
        reason: '$roiImagePath must exist',
      );
      expect(File(roiImagePath).lengthSync(), greaterThan(0));
    }
  });

  test('rejects fixture mismatch between assessment and previous visit', () {
    final assessmentJson = File(
      DemoFixtures.assessmentAsset,
    ).readAsStringSync();
    final previousVisitJson = File(DemoFixtures.previousVisitAsset)
        .readAsStringSync()
        .replaceFirst(
          '9ed90f6a458bd18ac1bb0d4f4ccf3f655ab2ba79d2ee104f87cdd0e86a7f2a5c',
          'different-patient-hash',
        );

    expect(
      () => DemoFixtures.fromJsonStrings(
        assessmentJson: assessmentJson,
        previousVisitJson: previousVisitJson,
      ),
      throwsFormatException,
    );
  });
}
