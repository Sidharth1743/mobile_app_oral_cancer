import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/models.dart';

class PreviousSiteMeasurement {
  const PreviousSiteMeasurement({
    required this.siteId,
    required this.siteLabel,
    required this.largestDiameterMm,
    required this.imagePath,
  });

  final String siteId;
  final String siteLabel;
  final double largestDiameterMm;
  final String imagePath;

  factory PreviousSiteMeasurement.fromJson(Map<String, Object?> json) {
    return PreviousSiteMeasurement(
      siteId: json['siteId'] as String,
      siteLabel: json['siteLabel'] as String,
      largestDiameterMm: (json['largestDiameterMm'] as num).toDouble(),
      imagePath: json['imagePath'] as String,
    );
  }
}

class PreviousVisitFixture {
  const PreviousVisitFixture({
    required this.visitId,
    required this.patientHash,
    required this.createdAt,
    required this.siteMeasurements,
    required this.riskSummary,
  });

  final String visitId;
  final String patientHash;
  final DateTime createdAt;
  final List<PreviousSiteMeasurement> siteMeasurements;
  final Map<String, Object?> riskSummary;

  factory PreviousVisitFixture.fromJson(Map<String, Object?> json) {
    return PreviousVisitFixture(
      visitId: json['visitId'] as String,
      patientHash: json['patientHash'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      siteMeasurements: (json['siteMeasurements'] as List)
          .map(
            (item) => PreviousSiteMeasurement.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(),
      riskSummary: Map<String, Object?>.from(json['riskSummary'] as Map),
    );
  }
}

class DemoFixtures {
  const DemoFixtures({required this.assessment, required this.previousVisit});

  static const assessmentAsset = 'assets/demo/assessment.json';
  static const previousVisitAsset = 'assets/demo/prev_visit.json';

  final FullAssessment assessment;
  final PreviousVisitFixture previousVisit;

  static Future<DemoFixtures> loadFromAssetBundle(AssetBundle bundle) async {
    final assessmentJson = await bundle.loadString(assessmentAsset);
    final previousVisitJson = await bundle.loadString(previousVisitAsset);
    return DemoFixtures.fromJsonStrings(
      assessmentJson: assessmentJson,
      previousVisitJson: previousVisitJson,
    );
  }

  factory DemoFixtures.fromJsonStrings({
    required String assessmentJson,
    required String previousVisitJson,
  }) {
    final assessment = FullAssessment.fromJson(
      Map<String, Object?>.from(jsonDecode(assessmentJson) as Map),
    );
    final previousVisit = PreviousVisitFixture.fromJson(
      Map<String, Object?>.from(jsonDecode(previousVisitJson) as Map),
    );

    if (assessment.patientHash != previousVisit.patientHash) {
      throw FormatException(
        'Assessment patient hash does not match previous visit patient hash.',
        assessment.patientHash,
      );
    }
    if (assessment.createdAt.isBefore(previousVisit.createdAt)) {
      throw FormatException(
        'Assessment fixture must be newer than previous visit fixture.',
        assessment.createdAt.toIso8601String(),
      );
    }
    if (assessment.siteResults.isEmpty) {
      throw const FormatException(
        'Assessment fixture must include at least one site result.',
      );
    }

    return DemoFixtures(assessment: assessment, previousVisit: previousVisit);
  }
}
