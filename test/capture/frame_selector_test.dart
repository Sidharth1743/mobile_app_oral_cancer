import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:oral_cancer/capture/frame_selector.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('frame_selector_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('ranks sharp, well-exposed oral-color frame above dark frame', () {
    final good = _writeImage(tempDir, 'good.jpg', _sharpOralImage());
    final dark = _writeImage(
      tempDir,
      'dark.jpg',
      img.Image(width: 96, height: 96)..clear(img.ColorRgb8(8, 5, 4)),
    );

    final ranked = const FrameSelector().rankFrames([dark.path, good.path]);

    expect(ranked.first.path, good.path);
    expect(ranked.first.exposureScore, greaterThan(0.9));
    expect(ranked.first.oralColorScore, greaterThan(0.7));
  });

  test('selectBestFrames returns requested count in score order', () {
    final good = _writeImage(tempDir, 'good.jpg', _sharpOralImage());
    final medium = _writeImage(
      tempDir,
      'medium.jpg',
      img.Image(width: 96, height: 96)..clear(img.ColorRgb8(150, 95, 85)),
    );
    final dark = _writeImage(
      tempDir,
      'dark.jpg',
      img.Image(width: 96, height: 96)..clear(img.ColorRgb8(8, 5, 4)),
    );

    final selected = const FrameSelector().selectBestFrames([
      dark.path,
      medium.path,
      good.path,
    ], count: 2);

    expect(selected, hasLength(2));
    expect(selected.first, good.path);
    expect(selected, isNot(contains(dark.path)));
  });

  test('rejects empty frame list and undecodable files', () {
    expect(
      () => const FrameSelector().rankFrames(const []),
      throwsArgumentError,
    );

    final bad = File('${tempDir.path}/bad.jpg')
      ..writeAsStringSync('not an image');
    expect(
      () => const FrameSelector().scoreFrame(bad.path),
      throwsFormatException,
    );
  });
}

File _writeImage(Directory tempDir, String name, img.Image image) {
  final file = File('${tempDir.path}/$name');
  file.writeAsBytesSync(img.encodeJpg(image));
  return file;
}

img.Image _sharpOralImage() {
  final image = img.Image(width: 96, height: 96);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final stripe = ((x ~/ 6) + (y ~/ 6)).isEven;
      image.setPixelRgb(
        x,
        y,
        stripe ? 205 : 120,
        stripe ? 115 : 55,
        stripe ? 105 : 50,
      );
    }
  }
  return image;
}
