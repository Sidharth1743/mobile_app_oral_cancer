import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/intake/date_of_birth.dart';

void main() {
  test('formats selected DOB as stable ISO date text', () {
    expect(formatDateOfBirth(DateTime.utc(1985, 1, 1)), '1985-01-01');
  });

  test('rejects future DOB', () {
    final now = DateTime.utc(2026, 5, 5);

    expect(
      validateDateOfBirth(DateTime.utc(2026, 5, 6), now: now),
      'DOB cannot be in the future',
    );
    expect(validateDateOfBirth(DateTime.utc(1978, 2, 12), now: now), isNull);
  });
}
