import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/role_auth.dart';
import 'firebase_role_auth.dart';
import 'research_cloud_sync_service.dart';

/// Writes de-identified research rows to Firestore without Cloud Functions.
///
/// Use when billing is not enabled for Cloud Functions deployment.
class ResearchFirestoreSyncService {
  ResearchFirestoreSyncService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<String> uploadResearchExport({
    required FirebaseUserProfile actor,
    required Map<String, Object?> payload,
  }) async {
    if (actor.role != AppRole.asha &&
        actor.role != AppRole.research &&
        actor.role != AppRole.admin) {
      throw StateError(
        'Research export upload requires ASHA, research, or admin role.',
      );
    }
    ResearchCloudFunctionUploader.validateResearchPayload(payload);
    final export =
        Map<String, Object?>.from(
              payload['export'] as Map? ?? payload,
            )
            as Map<String, Object?>;
    final visitId =
        (export['visitId'] as String?) ?? (payload['visitId'] as String?);
    if (visitId == null || visitId.trim().isEmpty) {
      throw StateError('Research export requires visitId.');
    }
    final exportId = 'research-$visitId';
    await _firestore.doc('researchExports/$exportId').set({
      ...export,
      'exportId': exportId,
      'status': 'accepted',
      'submittedByUid': actor.uid,
      'submittedByRole': const AppRoleCodec().toName(actor.role),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return exportId;
  }
}
