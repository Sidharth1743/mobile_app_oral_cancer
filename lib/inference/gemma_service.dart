class GemmaRequest {
  const GemmaRequest({
    required this.prompt,
    this.imagePaths = const [],
    this.maxTokens = 2048,
    this.temperature = 0.2,
  });

  final String prompt;
  final List<String> imagePaths;
  final int maxTokens;
  final double temperature;
}

class GemmaRawResponse {
  const GemmaRawResponse({
    required this.text,
    required this.modelName,
    required this.elapsed,
  });

  final String text;
  final String modelName;
  final Duration elapsed;
}

class GemmaParsedResponse {
  const GemmaParsedResponse({
    required this.thinking,
    required this.finalAnswer,
  });

  final String thinking;
  final String finalAnswer;
}

abstract interface class GemmaService {
  Future<GemmaRawResponse> infer(GemmaRequest request);
}

abstract interface class ReleasableGemmaService {
  Future<void> close();
}

GemmaParsedResponse parseGemmaThinking(String rawText) {
  final match = RegExp(
    r'<think>([\s\S]*?)<\/think>',
    caseSensitive: false,
  ).firstMatch(rawText);
  if (match == null) {
    return GemmaParsedResponse(thinking: '', finalAnswer: rawText.trim());
  }
  final thinking = match.group(1)?.trim() ?? '';
  final finalAnswer = rawText.replaceRange(match.start, match.end, '').trim();
  return GemmaParsedResponse(thinking: thinking, finalAnswer: finalAnswer);
}
