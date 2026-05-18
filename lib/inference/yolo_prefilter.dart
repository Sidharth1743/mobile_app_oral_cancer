import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../debug/yolo_debug_capture.dart';

class YoloDetection {
  const YoloDetection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double confidence;

  factory YoloDetection.fromJson(Map<Object?, Object?> json) => YoloDetection(
    x1: (json['x1'] as num).toDouble(),
    y1: (json['y1'] as num).toDouble(),
    x2: (json['x2'] as num).toDouble(),
    y2: (json['y2'] as num).toDouble(),
    confidence: (json['confidence'] as num).toDouble(),
  );
}

class YoloPrefilter {
  const YoloPrefilter({
    required String modelPath,
    MethodChannel channel = const MethodChannel('oral_cancer/yolo_prefilter'),
  }) : _modelPath = modelPath,
       _channel = channel;

  final String _modelPath;
  final MethodChannel _channel;

  Future<List<YoloDetection>> detect({
    required String imagePath,
    double confidenceThreshold = 0.25,
    double iouThreshold = 0.45,
    int inputSize = 640,
    int maxDetections = 10,
  }) async {
    try {
      final started = DateTime.now();
      debugPrint(
        '[OralCancerYOLO][Dart] detect_start image=$imagePath '
        'conf=$confidenceThreshold inputSize=$inputSize model=$_modelPath',
      );
      final result = await _channel.invokeListMethod<Object?>('detect', {
        'modelPath': _modelPath,
        'imagePath': imagePath,
        'confidenceThreshold': confidenceThreshold,
        'iouThreshold': iouThreshold,
        'inputSize': inputSize,
        'maxDetections': maxDetections,
      });
      final detections = (result ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(YoloDetection.fromJson)
          .toList();
      debugPrint(
        '[OralCancerYOLO][Dart] detect_done elapsedMs=${DateTime.now().difference(started).inMilliseconds} '
        'detections=${detections.length} best=${detections.isEmpty ? 'none' : detections.first.confidence.toStringAsFixed(3)}',
      );
      return detections;
    } on MissingPluginException {
      if (!kIsWeb &&
          (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
        return const [];
      }
      rethrow;
    }
  }

  Future<void> close() async {
    try {
      await _channel.invokeMethod<void>('close');
      debugPrint('[OralCancerYOLO][Dart] interpreter_closed');
    } on MissingPluginException {
      return;
    }
  }
}

class GemmaInputFrame {
  const GemmaInputFrame({
    required this.sourceFramePath,
    required this.gemmaImagePath,
    required this.selection,
    this.detection,
  });

  final String sourceFramePath;
  final String gemmaImagePath;
  final String selection;
  final YoloDetection? detection;
}

class YoloGemmaInputPreparer {
  const YoloGemmaInputPreparer({
    required YoloPrefilter yolo,
    this.confidenceThreshold = 0.25,
    this.paddingFraction = 0.20,
    this.cropSize = 224,
  }) : _yolo = yolo;

  final YoloPrefilter _yolo;
  final double confidenceThreshold;
  final double paddingFraction;
  final int cropSize;

  Future<List<GemmaInputFrame>> prepare({
    required List<String> framePaths,
    required Directory outputDirectory,
    int maxGemmaImages = 5,
    String? debugSessionId,
  }) async {
    if (framePaths.isEmpty) {
      throw ArgumentError.value(framePaths, 'framePaths', 'Must not be empty.');
    }
    if (maxGemmaImages <= 0) {
      throw ArgumentError.value(
        maxGemmaImages,
        'maxGemmaImages',
        'Must be positive.',
      );
    }
    await outputDirectory.create(recursive: true);
    debugPrint(
      '[OralCancerPipeline] prepare_start frames=${framePaths.length} '
      'maxGemmaImages=$maxGemmaImages outputDir=${outputDirectory.path}',
    );

    final selected = <GemmaInputFrame>[];
    for (var frameIndex = 0; frameIndex < framePaths.length; frameIndex++) {
      if (selected.length >= maxGemmaImages) break;
      final framePath = framePaths[frameIndex];
      final detections = await _yolo.detect(
        imagePath: framePath,
        confidenceThreshold: confidenceThreshold,
        maxDetections: YoloDebugCapture.enabled ? 10 : 1,
      );
      final detection = detections.isEmpty ? null : detections.first;
      final source = _decodeImage(framePath);
      final crop = detection == null
          ? source
          : _cropWithPadding(source, detection, paddingFraction);
      final outputPath = p.join(
        outputDirectory.path,
        '${p.basenameWithoutExtension(framePath)}_${detection == null ? 'fallback' : 'yolo'}.jpg',
      );
      _writeGemmaImage(crop, outputPath, cropSize);
      debugPrint(
        '[OralCancerPipeline] prepare_frame index=$frameIndex '
        'selection=${detection == null ? 'fallback_full_frame' : 'yolo_crop'} '
        'detections=${detections.length} output=$outputPath',
      );
      final selection = detection == null ? 'fallback_full_frame' : 'yolo_crop';
      selected.add(
        GemmaInputFrame(
          sourceFramePath: framePath,
          gemmaImagePath: outputPath,
          selection: selection,
          detection: detection,
        ),
      );
      if (YoloDebugCapture.enabled && debugSessionId != null) {
        await YoloDebugCapture.recordFrame(
          sessionId: debugSessionId,
          frameIndex: frameIndex,
          sourceFramePath: framePath,
          gemmaImagePath: outputPath,
          selection: selection,
          detections: detections,
        );
      }
    }
    debugPrint('[OralCancerPipeline] prepare_done selected=${selected.length}');
    return selected;
  }

  img.Image _decodeImage(String path) {
    final decoded = img.decodeImage(File(path).readAsBytesSync());
    if (decoded == null) {
      throw FormatException('Could not decode image.', path);
    }
    return decoded;
  }

  img.Image _cropWithPadding(
    img.Image source,
    YoloDetection detection,
    double padding,
  ) {
    final width = detection.x2 - detection.x1;
    final height = detection.y2 - detection.y1;
    final pad = max(width, height) * padding;
    final x1 = max(0, (detection.x1 - pad).round());
    final y1 = max(0, (detection.y1 - pad).round());
    final x2 = min(source.width, (detection.x2 + pad).round());
    final y2 = min(source.height, (detection.y2 + pad).round());
    return img.copyCrop(source, x: x1, y: y1, width: x2 - x1, height: y2 - y1);
  }

  void _writeGemmaImage(img.Image image, String outputPath, int size) {
    final resized = img.copyResize(
      image,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    );
    File(outputPath).writeAsBytesSync(img.encodeJpg(resized, quality: 92));
  }
}
