enum SyncStatus { queued, uploading, synced, failed }

class SyncState {
  const SyncState({
    required this.status,
    required this.attemptCount,
    required this.updatedAt,
    this.lastError,
  });

  final SyncStatus status;
  final int attemptCount;
  final DateTime updatedAt;
  final String? lastError;

  bool get canRetry =>
      status == SyncStatus.queued || status == SyncStatus.failed;

  SyncState markUploading(DateTime now) {
    if (!canRetry) {
      throw StateError('Only queued or failed sync items can upload.');
    }
    return SyncState(
      status: SyncStatus.uploading,
      attemptCount: attemptCount + 1,
      updatedAt: now,
    );
  }

  SyncState markSynced(DateTime now) {
    if (status != SyncStatus.uploading) {
      throw StateError('Only uploading sync items can be marked synced.');
    }
    return SyncState(
      status: SyncStatus.synced,
      attemptCount: attemptCount,
      updatedAt: now,
    );
  }

  SyncState markFailed(DateTime now, String error) {
    if (status != SyncStatus.uploading) {
      throw StateError('Only uploading sync items can fail.');
    }
    return SyncState(
      status: SyncStatus.failed,
      attemptCount: attemptCount,
      updatedAt: now,
      lastError: error,
    );
  }

  Map<String, Object?> toJson() => {
    'status': status.name,
    'attemptCount': attemptCount,
    'updatedAt': updatedAt.toIso8601String(),
    'lastError': lastError,
  };

  factory SyncState.fromJson(Map<String, Object?> json) => SyncState(
    status: SyncStatus.values.byName(json['status'] as String),
    attemptCount: (json['attemptCount'] as num).toInt(),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    lastError: json['lastError'] as String?,
  );
}
