import '../auth/role_auth.dart';
import '../cloud/assessment_cloud_sync_service.dart';
import '../cloud/firebase_role_auth.dart';
import '../cloud/research_cloud_sync_service.dart';
import '../cloud/research_firestore_sync_service.dart';
import '../data/local_database.dart';
import 'sync_worker.dart';

/// Uploads pending local queue rows to Firebase using the signed-in staff profile.
class CloudSyncRunner {
  CloudSyncRunner({
    required LocalDatabase database,
    required FirebaseUserProfile actor,
    AssessmentCloudSyncService? assessmentService,
    ResearchFirestoreSyncService? researchFirestore,
    ResearchCloudFunctionUploader? researchUploader,
    bool useResearchCloudFunction = false,
  }) : _database = database,
       _actor = actor,
       _assessmentService = assessmentService ?? AssessmentCloudSyncService(),
       _researchFirestore = researchFirestore ?? ResearchFirestoreSyncService(),
       _researchUploader = researchUploader ?? ResearchCloudFunctionUploader(),
       _useResearchCloudFunction = useResearchCloudFunction;

  final LocalDatabase _database;
  final FirebaseUserProfile _actor;
  final AssessmentCloudSyncService _assessmentService;
  final ResearchFirestoreSyncService _researchFirestore;
  final ResearchCloudFunctionUploader _researchUploader;
  final bool _useResearchCloudFunction;

  static const _stubKinds = {
    'doctor_share_request',
    'asha_share_request',
    'cloud_backup_request',
    'research_export_request',
  };

  Future<SyncWorkerResult> run() {
    final worker = LocalSyncWorker(
      database: _database,
      uploader: _RoleAwareSyncUploader(
        actor: _actor,
        assessmentService: _assessmentService,
        researchFirestore: _researchFirestore,
        researchUploader: _researchUploader,
        useResearchCloudFunction: _useResearchCloudFunction,
      ),
    );
    return worker.processPending();
  }
}

class _RoleAwareSyncUploader implements QueuedSyncUploader {
  const _RoleAwareSyncUploader({
    required FirebaseUserProfile actor,
    required AssessmentCloudSyncService assessmentService,
    required ResearchFirestoreSyncService researchFirestore,
    required ResearchCloudFunctionUploader researchUploader,
    required bool useResearchCloudFunction,
  }) : _actor = actor,
       _assessmentService = assessmentService,
       _researchFirestore = researchFirestore,
       _researchUploader = researchUploader,
       _useResearchCloudFunction = useResearchCloudFunction;

  final FirebaseUserProfile _actor;
  final AssessmentCloudSyncService _assessmentService;
  final ResearchFirestoreSyncService _researchFirestore;
  final ResearchCloudFunctionUploader _researchUploader;
  final bool _useResearchCloudFunction;

  @override
  Future<void> upload(SyncQueueItem item) async {
    if (CloudSyncRunner._stubKinds.contains(item.kind)) {
      throw StateError(
        '“${item.kind}” is only a consent flag, not an upload. '
        'From the result screen open “Prepare doctor package” (with the doctor’s '
        'Firebase UID) and “Create research export”, then sync again while signed '
        'in as ASHA.',
      );
    }

    switch (item.kind) {
      case 'identified_assessment_doctor_package':
        if (_actor.role != AppRole.asha && _actor.role != AppRole.admin) {
          throw StateError(
            'Doctor packages must be uploaded while signed in as ASHA (or admin).',
          );
        }
        await _assessmentService.uploadIdentifiedAssessmentPackage(
          actor: _actor,
          payload: item.payload,
        );
        return;
      case 'research_dataset_row':
        if (_actor.role != AppRole.asha &&
            _actor.role != AppRole.research &&
            _actor.role != AppRole.admin) {
          throw StateError(
            'Research exports must be uploaded while signed in as ASHA, research, or admin.',
          );
        }
        if (_useResearchCloudFunction) {
          await _researchUploader.uploadResearchExport(item.payload);
        } else {
          await _researchFirestore.uploadResearchExport(
            actor: _actor,
            payload: item.payload,
          );
        }
        return;
      default:
        throw StateError(
          'Queue item “${item.kind}” is not supported for cloud upload.',
        );
    }
  }
}
