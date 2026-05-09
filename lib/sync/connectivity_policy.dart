import '../consent/consent.dart';
import '../pipeline/screening_pipeline.dart';

class ConnectivityPolicy {
  const ConnectivityPolicy({this.checkInterval = const Duration(seconds: 90)});

  final Duration checkInterval;

  bool shouldCheck({
    required DateTime now,
    required DateTime? lastCheckedAt,
    required ScreeningResult? result,
    required ConsentRecord? consent,
    bool manual = false,
  }) {
    if (result == null || consent == null || !consent.hasAnyOnlineScope) {
      return false;
    }
    consent.validatePostResult();
    if (manual) {
      return true;
    }
    if (lastCheckedAt == null) {
      return true;
    }
    return !now.difference(lastCheckedAt).isNegative &&
        now.difference(lastCheckedAt) >= checkInterval;
  }
}
