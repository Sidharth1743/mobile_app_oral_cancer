import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SpeechIntakeResult {
  const SpeechIntakeResult({required this.text, this.alternatives = const []});

  final String text;
  final List<String> alternatives;
}

class SpeechIntakeService {
  const SpeechIntakeService();

  static const _channel = MethodChannel('oral_cancer/speech_intake');

  Future<SpeechIntakeResult> listenOnce({String languageTag = 'en-IN'}) async {
    if (kIsWeb || !Platform.isAndroid) {
      throw UnsupportedError('Voice intake is currently available on Android.');
    }
    final response = await _channel.invokeMapMethod<String, Object?>(
      'listenOnce',
      {'languageTag': languageTag},
    );
    final text = response?['text'] as String? ?? '';
    final alternatives =
        (response?['alternatives'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    if (text.trim().isEmpty) {
      throw const FormatException('No speech text was recognized.');
    }
    return SpeechIntakeResult(text: text.trim(), alternatives: alternatives);
  }
}
