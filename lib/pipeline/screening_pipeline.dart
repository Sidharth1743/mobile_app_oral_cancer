import '../data/models.dart';
import '../ehr/ehr_models.dart';

class ScreeningInput {
  const ScreeningInput({
    required this.visitId,
    required this.identity,
    required this.clinicalRecord,
    required this.videoPathsBySite,
    required this.previousVisits,
  });

  final String visitId;
  final IdentityRecord identity;
  final ClinicalRecord clinicalRecord;
  final Map<String, String> videoPathsBySite;
  final List<EhrVisit> previousVisits;

  Map<String, Object?> toJson() => {
    'visitId': visitId,
    'identity': identity.toJson(),
    'clinicalRecord': clinicalRecord.toJson(),
    'videoPathsBySite': videoPathsBySite,
    'previousVisits': previousVisits.map((visit) => visit.toJson()).toList(),
  };

  factory ScreeningInput.fromJson(Map<String, Object?> json) => ScreeningInput(
    visitId: json['visitId'] as String,
    identity: IdentityRecord.fromJson(
      Map<String, Object?>.from(json['identity'] as Map),
    ),
    clinicalRecord: ClinicalRecord.fromJson(
      Map<String, Object?>.from(json['clinicalRecord'] as Map),
    ),
    videoPathsBySite: Map<String, String>.from(json['videoPathsBySite'] as Map),
    previousVisits: (json['previousVisits'] as List)
        .map(
          (visit) => EhrVisit.fromJson(Map<String, Object?>.from(visit as Map)),
        )
        .toList(),
  );
}

class SegmentationArtifact {
  const SegmentationArtifact({
    required this.siteId,
    required this.roiImagePath,
    required this.maskPath,
    required this.lesionSizeMm,
  });

  final String siteId;
  final String roiImagePath;
  final String maskPath;
  final double lesionSizeMm;

  Map<String, Object?> toJson() => {
    'siteId': siteId,
    'roiImagePath': roiImagePath,
    'maskPath': maskPath,
    'lesionSizeMm': lesionSizeMm,
  };

  factory SegmentationArtifact.fromJson(Map<String, Object?> json) =>
      SegmentationArtifact(
        siteId: json['siteId'] as String,
        roiImagePath: json['roiImagePath'] as String,
        maskPath: json['maskPath'] as String,
        lesionSizeMm: (json['lesionSizeMm'] as num).toDouble(),
      );
}

class ScreeningResult {
  const ScreeningResult({
    required this.visitId,
    required this.patientHash,
    required this.createdAt,
    required this.riskLevel,
    required this.siteResults,
    required this.segmentation,
    required this.differentials,
    required this.uncertainty,
    required this.patientSummary,
    required this.ashaSummary,
    required this.doctorSummary,
    required this.recommendedAction,
    required this.modelName,
  });

  final String visitId;
  final String patientHash;
  final DateTime createdAt;
  final String riskLevel;
  final List<LesionSiteResult> siteResults;
  final List<SegmentationArtifact> segmentation;
  final List<HypothesisResult> differentials;
  final double uncertainty;
  final String patientSummary;
  final String ashaSummary;
  final String doctorSummary;
  final String recommendedAction;
  final String modelName;

  Map<String, Object?> toJson() => {
    'visitId': visitId,
    'patientHash': patientHash,
    'createdAt': createdAt.toIso8601String(),
    'riskLevel': riskLevel,
    'siteResults': siteResults.map((site) => site.toJson()).toList(),
    'segmentation': segmentation.map((item) => item.toJson()).toList(),
    'differentials': differentials.map((item) => item.toJson()).toList(),
    'uncertainty': uncertainty,
    'patientSummary': patientSummary,
    'ashaSummary': ashaSummary,
    'doctorSummary': doctorSummary,
    'recommendedAction': recommendedAction,
    'modelName': modelName,
  };

  factory ScreeningResult.fromJson(
    Map<String, Object?> json,
  ) => ScreeningResult(
    visitId: json['visitId'] as String,
    patientHash: json['patientHash'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    riskLevel: json['riskLevel'] as String,
    siteResults: (json['siteResults'] as List)
        .map(
          (site) =>
              LesionSiteResult.fromJson(Map<String, Object?>.from(site as Map)),
        )
        .toList(),
    segmentation: (json['segmentation'] as List)
        .map(
          (item) => SegmentationArtifact.fromJson(
            Map<String, Object?>.from(item as Map),
          ),
        )
        .toList(),
    differentials: (json['differentials'] as List)
        .map(
          (item) =>
              HypothesisResult.fromJson(Map<String, Object?>.from(item as Map)),
        )
        .toList(),
    uncertainty: (json['uncertainty'] as num).toDouble(),
    patientSummary: json['patientSummary'] as String,
    ashaSummary: json['ashaSummary'] as String,
    doctorSummary: json['doctorSummary'] as String,
    recommendedAction: json['recommendedAction'] as String,
    modelName: json['modelName'] as String,
  );
}

abstract interface class ScreeningPipeline {
  Future<ScreeningResult> analyze(ScreeningInput input);
}
