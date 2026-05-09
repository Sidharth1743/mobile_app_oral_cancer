import 'dart:convert';

class GeoCoords {
  const GeoCoords({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  Map<String, Object?> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };

  factory GeoCoords.fromJson(Map<String, Object?> json) => GeoCoords(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
  );
}

class IdentityRecord {
  const IdentityRecord({
    required this.fullName,
    required this.village,
    required this.dateOfBirth,
    required this.phone,
    required this.pinCode,
    this.state = 'Tamil Nadu',
    this.district,
  });

  final String fullName;
  final String village;
  final DateTime dateOfBirth;
  final String phone;
  final String pinCode;
  final String state;
  final String? district;

  Map<String, Object?> toJson() => {
    'fullName': fullName,
    'village': village,
    'dateOfBirth': dateOfBirth.toIso8601String(),
    'phone': phone,
    'pinCode': pinCode,
    'state': state,
    'district': district,
  };

  factory IdentityRecord.fromJson(Map<String, Object?> json) => IdentityRecord(
    fullName: json['fullName'] as String,
    village: json['village'] as String,
    dateOfBirth: DateTime.parse(json['dateOfBirth'] as String),
    phone: json['phone'] as String,
    pinCode: json['pinCode'] as String,
    state: json['state'] as String? ?? 'Tamil Nadu',
    district: json['district'] as String?,
  );
}

class ClinicalRecord {
  const ClinicalRecord({
    required this.id,
    required this.patientHash,
    required this.ageBand,
    required this.pinPrefix,
    required this.villageCode,
    required this.gender,
    required this.tobaccoBrand,
    required this.chewsPerDay,
    required this.yearsUsed,
    required this.alcoholUse,
    required this.cei,
    required this.createdAt,
    this.coords,
  });

  final String id;
  final String patientHash;
  final String ageBand;
  final String pinPrefix;
  final String villageCode;
  final String gender;
  final String tobaccoBrand;
  final int chewsPerDay;
  final int yearsUsed;
  final bool alcoholUse;
  final double cei;
  final DateTime createdAt;
  final GeoCoords? coords;

  Map<String, Object?> toJson() => {
    'id': id,
    'patientHash': patientHash,
    'ageBand': ageBand,
    'pinPrefix': pinPrefix,
    'villageCode': villageCode,
    'gender': gender,
    'tobaccoBrand': tobaccoBrand,
    'chewsPerDay': chewsPerDay,
    'yearsUsed': yearsUsed,
    'alcoholUse': alcoholUse,
    'cei': cei,
    'createdAt': createdAt.toIso8601String(),
    'coords': coords?.toJson(),
  };

  factory ClinicalRecord.fromJson(Map<String, Object?> json) => ClinicalRecord(
    id: json['id'] as String,
    patientHash: json['patientHash'] as String,
    ageBand: json['ageBand'] as String,
    pinPrefix: json['pinPrefix'] as String,
    villageCode: json['villageCode'] as String,
    gender: json['gender'] as String,
    tobaccoBrand: json['tobaccoBrand'] as String,
    chewsPerDay: (json['chewsPerDay'] as num).toInt(),
    yearsUsed: (json['yearsUsed'] as num).toInt(),
    alcoholUse: json['alcoholUse'] as bool,
    cei: (json['cei'] as num).toDouble(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    coords: json['coords'] == null
        ? null
        : GeoCoords.fromJson(Map<String, Object?>.from(json['coords'] as Map)),
  );
}

class CapturedSiteFrames {
  const CapturedSiteFrames({
    required this.siteId,
    required this.siteLabel,
    required this.framePaths,
    required this.createdAt,
    this.roiPath,
  });

