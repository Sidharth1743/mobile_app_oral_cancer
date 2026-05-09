import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:uuid/uuid.dart';

import '../consent/consent.dart';
import '../treatment/treatment_tracking.dart';
import 'models.dart';

class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.visitId,
    required this.kind,
    required this.payload,
    required this.createdAt,
    required this.status,
    this.attemptCount = 0,
    DateTime? updatedAt,
    this.lastError,
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final String visitId;
  final String kind;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final String status;
  final int attemptCount;
  final DateTime updatedAt;
  final String? lastError;
}

class LocalDatabase {
  LocalDatabase({
    sqflite.DatabaseFactory? databaseFactory,
    String? databasePath,
  }) : _databaseFactory = databaseFactory ?? sqflite.databaseFactory,
       _databasePath = databasePath;

  static const _databaseName = 'oral_cancer.db';
  static const _databaseVersion = 4;

  final sqflite.DatabaseFactory _databaseFactory;
  final String? _databasePath;
  sqflite.Database? _database;
  final Uuid _uuid = const Uuid();

  Future<sqflite.Database> get database async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }
    final opened = await _databaseFactory.openDatabase(
      await _resolvePath(),
      options: sqflite.OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    _database = opened;
    return opened;
  }

  Future<void> close() async {
    final existing = _database;
    if (existing != null) {
      await existing.close();
      _database = null;
    }
  }

  Future<void> saveClinicalRecord(ClinicalRecord record) async {
    final db = await database;
    await db.insert('clinical_records', {
      'id': record.id,
      'patient_hash': record.patientHash,
      'created_at': record.createdAt.toIso8601String(),
      'payload_json': jsonEncode(record.toJson()),
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
  }

  Future<ClinicalRecord?> clinicalRecordById(String id) async {
    final db = await database;
    final rows = await db.query(
      'clinical_records',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ClinicalRecord.fromJson(
      Map<String, Object?>.from(
        jsonDecode(rows.single['payload_json'] as String) as Map,
      ),
    );
  }

  Future<List<ClinicalRecord>> clinicalRecordsForPatient(
    String patientHash,
  ) async {
    final db = await database;
    final rows = await db.query(
      'clinical_records',
      where: 'patient_hash = ?',
      whereArgs: [patientHash],
      orderBy: 'created_at DESC',
    );
    return rows
        .map(
          (row) => ClinicalRecord.fromJson(
            Map<String, Object?>.from(
              jsonDecode(row['payload_json'] as String) as Map,
            ),
          ),
        )
        .toList();
  }

  Future<void> saveCapturedFrames({
    required String visitId,
    required String patientHash,
    required CapturedSiteFrames frames,
  }) async {
    final db = await database;
    await db.insert('captured_frames', {
      'id': '$visitId:${frames.siteId}',
      'visit_id': visitId,
      'patient_hash': patientHash,
      'site_id': frames.siteId,
      'created_at': frames.createdAt.toIso8601String(),
      'payload_json': jsonEncode(frames.toJson()),
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
  }

  Future<List<CapturedSiteFrames>> capturedFramesForVisit(
    String visitId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'captured_frames',
      where: 'visit_id = ?',
      whereArgs: [visitId],
      orderBy: 'site_id ASC',
    );
    return rows
        .map(
          (row) => CapturedSiteFrames.fromJson(
            Map<String, Object?>.from(
              jsonDecode(row['payload_json'] as String) as Map,
            ),
          ),
        )
        .toList();
  }

  Future<void> saveVisit(FullAssessment assessment) async {
    final db = await database;
    await db.insert('visits', {
      'id': assessment.visitId,
      'patient_hash': assessment.patientHash,
      'created_at': assessment.createdAt.toIso8601String(),
      'assessment_json': assessment.toJsonString(),
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
  }

  Future<FullAssessment?> visitById(String visitId) async {
    final db = await database;
    final rows = await db.query(
      'visits',
      where: 'id = ?',
      whereArgs: [visitId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return FullAssessment.fromJsonString(
      rows.single['assessment_json'] as String,
    );
  }

  Future<List<FullAssessment>> visitsForPatient(String patientHash) async {
    final db = await database;
    final rows = await db.query(
      'visits',
      where: 'patient_hash = ?',
      whereArgs: [patientHash],
      orderBy: 'created_at DESC',
    );
    return rows
        .map(
          (row) =>
              FullAssessment.fromJsonString(row['assessment_json'] as String),
        )
        .toList();
  }

  Future<void> saveConsent(ConsentRecord consent) async {
    consent.validatePostResult();
    final db = await database;
    await db.insert('consents', {
      'id': '${consent.visitId}:${consent.policyVersion}',
      'visit_id': consent.visitId,
      'patient_hash': consent.patientHash,
      'created_at': consent.recordedAt.toIso8601String(),
      'payload_json': jsonEncode(consent.toJson()),
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
  }

  Future<ConsentRecord?> consentForVisit(String visitId) async {
    final db = await database;
    final rows = await db.query(
      'consents',
      where: 'visit_id = ?',
      whereArgs: [visitId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ConsentRecord.fromJson(
      Map<String, Object?>.from(
        jsonDecode(rows.single['payload_json'] as String) as Map,
      ),
    );
  }

  Future<List<ConsentRecord>> consentsForPatient(String patientHash) async {
    final db = await database;
    final rows = await db.query(
      'consents',
      where: 'patient_hash = ?',
      whereArgs: [patientHash],
      orderBy: 'created_at DESC',
    );
    return rows
        .map(
          (row) => ConsentRecord.fromJson(
            Map<String, Object?>.from(
              jsonDecode(row['payload_json'] as String) as Map,
            ),
          ),
        )
        .toList();
  }

  Future<SyncQueueItem> enqueueSync({
    required String visitId,
    required String kind,
    required Map<String, Object?> payload,
  }) async {
    final db = await database;
    final item = SyncQueueItem(
      id: _uuid.v4(),
      visitId: visitId,
      kind: kind,
      payload: payload,
      createdAt: DateTime.now().toUtc(),
      status: 'queued',
      attemptCount: 0,
      updatedAt: DateTime.now().toUtc(),
    );
    await db.insert('sync_queue', {
      'id': item.id,
      'visit_id': item.visitId,
      'kind': item.kind,
      'status': item.status,
      'created_at': item.createdAt.toIso8601String(),
      'updated_at': item.updatedAt.toIso8601String(),
      'attempt_count': item.attemptCount,
      'last_error': item.lastError,
      'payload_json': jsonEncode(item.payload),
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.abort);
    return item;
  }

  Future<List<SyncQueueItem>> queuedSyncItems() async {
    return syncItemsByStatuses(const ['queued']);
  }

  Future<List<SyncQueueItem>> pendingSyncItems() async {
    return syncItemsByStatuses(const ['queued', 'failed']);
  }

  Future<List<SyncQueueItem>> syncItemsByStatuses(List<String> statuses) async {
    final db = await database;
    final placeholders = List.filled(statuses.length, '?').join(',');
    final rows = await db.query(
      'sync_queue',
      where: 'status IN ($placeholders)',
      whereArgs: statuses,
      orderBy: 'created_at ASC',
    );
    return rows.map(_syncQueueItemFromRow).toList();
  }

  Future<SyncQueueItem?> syncItemById(String id) async {
    final db = await database;
    final rows = await db.query(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _syncQueueItemFromRow(rows.single);
  }

  Future<SyncQueueItem> markSyncUploading({
    required String id,
    required DateTime updatedAt,
  }) async {
    final item = await syncItemById(id);
    if (item == null) {
      throw StateError('Sync item not found: $id');
    }
    if (item.status != 'queued' && item.status != 'failed') {
      throw StateError('Only queued or failed sync items can upload.');
    }
    final db = await database;
    await db.update(
      'sync_queue',
      {
        'status': 'uploading',
        'updated_at': updatedAt.toIso8601String(),
        'attempt_count': item.attemptCount + 1,
        'last_error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return (await syncItemById(id))!;
  }

  Future<SyncQueueItem> markSyncSynced({
    required String id,
    required DateTime updatedAt,
  }) async {
    final item = await syncItemById(id);
    if (item == null) {
      throw StateError('Sync item not found: $id');
    }
    if (item.status != 'uploading') {
      throw StateError('Only uploading sync items can be marked synced.');
    }
    final db = await database;
    await db.update(
      'sync_queue',
      {
        'status': 'synced',
        'updated_at': updatedAt.toIso8601String(),
        'last_error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return (await syncItemById(id))!;
  }

  Future<SyncQueueItem> markSyncFailed({
    required String id,
    required DateTime updatedAt,
    required String error,
  }) async {
    final item = await syncItemById(id);
    if (item == null) {
      throw StateError('Sync item not found: $id');
    }
    if (item.status != 'uploading') {
      throw StateError('Only uploading sync items can fail.');
    }
    final db = await database;
    await db.update(
      'sync_queue',
      {
        'status': 'failed',
        'updated_at': updatedAt.toIso8601String(),
        'last_error': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return (await syncItemById(id))!;
  }

  Future<void> saveTreatmentTimeline(TreatmentTimeline timeline) async {
    final db = await database;
    await db.insert('treatment_timelines', {
      'visit_id': timeline.visitId,
      'patient_hash': timeline.patientHash,
      'status': timeline.currentStatus?.name ?? 'none',
      'updated_at':
          (timeline.events.isEmpty
                  ? DateTime.now().toUtc()
                  : timeline.events.last.recordedAt)
              .toIso8601String(),
      'payload_json': jsonEncode(timeline.toJson()),
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
  }

  Future<TreatmentTimeline?> treatmentTimelineForVisit(String visitId) async {
    final db = await database;
    final rows = await db.query(
      'treatment_timelines',
      where: 'visit_id = ?',
      whereArgs: [visitId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return TreatmentTimeline.fromJson(
      Map<String, Object?>.from(
        jsonDecode(rows.single['payload_json'] as String) as Map,
      ),
    );
  }

  Future<String> _resolvePath() async {
    final configured = _databasePath;
    if (configured != null) {
      return configured;
    }
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _databaseName);
  }

  Future<void> _createSchema(sqflite.Database db, int version) async {
    await db.execute('''
CREATE TABLE clinical_records (
  id TEXT PRIMARY KEY,
  patient_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  payload_json TEXT NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX clinical_records_patient_idx ON clinical_records(patient_hash, created_at)',
    );

    await db.execute('''
CREATE TABLE captured_frames (
  id TEXT PRIMARY KEY,
  visit_id TEXT NOT NULL,
  patient_hash TEXT NOT NULL,
  site_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  payload_json TEXT NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX captured_frames_visit_idx ON captured_frames(visit_id, site_id)',
    );

    await db.execute('''
CREATE TABLE visits (
  id TEXT PRIMARY KEY,
  patient_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  assessment_json TEXT NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX visits_patient_idx ON visits(patient_hash, created_at)',
    );

    await _createConsentsTable(db);
    await _createTreatmentTimelinesTable(db);

    await db.execute('''
CREATE TABLE sync_queue (
  id TEXT PRIMARY KEY,
  visit_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  payload_json TEXT NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX sync_queue_status_idx ON sync_queue(status, created_at)',
    );
  }

  Future<void> _upgradeSchema(
    sqflite.Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion == newVersion) {
      return;
    }
    if (oldVersion < 2) {
      await _createConsentsTable(db);
    }
    if (oldVersion < 3) {
      await _addSyncStateColumns(db);
    }
    if (oldVersion < 4) {
      await _createTreatmentTimelinesTable(db);
    }
    if (newVersion > _databaseVersion) {
      throw UnsupportedError(
        'No SQLite migration path from $oldVersion to $newVersion.',
      );
    }
  }

  Future<void> _createConsentsTable(sqflite.Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS consents (
  id TEXT PRIMARY KEY,
  visit_id TEXT NOT NULL,
  patient_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  payload_json TEXT NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS consents_visit_idx ON consents(visit_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS consents_patient_idx ON consents(patient_hash, created_at)',
    );
  }

  Future<void> _addSyncStateColumns(sqflite.Database db) async {
    await db.execute(
      "ALTER TABLE sync_queue ADD COLUMN updated_at TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      'ALTER TABLE sync_queue ADD COLUMN attempt_count INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('ALTER TABLE sync_queue ADD COLUMN last_error TEXT');
    await db.execute(
      "UPDATE sync_queue SET updated_at = created_at WHERE updated_at = ''",
    );
  }

  Future<void> _createTreatmentTimelinesTable(sqflite.Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS treatment_timelines (
  visit_id TEXT PRIMARY KEY,
  patient_hash TEXT NOT NULL,
  status TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  payload_json TEXT NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS treatment_patient_idx ON treatment_timelines(patient_hash, updated_at)',
    );
  }

  SyncQueueItem _syncQueueItemFromRow(Map<String, Object?> row) {
    final createdAt = DateTime.parse(row['created_at'] as String);
    final rawUpdatedAt = row['updated_at'] as String?;
    return SyncQueueItem(
      id: row['id'] as String,
      visitId: row['visit_id'] as String,
      kind: row['kind'] as String,
      status: row['status'] as String,
      createdAt: createdAt,
      updatedAt: rawUpdatedAt == null || rawUpdatedAt.isEmpty
          ? createdAt
          : DateTime.parse(rawUpdatedAt),
      attemptCount: (row['attempt_count'] as num?)?.toInt() ?? 0,
      lastError: row['last_error'] as String?,
      payload: Map<String, Object?>.from(
        jsonDecode(row['payload_json'] as String) as Map,
      ),
    );
  }
}
