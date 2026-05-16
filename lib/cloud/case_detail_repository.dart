import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/role_auth.dart';

class CloudCaseDetail {
  const CloudCaseDetail({
    required this.caseId,
    required this.summary,
    this.screening,
    this.doctorPackage,
    this.consent,
    this.patientIdentity,
    this.storageObjects = const [],
  });

  final String caseId;
  final Map<String, Object?> summary;
  final Map<String, Object?>? screening;
  final Map<String, Object?>? doctorPackage;
  final Map<String, Object?>? consent;
  final Map<String, Object?>? patientIdentity;
  final List<Map<String, Object?>> storageObjects;
}

class CloudResearchExportDetail {
  const CloudResearchExportDetail({
    required this.exportId,
    required this.data,
  });

  final String exportId;
  final Map<String, Object?> data;
}

class CaseDetailRepository {
  CaseDetailRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<CloudCaseDetail> loadCaseDetail({
    required String caseId,
    required String visitId,
    required AppRole role,
  }) async {
    final caseSnap = await _firestore.doc('cases/$caseId').get();
    if (!caseSnap.exists) {
      throw StateError('Case not found: $caseId');
    }
    final summary = Map<String, Object?>.from(caseSnap.data() ?? {});

    Map<String, Object?>? screening;
    final screeningSnap = await _firestore
        .doc('cases/$caseId/screenings/$visitId')
        .get();
    if (screeningSnap.exists) {
      screening = Map<String, Object?>.from(screeningSnap.data() ?? {});
    }

    Map<String, Object?>? doctorPackage;
    final packageSnap = await _firestore
        .doc('cases/$caseId/doctorPackages/doctor-$visitId')
        .get();
    if (packageSnap.exists) {
      doctorPackage = Map<String, Object?>.from(packageSnap.data() ?? {});
    }

    Map<String, Object?>? consent;
    final consentId = 'consent-$visitId';
    final consentSnap = await _firestore
        .doc('cases/$caseId/consents/$consentId')
        .get();
    if (consentSnap.exists) {
      consent = Map<String, Object?>.from(consentSnap.data() ?? {});
    }

    Map<String, Object?>? patientIdentity;
    if (_canReadIdentity(role)) {
      final identitySnap = await _firestore
          .doc('cases/$caseId/private/patientIdentity')
          .get();
      if (identitySnap.exists) {
        patientIdentity = Map<String, Object?>.from(identitySnap.data() ?? {});
      }
    }

    final storageSnap = await _firestore
        .collection('cases/$caseId/storageObjects')
        .get();
    final storageObjects = storageSnap.docs
        .map((doc) => {'objectId': doc.id, ...doc.data()})
        .toList();

    return CloudCaseDetail(
      caseId: caseId,
      summary: summary,
      screening: screening,
      doctorPackage: doctorPackage,
      consent: consent,
      patientIdentity: patientIdentity,
      storageObjects: storageObjects,
    );
  }

  Future<CloudResearchExportDetail> loadResearchExport(String exportId) async {
    final snap = await _firestore.doc('researchExports/$exportId').get();
    if (!snap.exists) {
      throw StateError('Research export not found: $exportId');
    }
    return CloudResearchExportDetail(
      exportId: exportId,
      data: Map<String, Object?>.from(snap.data() ?? {}),
    );
  }

  bool _canReadIdentity(AppRole role) {
    return role == AppRole.asha ||
        role == AppRole.doctor ||
        role == AppRole.admin;
  }
}
