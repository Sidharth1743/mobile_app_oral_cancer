import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'gemma_service.dart';

class LiteRtGemmaService implements GemmaService, ReleasableGemmaService {
  LiteRtGemmaService({
    required String modelPath,
    String backend = 'gpu',
    MethodChannel channel = const MethodChannel('oral_cancer/litert_lm'),
  }) : _modelPath = modelPath,
       _backend = backend,
       _channel = channel;

  final String _modelPath;
  final String _backend;
  final MethodChannel _channel;

  @override
  Future<GemmaRawResponse> infer(GemmaRequest request) async {
    final modelPath = _modelPath.trim();
    if (modelPath.isEmpty) {
      throw StateError('LiteRT model path is required.');
    }
    final started = DateTime.now();
    debugPrint(
      '[OralCancerLiteRT][Dart] infer_start backend=$_backend '
      'images=${request.imagePaths.length} maxTokens=${request.maxTokens} '
      'temperature=${request.temperature} model=$modelPath',
    );
    final result = await _channel.invokeMapMethod<String, Object?>('infer', {
      'modelPath': modelPath,
      'backend': _backend,
      'prompt': request.prompt,
      'imagePaths': request.imagePaths,
      'maxTokens': request.maxTokens,
      'temperature': request.temperature,
    });
    if (result == null) {
      throw StateError('LiteRT-LM returned no result.');
    }
    final text = result['text'];
    final modelName = result['modelName'];
    if (text is! String || text.trim().isEmpty) {
      throw StateError('LiteRT-LM returned empty text.');
    }
    final elapsed = DateTime.now().difference(started);
    debugPrint(
      '[OralCancerLiteRT][Dart] infer_done elapsedMs=${elapsed.inMilliseconds} '
      'chars=${text.length} modelName=${modelName is String ? modelName : 'LiteRT-LM'}',
    );
    return GemmaRawResponse(
      text: text,
      modelName: modelName is String ? modelName : 'LiteRT-LM',
      elapsed: elapsed,
    );
  }

  @override
  Future<void> close() async {
    try {
      await _channel.invokeMethod<void>('close');
      debugPrint('[OralCancerLiteRT][Dart] engine_closed');
    } on MissingPluginException {
      return;
    }
  }
}
