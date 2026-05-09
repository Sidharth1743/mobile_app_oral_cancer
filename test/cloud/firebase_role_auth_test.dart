import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/auth/role_auth.dart';
import 'package:oral_cancer/cloud/firebase_role_auth.dart';

void main() {
  test('role codec accepts cloud role names and rejects unknown roles', () {
    const codec = AppRoleCodec();

    expect(codec.fromName('asha'), AppRole.asha);
    expect(codec.fromName('doctor'), AppRole.doctor);
    expect(codec.fromName('ngo_csr'), AppRole.ngoCsr);
    expect(codec.fromName('NGO/CSR'), AppRole.ngoCsr);
    expect(codec.toName(AppRole.research), 'research');
    expect(() => codec.fromName('guest'), throwsArgumentError);
  });

  test('Firebase user profile parses active role document', () {
    final profile = FirebaseUserProfile.fromJson(const {
      'uid': 'asha-1',
      'displayName': 'ASHA Worker',
      'role': 'asha',
      'active': true,
      'mobile': '+919999999999',
      'state': 'Tamil Nadu',
      'district': 'Madurai',
    });

    expect(profile.uid, 'asha-1');
    expect(profile.role, AppRole.asha);
    expect(profile.active, isTrue);
    expect(profile.district, 'Madurai');
    expect(jsonEncode(profile.toJson()), isNot(contains('ngo_csr')));
  });

  test(
    'Firebase user profile defaults inactive when active flag is absent',
    () {
      final profile = FirebaseUserProfile.fromJson(const {
        'uid': 'doctor-1',
        'displayName': 'Doctor',
        'role': 'doctor',
      });

      expect(profile.role, AppRole.doctor);
      expect(profile.active, isFalse);
    },
  );
}
