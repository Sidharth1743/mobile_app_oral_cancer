import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/research/research_export_file.dart';

void main() {
  test('writes research export JSON to supplied directory', () async {
    final dir = await Directory.systemTemp.createTemp('research_export_test_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final file = await const ResearchExportFileWriter().writeJson(
      visitId: 'visit-1',
      directory: dir,
      export: const {'studyPatientId': 'study-id', 'ageBand': '45-54'},
    );
    final decoded = jsonDecode(await file.readAsString()) as Map;

    expect(file.path, endsWith('visit-1-research.json'));
    expect(decoded['studyPatientId'], 'study-id');
    expect(decoded, isNot(contains('fullName')));
  });
}
