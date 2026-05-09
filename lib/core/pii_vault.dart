import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';

class PiiVaultException implements Exception {
  const PiiVaultException(this.message);

  final String message;

  @override
  String toString() => 'PiiVaultException: $message';
}

class PiiVault {
  PiiVault({
    required SharedPreferences preferences,
    AesGcm? cipher,
    Pbkdf2? kdf,
  }) : _preferences = preferences,
       _cipher = cipher ?? AesGcm.with256bits(),
       _kdf =
           kdf ??
           Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 210000, bits: 256);

  static const _cipherTextKey = 'pii_vault.cipher_text';
  static const _nonceKey = 'pii_vault.nonce';
  static const _macKey = 'pii_vault.mac';
  static const _saltKey = 'pii_vault.salt';
  static const _versionKey = 'pii_vault.version';
  static const _version = 1;

  final SharedPreferences _preferences;
  final AesGcm _cipher;
  final Pbkdf2 _kdf;

  Future<void> saveIdentity({
    required IdentityRecord identity,
    required String ashaPin,
  }) async {
    _validatePin(ashaPin);
    final salt = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final nonce = _cipher.newNonce();
    final key = await _deriveKey(ashaPin: ashaPin, salt: salt);
    final clearText = utf8.encode(jsonEncode(identity.toJson()));
    final secretBox = await _cipher.encrypt(
      clearText,
      secretKey: key,
      nonce: nonce,
    );

    await _preferences.setInt(_versionKey, _version);
    await _preferences.setString(_saltKey, base64Encode(salt));
    await _preferences.setString(_nonceKey, base64Encode(secretBox.nonce));
    await _preferences.setString(_macKey, base64Encode(secretBox.mac.bytes));
    await _preferences.setString(
      _cipherTextKey,
      base64Encode(secretBox.cipherText),
    );
  }

  Future<IdentityRecord> loadIdentity({required String ashaPin}) async {
    _validatePin(ashaPin);
    final version = _preferences.getInt(_versionKey);
    if (version != _version) {
      throw const PiiVaultException('No supported identity record is stored.');
    }

    final salt = _decodeRequired(_saltKey);
    final nonce = _decodeRequired(_nonceKey);
    final mac = _decodeRequired(_macKey);
    final cipherText = _decodeRequired(_cipherTextKey);
    final key = await _deriveKey(ashaPin: ashaPin, salt: salt);

    try {
      final clearText = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      final json = jsonDecode(utf8.decode(clearText)) as Map;
      return IdentityRecord.fromJson(Map<String, Object?>.from(json));
    } on SecretBoxAuthenticationError {
      throw const PiiVaultException(
        'ASHA PIN could not unlock this identity record.',
      );
    } on FormatException catch (error) {
      throw PiiVaultException(
        'Stored identity record is corrupt: ${error.message}',
      );
    }
  }

  bool get hasIdentity =>
      _preferences.containsKey(_cipherTextKey) &&
      _preferences.containsKey(_nonceKey) &&
      _preferences.containsKey(_macKey) &&
      _preferences.containsKey(_saltKey);

  Future<void> clear() async {
    await _preferences.remove(_versionKey);
    await _preferences.remove(_saltKey);
    await _preferences.remove(_nonceKey);
    await _preferences.remove(_macKey);
    await _preferences.remove(_cipherTextKey);
  }

  Future<SecretKey> _deriveKey({
    required String ashaPin,
    required List<int> salt,
  }) {
    return _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(ashaPin)),
      nonce: salt,
    );
  }

  List<int> _decodeRequired(String key) {
    final value = _preferences.getString(key);
    if (value == null) {
      throw PiiVaultException('Missing encrypted identity field: $key.');
    }
    return base64Decode(value);
  }

  void _validatePin(String ashaPin) {
    if (!RegExp(r'^\d{4,12}$').hasMatch(ashaPin)) {
      throw ArgumentError.value(
        ashaPin,
        'ashaPin',
        'ASHA PIN must be 4 to 12 digits.',
      );
    }
  }
}
