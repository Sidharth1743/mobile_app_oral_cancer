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
    final started = DateTime.now();
    final uri = Uri.parse('$_baseUrl/api/infer');

    final multiRequest = http.MultipartRequest('POST', uri);
    multiRequest.fields['prompt'] = request.prompt;
    if (_modelPath.isNotEmpty) {
      multiRequest.fields['modelPath'] = _modelPath;
    }
    multiRequest.fields['backend'] = _backend;
    if (request.imagePaths.isNotEmpty) {
      multiRequest.files.add(
        await http.MultipartFile.fromPath('file', request.imagePaths.first),
      );
    }

    final streamedResponse = await _client.send(multiRequest);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw StateError(
        'PC LiteRT helper failed (${response.statusCode}): ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('PC LiteRT helper returned invalid response.');
    }
    final text = decoded['raw_text'] ?? decoded['text'];
    if (text is! String || text.trim().isEmpty) {
      throw StateError('PC LiteRT helper returned empty text.');
    }
    return GemmaRawResponse(
      text: text,
      modelName:
          decoded['adapter_dir'] as String? ??
          decoded['modelName'] as String? ??
          'LiteRT-LM',
      elapsed: DateTime.now().difference(started),
    );
  }
}
