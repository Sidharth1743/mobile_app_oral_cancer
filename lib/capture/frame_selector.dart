import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

class FrameScore {
  const FrameScore({
    required this.path,
    required this.score,
    required this.blurScore,
    required this.exposureScore,
    required this.oralColorScore,
  });

  final String path;
  final double score;
  final double blurScore;
  final double exposureScore;
  final double oralColorScore;
}

class FrameSelector {
  const FrameSelector();

  List<FrameScore> rankFrames(List<String> framePaths) {
    if (framePaths.isEmpty) {
      throw ArgumentError.value(
        framePaths,
        'framePaths',
        'At least one frame is required.',
      );
    }
    final scores = framePaths.map(scoreFrame).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scores;
  }

  List<String> selectBestFrames(List<String> framePaths, {int count = 3}) {
    if (count <= 0) {
      throw ArgumentError.value(count, 'count', 'Must be positive.');
    }
    return rankFrames(
      framePaths,
    ).take(count).map((score) => score.path).toList();
  }

  FrameScore scoreFrame(String path) {
    final bytes = File(path).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw FormatException('Could not decode image frame.', path);
    }
    final resized = img.copyResize(image, width: min(160, image.width));
    final blur = _blurScore(resized);
    final exposure = _exposureScore(resized);
    final oralColor = _oralColorScore(resized);
    final score = (blur * 0.45) + (exposure * 0.25) + (oralColor * 0.30);
    return FrameScore(
      path: path,
      score: score.clamp(0.0, 1.0),
      blurScore: blur,
      exposureScore: exposure,
      oralColorScore: oralColor,
    );
  }

  double _blurScore(img.Image image) {
    var total = 0.0;
    var count = 0;
    for (var y = 1; y < image.height - 1; y++) {
      for (var x = 1; x < image.width - 1; x++) {
        final center = _luma(image.getPixel(x, y));
        final laplacian =
            (4 * center) -
            _luma(image.getPixel(x - 1, y)) -
            _luma(image.getPixel(x + 1, y)) -
            _luma(image.getPixel(x, y - 1)) -
            _luma(image.getPixel(x, y + 1));
        total += laplacian.abs();
        count++;
      }
    }
    if (count == 0) {
      return 0;
    }
    return (total / count / 55).clamp(0.0, 1.0);
  }

  double _exposureScore(img.Image image) {
    var good = 0;
    var total = 0;
    for (final pixel in image) {
      final luma = _luma(pixel);
      if (luma >= 45 && luma <= 225) {
        good++;
      }
      total++;
    }
    return total == 0 ? 0 : good / total;
  }

  double _oralColorScore(img.Image image) {
    var oral = 0;
    var total = 0;
    for (final pixel in image) {
      final r = pixel.r.toDouble();
      final g = pixel.g.toDouble();
      final b = pixel.b.toDouble();
      if (r > 80 && r >= g * 0.85 && g >= b * 0.65 && (r - b) > 25) {
        oral++;
      }
      total++;
    }
    return total == 0 ? 0 : oral / total;
  }

  double _luma(img.Pixel pixel) {
    return (0.2126 * pixel.r) + (0.7152 * pixel.g) + (0.0722 * pixel.b);
  }
}
