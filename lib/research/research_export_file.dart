import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ResearchExportFileWriter {
  const ResearchExportFileWriter();

  Future<File> writeJson({
    required String visitId,
    required Map<String, Object?> export,
    Directory? directory,
  }) async {
    final targetDir =
        directory ??
        Directory(
          p.join(
            (await getApplicationDocumentsDirectory()).path,
            'research_exports',
          ),
        );
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final file = File(p.join(targetDir.path, '$visitId-research.json'));
    const encoder = JsonEncoder.withIndent('  ');
    return file.writeAsString(encoder.convert(export), flush: true);
  }
}
