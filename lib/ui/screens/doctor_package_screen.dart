import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../consent/consent.dart';
import '../../core/pii_vault.dart';
import '../../data/local_database.dart';
import '../../data/models.dart';
import '../../output/doctor_package.dart';
import '../components/section_panel.dart';
import '../components/status_badge.dart';

class DoctorPackageScreen extends StatefulWidget {
  const DoctorPackageScreen({
    super.key,
    required this.assessment,
    required this.database,
    required this.consent,
  });

  final FullAssessment assessment;
  final LocalDatabase database;
  final ConsentRecord consent;

  @override
  State<DoctorPackageScreen> createState() => _DoctorPackageScreenState();
}

class _DoctorPackageScreenState extends State<DoctorPackageScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ashaPin = TextEditingController();
  final _doctorUid = TextEditingController();
  bool _busy = false;
  String? _error;
  SyncQueueItem? _queued;

  @override
  void dispose() {
    _ashaPin.dispose();
    _doctorUid.dispose();
    super.dispose();
  }

  Future<void> _queuePackage() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _queued = null;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      final identity = await PiiVault(
        preferences: preferences,
      ).loadIdentity(ashaPin: _ashaPin.text);
      final clinicalRecords = await widget.database.clinicalRecordsForPatient(
        widget.assessment.patientHash,
      );
      if (clinicalRecords.isEmpty) {
        throw StateError('No clinical record found for this assessment.');
      }
      final queued = await const IdentifiedAssessmentDoctorPackageBuilder()
          .queue(
            database: widget.database,
            identity: identity,
            clinicalRecord: clinicalRecords.first,
            assessment: widget.assessment,
            consent: widget.consent,
            assignedDoctorUid: _doctorUid.text,
          );
      if (!mounted) {
        return;
      }
      setState(() => _queued = queued);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final consentReady = widget.consent.doctorShare;
    return Scaffold(
      appBar: AppBar(title: const Text('Doctor package')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionPanel(
            title: 'Package access',
            subtitle:
                'The ASHA PIN unlocks the on-device identity vault for this package.',
            trailing: StatusBadge(
              label: consentReady ? 'Consent saved' : 'Consent missing',
              color: consentReady
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
              icon: consentReady ? Icons.verified_outlined : Icons.lock,
            ),
            children: [
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      key: const Key('doctor-uid-field'),
                      controller: _doctorUid,
                      decoration: const InputDecoration(
                        labelText: 'Assigned doctor UID',
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('doctor-package-asha-pin-field'),
                      controller: _ashaPin,
                      decoration: const InputDecoration(labelText: 'ASHA PIN'),
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('queue-doctor-package-button'),
                        onPressed: consentReady && !_busy
                            ? _queuePackage
                            : null,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.outbox_outlined),
                        label: Text(_busy ? 'Preparing' : 'Queue package'),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_queued != null) ...[
                const SizedBox(height: 12),
                Text('Queued ${_queued!.kind}'),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SectionPanel(
            title: 'Included clinical data',
            subtitle: 'Identity is included only after doctor-share consent.',
            children: [
              _InfoRow('Visit', widget.assessment.visitId),
              _InfoRow('Doctor brief', widget.assessment.carePlan.doctorBrief),
              _InfoRow(
                'ROI images',
                widget.assessment.siteResults
                    .where((site) => site.roiImagePath != null)
                    .length
                    .toString(),
              ),
            ],
          ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String? _required(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Required';
  }
  return null;
}
