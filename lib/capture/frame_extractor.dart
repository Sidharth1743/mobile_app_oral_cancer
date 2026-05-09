import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FrameExtractor {
  const FrameExtractor();

  Future<List<String>> extractFrames({
    required String videoPath,
    required String visitId,
    required String siteId,
    int framesPerSecond = 2,
  }) async {
    if (framesPerSecond <= 0) {
      throw ArgumentError.value(
        framesPerSecond,
        'framesPerSecond',
        'Must be positive.',
      );
    }
    final video = File(videoPath);
    if (!video.existsSync()) {
      throw FileSystemException('Video file does not exist.', videoPath);
    }

    final tempDir = await getTemporaryDirectory();
    final outputDir = Directory(
      p.join(tempDir.path, 'oral_cancer', visitId, siteId),
    );
    await outputDir.create(recursive: true);
    final outputPattern = p.join(outputDir.path, 'frame_%04d.jpg');
    final command = [
      '-y',
      '-i',
      _quote(video.path),
      '-vf',
      _quote('fps=$framesPerSecond'),
      '-q:v',
      '2',
      _quote(outputPattern),
    ].join(' ');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw StateError('Frame extraction failed: $logs');
    }

    final frames =
        outputDir
            .listSync()
            .whereType<File>()
            .where((file) => p.extension(file.path).toLowerCase() == '.jpg')
            .map((file) => file.path)
            .toList()
          ..sort();
    if (frames.isEmpty) {
      throw StateError('Frame extraction produced no frames.');
    }
    await video.delete();
    return frames;
  }

  String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";
}
