import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/core/pii_vault.dart';
import 'package:oral_cancer/data/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('encrypts and decrypts identity with ASHA PIN', () async {
    final preferences = await SharedPreferences.getInstance();
    final vault = PiiVault(preferences: preferences);
    final identity = IdentityRecord(
      fullName: 'Meena Kumar',
      village: 'Thiruvallur',
      dateOfBirth: DateTime.utc(1979, 4, 20),
      phone: '9876543210',
      pinCode: '600042',
    );

    await vault.saveIdentity(identity: identity, ashaPin: '123456');
    final unlocked = await vault.loadIdentity(ashaPin: '123456');

    expect(unlocked.fullName, identity.fullName);
    expect(unlocked.phone, identity.phone);
    expect(vault.hasIdentity, isTrue);
  });

  test('stored vault values do not contain plaintext PII', () async {
    final preferences = await SharedPreferences.getInstance();
    final vault = PiiVault(preferences: preferences);

    await vault.saveIdentity(
      identity: IdentityRecord(
        fullName: 'Meena Kumar',
        village: 'Thiruvallur',
        dateOfBirth: DateTime.utc(1979, 4, 20),
        phone: '9876543210',
        pinCode: '600042',
      ),
      ashaPin: '123456',
    );

    final storedValues = preferences
        .getKeys()
        .map((key) => preferences.get(key).toString())
        .join('\n');

    expect(storedValues, isNot(contains('Meena')));
    expect(storedValues, isNot(contains('9876543210')));
    expect(storedValues, isNot(contains('Thiruvallur')));
  });

  test('wrong PIN fails to decrypt identity', () async {
    final preferences = await SharedPreferences.getInstance();
    final vault = PiiVault(preferences: preferences);

    await vault.saveIdentity(
      identity: IdentityRecord(
        fullName: 'Meena Kumar',
        village: 'Thiruvallur',
        dateOfBirth: DateTime.utc(1979, 4, 20),
        phone: '9876543210',
        pinCode: '600042',
      ),
      ashaPin: '123456',
    );

    expect(
      () => vault.loadIdentity(ashaPin: '654321'),
      throwsA(isA<PiiVaultException>()),
    );
  });

  test('PIN policy requires 4 to 12 digits', () async {
    final preferences = await SharedPreferences.getInstance();
    final vault = PiiVault(preferences: preferences);
    final identity = IdentityRecord(
      fullName: 'Meena Kumar',
      village: 'Thiruvallur',
      dateOfBirth: DateTime.utc(1979, 4, 20),
      phone: '9876543210',
      pinCode: '600042',
    );

    expect(
      () => vault.saveIdentity(identity: identity, ashaPin: '123'),
      throwsArgumentError,
    );
    expect(
      () => vault.saveIdentity(identity: identity, ashaPin: 'abcd'),
      throwsArgumentError,
    );
  });
}
