import '../consent/consent.dart';
import '../data/local_database.dart';
import '../data/models.dart';

class PostResultShareQueue {
  const PostResultShareQueue();

  Future<List<SyncQueueItem>> enqueueAllowedShares({
    required LocalDatabase database,
    required FullAssessment assessment,
    required ConsentRecord consent,
  }) async {
    consent.validatePostResult();
    if (consent.visitId != assessment.visitId ||
        consent.patientHash != assessment.patientHash) {
      throw StateError('Consent does not match assessment.');
    }
    final queued = <SyncQueueItem>[];
    if (consent.doctorShare) {
      queued.add(
        await _enqueueRequest(
          database: database,
          assessment: assessment,
          consent: consent,
          kind: 'doctor_share_request',
        ),
      );
    }
    if (consent.ashaShare) {
      queued.add(
        await _enqueueRequest(
          database: database,
          assessment: assessment,
          consent: consent,
          kind: 'asha_share_request',
        ),
      );
    }
    if (consent.cloudBackup) {
      queued.add(
        await _enqueueRequest(
          database: database,
          assessment: assessment,
          consent: consent,
          kind: 'cloud_backup_request',
        ),
      );
    }
    if (consent.researchExport) {
      queued.add(
        await _enqueueRequest(
          database: database,
          assessment: assessment,
          consent: consent,
          kind: 'research_export_request',
        ),
      );
    }
    return queued;
  }

  Future<SyncQueueItem> _enqueueRequest({
    required LocalDatabase database,
    required FullAssessment assessment,
    required ConsentRecord consent,
    required String kind,
  }) {
    return database.enqueueSync(
      visitId: assessment.visitId,
      kind: kind,
      payload: {
        'visitId': assessment.visitId,
        'patientHash': assessment.patientHash,
        'consentPolicyVersion': consent.policyVersion,
        'assessmentCreatedAt': assessment.createdAt.toIso8601String(),
        'requestedAt': consent.recordedAt.toIso8601String(),
        'carePlanAction': assessment.carePlan.action,
      },
    );
  }
}
