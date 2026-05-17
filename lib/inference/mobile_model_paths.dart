import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves on-device model file paths for Android.
///
/// Prefers [String.fromEnvironment] overrides, then files under the app's
/// private `files/models/` directory (same place [push_model_to_phone.sh]
/// stages artifacts), then external storage, and finally legacy `/sdcard/...`
/// defaults.
class MobileModelPaths {
  const MobileModelPaths._();

  static const _gemmaCandidates = <String>[
    'gemma-4-E2B-it-final.litertlm',
    'model.litertlm',
    'gemma-4-E2B-it.litertlm',
  ];

  static const _yoloCandidates = <String>[
    'yolo11n_lesion_best_640_int8.tflite',
  ];

  static Future<String> resolveGemmaPath() async {
    const envPath = String.fromEnvironment('LITERT_MODEL_PATH');
    if (envPath.isNotEmpty) {
      final existing = await _firstExisting([envPath]);
      if (existing != null) {
        return existing;
      }
    }

    final staged =
        await _resolveFromAppFilesModelsDir(_gemmaCandidates) ??
        await _resolveFromExternalModelsDir(_gemmaCandidates) ??
        await _resolveFromSupportModelsDir(_gemmaCandidates);
    if (staged != null) {
      return staged;
    }

    return _legacyGemmaPath();
  }

  static Future<String> resolveYoloPath() async {
    const envPath = String.fromEnvironment('YOLO_MODEL_PATH');
    if (envPath.isNotEmpty) {
      final existing = await _firstExisting([envPath]);
      if (existing != null) {
        return existing;
      }
    }

    final staged =
        await _resolveFromAppFilesModelsDir(_yoloCandidates) ??
        await _resolveFromExternalModelsDir(_yoloCandidates) ??
        await _resolveFromSupportModelsDir(_yoloCandidates);
    if (staged != null) {
      return staged;
    }

    return _legacyYoloPath();
  }

  /// Same location as [push_model_to_phone.sh] (`files/models` via run-as).
  static Future<String?> _resolveFromAppFilesModelsDir(
    List<String> fileNames,
  ) async {
    if (kIsWeb || !Platform.isAndroid) {
      return null;
    }

    final filesDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(filesDir.path, 'models'));
    final candidates = fileNames
        .map((name) => p.join(modelsDir.path, name))
        .toList(growable: false);
    return _firstExisting(candidates);
  }

  static Future<String?> _resolveFromSupportModelsDir(
    List<String> fileNames,
  ) async {
    if (kIsWeb || !Platform.isAndroid) {
      return null;
    }

    final supportDir = await getApplicationSupportDirectory();
    final modelsDir = Directory(p.join(supportDir.path, 'models'));
    final candidates = fileNames
        .map((name) => p.join(modelsDir.path, name))
        .toList(growable: false);
    return _firstExisting(candidates);
  }

  static Future<String?> _resolveFromExternalModelsDir(
    List<String> fileNames,
  ) async {
    if (kIsWeb || !Platform.isAndroid) {
      return null;
    }

    final externalDir = await getExternalStorageDirectory();
    if (externalDir == null) {
      return null;
    }

    final modelsDir = Directory(p.join(externalDir.path, 'models'));
    final candidates = fileNames
        .map((name) => p.join(modelsDir.path, name))
        .toList(growable: false);
    return _firstExisting(candidates);
  }

  static Future<String?> _firstExisting(List<String> paths) async {
    for (final path in paths) {
      if (path.trim().isEmpty) {
        continue;
      }
      if (await File(path).exists()) {
        return path;
      }
    }
    return null;
  }

  static String _legacyGemmaPath() {
    return const String.fromEnvironment(
      'LITERT_MODEL_PATH',
      defaultValue:
          '/sdcard/Android/data/com.example.oral_cancer/files/models/gemma-4-E2B-it-final.litertlm',
    );
  }

  static String _legacyYoloPath() {
    return const String.fromEnvironment(
      'YOLO_MODEL_PATH',
      defaultValue:
          '/sdcard/Android/data/com.example.oral_cancer/files/models/yolo11n_lesion_best_640_int8.tflite',
    );
  }
}
