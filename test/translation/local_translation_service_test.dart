import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/inference/gemma_service.dart';
import 'package:oral_cancer/translation/local_translation_service.dart';

void main() {
  test(
    'translates patient text through local Gemma service response JSON',
    () async {
      final service = LocalGemmaTranslationService(
        gemmaService: StaticGemmaService(
          jsonEncode({
            'sourceLanguage': 'English',
            'targetLanguage': 'Tamil',
            'translatedText': 'மருத்துவரை சந்திக்கவும்',
          }),
        ),
      );

      final result = await service.translate(
        const TranslationRequest(
          text: 'Please visit the doctor.',
          targetLanguage: 'Tamil',
        ),
      );

      expect(result.targetLanguage, 'Tamil');
      expect(result.translatedText, contains('மருத்துவரை'));
    },
  );

  test('rejects empty translation text before model call', () async {
    final service = LocalGemmaTranslationService(
      gemmaService: StaticGemmaService('{}'),
    );

    expect(
      () => service.translate(
        const TranslationRequest(text: '', targetLanguage: 'Tamil'),
      ),
      throwsArgumentError,
    );
  });
}

class StaticGemmaService implements GemmaService {
  const StaticGemmaService(this.text);

  final String text;

  @override
  Future<GemmaRawResponse> infer(GemmaRequest request) async {
    expect(request.prompt, contains('translate_patient_text'));
    return GemmaRawResponse(
      text: text,
      modelName: 'local-test-gemma',
      elapsed: Duration.zero,
    );
  }
}
