import '../pipeline/screening_pipeline.dart';

class EhrSiteMeasurement {
  const EhrSiteMeasurement({
    required this.siteId,
    required this.siteLabel,
    required this.lesionSizeMm,
    required this.riskLevel,
    required this.recordedAt,
    this.roiImagePath,
    this.maskPath,
  });

  final String siteId;
  final String siteLabel;
  final double lesionSizeMm;
  final String riskLevel;
  final DateTime recordedAt;
  final String? roiImagePath;
  final String? maskPath;

  Map<String, Object?> toJson() => {
    'siteId': siteId,
    'siteLabel': siteLabel,
    'lesionSizeMm': lesionSizeMm,
    'riskLevel': riskLevel,
    'recordedAt': recordedAt.toIso8601String(),
    'roiImagePath': roiImagePath,
    'maskPath': maskPath,
  };

  factory EhrSiteMeasurement.fromJson(Map<String, Object?> json) =>
      EhrSiteMeasurement(
        siteId: json['siteId'] as String,
        siteLabel: json['siteLabel'] as String,
        lesionSizeMm: (json['lesionSizeMm'] as num).toDouble(),
        riskLevel: json['riskLevel'] as String,
        recordedAt: DateTime.parse(json['recordedAt'] as String),
        roiImagePath: json['roiImagePath'] as String?,
        maskPath: json['maskPath'] as String?,
      );
}

class EhrVisit {
  const EhrVisit({
    required this.visitId,
    required this.patientHash,
    required this.createdAt,
    required this.siteMeasurements,
    required this.doctorSummary,
    this.finalOutcome,
  });

  final String visitId;
  final String patientHash;
  final DateTime createdAt;
  final List<EhrSiteMeasurement> siteMeasurements;
  final String doctorSummary;
  final String? finalOutcome;

  Map<String, Object?> toJson() => {
    'visitId': visitId,
    'patientHash': patientHash,
    'createdAt': createdAt.toIso8601String(),
    'siteMeasurements': siteMeasurements.map((site) => site.toJson()).toList(),
    'doctorSummary': doctorSummary,
    'finalOutcome': finalOutcome,
  };

  factory EhrVisit.fromJson(Map<String, Object?> json) => EhrVisit(
    visitId: json['visitId'] as String,
    patientHash: json['patientHash'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    siteMeasurements: (json['siteMeasurements'] as List)
        .map(
          (site) => EhrSiteMeasurement.fromJson(
            Map<String, Object?>.from(site as Map),
          ),
        )
        .toList(),
    doctorSummary: json['doctorSummary'] as String,
    finalOutcome: json['finalOutcome'] as String?,
  );
}

class EhrSiteDelta {
  const EhrSiteDelta({
    required this.siteId,
    required this.siteLabel,
    required this.previousSizeMm,
    required this.currentSizeMm,
    required this.sizeChangeMm,
    required this.concernIncreased,
  });

  final String siteId;
  final String siteLabel;
  final double previousSizeMm;
  final double currentSizeMm;
  final double sizeChangeMm;
  final bool concernIncreased;
}

class EhrDeltaReport {
  const EhrDeltaReport({
    required this.summary,
    required this.siteDeltas,
    required this.repeatedHighRiskSite,
  });

  final String summary;
  final List<EhrSiteDelta> siteDeltas;
  final bool repeatedHighRiskSite;
}

class EhrDeltaCalculator {
  const EhrDeltaCalculator();

  EhrDeltaReport compare({
    required ScreeningResult current,
    required List<EhrVisit> previousVisits,
  }) {
    if (previousVisits.isEmpty) {
      return const EhrDeltaReport(
        summary: 'No previous EHR visit available.',
        siteDeltas: [],
        repeatedHighRiskSite: false,
      );
    }

    final sorted = [...previousVisits]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final previous = sorted.first;
    final previousBySite = {
      for (final site in previous.siteMeasurements) site.siteId: site,
    };
    final currentSegmentation = {
      for (final artifact in current.segmentation) artifact.siteId: artifact,
    };

    final deltas = <EhrSiteDelta>[];
    for (final site in current.siteResults) {
      final previousSite = previousBySite[site.siteId];
      final currentArtifact = currentSegmentation[site.siteId];
      if (previousSite == null || currentArtifact == null) {
        continue;
      }
      final change = currentArtifact.lesionSizeMm - previousSite.lesionSizeMm;
      deltas.add(
        EhrSiteDelta(
          siteId: site.siteId,
          siteLabel: site.siteLabel,
          previousSizeMm: previousSite.lesionSizeMm,
          currentSizeMm: currentArtifact.lesionSizeMm,
          sizeChangeMm: change,
          concernIncreased:
              change >= 2 ||
              _riskRank(current.riskLevel) > _riskRank(previousSite.riskLevel),
        ),
      );
    }

    final repeatedHighRiskSite = current.siteResults.any((site) {
      final previousSite = previousBySite[site.siteId];
      return site.suspicionScore >= 0.7 &&
          previousSite != null &&
          _riskRank(previousSite.riskLevel) >= _riskRank('high');
    });

    final largestGrowth = deltas.isEmpty
        ? null
        : deltas.reduce(
            (a, b) => a.sizeChangeMm.abs() >= b.sizeChangeMm.abs() ? a : b,
          );
    final summary = largestGrowth == null
        ? 'No comparable site measurements.'
        : '${largestGrowth.siteLabel} changed by ${largestGrowth.sizeChangeMm.toStringAsFixed(1)}mm since the last EHR visit.';

    return EhrDeltaReport(
      summary: summary,
      siteDeltas: deltas,
      repeatedHighRiskSite: repeatedHighRiskSite,
    );
  }

  static int _riskRank(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'urgent':
        return 4;
      case 'high':
        return 3;
      case 'medium':
        return 2;
      case 'low':
        return 1;
      default:
        return 0;
    }
  }
}
