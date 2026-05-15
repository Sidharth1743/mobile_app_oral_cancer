import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FrameExtractor {
  const FrameExtractor();

  Future<List<String>> extractFrames({
    required String videoPath,
    required String visitId,
    required String siteId,
    int framesPerSecond = 2,
    bool deleteSourceVideo = true,
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
    await _runFfmpeg(
      videoPath: video.path,
      outputPattern: outputPattern,
      framesPerSecond: framesPerSecond,
    );

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
    if (deleteSourceVideo) {
      await video.delete();
    }
    return frames;
  }

  Future<void> _runFfmpeg({
    required String videoPath,
    required String outputPattern,
    required int framesPerSecond,
  }) async {
    final args = [
      '-y',
      '-i',
      videoPath,
      '-vf',
      'fps=$framesPerSecond',
      '-q:v',
      '2',
      outputPattern,
    ];
    if (_useSystemFfmpeg) {
      final result = await Process.run('ffmpeg', args);
      if (result.exitCode != 0) {
        throw StateError(
          'Frame extraction failed: ${result.stderr}\n${result.stdout}',
        );
      }
      return;
    }

    final command = args.map(_quote).join(' ');
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw StateError('Frame extraction failed: $logs');
    }
  }

  bool get _useSystemFfmpeg =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";
}
