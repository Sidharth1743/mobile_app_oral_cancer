import '../consent/consent.dart';
import '../data/models.dart';
import '../pipeline/screening_pipeline.dart';

class CloudCasePayloadBuilder {
  const CloudCasePayloadBuilder();

  Map<String, Object?> buildCaseMetadata({
    required String caseId,
    required String createdByUid,
    required String state,
    required String district,
    required ClinicalRecord clinicalRecord,
    required ScreeningResult result,
    required ConsentRecord consent,
    String? assignedDoctorUid,
  }) {
    _validateResultConsent(result, consent);
    return {
      'caseId': caseId,
      'visitId': result.visitId,
      'patientHash': result.patientHash,
      'state': state,
      'district': district,
      'villageCode': clinicalRecord.villageCode,
      'createdByUid': createdByUid,
      'assignedDoctorUid': assignedDoctorUid,
      'riskLevel': result.riskLevel,
      'recommendedAction': result.recommendedAction,
      'status': 'queued',
      'consentScopes': consent.scopes.map((scope) => scope.name).toList()
        ..sort(),
    };
  }

  Map<String, Object?> buildPatientIdentity({
    required IdentityRecord identity,
    required ConsentRecord consent,
    required String consentId,
  }) {
    consent.validatePostResult();
    return {
      'fullName': identity.fullName,
      'dateOfBirth': identity.dateOfBirth.toIso8601String().split('T').first,
      'phone': identity.phone,
      'pinCode': identity.pinCode,
      'state': identity.state,
      'district': identity.district,
      'village': identity.village,
      'consentId': consentId,
    };
  }

  Map<String, Object?> buildScreeningResult({
    required ScreeningResult result,
    required ConsentRecord consent,
  }) {
    _validateResultConsent(result, consent);
    return result.toJson();
  }

  void _validateResultConsent(ScreeningResult result, ConsentRecord consent) {
    consent.validatePostResult();
    if (consent.visitId != result.visitId ||
        consent.patientHash != result.patientHash) {
      throw StateError('Consent does not match screening result.');
    }
  }
}
