import '../consent/consent.dart';
import '../data/local_database.dart';
import '../data/models.dart';

class PostResultShareQueue {
  const PostResultShareQueue();

  /// Consent scopes are stored on [ConsentRecord]; uploads are separate queue rows
  /// created from Doctor package / Research export screens.
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
    return const [];
  }
}
