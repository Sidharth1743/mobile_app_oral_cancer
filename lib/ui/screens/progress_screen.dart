import 'package:flutter/material.dart';

import '../../data/local_database.dart';
import '../../data/models.dart';
import '../components/section_panel.dart';
import '../components/status_badge.dart';
import 'treatment_tracking_screen.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, required this.assessment, this.database});

  final FullAssessment assessment;
  final LocalDatabase? database;

  @override
  Widget build(BuildContext context) {
    final increased = assessment.delta.concernIncreased;
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionPanel(
            title: 'Visit change',
            subtitle: assessment.delta.summary,
            trailing: StatusBadge(
              label: increased ? 'Increased' : 'Stable',
              color: increased
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
              icon: increased ? Icons.trending_up : Icons.check_circle_outline,
            ),
            children: [
              _InfoRow(
                'Size change',
                '${assessment.delta.sizeChangeMm.toStringAsFixed(1)} mm',
              ),
              _InfoRow(
                'Next screen',
                assessment.carePlan.rescreenDate
                    .toIso8601String()
                    .split('T')
                    .first,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionPanel(
            title: 'Flagged sites',
            children: [
              for (final site in assessment.siteResults)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(site.siteLabel),
                  subtitle: Text(site.findings),
                  trailing: Text(
                    '${(site.suspicionScore * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          if (database != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TreatmentTrackingScreen(
                        assessment: assessment,
                        database: database!,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Treatment tracking'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value),
        ],
      ),
    );
  }
}
