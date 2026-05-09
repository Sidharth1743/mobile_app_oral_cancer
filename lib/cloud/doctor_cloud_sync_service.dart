import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../auth/role_auth.dart';
import '../consent/consent.dart';
import '../data/models.dart';
import '../pipeline/screening_pipeline.dart';
import 'cloud_paths.dart';
import 'cloud_payloads.dart';
import 'cloud_sync_planner.dart';
import 'firebase_role_auth.dart';

class DoctorCloudSyncResult {
  const DoctorCloudSyncResult({
    required this.caseId,
    required this.packageId,
    required this.uploadedStoragePaths,
  });

  final String caseId;
  final String packageId;
  final List<String> uploadedStoragePaths;
}

class DoctorCloudSyncService {
  DoctorCloudSyncService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    CloudPaths paths = const CloudPaths(),
    CloudCasePayloadBuilder payloadBuilder = const CloudCasePayloadBuilder(),
    CloudSyncPlanner planner = const CloudSyncPlanner(),
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _paths = paths,
       _payloadBuilder = payloadBuilder,
       _planner = planner;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final CloudPaths _paths;
  final CloudCasePayloadBuilder _payloadBuilder;
  final CloudSyncPlanner _planner;

  Future<DoctorCloudSyncResult> uploadDoctorPackage({
    required FirebaseUserProfile actor,
    required IdentityRecord identity,
    required ClinicalRecord clinicalRecord,
    required ScreeningResult result,
    required ConsentRecord consent,
    required String assignedDoctorUid,
  }) async {
    _requireUploaderRole(actor.role);
    if (assignedDoctorUid.trim().isEmpty) {
      throw ArgumentError.value(
        assignedDoctorUid,
        'assignedDoctorUid',
        'Doctor package requires an assigned doctor.',
      );
    }
    const ConsentGate().requireScope(consent, ConsentScope.doctorShare);
    final caseId = _caseId(result);
    final consentId = 'consent-${result.visitId}';
    final packageId = 'doctor-${result.visitId}';
    final plan = _planner.doctorSharePlan(
      caseId: caseId,
      result: result,
      consent: consent,
    );

    final uploadedPaths = <String>[];
    for (final upload in plan.uploads) {
      await _uploadObject(upload);
      uploadedPaths.add(upload.storagePath);
    }

    final caseMetadata = _payloadBuilder.buildCaseMetadata(
      caseId: caseId,
      createdByUid: actor.uid,
      state: identity.state,
      district: identity.district ?? '',
      clinicalRecord: clinicalRecord,
      result: result,
      consent: consent,
      assignedDoctorUid: assignedDoctorUid,
    );
    final batch = _firestore.batch();
    batch.set(_firestore.doc(_paths.caseDocument(caseId)), {
      ...caseMetadata,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(
      _firestore.doc(_paths.patientIdentityDocument(caseId)),
      {
        ..._payloadBuilder.buildPatientIdentity(
          identity: identity,
          consent: consent,
          consentId: consentId,
        ),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _firestore.doc(_paths.consentDocument(caseId, consentId)),
      {
        ...consent.toJson(),
        'consentId': consentId,
        'ashaUid': actor.uid,
        'serverRecordedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _firestore.doc(_paths.screeningDocument(caseId, result.visitId)),
      {
        ..._payloadBuilder.buildScreeningResult(
          result: result,
          consent: consent,
        ),
        'uploadedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _firestore.doc(_paths.doctorPackageDocument(caseId, packageId)),
      {
        'packageId': packageId,
        'visitId': result.visitId,
        'doctorUid': assignedDoctorUid,
        'ashaUid': actor.uid,
        'status': 'queued',
        'doctorBrief': result.doctorSummary,
        'imageRefs': uploadedPaths,
        'consentId': consentId,
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    for (final upload in plan.uploads) {
      final objectId = '${upload.kind}-${upload.siteId}';
      batch.set(
        _firestore.doc(_paths.storageObjectDocument(caseId, objectId)),
        {
          'objectId': objectId,
          'kind': upload.kind,
          'siteId': upload.siteId,
          'storagePath': upload.storagePath,
          'contentType': upload.contentType,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    final auditRef = _firestore.collection('auditEvents').doc();
    batch.set(auditRef, {
      'eventId': auditRef.id,
      'actorUid': actor.uid,
      'role': const AppRoleCodec().toName(actor.role),
      'action': 'doctor_package_uploaded',
      'caseId': caseId,
      'visitId': result.visitId,
      'createdAt': FieldValue.serverTimestamp(),
      'result': 'allowed',
    });
    await batch.commit();
    return DoctorCloudSyncResult(
      caseId: caseId,
      packageId: packageId,
      uploadedStoragePaths: uploadedPaths,
    );
  }

  Future<void> _uploadObject(CloudUploadObject upload) async {
    _paths.validateUploadPath(upload.storagePath);
    final file = File(upload.localPath);
    if (!await file.exists()) {
      throw StateError('Upload file does not exist: ${upload.localPath}');
    }
    await _storage
        .ref(upload.storagePath)
        .putFile(file, SettableMetadata(contentType: upload.contentType));
  }

  void _requireUploaderRole(AppRole role) {
    if (role != AppRole.asha && role != AppRole.admin) {
      throw StateError('Only ASHA or admin can upload doctor packages.');
    }
  }

  String _caseId(ScreeningResult result) {
    final raw = '${result.patientHash}-${result.visitId}';
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }
}
