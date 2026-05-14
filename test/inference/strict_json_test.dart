import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/inference/strict_json.dart';

void main() {
  test('decodes fenced JSON object emitted by LiteRT CLI', () {
    final decoded = decodeJsonObject('''
```json
{"category":"refer_for_clinical_review","brief_reason":"Review needed."}
```
''');

    expect(decoded['category'], 'refer_for_clinical_review');
  });

  test('extracts first JSON object from mixed model text', () {
    final decoded = decodeJsonObject(
      'Model text before {"sizeChangeMm":"2.5mm","concernIncreased":true} tail',
    );

    expect(decoded['concernIncreased'], isTrue);
  });
}
