import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/data/local_database.dart';
import 'package:oral_cancer/treatment/treatment_tracking.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('treatment timeline reaches completed after ordered events', () {
    final timeline =
        TreatmentTimeline(
              visitId: 'visit-1',
              patientHash: 'patient-hash',
              events: const [],
            )
            .addEvent(
              TreatmentEvent(
                status: TreatmentStatus.referred,
                recordedAt: DateTime.utc(2026, 5, 3),
                actorUid: 'asha-1',
                note: 'Referred.',
              ),
            )
            .addEvent(
              TreatmentEvent(
                status: TreatmentStatus.treatmentStarted,
                recordedAt: DateTime.utc(2026, 5, 10),
                actorUid: 'doctor-1',
                note: 'Started.',
              ),
            )
            .addEvent(
              TreatmentEvent(
                status: TreatmentStatus.completed,
                recordedAt: DateTime.utc(2026, 6, 1),
                actorUid: 'doctor-1',
                note: 'Completed.',
              ),
            );

    expect(timeline.completed, isTrue);
    expect(timeline.completedAt, DateTime.utc(2026, 6, 1));
  });

  test('treatment timeline rejects immediate completion after referral', () {
    final timeline = TreatmentTimeline(
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      events: [
        TreatmentEvent(
          status: TreatmentStatus.referred,
          recordedAt: DateTime.utc(2026, 5, 3),
          actorUid: 'asha-1',
          note: 'Referred.',
        ),
      ],
    );

    expect(
      () => timeline.addEvent(
        TreatmentEvent(
          status: TreatmentStatus.completed,
          recordedAt: DateTime.utc(2026, 5, 4),
          actorUid: 'doctor-1',
          note: 'Completed.',
        ),
      ),
      throwsStateError,
    );
  });

  test('saves treatment timeline locally by visit', () async {
    final database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final timeline = TreatmentTimeline(
      visitId: 'visit-1',
      patientHash: 'patient-hash',
      events: [
        TreatmentEvent(
          status: TreatmentStatus.doctorReviewed,
          recordedAt: DateTime.utc(2026, 5, 5),
          actorUid: 'doctor-1',
          note: 'Reviewed.',
        ),
      ],
    );

    await database.saveTreatmentTimeline(timeline);

    final saved = await database.treatmentTimelineForVisit('visit-1');
    expect(saved?.currentStatus, TreatmentStatus.doctorReviewed);
  });
}
