import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter UI avoids banned generated UI patterns', () {
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final combined = files.map((file) => file.readAsStringSync()).join('\n');

    for (final token in const [
      'FontWeight.w800',
      'FontWeight.w900',
      'font-extrabold',
      'font-black',
      'shadow-xl',
      'shadow-2xl',
      'tracking-[0.18em]',
      'tracking-[0.2em]',
      'tracking-[0.24em]',
    ]) {
      expect(combined, isNot(contains(token)));
    }
  });
}
