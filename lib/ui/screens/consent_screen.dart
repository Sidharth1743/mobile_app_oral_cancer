import 'package:flutter/material.dart';

import '../../consent/consent.dart';
import '../../data/local_database.dart';
import '../../data/models.dart';
import '../../sync/post_result_share_queue.dart';
import '../components/section_panel.dart';
import '../components/status_badge.dart';
import 'doctor_package_screen.dart';
import 'research_export_screen.dart';
import 'sync_queue_screen.dart';

typedef ConsentSaver =
    Future<ConsentSaveResult> Function(ConsentRecord consent);

class ConsentSaveResult {
  const ConsentSaveResult({required this.consent, required this.queuedCount});

  final ConsentRecord consent;
  final int queuedCount;
}

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({
    super.key,
    required this.assessment,
    required this.database,
    this.clock,
    this.saveConsent,
  });

  final FullAssessment assessment;
  final LocalDatabase database;
  final DateTime Function()? clock;
  final ConsentSaver? saveConsent;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _doctorShare = false;
  bool _ashaShare = false;
  bool _cloudBackup = false;
  bool _researchExport = false;
  bool _busy = false;
  String? _error;
  String? _status;
  ConsentRecord? _savedConsent;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final scopes = <ConsentScope>{
        if (_doctorShare) ConsentScope.doctorShare,
        if (_ashaShare) ConsentScope.ashaShare,
        if (_cloudBackup) ConsentScope.cloudBackup,
        if (_researchExport) ConsentScope.researchExport,
      };
      final now = (widget.clock ?? () => DateTime.now().toUtc())();
      final consent = ConsentRecord(
        visitId: widget.assessment.visitId,
        patientHash: widget.assessment.patientHash,
        scopes: scopes,
        recordedAt: now,
        policyVersion: '2026-05',
        screeningCompletedAt: widget.assessment.createdAt,
      );
      final saver = widget.saveConsent ?? _saveConsentToDatabase;
      final result = await saver(consent);
      if (!mounted) {
        return;
      }
      setState(() {
        _savedConsent = result.consent;
        _status = result.queuedCount == 0
            ? 'Consent stored. No sharing request selected.'
            : 'Consent stored. ${result.queuedCount} request(s) queued.';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<ConsentSaveResult> _saveConsentToDatabase(
    ConsentRecord consent,
  ) async {
    await widget.database.saveConsent(consent);
    final queued = await const PostResultShareQueue().enqueueAllowedShares(
      database: widget.database,
      assessment: widget.assessment,
      consent: consent,
    );
    return ConsentSaveResult(consent: consent, queuedCount: queued.length);
  }

  @override
  Widget build(BuildContext context) {
    final consent = _savedConsent;
    return Scaffold(
      appBar: AppBar(title: const Text('Consent')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionPanel(
            title: 'After result sharing',
            subtitle:
                'Choose only what the patient agrees to share for this visit.',
            trailing: StatusBadge(
              label: 'Post result',
              color: Theme.of(context).colorScheme.primary,
              icon: Icons.lock_open_outlined,
            ),
            children: [
              SwitchListTile(
                key: const Key('consent-doctor-share'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Share with assigned doctor'),
                value: _doctorShare,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _doctorShare = value),
              ),
              SwitchListTile(
                key: const Key('consent-asha-share'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Share with ASHA worker'),
                value: _ashaShare,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _ashaShare = value),
              ),
              SwitchListTile(
                key: const Key('consent-cloud-backup'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Cloud backup'),
                value: _cloudBackup,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _cloudBackup = value),
              ),
              SwitchListTile(
                key: const Key('consent-research-export'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Research dataset export'),
                value: _researchExport,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _researchExport = value),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('save-consent-button'),
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_busy ? 'Saving' : 'Save consent'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(_status!),
              ],
            ],
          ),
          if (consent != null) ...[
            const SizedBox(height: 12),
            SectionPanel(
              title: 'Next actions',
              subtitle: 'Actions are enabled only for saved consent scopes.',
              children: [
                _ActionRow(
                  enabled: consent.doctorShare,
                  icon: Icons.medical_information_outlined,
                  label: 'Prepare doctor package',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DoctorPackageScreen(
                          assessment: widget.assessment,
                          database: widget.database,
                          consent: consent,
                        ),
                      ),
                    );
                  },
                ),
                _ActionRow(
                  enabled: consent.researchExport,
                  icon: Icons.dataset_outlined,
                  label: 'Create research export',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ResearchExportScreen(
                          assessment: widget.assessment,
                          database: widget.database,
                          consent: consent,
                        ),
                      ),
                    );
                  },
                ),
                _ActionRow(
                  enabled: consent.hasAnyOnlineScope,
                  icon: Icons.sync_outlined,
                  label: 'Open sync queue',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            SyncQueueScreen(database: widget.database),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.enabled,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      enabled: enabled,
      onTap: enabled ? onPressed : null,
    );
  }
}
