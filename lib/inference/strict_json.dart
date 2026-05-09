import 'dart:convert';

Map<String, Object?> decodeJsonObject(String source) {
  final trimmed = source.trim();
  final decoded = jsonDecode(trimmed);
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
