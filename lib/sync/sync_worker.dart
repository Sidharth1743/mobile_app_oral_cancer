import '../data/local_database.dart';

abstract interface class QueuedSyncUploader {
  Future<void> upload(SyncQueueItem item);
}

class SyncWorkerResult {
  const SyncWorkerResult({
    required this.processed,
    required this.synced,
    required this.failed,
  });

  final int processed;
  final int synced;
  final int failed;
}

class LocalSyncWorker {
  const LocalSyncWorker({
    required LocalDatabase database,
    required QueuedSyncUploader uploader,
    DateTime Function()? clock,
  }) : _database = database,
       _uploader = uploader,
       _clock = clock ?? DateTime.now;

  final LocalDatabase _database;
  final QueuedSyncUploader _uploader;
  final DateTime Function() _clock;

  Future<SyncWorkerResult> processPending({int? limit}) async {
    final pending = await _database.pendingSyncItems();
    final selected = limit == null ? pending : pending.take(limit).toList();
    var synced = 0;
    var failed = 0;

    for (final item in selected) {
      final uploading = await _database.markSyncUploading(
        id: item.id,
        updatedAt: _clock().toUtc(),
      );
      try {
        await _uploader.upload(uploading);
        await _database.markSyncSynced(
          id: item.id,
          updatedAt: _clock().toUtc(),
        );
        synced += 1;
      } catch (error) {
        await _database.markSyncFailed(
          id: item.id,
          updatedAt: _clock().toUtc(),
          error: error.toString(),
        );
        failed += 1;
      }
    }

    return SyncWorkerResult(
      processed: selected.length,
      synced: synced,
      failed: failed,
    );
  }
}
