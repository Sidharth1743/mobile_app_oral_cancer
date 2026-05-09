import '../pipeline/screening_pipeline.dart';

class DashboardMetrics {
  const DashboardMetrics({
    required this.totalScreenings,
    required this.highRiskCount,
    required this.urgentCount,
    required this.averageUncertainty,
    required this.byVillageCode,
  });

  final int totalScreenings;
  final int highRiskCount;
  final int urgentCount;
  final double averageUncertainty;
  final Map<String, int> byVillageCode;

  Map<String, Object?> toJson() => {
    'totalScreenings': totalScreenings,
    'highRiskCount': highRiskCount,
    'urgentCount': urgentCount,
    'averageUncertainty': averageUncertainty,
    'byVillageCode': byVillageCode,
  };

  factory DashboardMetrics.fromResults(
    Iterable<ScreeningResult> results, {
    required Map<String, String> villageCodeByPatientHash,
  }) {
    final list = results.toList();
    final byVillageCode = <String, int>{};
    for (final result in list) {
      final villageCode =
          villageCodeByPatientHash[result.patientHash] ?? 'unknown';
      byVillageCode[villageCode] = (byVillageCode[villageCode] ?? 0) + 1;
    }
    return DashboardMetrics(
      totalScreenings: list.length,
      highRiskCount: list
          .where(
            (result) =>
                result.riskLevel == 'high' || result.riskLevel == 'urgent',
          )
          .length,
      urgentCount: list.where((result) => result.riskLevel == 'urgent').length,
      averageUncertainty: list.isEmpty
          ? 0
          : list.map((result) => result.uncertainty).reduce((a, b) => a + b) /
                list.length,
      byVillageCode: byVillageCode,
    );
  }
}
