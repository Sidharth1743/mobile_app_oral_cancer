import 'dart:io';

import 'package:image/image.dart' as img;

import 'yolo_prefilter.dart';

/// Draws YOLO boxes on a frame and writes a JPEG preview [outputPath].
Future<void> writeAnnotatedFramePreview({
  required String sourceFramePath,
  required String outputPath,
  required List<YoloDetection> detections,
}) async {
  final bytes = await File(sourceFramePath).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw FormatException('Could not decode image.', sourceFramePath);
  }
  final annotated = img.Image.from(decoded);
  for (var i = 0; i < detections.length; i++) {
    final detection = detections[i];
    final color = i == 0 ? img.ColorRgb8(0, 220, 80) : img.ColorRgb8(255, 180, 0);
    final x1 = detection.x1.round().clamp(0, annotated.width - 1);
    final y1 = detection.y1.round().clamp(0, annotated.height - 1);
    final x2 = detection.x2.round().clamp(0, annotated.width - 1);
    final y2 = detection.y2.round().clamp(0, annotated.height - 1);
    img.drawRect(
      annotated,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      color: color,
      thickness: 3,
    );
    img.drawString(
      annotated,
      i == 0 ? '#1' : '#${i + 1}',
      font: img.arial14,
      x: x1,
      y: y1 > 16 ? y1 - 16 : y1,
      color: color,
    );
  }
  await File(outputPath).writeAsBytes(img.encodeJpg(annotated, quality: 92));
}
