import 'dart:convert';

import '../inference/gemma_service.dart';
import '../inference/strict_json.dart';
import '../intake/intake_extraction_service.dart';

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

  Future<ExtractedIntake> translateExtractedIntake({
    required ExtractedIntake intake,
    required String targetLanguage,
    String sourceLanguage = 'auto',
  }) async {
    if (targetLanguage.trim().isEmpty) {
      throw ArgumentError.value(
        targetLanguage,
        'targetLanguage',
        'Target language is required.',
      );
    }
    final fields = <String, String>{};
    void addField(String key, String? value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        fields[key] = trimmed;
      }
    }

    addField('patient_name', intake.patientName);
    addField('village_or_area', intake.villageOrArea);
    addField('state', intake.state);
    addField('district', intake.district);
    addField('tobacco_brand', intake.tobaccoBrand);
    addField('symptom_duration', intake.symptomDuration);
    if (intake.symptoms.isNotEmpty) {
      fields['symptoms'] = intake.symptoms.join(', ');
    }
    if (fields.isEmpty) {
      return intake;
    }

    final raw = await _gemmaService.infer(
      GemmaRequest(
        prompt: _extractedFieldsPrompt(
          fields: fields,
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
        ),
        maxTokens: 768,
        temperature: 0,
      ),
    );
    final parsed = parseGemmaThinking(raw.text);
    final json = decodeJsonObject(parsed.finalAnswer);
    final translatedSymptoms = _stringField(json['symptoms']);
    return intake.copyWith(
      patientName: _stringField(json['patient_name']) ?? intake.patientName,
      villageOrArea:
          _stringField(json['village_or_area']) ?? intake.villageOrArea,
      state: _stringField(json['state']) ?? intake.state,
      district: _stringField(json['district']) ?? intake.district,
      tobaccoBrand: _stringField(json['tobacco_brand']) ?? intake.tobaccoBrand,
      symptomDuration:
          _stringField(json['symptom_duration']) ?? intake.symptomDuration,
      symptoms: translatedSymptoms == null
          ? intake.symptoms
          : translatedSymptoms
                .split(',')
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList(),
      modelName: raw.modelName,
    );
  }

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

  String? _stringField(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _extractedFieldsPrompt({
    required Map<String, String> fields,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    final payload = {
      'task': 'translate_extracted_intake_fields',
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
      'fields': fields,
      'outputSchema': {
        'patient_name': 'string_or_null',
        'village_or_area': 'string_or_null',
        'state': 'string_or_null',
        'district': 'string_or_null',
        'tobacco_brand': 'string_or_null',
        'symptoms': 'string_or_null',
        'symptom_duration': 'string_or_null',
      },
    };
    return [
      'Translate only the provided intake field strings for a medical screening app.',
      'Preserve meaning and names where appropriate. Return strict JSON only.',
      jsonEncode(payload),
    ].join('\n\n');
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
