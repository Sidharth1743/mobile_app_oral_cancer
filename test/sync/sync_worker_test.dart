import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/data/local_database.dart';
import 'package:oral_cancer/sync/sync_worker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LocalDatabase database;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('sync worker marks successful uploads as synced', () async {
    final item = await database.enqueueSync(
      visitId: 'visit-1',
      kind: 'identified_assessment_doctor_package',
      payload: const {'visitId': 'visit-1'},
    );
    final uploader = RecordingUploader();
    final worker = LocalSyncWorker(
      database: database,
      uploader: uploader,
      clock: () => DateTime.utc(2026, 5, 3, 10),
    );

    final result = await worker.processPending();
    final saved = await database.syncItemById(item.id);

    expect(result.synced, 1);
    expect(result.failed, 0);
    expect(saved?.status, 'synced');
    expect(saved?.attemptCount, 1);
    expect(uploader.uploaded.single.id, item.id);
  });

  test('sync worker marks failed uploads with retryable error', () async {
    final item = await database.enqueueSync(
      visitId: 'visit-1',
      kind: 'doctor_share_request',
      payload: const {'visitId': 'visit-1'},
    );
    final worker = LocalSyncWorker(
      database: database,
      uploader: FailingUploader(),
      clock: () => DateTime.utc(2026, 5, 3, 10),
    );

    final result = await worker.processPending();
    final saved = await database.syncItemById(item.id);

    expect(result.failed, 1);
    expect(saved?.status, 'failed');
    expect(saved?.attemptCount, 1);
    expect(saved?.lastError, contains('not complete'));
  });
}

class RecordingUploader implements QueuedSyncUploader {
  final uploaded = <SyncQueueItem>[];

  @override
  Future<void> upload(SyncQueueItem item) async {
    uploaded.add(item);
  }
}

class FailingUploader implements QueuedSyncUploader {
  @override
  Future<void> upload(SyncQueueItem item) async {
    throw StateError('not complete');
  }
}
