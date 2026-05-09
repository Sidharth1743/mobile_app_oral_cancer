import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/auth/role_auth.dart';
import 'package:oral_cancer/cloud/firebase_role_auth.dart';
import 'package:oral_cancer/cloud/role_home_repository.dart';
import 'package:oral_cancer/ui/app_theme.dart';
import 'package:oral_cancer/ui/screens/role_home_screen.dart';

void main() {
  testWidgets('doctor home renders assigned Firestore cases without identity', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        RoleHomeScreen(
          profile: const FirebaseUserProfile(
            uid: 'doctor-1',
            displayName: 'Doctor',
            role: AppRole.doctor,
            active: true,
          ),
          repository: FakeRoleHomeRepository(
            doctor: [
              CloudCaseSummary(
                caseId: 'case-1',
                visitId: 'visit-1',
                patientHash: 'patient-hash',
                status: 'queued',
                recommendedAction: 'see_doctor_free',
                updatedAt: DateTime.utc(2026, 5, 3),
                district: 'Madurai',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Doctor home'), findsOneWidget);
    expect(find.text('see doctor free'), findsOneWidget);
    expect(find.textContaining('patient-hash'), findsOneWidget);
    expect(find.textContaining('9999999999'), findsNothing);
  });

  testWidgets('research home renders export summaries', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RoleHomeScreen(
          profile: const FirebaseUserProfile(
            uid: 'research-1',
            displayName: 'Research',
            role: AppRole.research,
            active: true,
          ),
          repository: FakeRoleHomeRepository(
            exports: [
              ResearchExportSummary(
                exportId: 'research-visit-1',
                visitId: 'visit-1',
                status: 'accepted',
                createdAt: DateTime.utc(2026, 5, 3),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Research home'), findsOneWidget);
    expect(find.text('research-visit-1'), findsOneWidget);
    expect(find.text('accepted'), findsOneWidget);
  });
}

Widget _wrap(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

class FakeRoleHomeRepository implements RoleHomeRepository {
  FakeRoleHomeRepository({
    this.asha = const [],
    this.doctor = const [],
    this.exports = const [],
  });

  final List<CloudCaseSummary> asha;
  final List<CloudCaseSummary> doctor;
  final List<ResearchExportSummary> exports;

  @override
  Stream<List<CloudCaseSummary>> ashaCases(FirebaseUserProfile profile) =>
      Stream.value(asha);

  @override
  Stream<List<CloudCaseSummary>> doctorCases(FirebaseUserProfile profile) =>
      Stream.value(doctor);

  @override
  Stream<List<ResearchExportSummary>> researchExports(
    FirebaseUserProfile profile,
  ) => Stream.value(exports);
}
