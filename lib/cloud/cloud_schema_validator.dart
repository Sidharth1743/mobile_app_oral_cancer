import '../auth/role_auth.dart';
import '../consent/consent.dart';

class CloudSchemaValidator {
  const CloudSchemaValidator();

  static const directIdentityKeys = {
    'fullName',
    'phone',
    'dateOfBirth',
    'dob',
    'pinCode',
    'village',
  };

  static const allowedStorageKinds = {
    'roiImage',
    'segmentationMask',
    'selectedFrame',
    'researchExport',
  };

  void assertNoDirectIdentity(Map<String, Object?> payload) {
    final offendingPath = _findIdentityKey(payload, const []);
    if (offendingPath != null) {
      throw StateError('Direct identity field found at $offendingPath.');
    }
  }

  void validateConsentPayload(Map<String, Object?> payload) {
    final scopes = List<String>.from(payload['scopes'] as List? ?? const []);
    if (scopes.isEmpty) {
      throw StateError('Consent payload must include at least one scope.');
    }
    for (final scope in scopes) {
      ConsentScope.values.byName(scope);
    }
    final recordedAt = DateTime.parse(payload['recordedAt'] as String);
    final completedAt = DateTime.parse(
      payload['screeningCompletedAt'] as String,
    );
    if (recordedAt.isBefore(completedAt)) {
      throw StateError('Cloud consent must be after screening completion.');
    }
  }

  void validateStorageObjectMetadata(Map<String, Object?> payload) {
    final kind = payload['kind'] as String?;
    if (kind == null || !allowedStorageKinds.contains(kind)) {
      throw StateError('Unsupported storage object kind: $kind.');
    }
    final storagePath = payload['storagePath'] as String? ?? '';
    final contentType = payload['contentType'] as String? ?? '';
    if (storagePath.contains('/raw/') ||
        storagePath.endsWith('.mp4') ||
        storagePath.endsWith('.mov') ||
        storagePath.endsWith('.litertlm') ||
        storagePath.endsWith('.db') ||
        storagePath.endsWith('.sqlite')) {
      throw StateError('Forbidden storage path: $storagePath.');
    }
    if (kind == 'roiImage' && contentType != 'image/jpeg') {
      throw StateError('ROI image must be image/jpeg.');
    }
    if (kind == 'segmentationMask' && contentType != 'image/png') {
      throw StateError('Segmentation mask must be image/png.');
    }
  }

  void validateUserProfile(Map<String, Object?> payload) {
    final uid = payload['uid'] as String? ?? '';
    if (uid.trim().isEmpty) {
      throw StateError('User profile requires uid.');
    }
    const AppRoleCodec().fromName(payload['role'] as String);
    if (payload['active'] is! bool) {
      throw StateError('User profile active must be boolean.');
    }
  }

  String? _findIdentityKey(Object? value, List<String> path) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final nextPath = [...path, key];
        if (directIdentityKeys.contains(key)) {
          return nextPath.join('.');
        }
        final nested = _findIdentityKey(entry.value, nextPath);
        if (nested != null) {
          return nested;
        }
      }
    } else if (value is List) {
      for (var index = 0; index < value.length; index += 1) {
        final nested = _findIdentityKey(value[index], [...path, '$index']);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }
}
