import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../consent/consent.dart';
import '../../core/pii_vault.dart';
import '../../data/local_database.dart';
import '../../data/models.dart';
import '../../research/research_export.dart';
import '../../research/research_export_file.dart';
import '../components/section_panel.dart';
import '../components/status_badge.dart';

class ResearchExportScreen extends StatefulWidget {
  const ResearchExportScreen({
    super.key,
    required this.assessment,
    required this.database,
    required this.consent,
  });

  final FullAssessment assessment;
  final LocalDatabase database;
  final ConsentRecord consent;

  @override
  State<ResearchExportScreen> createState() => _ResearchExportScreenState();
}

class _ResearchExportScreenState extends State<ResearchExportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ashaPin = TextEditingController();
  final _studySecret = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _exportJson;
  String? _filePath;

  @override
  void dispose() {
    _ashaPin.dispose();
    _studySecret.dispose();
    super.dispose();
  }

  Future<void> _createExport() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _exportJson = null;
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
      final export = const AssessmentResearchExporter().export(
        identity: identity,
        clinicalRecord: clinicalRecords.first,
        assessment: widget.assessment,
        consent: widget.consent,
        studySecret: _studySecret.text,
      );
      final file = await const ResearchExportFileWriter().writeJson(
        visitId: widget.assessment.visitId,
        export: export,
      );
      await widget.database.enqueueSync(
        visitId: widget.assessment.visitId,
        kind: 'research_dataset_row',
        payload: {
          'visitId': widget.assessment.visitId,
          'patientHash': widget.assessment.patientHash,
          'consent': widget.consent.toJson(),
          'export': {...export, 'localFilePath': file.path},
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _exportJson = const JsonEncoder.withIndent('  ').convert(export);
        _filePath = file.path;
      });
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
    final consentReady = widget.consent.researchExport;
    return Scaffold(
      appBar: AppBar(title: const Text('Research export')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionPanel(
            title: 'Dataset row',
            subtitle: 'Direct identifiers are removed before queueing.',
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
                      key: const Key('research-asha-pin-field'),
                      controller: _ashaPin,
                      decoration: const InputDecoration(labelText: 'ASHA PIN'),
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('study-secret-field'),
                      controller: _studySecret,
                      decoration: const InputDecoration(
                        labelText: 'Study secret',
                      ),
                      obscureText: true,
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('create-research-export-button'),
                        onPressed: consentReady && !_busy
                            ? _createExport
                            : null,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.dataset_outlined),
                        label: Text(_busy ? 'Creating' : 'Create export'),
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
            ],
          ),
          if (_exportJson != null) ...[
            const SizedBox(height: 12),
            SectionPanel(
              title: 'Queued export',
              subtitle: _filePath,
              children: [
                SelectableText(
                  _exportJson!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
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
