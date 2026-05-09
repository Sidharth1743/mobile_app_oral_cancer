import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/auth/role_auth.dart';

void main() {
  test('authenticates role users with salted password hashes', () {
    const hasher = PasswordHasher();
    final user = hasher.createUser(
      userId: 'asha-1',
      login: '  ASHA01 ',
      role: AppRole.asha,
      password: 'local-pass',
      salt: 'test-salt',
    );
    final directory = UserDirectory(users: [user]);

    expect(
      directory.login(login: 'asha01', password: 'local-pass').role,
      AppRole.asha,
    );
    expect(
      () => directory.login(login: 'asha01', password: 'wrong'),
      throwsStateError,
    );
    expect(user.passwordHash, isNot(contains('local-pass')));
  });

  test('enforces role visibility boundaries', () {
    const permissions = RolePermissions();

    expect(permissions.canSeePatientIdentity(AppRole.asha), isTrue);
    expect(permissions.canSeePatientIdentity(AppRole.doctor), isTrue);
    expect(permissions.canSeePatientIdentity(AppRole.ngoCsr), isFalse);
    expect(permissions.canSeeAggregateDashboard(AppRole.ngoCsr), isTrue);
    expect(permissions.canExportResearchDataset(AppRole.research), isTrue);
  });
}
