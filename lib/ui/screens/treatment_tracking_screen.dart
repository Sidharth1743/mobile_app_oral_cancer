import 'package:flutter/material.dart';

import '../../data/local_database.dart';
import '../../data/models.dart';
import '../../treatment/treatment_tracking.dart';
import '../components/section_panel.dart';
import '../components/status_badge.dart';

class TreatmentTrackingScreen extends StatefulWidget {
  const TreatmentTrackingScreen({
    super.key,
    required this.assessment,
    required this.database,
    this.actorUid = 'local-user',
    this.clock,
  });

  final FullAssessment assessment;
  final LocalDatabase database;
  final String actorUid;
  final DateTime Function()? clock;

  @override
  State<TreatmentTrackingScreen> createState() =>
      _TreatmentTrackingScreenState();
}

class _TreatmentTrackingScreenState extends State<TreatmentTrackingScreen> {
  final _note = TextEditingController();
  TreatmentStatus _status = TreatmentStatus.referred;
  Future<TreatmentTimeline?>? _future;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = widget.database.treatmentTimelineForVisit(
      widget.assessment.visitId,
    );
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _addEvent(TreatmentTimeline? existing) async {
    setState(() => _error = null);
    try {
      final timeline =
          existing ??
          TreatmentTimeline(
            visitId: widget.assessment.visitId,
            patientHash: widget.assessment.patientHash,
            events: const [],
          );
      final updated = timeline.addEvent(
        TreatmentEvent(
          status: _status,
          recordedAt: (widget.clock ?? () => DateTime.now().toUtc())(),
          actorUid: widget.actorUid,
          note: _note.text.trim(),
        ),
      );
      await widget.database.saveTreatmentTimeline(updated);
      _note.clear();
      setState(() {
        _future = widget.database.treatmentTimelineForVisit(
          widget.assessment.visitId,
        );
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Treatment tracking')),
      body: FutureBuilder<TreatmentTimeline?>(
        future: _future,
        builder: (context, snapshot) {
          final timeline = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionPanel(
                title: 'Current status',
                subtitle: widget.assessment.visitId,
                trailing: StatusBadge(
                  label: timeline?.currentStatus?.name ?? 'not started',
                  color: timeline?.completed == true
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.secondary,
                  icon: timeline?.completed == true
                      ? Icons.check_circle_outline
                      : Icons.pending_actions_outlined,
                ),
                children: [
                  DropdownButtonFormField<TreatmentStatus>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: TreatmentStatus.values
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(status.name.replaceAll('_', ' ')),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _status = value ?? _status),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _note,
                    decoration: const InputDecoration(labelText: 'Note'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _addEvent(timeline),
                      icon: const Icon(Icons.add),
                      label: const Text('Add event'),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              SectionPanel(
                title: 'Timeline',
                children: [
                  if (timeline == null || timeline.events.isEmpty)
                    const Text('No treatment events recorded.'),
                  for (final event
                      in timeline?.events ?? const <TreatmentEvent>[])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(event.status.name.replaceAll('_', ' ')),
                      subtitle: Text(event.note),
                      trailing: Text(
                        event.recordedAt.toIso8601String().split('T').first,
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
