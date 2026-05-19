import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../inference/yolo_frame_annotation.dart';
import '../inference/yolo_prefilter.dart';

/// Saves YOLO boxes, annotated frames, and Gemma crops in debug builds (adb pull to PC).
class YoloDebugCapture {
  const YoloDebugCapture._();

  static const enabled = kDebugMode;

  static Future<Directory?> captureDirectory() async {
    if (!enabled || kIsWeb) {
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
      final dir = Directory(p.join(base.path, 'debug', 'yolo_outputs'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (error, stack) {
      debugPrint('[YoloDebugCapture] directory error: $error\n$stack');
      return null;
    }
  }

  static Future<void> recordFrame({
    required String sessionId,
    required int frameIndex,
    required String sourceFramePath,
    required String gemmaImagePath,
    required String selection,
    required List<YoloDetection> detections,
  }) async {
    if (!enabled) {
      return;
    }
    final root = await captureDirectory();
    if (root == null) {
      return;
    }

    final safeSession = sessionId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    final frameDir = Directory(
      p.join(root.path, safeSession, 'frame_${frameIndex.toString().padLeft(4, '0')}'),
    );
    await frameDir.create(recursive: true);

    try {
      await File(p.join(frameDir.path, 'source.jpg')).writeAsBytes(
        await File(sourceFramePath).readAsBytes(),
      );

      await writeAnnotatedFramePreview(
        sourceFramePath: sourceFramePath,
        outputPath: p.join(frameDir.path, 'annotated_boxes.jpg'),
        detections: detections,
      );

      await File(
        p.join(frameDir.path, 'gemma_input.jpg'),
      ).writeAsBytes(await File(gemmaImagePath).readAsBytes());

      final meta = {
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'sessionId': sessionId,
        'frameIndex': frameIndex,
        'sourceFramePath': sourceFramePath,
        'gemmaImagePath': gemmaImagePath,
        'selection': selection,
        'detectionCount': detections.length,
        'detections': detections
            .map(
              (d) => {
                'x1': d.x1,
                'y1': d.y1,
                'x2': d.x2,
                'y2': d.y2,
                'confidence': d.confidence,
                'width': d.x2 - d.x1,
                'height': d.y2 - d.y1,
              },
            )
            .toList(),
      };
      await File(p.join(frameDir.path, 'meta.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(meta),
      );

      await _appendSessionManifest(root, safeSession, frameIndex, meta);

      debugPrint(
        '[YoloDebugCapture] saved frame $frameIndex '
        'detections=${detections.length} dir=${frameDir.path}',
      );
    } catch (error, stack) {
      debugPrint('[YoloDebugCapture] record error: $error\n$stack');
    }
  }

  static Future<void> _appendSessionManifest(
    Directory root,
    String sessionId,
    int frameIndex,
    Map<String, Object?> frameMeta,
  ) async {
    final sessionDir = Directory(p.join(root.path, sessionId));
    final manifestFile = File(p.join(sessionDir.path, 'manifest.json'));
    final existing = <Map<String, Object?>>[];
    if (await manifestFile.exists()) {
      try {
        final decoded = jsonDecode(await manifestFile.readAsString());
        if (decoded is List) {
          existing.addAll(
            decoded.whereType<Map>().map(Map<String, Object?>.from),
          );
        }
      } catch (_) {}
    }
    existing.add({
      'frameIndex': frameIndex,
      'selection': frameMeta['selection'],
      'detectionCount': frameMeta['detectionCount'],
      'folder': 'frame_${frameIndex.toString().padLeft(4, '0')}',
    });
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(existing),
    );
    await File(p.join(root.path, 'LATEST.txt')).writeAsString(
      'Session: $sessionId\n'
      'Pull to PC: ./scripts/pull_yolo_debug_outputs.sh\n'
      'Files per frame: source.jpg, annotated_boxes.jpg, gemma_input.jpg, meta.json\n',
    );
  }
}
