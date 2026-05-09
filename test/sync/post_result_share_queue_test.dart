import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/consent/consent.dart';
import 'package:oral_cancer/data/local_database.dart';
import 'package:oral_cancer/data/models.dart';
import 'package:oral_cancer/sync/post_result_share_queue.dart';
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

  test('queues only selected post-result consent scopes', () async {
    final queued = await const PostResultShareQueue().enqueueAllowedShares(
      database: database,
      assessment: _assessment(),
      consent: _consent(const {
        ConsentScope.doctorShare,
        ConsentScope.cloudBackup,
      }),
    );
    final items = await database.queuedSyncItems();

    expect(queued.map((item) => item.kind), [
      'doctor_share_request',
      'cloud_backup_request',
    ]);
    expect(items, hasLength(2));
    expect(items.first.payload['patientHash'], 'patient-hash');
    expect(items.first.payload, isNot(contains('fullName')));
  });

  test('queues nothing when no online sharing scope is selected', () async {
    final queued = await const PostResultShareQueue().enqueueAllowedShares(
      database: database,
      assessment: _assessment(),
      consent: _consent(const {}),
    );

    expect(queued, isEmpty);
    expect(await database.queuedSyncItems(), isEmpty);
  });

  test('rejects consent for a different assessment', () async {
    await expectLater(
      const PostResultShareQueue().enqueueAllowedShares(
        database: database,
        assessment: _assessment(),
        consent: ConsentRecord(
          visitId: 'other-visit',
          patientHash: 'patient-hash',
          scopes: const {ConsentScope.doctorShare},
          recordedAt: DateTime.utc(2026, 5, 3, 10),
          policyVersion: '2026-05',
          screeningCompletedAt: DateTime.utc(2026, 5, 3, 9),
        ),
      ),
      throwsStateError,
    );
  });
}

ConsentRecord _consent(Set<ConsentScope> scopes) => ConsentRecord(
  visitId: 'visit-1',
  patientHash: 'patient-hash',
  scopes: scopes,
  recordedAt: DateTime.utc(2026, 5, 3, 10),
  policyVersion: '2026-05',
  screeningCompletedAt: DateTime.utc(2026, 5, 3, 9),
);

FullAssessment _assessment() => FullAssessment(
  visitId: 'visit-1',
  patientHash: 'patient-hash',
  createdAt: DateTime.utc(2026, 5, 3, 9),
  siteResults: const [],
  hypotheses: const [],
  delta: const DeltaResult(
    summary: 'No earlier measurement.',
    sizeChangeMm: 0,
    concernIncreased: false,
  ),
  carePlan: CarePlan(
    action: 'rescreen',
    patientMessage: 'Return for rescreening.',
    ashaMessage: 'Schedule rescreen.',
    rescreenDate: DateTime.utc(2026, 6, 3),
    doctorBrief: 'No doctor package required.',
  ),
  thinking: '',
  citations: const [],
);
