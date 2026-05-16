import 'package:flutter/material.dart';

import '../../auth/role_auth.dart';
import '../../cloud/case_detail_repository.dart';
import '../../cloud/role_home_repository.dart';
import '../components/section_panel.dart';
import '../components/status_badge.dart';

class CaseDetailScreen extends StatefulWidget {
  const CaseDetailScreen({
    super.key,
    required this.caseSummary,
    required this.role,
    this.repository,
  });

  final CloudCaseSummary caseSummary;
  final AppRole role;
  final CaseDetailRepository? repository;

  @override
  State<CaseDetailScreen> createState() => _CaseDetailScreenState();
}

class _CaseDetailScreenState extends State<CaseDetailScreen> {
  late final CaseDetailRepository _repository =
      widget.repository ?? CaseDetailRepository();
  CloudCaseDetail? _detail;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _repository.loadCaseDetail(
        caseId: widget.caseSummary.caseId,
        visitId: widget.caseSummary.visitId,
        role: widget.role,
      );
      if (!mounted) {
        return;
      }
      setState(() => _detail = detail);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _label(widget.caseSummary.recommendedAction);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionPanel(
                  title: 'Case overview',
                  subtitle: widget.caseSummary.updatedAt.toLocal().toString(),
                  trailing: StatusBadge(
                    label: widget.caseSummary.status,
                    color: Theme.of(context).colorScheme.primary,
                    icon: Icons.assignment_outlined,
                  ),
                  children: [
                    _row('Visit', widget.caseSummary.visitId),
                    _row('Case', widget.caseSummary.caseId),
                    if (widget.role != AppRole.ngoCsr)
                      _row('Patient hash', widget.caseSummary.patientHash),
                    _row('District', widget.caseSummary.district ?? '—'),
                    _row('Village code', widget.caseSummary.villageCode ?? '—'),
                    _row('State', widget.caseSummary.state ?? '—'),
                    _row('Risk', widget.caseSummary.riskLevel ?? '—'),
                    _row('Action', _label(widget.caseSummary.recommendedAction)),
                  ],
                ),
                if (widget.caseSummary.consentScopes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SectionPanel(
                    title: 'Consent scopes',
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.caseSummary.consentScopes
                            .map((scope) => Chip(label: Text(_label(scope))))
                            .toList(),
                      ),
                    ],
                  ),
                ],
                if (_detail?.patientIdentity != null) ...[
                  const SizedBox(height: 12),
                  SectionPanel(
                    title: 'Patient identity',
                    subtitle: 'Visible to ASHA and assigned doctor only.',
                    children: _mapRows(_detail!.patientIdentity!),
                  ),
                ],
                if (_detail?.screening != null) ...[
                  const SizedBox(height: 12),
                  _screeningSection(_detail!.screening!),
                ],
                if (_detail?.doctorPackage != null) ...[
                  const SizedBox(height: 12),
                  SectionPanel(
                    title: 'Doctor package',
                    children: _mapRows(_detail!.doctorPackage!),
                  ),
                ],
                if (_detail!.storageObjects.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SectionPanel(
                    title: 'Cloud images',
                    subtitle:
                        'ROI paths in Storage. Upload may be skipped on Spark plan.',
                    children: [
                      for (final object in _detail!.storageObjects)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            object['storagePath']?.toString() ?? object.toString(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  Widget _screeningSection(Map<String, Object?> screening) {
    final carePlan = screening['carePlan'];
    final hypotheses = screening['hypotheses'];
    final siteResults = screening['siteResults'];
    return SectionPanel(
      title: 'Screening assessment',
      children: [
        if (carePlan is Map)
          ..._mapRows(Map<String, Object?>.from(carePlan))
        else
          ..._mapRows(screening),
        if (hypotheses is List && hypotheses.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Hypotheses',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final item in hypotheses)
            if (item is Map)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${item['label']}: ${item['probability']} — ${item['rationale'] ?? ''}',
                ),
              ),
        ],
        if (siteResults is List && siteResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Site results', style: Theme.of(context).textTheme.titleSmall),
          for (final item in siteResults)
            if (item is Map)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${item['siteLabel'] ?? item['siteId']}: ${item['findings'] ?? ''}',
                ),
              ),
        ],
      ],
    );
  }

  List<Widget> _mapRows(Map<String, Object?> data) {
    return data.entries
        .where((entry) => entry.value != null)
        .map((entry) => _row(_label(entry.key), entry.value.toString()))
        .toList();
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _label(String raw) {
    if (raw.trim().isEmpty) {
      return '—';
    }
    return raw.replaceAll('_', ' ');
  }
}
