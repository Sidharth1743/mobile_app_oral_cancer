import 'package:flutter/services.dart';

import 'gemma_service.dart';

class LiteRtGemmaService implements GemmaService {
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
    return GemmaRawResponse(
      text: text,
      modelName: modelName is String ? modelName : 'LiteRT-LM',
      elapsed: DateTime.now().difference(started),
    );
  }
}