  final String siteId;
  final String siteLabel;
  final List<String> framePaths;
  final String? roiPath;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'siteId': siteId,
    'siteLabel': siteLabel,
    'framePaths': framePaths,
    'roiPath': roiPath,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CapturedSiteFrames.fromJson(Map<String, Object?> json) =>
      CapturedSiteFrames(
        siteId: json['siteId'] as String,
        siteLabel: json['siteLabel'] as String,
        framePaths: List<String>.from(json['framePaths'] as List),
        roiPath: json['roiPath'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class LesionSiteResult {
  const LesionSiteResult({
    required this.siteId,
    required this.siteLabel,
    required this.suspicionScore,
    required this.findings,
    required this.roiImagePath,
    required this.uncertain,
  });

  final String siteId;
  final String siteLabel;
  final double suspicionScore;
  final String findings;
  final String? roiImagePath;
  final bool uncertain;

  Map<String, Object?> toJson() => {
    'siteId': siteId,
    'siteLabel': siteLabel,
    'suspicionScore': suspicionScore,
    'findings': findings,
    'roiImagePath': roiImagePath,
    'uncertain': uncertain,
  };

  factory LesionSiteResult.fromJson(Map<String, Object?> json) =>
      LesionSiteResult(
        siteId: json['siteId'] as String,
        siteLabel: json['siteLabel'] as String,
        suspicionScore: (json['suspicionScore'] as num).toDouble(),
        findings: json['findings'] as String,
        roiImagePath: json['roiImagePath'] as String?,
        uncertain: json['uncertain'] as bool,
      );
}

class HypothesisResult {
  const HypothesisResult({
    required this.label,
    required this.probability,
    required this.rationale,
  });

  final String label;
  final double probability;
  final String rationale;

  Map<String, Object?> toJson() => {
    'label': label,
    'probability': probability,
    'rationale': rationale,
  };

  factory HypothesisResult.fromJson(Map<String, Object?> json) =>
      HypothesisResult(
        label: json['label'] as String,
        probability: (json['probability'] as num).toDouble(),
        rationale: json['rationale'] as String,
      );
}

class DeltaResult {
  const DeltaResult({
    required this.summary,
    required this.sizeChangeMm,
    required this.concernIncreased,
  });

  final String summary;
  final double sizeChangeMm;
  final bool concernIncreased;

  Map<String, Object?> toJson() => {
    'summary': summary,
    'sizeChangeMm': sizeChangeMm,
    'concernIncreased': concernIncreased,
  };

  factory DeltaResult.fromJson(Map<String, Object?> json) => DeltaResult(
    summary: json['summary'] as String,
    sizeChangeMm: (json['sizeChangeMm'] as num).toDouble(),
    concernIncreased: json['concernIncreased'] as bool,
  );
}

class CarePlan {
  const CarePlan({
    required this.action,
    required this.patientMessage,
    required this.ashaMessage,
    required this.rescreenDate,
    required this.doctorBrief,
  });

  final String action;
  final String patientMessage;
  final String ashaMessage;
  final DateTime rescreenDate;
  final String doctorBrief;

  Map<String, Object?> toJson() => {
    'action': action,
    'patientMessage': patientMessage,
    'ashaMessage': ashaMessage,
    'rescreenDate': rescreenDate.toIso8601String(),
    'doctorBrief': doctorBrief,
  };

  factory CarePlan.fromJson(Map<String, Object?> json) => CarePlan(
    action: json['action'] as String,
    patientMessage: json['patientMessage'] as String,
    ashaMessage: json['ashaMessage'] as String,
    rescreenDate: DateTime.parse(json['rescreenDate'] as String),
    doctorBrief: json['doctorBrief'] as String,
  );
}

class FullAssessment {
  const FullAssessment({
    required this.visitId,
    required this.patientHash,
    required this.createdAt,
    required this.siteResults,
    required this.hypotheses,
    required this.delta,
    required this.carePlan,
    required this.thinking,
    required this.citations,
  });

  final String visitId;
  final String patientHash;
  final DateTime createdAt;
  final List<LesionSiteResult> siteResults;
  final List<HypothesisResult> hypotheses;
  final DeltaResult delta;
  final CarePlan carePlan;
  final String thinking;
  final List<String> citations;

  Map<String, Object?> toJson() => {
    'visitId': visitId,
    'patientHash': patientHash,
    'createdAt': createdAt.toIso8601String(),
    'siteResults': siteResults.map((site) => site.toJson()).toList(),
    'hypotheses': hypotheses.map((hypothesis) => hypothesis.toJson()).toList(),
    'delta': delta.toJson(),
    'carePlan': carePlan.toJson(),
    'thinking': thinking,
    'citations': citations,
  };

  String toJsonString() => jsonEncode(toJson());

  factory FullAssessment.fromJson(Map<String, Object?> json) => FullAssessment(
    visitId: json['visitId'] as String,
    patientHash: json['patientHash'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    siteResults: (json['siteResults'] as List)
        .map(
          (site) =>
              LesionSiteResult.fromJson(Map<String, Object?>.from(site as Map)),
        )
        .toList(),
    hypotheses: (json['hypotheses'] as List)
        .map(
          (item) =>
              HypothesisResult.fromJson(Map<String, Object?>.from(item as Map)),
        )
        .toList(),
    delta: DeltaResult.fromJson(
      Map<String, Object?>.from(json['delta'] as Map),
    ),
    carePlan: CarePlan.fromJson(
      Map<String, Object?>.from(json['carePlan'] as Map),
    ),
    thinking: json['thinking'] as String,
    citations: List<String>.from(json['citations'] as List),
  );

  factory FullAssessment.fromJsonString(String source) =>
      FullAssessment.fromJson(
        Map<String, Object?>.from(jsonDecode(source) as Map),
      );
}
