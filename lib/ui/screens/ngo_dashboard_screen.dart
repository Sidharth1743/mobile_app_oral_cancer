import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../auth/role_auth.dart';
import '../../cloud/firebase_role_auth.dart';
import '../../cloud/role_home_repository.dart';
import '../../dashboard/ngo_dashboard_metrics.dart';
import '../components/empty_state.dart';
import '../components/section_panel.dart';
import 'case_detail_screen.dart';
import 'role_login_screen.dart';

class NgoCsrDashboardScreen extends StatelessWidget {
  const NgoCsrDashboardScreen({
    super.key,
    RoleHomeRepository? repository,
    FirebaseRoleAuthService? authService,
  }) : _repository = repository,
       _authService = authService;

  final RoleHomeRepository? _repository;
  final FirebaseRoleAuthService? _authService;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('NGO / CSR dashboard')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const EmptyState(
                icon: Icons.login,
                title: 'Sign in required',
                message:
                    'Program metrics load from synced Firestore cases. Sign in with an NGO/CSR account.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RoleLoginScreen()),
                  );
                },
                icon: const Icon(Icons.login),
                label: const Text('Staff login'),
              ),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<FirebaseUserProfile>(
      future: (_authService ?? FirebaseRoleAuthService()).profileForUid(user.uid),
      builder: (context, profileSnap) {
        if (profileSnap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('NGO / CSR dashboard')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (profileSnap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('NGO / CSR dashboard')),
            body: EmptyState(
              icon: Icons.error_outline,
              title: 'Profile unavailable',
              message: profileSnap.error.toString(),
            ),
          );
        }
        final profile = profileSnap.data!;
        if (profile.role != AppRole.ngoCsr && profile.role != AppRole.admin) {
          return Scaffold(
            appBar: AppBar(title: const Text('NGO / CSR dashboard')),
            body: const EmptyState(
              icon: Icons.lock_outline,
              title: 'NGO / CSR role required',
              message: 'This dashboard is for NGO/CSR or admin accounts only.',
            ),
          );
        }

        final repository = _repository ?? FirestoreRoleHomeRepository();
        return Scaffold(
          appBar: AppBar(title: const Text('NGO / CSR program dashboard')),
          body: StreamBuilder<List<CloudCaseSummary>>(
            stream: repository.ngoProgramCases(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'Dashboard unavailable',
                  message: snapshot.error.toString(),
                );
              }
              final cases = snapshot.data ?? const [];
              if (cases.isEmpty) {
                return const EmptyState(
                  icon: Icons.bar_chart_outlined,
                  title: 'No program data yet',
                  message:
                      'Metrics appear after ASHA workers sync consented cases to Firestore.',
                );
              }

              final metrics = NgoDashboardMetrics.fromCases(cases);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'De-identified program view',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Village codes and districts only — no patient names or phone numbers.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  _metricGrid(context, metrics),
                  const SizedBox(height: 16),
                  SectionPanel(
                    title: 'Consent-enabled sync (program)',
                    subtitle: 'Counts of cases with each online consent scope.',
                    children: [
                      _consentRow(
                        'Doctor share',
                        metrics.doctorShareEnabled,
                        cases.length,
                      ),
                      _consentRow(
                        'Cloud backup',
                        metrics.cloudBackupEnabled,
                        cases.length,
                      ),
                      _consentRow(
                        'Research export',
                        metrics.researchExportEnabled,
                        cases.length,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _breakdownPanel(
                    'By district',
                    metrics.byDistrict,
                  ),
                  const SizedBox(height: 12),
                  _breakdownPanel(
                    'By village code',
                    metrics.byVillageCode,
                  ),
                  const SizedBox(height: 12),
                  _breakdownPanel(
                    'By recommended action',
                    metrics.byAction,
                  ),
                  const SizedBox(height: 12),
                  SectionPanel(
                    title: 'Recent screenings',
                    subtitle: 'Tap a row for de-identified case detail.',
                    children: [
                      for (final item in metrics.recentCases)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_label(item.recommendedAction)),
                          subtitle: Text(
                            [
                              item.district,
                              item.villageCode,
                              item.updatedAt.toLocal().toString(),
                            ].whereType<String>().join(' · '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CaseDetailScreen(
                                  caseSummary: item,
                                  role: AppRole.ngoCsr,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _metricGrid(BuildContext context, NgoProgramMetrics metrics) {
    final scheme = Theme.of(context).colorScheme;
    final tiles = [
      _MetricTile('Total screenings', '${metrics.totalScreenings}'),
      _MetricTile('Referrals', '${metrics.referralCount}'),
      _MetricTile('Urgent', '${metrics.urgentCount}'),
      _MetricTile(
        'Referral rate',
        '${(metrics.referralRate * 100).round()}%',
      ),
      _MetricTile('Districts', '${metrics.uniqueDistricts}'),
      _MetricTile('Villages', '${metrics.uniqueVillages}'),
      _MetricTile('Low risk', '${metrics.lowRiskCount}'),
      _MetricTile('Recapture', '${metrics.recaptureCount}'),
    ];
    return GridView.count(
      crossAxisCount: MediaQuery.sizeOf(context).width > 640 ? 4 : 2,
      childAspectRatio: 1.45,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: tiles
          .map(
            (tile) => DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tile.label,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    Text(
                      tile.value,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _breakdownPanel(String title, Map<String, int> counts) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return SectionPanel(
      title: title,
      children: [
        for (final entry in entries.take(12))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: Text(entry.key)),
                Text(entry.value.toString()),
              ],
            ),
          ),
      ],
    );
  }

  Widget _consentRow(String label, int count, int total) {
    final pct = total == 0 ? 0 : ((count / total) * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('$count ($pct%)'),
        ],
      ),
    );
  }

  String _label(String raw) => raw.replaceAll('_', ' ');
}

class _MetricTile {
  const _MetricTile(this.label, this.value);
  final String label;
  final String value;
}
