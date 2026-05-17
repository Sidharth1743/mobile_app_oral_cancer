import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Saves Gemma / LiteRT raw text to disk in debug builds for adb pull to a dev PC.
class RawModelOutputCapture {
  const RawModelOutputCapture._();

  static const enabled = kDebugMode;

  static Future<Directory?> captureDirectory() async {
    if (!enabled) {
      return null;
    }
    if (kIsWeb) {
      return null;
    }
    try {
      Directory base;
      if (Platform.isAndroid) {
        base = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
      } else {
        base = await getApplicationDocumentsDirectory();
      }
      final dir = Directory(p.join(base.path, 'debug', 'raw_outputs'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (error, stack) {
      debugPrint('[RawModelOutputCapture] directory error: $error\n$stack');
      return null;
    }
  }

  static Future<void> recordInference({
    required String label,
    required String prompt,
    required List<String> imagePaths,
    required String rawText,
    required String modelName,
    required Duration elapsed,
  }) async {
    if (!enabled) {
      return;
    }
    final dir = await captureDirectory();
    if (dir == null) {
      return;
    }
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final safeLabel = label.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    final file = File(p.join(dir.path, '${stamp}_$safeLabel.txt'));
    final body = '''
=== Oral Gemma raw inference (debug) ===
capturedAt: ${DateTime.now().toUtc().toIso8601String()}
label: $label
model: $modelName
elapsedMs: ${elapsed.inMilliseconds}
imageCount: ${imagePaths.length}
images:
${imagePaths.map((path) => '  - $path').join('\n')}

--- prompt ---
$prompt

--- raw model response ---
$rawText
''';
    try {
      await file.writeAsString(body);
      await _appendManifest(
        dir,
        RawCaptureManifestEntry(
          fileName: p.basename(file.path),
          label: label,
          capturedAt: DateTime.now().toUtc(),
          chars: rawText.length,
          modelName: modelName,
        ),
      );
      debugPrint(
        '[RawModelOutputCapture] wrote ${file.path} (${rawText.length} chars)',
      );
    } catch (error, stack) {
      debugPrint('[RawModelOutputCapture] write error: $error\n$stack');
    }
  }

  static Future<void> recordAssessmentBundle({
    required String visitId,
    required List<String> rawModelOutputs,
    String? carePlanAction,
  }) async {
    if (!enabled || rawModelOutputs.isEmpty) {
      return;
    }
    final dir = await captureDirectory();
    if (dir == null) {
      return;
    }
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final file = File(p.join(dir.path, '${stamp}_assessment_$visitId.txt'));
    final sections = <String>[
      '=== Oral Gemma assessment bundle (debug) ===',
      'capturedAt: ${DateTime.now().toUtc().toIso8601String()}',
      'visitId: $visitId',
      if (carePlanAction != null) 'carePlanAction: $carePlanAction',
      'outputCount: ${rawModelOutputs.length}',
      '',
    ];
    for (var i = 0; i < rawModelOutputs.length; i++) {
      sections.add('--- output ${i + 1} / ${rawModelOutputs.length} ---');
      sections.add(rawModelOutputs[i]);
      sections.add('');
    }
    try {
      await file.writeAsString(sections.join('\n'));
      await _appendManifest(
        dir,
        RawCaptureManifestEntry(
          fileName: p.basename(file.path),
          label: 'assessment_$visitId',
          capturedAt: DateTime.now().toUtc(),
          chars: rawModelOutputs.join().length,
          modelName: 'bundle',
        ),
      );
      debugPrint('[RawModelOutputCapture] assessment bundle ${file.path}');
    } catch (error, stack) {
      debugPrint('[RawModelOutputCapture] bundle error: $error\n$stack');
    }
  }

  static Future<void> _appendManifest(
    Directory dir,
    RawCaptureManifestEntry entry,
  ) async {
    final manifestFile = File(p.join(dir.path, 'manifest.json'));
    final existing = <Map<String, Object?>>[];
    if (await manifestFile.exists()) {
      try {
        final decoded = jsonDecode(await manifestFile.readAsString());
        if (decoded is List) {
          existing.addAll(
            decoded.whereType<Map>().map(Map<String, Object?>.from),
          );
        }
      } catch (_) {
        // Overwrite corrupt manifest.
      }
    }
    existing.insert(0, entry.toJson());
    final trimmed = existing.take(200).toList();
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(trimmed),
    );
    await File(p.join(dir.path, 'LATEST.txt')).writeAsString(
      'Most recent: ${entry.fileName}\nPull folder to PC: ./scripts/pull_raw_model_outputs.sh\n',
    );
  }
}

class RawCaptureManifestEntry {
  const RawCaptureManifestEntry({
    required this.fileName,
    required this.label,
    required this.capturedAt,
    required this.chars,
    required this.modelName,
  });

  final String fileName;
  final String label;
  final DateTime capturedAt;
  final int chars;
  final String modelName;

  Map<String, Object?> toJson() => {
    'fileName': fileName,
    'label': label,
    'capturedAt': capturedAt.toIso8601String(),
    'chars': chars,
    'modelName': modelName,
  };
}
