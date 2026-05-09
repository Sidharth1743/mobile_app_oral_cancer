import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

enum AppRole { asha, doctor, ngoCsr, research, admin }

class AppRoleCodec {
  const AppRoleCodec();

  AppRole fromName(String value) {
    final normalized = value.trim().toLowerCase().replaceAll('-', '_');
    switch (normalized) {
      case 'asha':
        return AppRole.asha;
      case 'doctor':
        return AppRole.doctor;
      case 'ngo_csr':
      case 'ngocsr':
      case 'ngo/csr':
        return AppRole.ngoCsr;
      case 'research':
        return AppRole.research;
      case 'admin':
        return AppRole.admin;
      default:
        throw ArgumentError.value(value, 'role', 'Unknown role.');
    }
  }

  String toName(AppRole role) {
    switch (role) {
      case AppRole.asha:
        return 'asha';
      case AppRole.doctor:
        return 'doctor';
      case AppRole.ngoCsr:
        return 'ngo_csr';
      case AppRole.research:
        return 'research';
      case AppRole.admin:
        return 'admin';
    }
  }
}

class AppUser {
  const AppUser({
    required this.userId,
    required this.login,
    required this.role,
    required this.passwordSalt,
    required this.passwordHash,
  });

  final String userId;
  final String login;
  final AppRole role;
  final String passwordSalt;
  final String passwordHash;
}

class PasswordHasher {
  const PasswordHasher();

  AppUser createUser({
    required String userId,
    required String login,
    required AppRole role,
    required String password,
    String? salt,
  }) {
    final effectiveSalt = salt ?? _newSalt();
    return AppUser(
      userId: userId,
      login: _normalizeLogin(login),
      role: role,
      passwordSalt: effectiveSalt,
      passwordHash: hashPassword(password: password, salt: effectiveSalt),
    );
  }

  bool verify(AppUser user, String password) =>
      user.passwordHash ==
      hashPassword(password: password, salt: user.passwordSalt);

  String hashPassword({required String password, required String salt}) {
    List<int> bytes = utf8.encode('$salt:$password');
    for (var i = 0; i < 120000; i += 1) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64UrlEncode(bytes);
  }

  String _newSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}

class UserDirectory {
  UserDirectory({required List<AppUser> users})
    : _users = {for (final user in users) user.login: user};

  final Map<String, AppUser> _users;
  final PasswordHasher _hasher = const PasswordHasher();

  AppUser login({required String login, required String password}) {
    final user = _users[_normalizeLogin(login)];
    if (user == null || !_hasher.verify(user, password)) {
      throw StateError('Invalid login.');
    }
    return user;
  }
}

class RolePermissions {
  const RolePermissions();

  bool canSeePatientIdentity(AppRole role) =>
      role == AppRole.asha || role == AppRole.doctor || role == AppRole.admin;

  bool canSeeAggregateDashboard(AppRole role) =>
      role == AppRole.ngoCsr || role == AppRole.admin;

  bool canExportResearchDataset(AppRole role) =>
      role == AppRole.research || role == AppRole.admin;
}

String _normalizeLogin(String login) => login.trim().toLowerCase();
