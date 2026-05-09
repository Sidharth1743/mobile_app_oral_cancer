import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/core/deidentification.dart';
import 'package:oral_cancer/data/models.dart';

void main() {
  final identity = IdentityRecord(
    fullName: '  Meena   Kumar ',
    village: ' Thiruvallur ',
    dateOfBirth: DateTime.utc(1979, 4, 20),
    phone: '9876543210',
    pinCode: '600 042',
  );

  test('patient hash is stable after whitespace and case normalization', () {
    final sameIdentity = IdentityRecord(
      fullName: 'meena kumar',
      village: 'thiruvallur',
      dateOfBirth: DateTime.utc(1979, 4, 20),
      phone: '000',
      pinCode: '111111',
    );

    expect(
      patientHashForIdentity(identity),
      patientHashForIdentity(sameIdentity),
    );
  });

  test(
    'de-identification converts age and pincode without identity fields',
    () {
      final record = deIdentifyClinicalRecord(
        id: 'clinical-1',
        identity: identity,
        gender: 'female',
        tobaccoBrand: 'Hans',
        chewsPerDay: 10,
        yearsUsed: 15,
        alcoholUse: false,
        createdAt: DateTime.utc(2026, 5, 3),
      );

      final json = record.toJson();

      expect(record.ageBand, '38-47');
      expect(record.pinPrefix, '600');
      expect(record.villageCode, hasLength(12));
      expect(json.containsKey('fullName'), isFalse);
      expect(json.containsKey('phone'), isFalse);
      expect(json.containsKey('dateOfBirth'), isFalse);
    },
  );

  test('CEI uses TSNA brand weights, unknown fallback, and clamp behavior', () {
    final hans = calculateCei(
      tobaccoBrand: 'Hans',
      chewsPerDay: 10,
      yearsUsed: 15,
      alcoholUse: false,
    );
    final unknown = calculateCei(
      tobaccoBrand: 'Local pouch',
      chewsPerDay: 10,
      yearsUsed: 15,
      alcoholUse: false,
    );
    final clamped = calculateCei(
      tobaccoBrand: 'Hans',
      chewsPerDay: 80,
      yearsUsed: 80,
      alcoholUse: true,
    );

    expect(hans, closeTo(0.25, 0.0001));
    expect(unknown, closeTo(0.125, 0.0001));
    expect(clamped, 1.0);
  });

  test('invalid future DOB and short PIN code are rejected', () {
    expect(
      () => ageBandFromDateOfBirth(
        DateTime.utc(2030, 1, 1),
        now: DateTime.utc(2026, 5, 3),
      ),
      throwsArgumentError,
    );
    expect(() => pinPrefix('42'), throwsArgumentError);
  });
}
