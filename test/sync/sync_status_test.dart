import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/sync/sync_status.dart';

void main() {
  test('sync state transitions queued to uploading to synced', () {
    final queued = SyncState(
      status: SyncStatus.queued,
      attemptCount: 0,
      updatedAt: DateTime.utc(2026, 5, 3, 9),
    );

    final uploading = queued.markUploading(DateTime.utc(2026, 5, 3, 10));
    final synced = uploading.markSynced(DateTime.utc(2026, 5, 3, 10, 1));

    expect(uploading.status, SyncStatus.uploading);
    expect(uploading.attemptCount, 1);
    expect(synced.status, SyncStatus.synced);
    expect(synced.attemptCount, 1);
  });

  test('failed sync can retry and increments attempt count', () {
    final uploading = SyncState(
      status: SyncStatus.uploading,
      attemptCount: 1,
      updatedAt: DateTime.utc(2026, 5, 3, 10),
    );

    final failed = uploading.markFailed(
      DateTime.utc(2026, 5, 3, 10, 1),
      'network unavailable',
    );
    final retrying = failed.markUploading(DateTime.utc(2026, 5, 3, 10, 3));

    expect(failed.status, SyncStatus.failed);
    expect(failed.lastError, 'network unavailable');
    expect(retrying.attemptCount, 2);
  });

  test('invalid sync state transitions are rejected', () {
    final synced = SyncState(
      status: SyncStatus.synced,
      attemptCount: 1,
      updatedAt: DateTime.utc(2026, 5, 3, 10),
    );

    expect(
      () => synced.markUploading(DateTime.utc(2026, 5, 3, 11)),
      throwsStateError,
    );
    expect(
      () => synced.markFailed(DateTime.utc(2026, 5, 3, 11), 'error'),
      throwsStateError,
    );
  });

  test('sync state serializes for local queue payloads', () {
    final state = SyncState(
      status: SyncStatus.failed,
      attemptCount: 2,
      updatedAt: DateTime.utc(2026, 5, 3, 10),
      lastError: 'permission denied',
    );

    final decoded = SyncState.fromJson(
      Map<String, Object?>.from(jsonDecode(jsonEncode(state.toJson())) as Map),
    );

    expect(decoded.status, SyncStatus.failed);
    expect(decoded.attemptCount, 2);
    expect(decoded.lastError, 'permission denied');
  });
}
