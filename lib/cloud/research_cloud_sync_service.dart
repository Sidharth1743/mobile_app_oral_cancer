import 'package:cloud_functions/cloud_functions.dart';

class ResearchCloudFunctionUploader {
  ResearchCloudFunctionUploader({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  final FirebaseFunctions _functions;

  Future<void> uploadResearchExport(Map<String, Object?> payload) async {
    validateResearchPayload(payload);
    await _functions.httpsCallable('submitResearchExport').call(payload);
  }

  static void validateResearchPayload(Map<String, Object?> payload) {
    final consent = payload['consent'] as Map?;
    if (consent != null) {
      final scopes = List<String>.from(consent['scopes'] as List? ?? const []);
      if (!scopes.contains('researchExport')) {
        throw StateError('Research export payload lacks research consent.');
      }
    }
    for (final key in const [
      'fullName',
      'phone',
      'dateOfBirth',
      'dob',
      'pinCode',
      'village',
    ]) {
      _assertKeyAbsent(payload, key);
    }
  }

  static void _assertKeyAbsent(Object? value, String blockedKey) {
    if (value is Map) {
      if (value.containsKey(blockedKey)) {
        throw StateError(
          'Research export contains direct identity: $blockedKey',
        );
      }
      for (final nested in value.values) {
        _assertKeyAbsent(nested, blockedKey);
      }
    } else if (value is List) {
      for (final item in value) {
        _assertKeyAbsent(item, blockedKey);
      }
    }
  }
}
