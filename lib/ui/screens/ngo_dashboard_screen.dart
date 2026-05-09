import 'package:flutter/material.dart';

import '../../dashboard/dashboard_models.dart';
import '../components/empty_state.dart';
import '../components/section_panel.dart';

class NgoCsrDashboardScreen extends StatelessWidget {
  const NgoCsrDashboardScreen({super.key, this.metrics});

  final DashboardMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final data = metrics;
    return Scaffold(
      appBar: AppBar(title: const Text('NGO / CSR dashboard')),
      body: data == null || data.totalScreenings == 0
          ? const EmptyState(
              icon: Icons.bar_chart_outlined,
              title: 'No aggregate data',
              message:
                  'Aggregate counts appear after consented cases sync to the dashboard.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GridView.count(
                  crossAxisCount: MediaQuery.sizeOf(context).width > 640
                      ? 4
                      : 2,
                  childAspectRatio: 1.45,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  children: [
                    _MetricTile('Screenings', data.totalScreenings.toString()),
                    _MetricTile('High risk', data.highRiskCount.toString()),
                    _MetricTile('Urgent', data.urgentCount.toString()),
                    _MetricTile(
                      'Uncertainty',
                      '${(data.averageUncertainty * 100).round()}%',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SectionPanel(
                  title: 'Village-code coverage',
                  subtitle: 'Only de-identified village codes are shown.',
                  children: [
                    for (final entry in data.byVillageCode.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(child: Text(entry.key)),
                            Text(entry.value.toString()),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
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
            Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}
