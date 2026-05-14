import 'dart:convert';

Map<String, Object?> decodeJsonObject(String source) {
  final decoded = jsonDecode(_normalizeJsonObjectSource(source));
  if (decoded is! Map) {
    throw const FormatException('Expected a JSON object.');
  }
  return Map<String, Object?>.from(decoded);
}

List<Map<String, Object?>> decodeJsonObjectList(Object? source, String field) {
  if (source is! List) {
    throw FormatException('Expected $field to be a JSON array.');
  }
  return source.map((item) {
    if (item is! Map) {
      throw FormatException('Expected every $field item to be a JSON object.');
    }
    return Map<String, Object?>.from(item);
  }).toList();
}

String _normalizeJsonObjectSource(String source) {
  final trimmed = source.trim();
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
    return trimmed;
  }

  // Accept common LLM markdown output:
  // ```json
  // {...}
  // ```
  final fencedMatch = RegExp(
    r'```(?:json)?\s*([\s\S]*?)\s*```',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (fencedMatch != null) {
    final inner = (fencedMatch.group(1) ?? '').trim();
    if (inner.startsWith('{') && inner.endsWith('}')) {
      return inner;
    }
  }

  // Fallback: extract first JSON object block from mixed text.
  final start = trimmed.indexOf('{');
  final end = trimmed.lastIndexOf('}');
  if (start != -1 && end > start) {
    return trimmed.substring(start, end + 1);
  }
  return trimmed;
}
