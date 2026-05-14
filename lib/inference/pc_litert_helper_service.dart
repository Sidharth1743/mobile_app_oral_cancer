import 'dart:convert';

import 'package:http/http.dart' as http;

import 'gemma_service.dart';

class PcLiteRtHelperService implements GemmaService {
  PcLiteRtHelperService({
    required String modelPath,
    String backend = 'cpu',
    String baseUrl = 'http://127.0.0.1:8010',
    http.Client? client,
  }) : _modelPath = modelPath,
       _backend = backend,
       _baseUrl = baseUrl,
       _client = client ?? http.Client();

  final String _modelPath;
  final String _backend;
  final String _baseUrl;
  final http.Client _client;

  @override
  Future<GemmaRawResponse> infer(GemmaRequest request) async {
    final modelPath = _modelPath.trim();
    final started = DateTime.now();
    final uri = Uri.parse('$_baseUrl/api/infer');
    final payload = <String, dynamic>{
      'backend': _backend,
      'prompt': request.prompt,
      'imagePaths': request.imagePaths,
      'maxTokens': request.maxTokens,
      'temperature': request.temperature,
    };
    if (modelPath.isNotEmpty) {
      payload['modelPath'] = modelPath;
    }
    final response = await _client.post(
      uri,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (response.statusCode != 200) {
      throw StateError(
        'PC LiteRT helper failed (${response.statusCode}): ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('PC LiteRT helper returned invalid response.');
    }
    final text = decoded['text'];
    if (text is! String || text.trim().isEmpty) {
      throw StateError('PC LiteRT helper returned empty text.');
    }
    return GemmaRawResponse(
      text: text,
      modelName: decoded['modelName'] as String? ?? 'LiteRT-LM',
      elapsed: DateTime.now().difference(started),
    );
  }
}
