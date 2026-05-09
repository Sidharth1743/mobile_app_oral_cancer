import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/consent/consent.dart';
import 'package:oral_cancer/data/local_database.dart';
import 'package:oral_cancer/data/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LocalDatabase store;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    store = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await store.close();
  });

  test('creates SQLite schema with MVP tables', () async {
    final db = await store.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
    );
    final tableNames = tables.map((row) => row['name']).toSet();

    expect(
      tableNames,
      containsAll([
        'clinical_records',
        'captured_frames',
        'consents',
        'treatment_timelines',
        'visits',
        'sync_queue',
      ]),
    );
  });

  test('saves and reads clinical records by id and patient hash', () async {
    final record = _clinicalRecord(
      id: 'clinical-1',
      createdAt: DateTime.utc(2026, 5, 3),
    );

    await store.saveClinicalRecord(record);

    final byId = await store.clinicalRecordById('clinical-1');
    final byPatient = await store.clinicalRecordsForPatient('patient-hash');

    expect(byId?.ageBand, '48-57');
    expect(byPatient.single.patientHash, 'patient-hash');
    expect(byPatient.single.pinPrefix, '600');
  });

  test('saves captured frames for a visit', () async {
    await store.saveCapturedFrames(
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      frames: CapturedSiteFrames(
        siteId: 'left_buccal',
        siteLabel: 'Left buccal mucosa',
        framePaths: const [
          'app/documents/visit-1/left-1.jpg',
          'app/documents/visit-1/left-2.jpg',
        ],
        roiPath: 'app/documents/visit-1/left-roi.jpg',
        createdAt: DateTime.utc(2026, 5, 3, 8),
      ),
    );

    final frames = await store.capturedFramesForVisit('visit-1');

    expect(frames, hasLength(1));
    expect(frames.single.siteId, 'left_buccal');
    expect(frames.single.framePaths, hasLength(2));
  });

  test('saves visits and returns newest first for patient', () async {
    final older = _assessment(
      visitId: 'visit-older',
      createdAt: DateTime.utc(2026, 4, 1),
    );
    final newer = _assessment(
      visitId: 'visit-newer',
      createdAt: DateTime.utc(2026, 5, 1),
    );

    await store.saveVisit(older);
    await store.saveVisit(newer);

    final byId = await store.visitById('visit-newer');
    final visits = await store.visitsForPatient('patient-hash');

    expect(byId?.delta.sizeChangeMm, 4);
    expect(visits.map((visit) => visit.visitId), [
      'visit-newer',
      'visit-older',
    ]);
  });

  test('queues sync payloads without identity fields', () async {
    final item = await store.enqueueSync(
      visitId: 'visit-1',
      kind: 'doctor_package',
      payload: {
        'patientHash': 'patient-hash',
        'doctorBrief': 'Suspicious lesion requiring referral.',
      },
    );

    final queued = await store.queuedSyncItems();

    expect(item.status, 'queued');
    expect(item.attemptCount, 0);
    expect(queued.single.kind, 'doctor_package');
    expect(queued.single.payload, isNot(contains('fullName')));
    expect(queued.single.payload, isNot(contains('phone')));
  });

  test('updates sync queue status, attempts, and errors', () async {
    final item = await store.enqueueSync(
      visitId: 'visit-1',
      kind: 'research_dataset_row',
      payload: const {'visitId': 'visit-1'},
    );

    final uploading = await store.markSyncUploading(
      id: item.id,
      updatedAt: DateTime.utc(2026, 5, 3, 10),
    );
    final failed = await store.markSyncFailed(
      id: item.id,
      updatedAt: DateTime.utc(2026, 5, 3, 10, 1),
      error: 'network unavailable',
    );

    expect(uploading.status, 'uploading');
    expect(uploading.attemptCount, 1);
    expect(failed.status, 'failed');
    expect(failed.lastError, 'network unavailable');
    expect((await store.pendingSyncItems()).single.id, item.id);
  });

  test('saves and reads consent records by visit and patient', () async {
    final consent = ConsentRecord(
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      scopes: const {ConsentScope.doctorShare, ConsentScope.researchExport},
      recordedAt: DateTime.utc(2026, 5, 3, 10),
      policyVersion: '2026-05',
      screeningCompletedAt: DateTime.utc(2026, 5, 3, 9),
    );

    await store.saveConsent(consent);

    final byVisit = await store.consentForVisit('visit-1');
    final byPatient = await store.consentsForPatient('patient-hash');

    expect(byVisit?.doctorShare, isTrue);
    expect(byVisit?.researchExport, isTrue);
    expect(byPatient.single.visitId, 'visit-1');
  });
}

ClinicalRecord _clinicalRecord({
  required String id,
  required DateTime createdAt,
}) {
  return ClinicalRecord(
    id: id,
    patientHash: 'patient-hash',
    ageBand: '48-57',
    pinPrefix: '600',
    villageCode: 'abc123def456',
    gender: 'female',
    tobaccoBrand: 'Hans',
    chewsPerDay: 8,
    yearsUsed: 20,
    alcoholUse: false,
    cei: 0.27,
    createdAt: createdAt,
  );
}

FullAssessment _assessment({
  required String visitId,
  required DateTime createdAt,
}) {
  return FullAssessment(
    visitId: visitId,
    patientHash: 'patient-hash',
    createdAt: createdAt,
    siteResults: const [
      LesionSiteResult(
        siteId: 'left_buccal',
        siteLabel: 'Left buccal mucosa',
        suspicionScore: 0.84,
        findings: 'Non-healing mixed red-white lesion.',
        roiImagePath: 'app/documents/visit/left-roi.jpg',
        uncertain: false,
      ),
    ],
    hypotheses: const [
      HypothesisResult(
        label: 'Potentially malignant oral disorder',
        probability: 0.76,
        rationale: 'Appearance and habit history increase concern.',
      ),
    ],
    delta: const DeltaResult(
      summary: 'Lesion grew 4mm since last visit.',
      sizeChangeMm: 4,
      concernIncreased: true,
    ),
    carePlan: CarePlan(
      action: 'see_doctor_free',
      patientMessage: 'Visit the free doctor camp this week.',
      ashaMessage: 'Prepare referral package.',
      rescreenDate: DateTime.utc(2026, 5, 10),
      doctorBrief: 'Left buccal lesion with interval growth.',
    ),
    thinking: 'Assessment considered image findings and risk exposure.',
    citations: const ['WHO oral cancer screening manual'],
  );
}
