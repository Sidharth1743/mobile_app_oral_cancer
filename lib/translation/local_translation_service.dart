import 'dart:convert';

import '../inference/gemma_service.dart';
import '../inference/strict_json.dart';

class TranslationRequest {
  const TranslationRequest({
    required this.text,
    required this.targetLanguage,
    this.sourceLanguage = 'English',
  });

  final String text;
  final String sourceLanguage;
  final String targetLanguage;
}

class TranslationResult {
  const TranslationResult({
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.translatedText,
    required this.modelName,
  });

  final String sourceLanguage;
  final String targetLanguage;
  final String translatedText;
  final String modelName;
}

class LocalGemmaTranslationService {
  const LocalGemmaTranslationService({required GemmaService gemmaService})
    : _gemmaService = gemmaService;

  final GemmaService _gemmaService;

  Future<TranslationResult> translate(TranslationRequest request) async {
    _validateRequest(request);
    final raw = await _gemmaService.infer(
      GemmaRequest(prompt: _prompt(request), maxTokens: 512, temperature: 0),
    );
    final parsed = parseGemmaThinking(raw.text);
    final json = decodeJsonObject(parsed.finalAnswer);
    final translated = json['translatedText'] as String? ?? '';
    if (translated.trim().isEmpty) {
      throw const FormatException('translatedText is required.');
    }
    return TranslationResult(
      sourceLanguage:
          json['sourceLanguage'] as String? ?? request.sourceLanguage,
      targetLanguage:
          json['targetLanguage'] as String? ?? request.targetLanguage,
      translatedText: translated,
      modelName: raw.modelName,
    );
  }

  void _validateRequest(TranslationRequest request) {
    if (request.text.trim().isEmpty) {
      throw ArgumentError.value(request.text, 'text', 'Text is required.');
    }
    if (request.targetLanguage.trim().isEmpty) {
      throw ArgumentError.value(
        request.targetLanguage,
        'targetLanguage',
        'Target language is required.',
      );
    }
  }

  String _prompt(TranslationRequest request) {
    final payload = {
      'task': 'translate_patient_text',
      'sourceLanguage': request.sourceLanguage,
      'targetLanguage': request.targetLanguage,
      'text': request.text,
      'outputSchema': {
        'sourceLanguage': 'string',
        'targetLanguage': 'string',
        'translatedText': 'string',
      },
    };
    return [
      'Translate patient-facing medical screening text using the local on-device model.',
      'Preserve meaning. Do not add advice. Return strict JSON only.',
      jsonEncode(payload),
    ].join('\n\n');
  }
}
