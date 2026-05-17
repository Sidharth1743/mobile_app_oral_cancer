import 'gemma_service.dart';
import 'strict_json.dart';

/// One Gemma frame classifier response (category kept exactly as the model returned).
class FrameScreeningResult {
  const FrameScreeningResult({
    required this.category,
    required this.recommendation,
    required this.briefReason,
    required this.disclaimer,
    required this.rawJson,
  });

  final String category;
  final String recommendation;
  final String briefReason;
  final String disclaimer;
  final Map<String, Object?> rawJson;

  factory FrameScreeningResult.fromParsedMap(Map<String, Object?> json) {
    return FrameScreeningResult(
      category: _stringField(json['category']),
      recommendation: _stringField(json['recommendation']),
      briefReason: _stringField(json['brief_reason']),
      disclaimer: _stringField(json['disclaimer']),
      rawJson: json,
    );
  }

  Map<String, Object?> toLegacyMap() => {
    'category': category,
    'recommendation': recommendation,
    'brief_reason': briefReason,
    'disclaimer': disclaimer,
  };
}

/// Vote counts and majority label across video frames.
class ScreeningFrameAggregation {
  const ScreeningFrameAggregation({
    required this.frames,
    required this.categoryCounts,
    required this.majorityCategory,
  });

  final List<FrameScreeningResult> frames;
  final Map<String, int> categoryCounts;
  final String majorityCategory;

  bool get shouldRefer => frames.any((frame) => _signalsRefer(frame));
  bool get needsRecapture =>
      !shouldRefer &&
      frames.isNotEmpty &&
      frames.every((frame) => _signalsRecapture(frame));

  static ScreeningFrameAggregation fromParsedMaps(
    List<Map<String, Object?>> maps,
  ) {
    final frames = maps
        .map(FrameScreeningResult.fromParsedMap)
        .toList(growable: false);
    final counts = <String, int>{};
    for (final frame in frames) {
      final key = frame.category.isEmpty ? '(no category)' : frame.category;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final majority = _majorityCategory(counts);
    return ScreeningFrameAggregation(
      frames: frames,
      categoryCounts: counts,
      majorityCategory: majority,
    );
  }
}

/// Parses Gemma screening JSON; never replaces unknown [category] values.
Map<String, Object?> parseScreeningClassifierOutput(String raw) {
  final answer = parseGemmaThinking(raw).finalAnswer;
  try {
    return FrameScreeningResult.fromParsedMap(
      decodeJsonObject(answer),
    ).toLegacyMap();
  } on FormatException {
    final category = _categoryFromLooseText(answer);
    if (category.isEmpty) {
      return {
        'category': '',
        'recommendation': '',
        'brief_reason': answer.trim(),
        'disclaimer': '',
      };
    }
    return {
      'category': category,
      'recommendation': category,
      'brief_reason': answer.trim(),
      'disclaimer': '',
    };
  }
}

String formatCategoryLabel(String category) {
  if (category.isEmpty || category == '(no category)') {
    return 'No category';
  }
  return category
      .split(RegExp(r'[_\s]+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) =>
            '${part[0].toUpperCase()}${part.length > 1 ? part.substring(1).toLowerCase() : ''}',
      )
      .join(' ');
}

String _majorityCategory(Map<String, int> counts) {
  if (counts.isEmpty) {
    return '';
  }
  final sorted = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) {
        return byCount;
      }
      return _categoryPriority(b.key).compareTo(_categoryPriority(a.key));
    });
  return sorted.first.key;
}

int _categoryPriority(String category) {
  if (_signalsReferCategory(category)) {
    return 3;
  }
  if (category == 'recapture_required') {
    return 2;
  }
  if (category == 'low_risk_or_variation') {
    return 1;
  }
  return 0;
}

bool _signalsRefer(FrameScreeningResult frame) {
  return _signalsReferCategory(frame.category) ||
      _signalsReferCategory(frame.recommendation);
}

bool _signalsRecapture(FrameScreeningResult frame) {
  return frame.category == 'recapture_required' ||
      frame.recommendation == 'recapture_required';
}

bool _signalsReferCategory(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  return normalized == 'refer_for_clinical_review' ||
      normalized.contains('refer');
}

String _stringField(Object? value) {
  if (value is! String) {
    return '';
  }
  return value.trim();
}

String _categoryFromLooseText(String source) {
  final match = RegExp(
    r'"?category"?\s*:\s*"?([a-zA-Z0-9_]+)"?',
    caseSensitive: false,
  ).firstMatch(source);
  return match?.group(1)?.trim().toLowerCase() ?? '';
}
