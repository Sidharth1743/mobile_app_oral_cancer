import '../cloud/role_home_repository.dart';

class NgoProgramMetrics {
  const NgoProgramMetrics({
    required this.totalScreenings,
    required this.referralCount,
    required this.urgentCount,
    required this.lowRiskCount,
    required this.recaptureCount,
    required this.uniqueVillages,
    required this.uniqueDistricts,
    required this.byDistrict,
    required this.byVillageCode,
    required this.byAction,
    required this.byState,
    required this.recentCases,
    required this.cloudBackupEnabled,
    required this.researchExportEnabled,
    required this.doctorShareEnabled,
  });

  final int totalScreenings;
  final int referralCount;
  final int urgentCount;
  final int lowRiskCount;
  final int recaptureCount;
  final int uniqueVillages;
  final int uniqueDistricts;
  final Map<String, int> byDistrict;
  final Map<String, int> byVillageCode;
  final Map<String, int> byAction;
  final Map<String, int> byState;
  final List<CloudCaseSummary> recentCases;
  final int cloudBackupEnabled;
  final int researchExportEnabled;
  final int doctorShareEnabled;

  double get referralRate =>
      totalScreenings == 0 ? 0 : referralCount / totalScreenings;
}

class NgoDashboardMetrics {
  static NgoProgramMetrics fromCases(List<CloudCaseSummary> cases) {
    final byDistrict = <String, int>{};
    final byVillageCode = <String, int>{};
    final byAction = <String, int>{};
    final byState = <String, int>{};
    var referralCount = 0;
    var urgentCount = 0;
    var lowRiskCount = 0;
    var recaptureCount = 0;
    var cloudBackup = 0;
    var researchExport = 0;
    var doctorShare = 0;

    for (final item in cases) {
      final action = item.recommendedAction.trim().isEmpty
          ? 'unknown'
          : item.recommendedAction;
      byAction[action] = (byAction[action] ?? 0) + 1;

      final district = (item.district ?? '').trim().isEmpty
          ? 'Unknown district'
          : item.district!.trim();
      byDistrict[district] = (byDistrict[district] ?? 0) + 1;

      final village = (item.villageCode ?? '').trim().isEmpty
          ? 'unknown'
          : item.villageCode!.trim();
      byVillageCode[village] = (byVillageCode[village] ?? 0) + 1;

      final state = (item.state ?? '').trim().isEmpty
          ? 'Unknown state'
          : item.state!.trim();
      byState[state] = (byState[state] ?? 0) + 1;

      if (_isReferral(action)) {
        referralCount += 1;
      }
      if (_isUrgent(action)) {
        urgentCount += 1;
      }
      if (_isLowRisk(action)) {
        lowRiskCount += 1;
      }
      if (_isRecapture(action)) {
        recaptureCount += 1;
      }

      if (item.consentScopes.contains('cloudBackup')) {
        cloudBackup += 1;
      }
      if (item.consentScopes.contains('researchExport')) {
        researchExport += 1;
      }
      if (item.consentScopes.contains('doctorShare')) {
        doctorShare += 1;
      }
    }

    final sorted = [...cases]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return NgoProgramMetrics(
      totalScreenings: cases.length,
      referralCount: referralCount,
      urgentCount: urgentCount,
      lowRiskCount: lowRiskCount,
      recaptureCount: recaptureCount,
      uniqueVillages: byVillageCode.keys.length,
      uniqueDistricts: byDistrict.keys.length,
      byDistrict: byDistrict,
      byVillageCode: byVillageCode,
      byAction: byAction,
      byState: byState,
      recentCases: sorted.take(20).toList(),
      cloudBackupEnabled: cloudBackup,
      researchExportEnabled: researchExport,
      doctorShareEnabled: doctorShare,
    );
  }

  static bool _isReferral(String action) {
    final lower = action.toLowerCase();
    return lower.contains('refer') || lower.contains('urgent');
  }

  static bool _isUrgent(String action) {
    return action.toLowerCase().contains('urgent');
  }

  static bool _isLowRisk(String action) {
    final lower = action.toLowerCase();
    return lower.contains('low') ||
        lower.contains('routine') ||
        lower.contains('rescreen');
  }

  static bool _isRecapture(String action) {
    return action.toLowerCase().contains('recapture');
  }
}
