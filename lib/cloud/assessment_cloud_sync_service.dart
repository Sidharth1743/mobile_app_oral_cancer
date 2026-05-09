import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../auth/role_auth.dart';
import '../consent/consent.dart';
import '../data/local_database.dart';
import '../data/models.dart';
import '../sync/sync_worker.dart';
import 'cloud_paths.dart';
import 'firebase_role_auth.dart';
import 'research_cloud_sync_service.dart';

class AssessmentCloudSyncResult {
  const AssessmentCloudSyncResult({
    required this.caseId,
    required this.packageId,
    required this.uploadedStoragePaths,
  });

  final String caseId;
  final String packageId;
  final List<String> uploadedStoragePaths;
}

class AssessmentCloudSyncService {
  AssessmentCloudSyncService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    CloudPaths paths = const CloudPaths(),
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _paths = paths;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final CloudPaths _paths;

  Future<AssessmentCloudSyncResult> uploadIdentifiedAssessmentPackage({
    required FirebaseUserProfile actor,
    required Map<String, Object?> payload,
  }) async {
    _requireUploaderRole(actor.role);
    final parsed = IdentifiedAssessmentCloudPayload.fromJson(payload);
    const ConsentGate().requireScope(parsed.consent, ConsentScope.doctorShare);
    final caseId = _caseId(parsed.assessment);
    final consentId = 'consent-${parsed.assessment.visitId}';
    final packageId = 'doctor-${parsed.assessment.visitId}';

    final uploadedPaths = <String>[];
    for (final site in parsed.assessment.siteResults) {
      final roiPath = site.roiImagePath;
      if (roiPath == null || roiPath.trim().isEmpty) {
        continue;
      }
      final storagePath = _paths.roiImage(
        caseId,
        parsed.assessment.visitId,
        site.siteId,
      );
      _paths.validateUploadPath(storagePath);
      final file = File(roiPath);
      if (!await file.exists()) {
        throw StateError('ROI image does not exist: $roiPath');
      }
      await _storage
          .ref(storagePath)
          .putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      uploadedPaths.add(storagePath);
    }

    final batch = _firestore.batch();
    batch.set(_firestore.doc(_paths.caseDocument(caseId)), {
      'caseId': caseId,
      'visitId': parsed.assessment.visitId,
      'patientHash': parsed.assessment.patientHash,
      'state': parsed.identity.state,
      'district': parsed.identity.district ?? '',
      'villageCode': parsed.clinicalRecord.villageCode,
      'createdByUid': actor.uid,
      'assignedDoctorUid': parsed.assignedDoctorUid,
      'riskLevel': parsed.assessment.carePlan.action,
      'recommendedAction': parsed.assessment.carePlan.action,
      'status': 'queued',
      'consentScopes': parsed.consent.scopes.map((scope) => scope.name).toList()
        ..sort(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(
      _firestore.doc(_paths.patientIdentityDocument(caseId)),
      {
        'fullName': parsed.identity.fullName,
        'dateOfBirth': parsed.identity.dateOfBirth
            .toIso8601String()
            .split('T')
            .first,
        'phone': parsed.identity.phone,
        'pinCode': parsed.identity.pinCode,
        'state': parsed.identity.state,
        'district': parsed.identity.district,
        'village': parsed.identity.village,
        'consentId': consentId,
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _firestore.doc(_paths.consentDocument(caseId, consentId)),
      {
        ...parsed.consent.toJson(),
        'consentId': consentId,
        'ashaUid': actor.uid,
        'serverRecordedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _firestore.doc(
        _paths.screeningDocument(caseId, parsed.assessment.visitId),
      ),
      {
        ...parsed.assessment.toJson(),
        'uploadedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _firestore.doc(_paths.doctorPackageDocument(caseId, packageId)),
      {
        'packageId': packageId,
        'visitId': parsed.assessment.visitId,
        'doctorUid': parsed.assignedDoctorUid,
        'ashaUid': actor.uid,
        'status': 'queued',
        'doctorBrief': parsed.assessment.carePlan.doctorBrief,
        'imageRefs': uploadedPaths,
        'consentId': consentId,
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    for (final storagePath in uploadedPaths) {
      final objectId = 'roiImage-${storagePath.split('/').last}';
      batch.set(
        _firestore.doc(_paths.storageObjectDocument(caseId, objectId)),
        {
          'objectId': objectId,
          'kind': 'roiImage',
          'storagePath': storagePath,
          'contentType': 'image/jpeg',
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
    return AssessmentCloudSyncResult(
      caseId: caseId,
      packageId: packageId,
      uploadedStoragePaths: uploadedPaths,
    );
  }

  void _requireUploaderRole(AppRole role) {
    if (role != AppRole.asha && role != AppRole.admin) {
      throw StateError('Only ASHA or admin can upload doctor packages.');
    }
  }

  String _caseId(FullAssessment assessment) {
    final raw = '${assessment.patientHash}-${assessment.visitId}';
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }
}

class IdentifiedAssessmentCloudPayload {
  const IdentifiedAssessmentCloudPayload({
    required this.identity,
    required this.clinicalRecord,
    required this.assessment,
    required this.consent,
    required this.assignedDoctorUid,
  });

  final IdentityRecord identity;
  final ClinicalRecord clinicalRecord;
  final FullAssessment assessment;
  final ConsentRecord consent;
  final String assignedDoctorUid;

  factory IdentifiedAssessmentCloudPayload.fromJson(Map<String, Object?> json) {
    final identity = IdentityRecord.fromJson(
      Map<String, Object?>.from(json['patient'] as Map),
    );
    final clinicalRecord = ClinicalRecord.fromJson(
      Map<String, Object?>.from(json['clinical'] as Map),
    );
    final assessment = FullAssessment.fromJson(
      Map<String, Object?>.from(json['assessment'] as Map),
    );
    final consent = ConsentRecord.fromJson(
      Map<String, Object?>.from(json['consent'] as Map),
    );
    if (clinicalRecord.patientHash != assessment.patientHash ||
        consent.visitId != assessment.visitId ||
        consent.patientHash != assessment.patientHash) {
      throw StateError('Queued doctor package payload is inconsistent.');
    }
    final assignedDoctorUid = json['assignedDoctorUid'] as String? ?? '';
    if (assignedDoctorUid.trim().isEmpty) {
      throw StateError('Queued doctor package has no assigned doctor.');
    }
    return IdentifiedAssessmentCloudPayload(
      identity: identity,
      clinicalRecord: clinicalRecord,
      assessment: assessment,
      consent: consent,
      assignedDoctorUid: assignedDoctorUid.trim(),
    );
  }
}

class FirebaseQueuedSyncUploader implements QueuedSyncUploader {
  FirebaseQueuedSyncUploader({
    required FirebaseUserProfile actor,
    AssessmentCloudSyncService? assessmentService,
    ResearchCloudFunctionUploader? researchUploader,
  }) : _actor = actor,
       _assessmentService = assessmentService ?? AssessmentCloudSyncService(),
       _researchUploader = researchUploader ?? ResearchCloudFunctionUploader();

  final FirebaseUserProfile _actor;
  final AssessmentCloudSyncService _assessmentService;
  final ResearchCloudFunctionUploader _researchUploader;

  @override
  Future<void> upload(SyncQueueItem item) async {
    switch (item.kind) {
      case 'identified_assessment_doctor_package':
        await _assessmentService.uploadIdentifiedAssessmentPackage(
          actor: _actor,
          payload: item.payload,
        );
        return;
      case 'research_dataset_row':
        await _researchUploader.uploadResearchExport(item.payload);
        return;
      default:
        throw StateError(
          'Queue item ${item.kind} is not a complete upload payload.',
        );
    }
  }
}
