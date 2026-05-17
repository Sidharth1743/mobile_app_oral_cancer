import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/auth/role_auth.dart';
import 'package:oral_cancer/cloud/firebase_role_auth.dart';
import 'package:oral_cancer/consent/consent.dart';
import 'package:oral_cancer/cloud/role_home_repository.dart';
import 'package:oral_cancer/dashboard/ngo_dashboard_metrics.dart';
import 'package:oral_cancer/data/local_database.dart';
import 'package:oral_cancer/data/models.dart';
import 'package:oral_cancer/ui/app_theme.dart';
import 'package:oral_cancer/ui/screens/consent_screen.dart';
import 'package:oral_cancer/ui/screens/role_login_screen.dart';
import 'package:oral_cancer/ui/screens/sync_queue_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  testWidgets('consent screen stores consent and queues selected scopes', (
    tester,
  ) async {
    final database = _database();
    ConsentRecord? savedConsent;
    await tester.pumpWidget(
      _wrap(
        ConsentScreen(
          assessment: _assessment(),
          database: database,
          clock: () => DateTime.utc(2026, 5, 3, 10),
          saveConsent: (consent) async {
            savedConsent = consent;
            return ConsentSaveResult(consent: consent, queuedCount: 2);
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('consent-doctor-share')));
    await tester.tap(find.byKey(const Key('consent-cloud-backup')));
    await tester.tap(find.byKey(const Key('save-consent-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('2 request'), findsOneWidget);
    expect(savedConsent?.doctorShare, isTrue);
    expect(savedConsent?.cloudBackup, isTrue);
    await database.close();
  });

  testWidgets('role login uses real sign-in boundary and shows profile role', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        RoleLoginScreen(
          signIn: ({required email, required password}) async {
            expect(email, 'doctor@example.com');
            expect(password, 'secret-pass');
            return const FirebaseUserProfile(
              uid: 'doctor-1',
              displayName: 'Dr Kumar',
              role: AppRole.doctor,
              active: true,
              email: 'doctor@example.com',
              state: 'Tamil Nadu',
              district: 'Madurai',
            );
          },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('role-email-field')),
      'doctor@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('role-password-field')),
      'secret-pass',
    );
    await tester.tap(find.byKey(const Key('role-login-button')));
    await tester.pumpAndSettle();

    expect(find.text('Dr Kumar'), findsOneWidget);
    expect(find.text('doctor'), findsOneWidget);
    expect(find.text('Tamil Nadu / Madurai'), findsOneWidget);
  });

  testWidgets('sync queue screen has empty state and renders queued work', (
    tester,
  ) async {
    var items = <SyncQueueItem>[];
    await tester.pumpWidget(
      _wrap(SyncQueueScreen(loadItems: () async => items)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Nothing queued'), findsOneWidget);

    items = [
      SyncQueueItem(
        id: 'queue-1',
        visitId: 'visit-1',
        kind: 'doctor_share_request',
        payload: const {'visitId': 'visit-1', 'patientHash': 'patient-hash'},
        createdAt: DateTime.utc(2026, 5, 3, 10),
        status: 'queued',
      ),
    ];
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('doctor share request'), findsOneWidget);
    expect(find.text('Visit visit-1'), findsOneWidget);
  });

  test('NGO program metrics aggregate de-identified case data', () {
    final cases = <CloudCaseSummary>[
      for (var i = 0; i < 12; i++)
        CloudCaseSummary(
          caseId: 'case-$i',
          visitId: 'visit-$i',
          patientHash: 'patient-hash-$i',
          status: 'synced',
          recommendedAction: i == 0 ? 'urgent_referral' : 'low_risk',
          updatedAt: DateTime.utc(2026, 5, 3, 10 + i),
          district: 'Chennai',
          villageCode: i < 7 ? 'village-code-1' : 'village-code-2',
          consentScopes: const ['cloudBackup', 'researchExport'],
        ),
    ];

    final metrics = NgoDashboardMetrics.fromCases(cases);

    expect(metrics.totalScreenings, 12);
    expect(metrics.urgentCount, 1);
    expect(metrics.byVillageCode['village-code-1'], 7);
    expect(metrics.byVillageCode['village-code-2'], 5);
    expect(metrics.cloudBackupEnabled, 12);
    expect(
      metrics.recentCases.every((item) => !item.patientHash.contains('Meera')),
      isTrue,
    );
    for (final item in metrics.recentCases) {
      expect(item.patientHash, isNot(contains('9999999999')));
    }
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(theme: buildAppTheme(), home: child);
}

LocalDatabase _database() {
  return LocalDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
}

FullAssessment _assessment() => FullAssessment(
  visitId: 'visit-1',
  patientHash: 'patient-hash',
  createdAt: DateTime.utc(2026, 5, 3, 9),
  siteResults: const [
    LesionSiteResult(
      siteId: 'left_buccal',
      siteLabel: 'Left buccal mucosa',
      suspicionScore: 0.82,
      findings: 'Irregular red-white patch.',
      roiImagePath: 'app/roi/left.jpg',
      uncertain: false,
    ),
  ],
  hypotheses: const [
    HypothesisResult(
      label: 'Potentially malignant oral disorder',
      probability: 0.72,
      rationale: 'Visual change and exposure history.',
    ),
  ],
  delta: const DeltaResult(
    summary: 'Lesion grew 4mm.',
    sizeChangeMm: 4,
    concernIncreased: true,
  ),
  carePlan: CarePlan(
    action: 'see_doctor_free',
    patientMessage: 'A doctor check is needed.',
    ashaMessage: 'Prepare referral.',
    doctorBrief: 'Left buccal lesion with elevated suspicion.',
    rescreenDate: DateTime.utc(2026, 5, 10),
  ),
  thinking: 'Model reasoning.',
  citations: const ['WHO oral cancer early detection guidance'],
);
