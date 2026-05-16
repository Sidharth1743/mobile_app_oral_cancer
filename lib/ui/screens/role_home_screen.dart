import 'package:flutter/material.dart';

import '../../auth/role_auth.dart';
import '../../cloud/firebase_role_auth.dart';
import '../../cloud/role_home_repository.dart';
import '../components/empty_state.dart';
import '../components/section_panel.dart';
import '../components/status_badge.dart';
import 'case_detail_screen.dart';
import 'ngo_dashboard_screen.dart';
import 'research_export_detail_screen.dart';

class RoleHomeScreen extends StatelessWidget {
  const RoleHomeScreen({
    super.key,
    required this.profile,
    RoleHomeRepository? repository,
  }) : _repository = repository;

  final FirebaseUserProfile profile;
  final RoleHomeRepository? _repository;

  @override
  Widget build(BuildContext context) {
    final repository = _repository ?? FirestoreRoleHomeRepository();
    switch (profile.role) {
      case AppRole.asha:
      case AppRole.admin:
        return _CaseHome(
          title: 'ASHA home',
          emptyTitle: 'No synced cases',
          stream: repository.ashaCases(profile),
          role: profile.role,
        );
      case AppRole.doctor:
        return _CaseHome(
          title: 'Doctor home',
          emptyTitle: 'No assigned cases',
          stream: repository.doctorCases(profile),
          role: profile.role,
        );
      case AppRole.research:
        return _ResearchHome(stream: repository.researchExports(profile));
      case AppRole.ngoCsr:
        return const NgoCsrDashboardScreen();
    }
  }
}

class _CaseHome extends StatelessWidget {
  const _CaseHome({
    required this.title,
    required this.emptyTitle,
    required this.stream,
    required this.role,
  });

  final String title;
  final String emptyTitle;
  final Stream<List<CloudCaseSummary>> stream;
  final AppRole role;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StreamBuilder<List<CloudCaseSummary>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Cases unavailable',
              message: snapshot.error.toString(),
            );
          }
          final cases = snapshot.data ?? const [];
          if (cases.isEmpty) {
            return EmptyState(
              icon: Icons.folder_open_outlined,
              title: emptyTitle,
              message: 'Cases appear here only after consented sync.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) => _CaseRow(
              caseSummary: cases[index],
              role: role,
            ),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemCount: cases.length,
          );
        },
      ),
    );
  }
}

class _CaseRow extends StatelessWidget {
  const _CaseRow({required this.caseSummary, required this.role});

  final CloudCaseSummary caseSummary;
  final AppRole role;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CaseDetailScreen(
                caseSummary: caseSummary,
                role: role,
              ),
            ),
          );
        },
        child: SectionPanel(
          title: caseSummary.recommendedAction.isEmpty
              ? caseSummary.caseId
              : caseSummary.recommendedAction.replaceAll('_', ' '),
          subtitle: [
            caseSummary.district,
            caseSummary.updatedAt.toLocal().toString(),
          ].whereType<String>().join(' · '),
          trailing: const Icon(Icons.chevron_right),
          children: [
            Row(
              children: [
                StatusBadge(
                  label: caseSummary.status,
                  color: Theme.of(context).colorScheme.primary,
                  icon: Icons.assignment_outlined,
                ),
                const SizedBox(width: 8),
                const Text('Tap to inspect'),
              ],
            ),
            Text('Visit ${caseSummary.visitId}'),
            if (role != AppRole.ngoCsr)
              Text('Patient hash ${caseSummary.patientHash}'),
          ],
        ),
      ),
    );
  }
}

class _ResearchHome extends StatelessWidget {
  const _ResearchHome({required this.stream});

  final Stream<List<ResearchExportSummary>> stream;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Research home')),
      body: StreamBuilder<List<ResearchExportSummary>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Exports unavailable',
              message: snapshot.error.toString(),
            );
          }
          final exports = snapshot.data ?? const [];
          if (exports.isEmpty) {
            return const EmptyState(
              icon: Icons.dataset_outlined,
              title: 'No research exports',
              message: 'Exports appear after research consent and sync.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final item = exports[index];
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ResearchExportDetailScreen(summary: item),
                      ),
                    );
                  },
                  child: SectionPanel(
                    title: item.exportId,
                    subtitle: item.createdAt.toLocal().toString(),
                    trailing: const Icon(Icons.chevron_right),
                    children: [
                      StatusBadge(
                        label: item.status,
                        color: Theme.of(context).colorScheme.primary,
                        icon: Icons.dataset_outlined,
                      ),
                      const SizedBox(height: 6),
                      Text('Visit ${item.visitId} · Tap to inspect'),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemCount: exports.length,
          );
        },
      ),
    );
  }
}
