import '../data/local_database.dart';
import '../data/models.dart';
import '../consent/consent.dart';
import '../pipeline/screening_pipeline.dart';

class DoctorPackage {
  const DoctorPackage({
    required this.packageId,
    required this.visitId,
    required this.patientHash,
    required this.createdAt,
    required this.doctorBrief,
    required this.siteResults,
    required this.hypotheses,
    required this.delta,
    required this.carePlanAction,
    required this.reasoning,
    required this.citations,
    required this.imageReferences,
  });

  final String packageId;
  final String visitId;
  final String patientHash;
  final DateTime createdAt;
  final String doctorBrief;
  final List<Map<String, Object?>> siteResults;
  final List<Map<String, Object?>> hypotheses;
  final Map<String, Object?> delta;
  final String carePlanAction;
  final String reasoning;
  final List<String> citations;
  final List<String> imageReferences;

  Map<String, Object?> toJson() => {
    'packageId': packageId,
    'visitId': visitId,
    'patientHash': patientHash,
    'createdAt': createdAt.toIso8601String(),
    'doctorBrief': doctorBrief,
    'siteResults': siteResults,
    'hypotheses': hypotheses,
    'delta': delta,
    'carePlanAction': carePlanAction,
    'reasoning': reasoning,
    'citations': citations,
    'imageReferences': imageReferences,
  };
}

class DoctorPackageBuilder {
  const DoctorPackageBuilder();

  DoctorPackage build(FullAssessment assessment) {
    final imageReferences = assessment.siteResults
        .map((site) => site.roiImagePath)
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .toList();
    final package = DoctorPackage(
      packageId: 'doctor-${assessment.visitId}',
      visitId: assessment.visitId,
      patientHash: assessment.patientHash,
      createdAt: DateTime.now().toUtc(),
      doctorBrief: assessment.carePlan.doctorBrief,
      siteResults: assessment.siteResults.map((site) => site.toJson()).toList(),
      hypotheses: assessment.hypotheses
          .map((hypothesis) => hypothesis.toJson())
          .toList(),
      delta: assessment.delta.toJson(),
      carePlanAction: assessment.carePlan.action,
      reasoning: assessment.thinking,
      citations: assessment.citations,
      imageReferences: imageReferences,
    );
    _assertNoIdentityFields(package.toJson());
    return package;
  }

  Future<SyncQueueItem> queue({
    required LocalDatabase database,
    required FullAssessment assessment,
  }) async {
    final package = build(assessment);
    return database.enqueueSync(
      visitId: assessment.visitId,
      kind: 'doctor_package',
      payload: package.toJson(),
    );
  }

  void _assertNoIdentityFields(Object? value) {
    const blocked = {'fullName', 'phone', 'dateOfBirth', 'pinCode', 'dob'};
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (blocked.contains(key)) {
          throw StateError('Doctor package contains identity field: $key');
        }
        _assertNoIdentityFields(entry.value);
      }
    } else if (value is List) {
      for (final item in value) {
        _assertNoIdentityFields(item);
      }
    }
  }
}

class IdentifiedDoctorPackageBuilder {
  const IdentifiedDoctorPackageBuilder({
    ConsentGate consentGate = const ConsentGate(),
  }) : _consentGate = consentGate;

  final ConsentGate _consentGate;

  Map<String, Object?> build({
    required IdentityRecord identity,
    required ClinicalRecord clinicalRecord,
    required ScreeningResult result,
    required ConsentRecord consent,
  }) {
    _consentGate.requireScope(consent, ConsentScope.doctorShare);
    if (consent.visitId != result.visitId ||
        consent.patientHash != result.patientHash ||
        clinicalRecord.patientHash != result.patientHash) {
      throw StateError('Consent, clinical record, and result do not match.');
    }
    final imageReferences = result.segmentation
        .map((artifact) => artifact.roiImagePath)
        .where((path) => path.trim().isNotEmpty)
        .toList();
    return {
      'packageId': 'doctor-${result.visitId}',
      'visitId': result.visitId,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'patient': {
        'fullName': identity.fullName,
        'dateOfBirth': identity.dateOfBirth.toIso8601String(),
        'phone': identity.phone,
        'village': identity.village,
        'pinCode': identity.pinCode,
      },
      'clinical': clinicalRecord.toJson(),
      'screening': result.toJson(),
      'doctorBrief': result.doctorSummary,
      'imageReferences': imageReferences,
      'consent': consent.toJson(),
    };
  }

  Future<SyncQueueItem> queue({
    required LocalDatabase database,
    required IdentityRecord identity,
    required ClinicalRecord clinicalRecord,
    required ScreeningResult result,
    required ConsentRecord consent,
  }) async {
    final package = build(
      identity: identity,
      clinicalRecord: clinicalRecord,
      result: result,
      consent: consent,
    );
    return database.enqueueSync(
      visitId: result.visitId,
      kind: 'identified_doctor_package',
      payload: package,
    );
  }
}

class IdentifiedAssessmentDoctorPackageBuilder {
  const IdentifiedAssessmentDoctorPackageBuilder({
    ConsentGate consentGate = const ConsentGate(),
  }) : _consentGate = consentGate;

  final ConsentGate _consentGate;

  Map<String, Object?> build({
    required IdentityRecord identity,
    required ClinicalRecord clinicalRecord,
    required FullAssessment assessment,
    required ConsentRecord consent,
    required String assignedDoctorUid,
  }) {
    _consentGate.requireScope(consent, ConsentScope.doctorShare);
    if (assignedDoctorUid.trim().isEmpty) {
      throw ArgumentError.value(
        assignedDoctorUid,
        'assignedDoctorUid',
        'Doctor package requires an assigned doctor.',
      );
    }
    if (consent.visitId != assessment.visitId ||
        consent.patientHash != assessment.patientHash ||
        clinicalRecord.patientHash != assessment.patientHash) {
      throw StateError(
        'Consent, clinical record, and assessment do not match.',
      );
    }
    final imageReferences = assessment.siteResults
        .map((site) => site.roiImagePath)
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .toList();
    return {
      'packageId': 'doctor-${assessment.visitId}',
      'visitId': assessment.visitId,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'assignedDoctorUid': assignedDoctorUid.trim(),
      'patient': {
        'fullName': identity.fullName,
        'dateOfBirth': identity.dateOfBirth.toIso8601String(),
        'phone': identity.phone,
        'village': identity.village,
        'pinCode': identity.pinCode,
        'state': identity.state,
        'district': identity.district,
      },
      'clinical': clinicalRecord.toJson(),
      'assessment': assessment.toJson(),
      'doctorBrief': assessment.carePlan.doctorBrief,
      'imageReferences': imageReferences,
      'consent': consent.toJson(),
    };
  }

  Future<SyncQueueItem> queue({
    required LocalDatabase database,
    required IdentityRecord identity,
    required ClinicalRecord clinicalRecord,
    required FullAssessment assessment,
    required ConsentRecord consent,
    required String assignedDoctorUid,
  }) async {
    final package = build(
      identity: identity,
      clinicalRecord: clinicalRecord,
      assessment: assessment,
      consent: consent,
      assignedDoctorUid: assignedDoctorUid,
    );
    return database.enqueueSync(
      visitId: assessment.visitId,
      kind: 'identified_assessment_doctor_package',
      payload: package,
    );
  }
}
