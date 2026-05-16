import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_role_auth.dart';

class CloudCaseSummary {
  const CloudCaseSummary({
    required this.caseId,
    required this.visitId,
    required this.patientHash,
    required this.status,
    required this.recommendedAction,
    required this.updatedAt,
    this.district,
    this.riskLevel,
    this.state,
    this.villageCode,
    this.consentScopes = const [],
  });

  final String caseId;
  final String visitId;
  final String patientHash;
  final String status;
  final String recommendedAction;
  final DateTime updatedAt;
  final String? district;
  final String? riskLevel;
  final String? state;
  final String? villageCode;
  final List<String> consentScopes;

  factory CloudCaseSummary.fromJson(Map<String, Object?> json) {
    return CloudCaseSummary(
      caseId: json['caseId'] as String,
      visitId: json['visitId'] as String,
      patientHash: json['patientHash'] as String,
      status: json['status'] as String? ?? 'unknown',
      recommendedAction: json['recommendedAction'] as String? ?? '',
      district: json['district'] as String?,
      riskLevel: json['riskLevel'] as String?,
      state: json['state'] as String?,
      villageCode: json['villageCode'] as String?,
      consentScopes: List<String>.from(json['consentScopes'] as List? ?? const []),
      updatedAt: _dateTimeFromCloud(json['updatedAt']) ?? DateTime.utc(1970),
    );
  }
}

class ResearchExportSummary {
  const ResearchExportSummary({
    required this.exportId,
    required this.visitId,
    required this.status,
    required this.createdAt,
  });

  final String exportId;
  final String visitId;
  final String status;
  final DateTime createdAt;

  factory ResearchExportSummary.fromJson(Map<String, Object?> json) {
    return ResearchExportSummary(
      exportId: json['exportId'] as String,
      visitId: json['visitId'] as String? ?? '',
      status: json['status'] as String? ?? 'queued',
      createdAt: _dateTimeFromCloud(json['createdAt']) ?? DateTime.utc(1970),
    );
  }
}

abstract interface class RoleHomeRepository {
  Stream<List<CloudCaseSummary>> ashaCases(FirebaseUserProfile profile);

  Stream<List<CloudCaseSummary>> doctorCases(FirebaseUserProfile profile);

  Stream<List<ResearchExportSummary>> researchExports(
    FirebaseUserProfile profile,
  );

  Stream<List<CloudCaseSummary>> ngoProgramCases();
}

class FirestoreRoleHomeRepository implements RoleHomeRepository {
  FirestoreRoleHomeRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Stream<List<CloudCaseSummary>> ashaCases(FirebaseUserProfile profile) {
    return _firestore
        .collection('cases')
        .where('createdByUid', isEqualTo: profile.uid)
        .limit(50)
        .snapshots()
        .map(_sortedCaseSummaries);
  }

  @override
  Stream<List<CloudCaseSummary>> doctorCases(FirebaseUserProfile profile) {
    return _firestore
        .collection('cases')
        .where('assignedDoctorUid', isEqualTo: profile.uid)
        .limit(50)
        .snapshots()
        .map(_sortedCaseSummaries);
  }

  @override
  Stream<List<CloudCaseSummary>> ngoProgramCases() {
    return _firestore
        .collection('cases')
        .limit(200)
        .snapshots()
        .map(_sortedCaseSummaries);
  }

  @override
  Stream<List<ResearchExportSummary>> researchExports(
    FirebaseUserProfile profile,
  ) {
    return _firestore
        .collection('researchExports')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => ResearchExportSummary.fromJson({
                  'exportId': doc.id,
                  ...doc.data(),
                }),
              )
              .toList(),
        );
  }

  List<CloudCaseSummary> _sortedCaseSummaries(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final cases = _caseSummaries(snapshot);
    cases.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return cases;
  }

  List<CloudCaseSummary> _caseSummaries(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs
        .map(
          (doc) => CloudCaseSummary.fromJson({'caseId': doc.id, ...doc.data()}),
        )
        .toList();
  }
}

DateTime? _dateTimeFromCloud(Object? value) {
  if (value is Timestamp) {
    return value.toDate().toUtc();
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}
