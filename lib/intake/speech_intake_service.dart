import 'dart:async';
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
  static const _events = EventChannel('oral_cancer/speech_intake_events');

  /// Live transcript while [startListening] is active.
  static Stream<String> transcriptUpdates() {
    return _events.receiveBroadcastStream().map(
      (event) => event?.toString() ?? '',
    );
  }

  /// Starts microphone capture. Call [stopListening] when the user is done.
  Future<void> startListening({String languageTag = 'en-IN'}) async {
    if (kIsWeb || !Platform.isAndroid) {
      throw UnsupportedError('Voice intake is currently available on Android.');
    }
    await _channel.invokeMethod<void>('startListening', {
      'languageTag': languageTag,
    });
  }

  /// Stops capture and returns the recognized transcript.
  Future<SpeechIntakeResult> stopListening() async {
    if (kIsWeb || !Platform.isAndroid) {
      throw UnsupportedError('Voice intake is currently available on Android.');
    }
    final response = await _channel.invokeMapMethod<String, Object?>(
      'stopListening',
    );
    final text = response?['text'] as String? ?? '';
    final alternatives =
        (response?['alternatives'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    if (text.trim().isEmpty) {
      throw const FormatException(
        'No speech was recognized. Tap start, speak clearly, then tap stop.',
      );
    }
    return SpeechIntakeResult(text: text.trim(), alternatives: alternatives);
  }

  /// Cancels an in-progress session without returning a transcript.
  Future<void> cancelListening() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('cancelListening');
    } on PlatformException {
      // Ignore if nothing was listening.
    }
  }

  @Deprecated('Use startListening/stopListening for manual control.')
  Future<SpeechIntakeResult> listenOnce({String languageTag = 'en-IN'}) async {
    await startListening(languageTag: languageTag);
    return stopListening();
  }
}
