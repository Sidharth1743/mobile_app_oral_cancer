import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/inference/gemma_service.dart';

void main() {
  test('parses thinking block and final answer', () {
    final parsed = parseGemmaThinking('''<think>
Consider site morphology, exposure, and interval change.
</think>
{"action":"see_doctor_free"}''');

    expect(
      parsed.thinking,
      'Consider site morphology, exposure, and interval change.',
    );
    expect(parsed.finalAnswer, '{"action":"see_doctor_free"}');
  });

  test('returns empty thinking when model emits final answer only', () {
    final parsed = parseGemmaThinking('{"action":"rescreen"}');

    expect(parsed.thinking, isEmpty);
    expect(parsed.finalAnswer, '{"action":"rescreen"}');
  });
}
