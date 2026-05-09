import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../consent/consent.dart';
import '../data/models.dart';
import '../pipeline/screening_pipeline.dart';

class ResearchExporter {
  const ResearchExporter({ConsentGate consentGate = const ConsentGate()})
    : _consentGate = consentGate;

  final ConsentGate _consentGate;

  Map<String, Object?> export({
    required IdentityRecord identity,
    required ClinicalRecord clinicalRecord,
    required ScreeningResult result,
    required ConsentRecord consent,
    required String studySecret,
  }) {
    _consentGate.requireScope(consent, ConsentScope.researchExport);
    return {
      'studyPatientId': _hmacPatient(identity, studySecret),
      'visitId': result.visitId,
      'createdAt': result.createdAt.toIso8601String(),
      'ageBand': clinicalRecord.ageBand,
      'pinPrefix': clinicalRecord.pinPrefix,
      'villageCode': clinicalRecord.villageCode,
      'gender': clinicalRecord.gender,
      'cei': clinicalRecord.cei,
      'riskLevel': result.riskLevel,
      'uncertainty': result.uncertainty,
      'recommendedAction': result.recommendedAction,
      'modelName': result.modelName,
      'siteResults': result.siteResults
          .map(
            (site) => {
              'siteId': site.siteId,
              'suspicionScore': site.suspicionScore,
              'uncertain': site.uncertain,
            },
          )
          .toList(),
      'segmentation': result.segmentation
          .map(
            (artifact) => {
              'siteId': artifact.siteId,
              'lesionSizeMm': artifact.lesionSizeMm,
            },
          )
          .toList(),
    };
  }

  String _hmacPatient(IdentityRecord identity, String secret) {
    final normalized = [
      identity.fullName.trim().toLowerCase(),
      identity.village.trim().toLowerCase(),
      identity.dateOfBirth.toIso8601String().substring(0, 10),
    ].join('|');
    final digest = Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode(normalized));
    return digest.toString();
  }
}

class AssessmentResearchExporter {
  const AssessmentResearchExporter({
    ConsentGate consentGate = const ConsentGate(),
  }) : _consentGate = consentGate;

  final ConsentGate _consentGate;

  Map<String, Object?> export({
    required IdentityRecord identity,
    required ClinicalRecord clinicalRecord,
    required FullAssessment assessment,
    required ConsentRecord consent,
    required String studySecret,
  }) {
    _consentGate.requireScope(consent, ConsentScope.researchExport);
    if (clinicalRecord.patientHash != assessment.patientHash ||
        consent.visitId != assessment.visitId ||
        consent.patientHash != assessment.patientHash) {
      throw StateError(
        'Consent, clinical record, and assessment do not match.',
      );
    }
    return {
      'studyPatientId': _hmacPatient(identity, studySecret),
      'visitId': assessment.visitId,
      'patientHash': assessment.patientHash,
      'createdAt': assessment.createdAt.toIso8601String(),
      'ageBand': clinicalRecord.ageBand,
      'pinPrefix': clinicalRecord.pinPrefix,
      'villageCode': clinicalRecord.villageCode,
      'gender': clinicalRecord.gender,
      'cei': clinicalRecord.cei,
      'carePlanAction': assessment.carePlan.action,
      'deltaSizeChangeMm': assessment.delta.sizeChangeMm,
      'deltaConcernIncreased': assessment.delta.concernIncreased,
      'siteResults': assessment.siteResults
          .map(
            (site) => {
              'siteId': site.siteId,
              'suspicionScore': site.suspicionScore,
              'uncertain': site.uncertain,
            },
          )
          .toList(),
      'hypotheses': assessment.hypotheses
          .map(
            (hypothesis) => {
              'label': hypothesis.label,
              'probability': hypothesis.probability,
            },
          )
          .toList(),
    };
  }

  String _hmacPatient(IdentityRecord identity, String secret) {
    final normalized = [
      identity.fullName.trim().toLowerCase(),
      identity.village.trim().toLowerCase(),
      identity.dateOfBirth.toIso8601String().substring(0, 10),
    ].join('|');
    final digest = Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode(normalized));
    return digest.toString();
  }
}
