import 'package:flutter/material.dart';

import '../../cloud/case_detail_repository.dart';
import '../../cloud/role_home_repository.dart';
import '../components/section_panel.dart';
import '../components/status_badge.dart';

class ResearchExportDetailScreen extends StatefulWidget {
  const ResearchExportDetailScreen({
    super.key,
    required this.summary,
    this.repository,
  });

  final ResearchExportSummary summary;
  final CaseDetailRepository? repository;

  @override
  State<ResearchExportDetailScreen> createState() =>
      _ResearchExportDetailScreenState();
}

class _ResearchExportDetailScreenState extends State<ResearchExportDetailScreen> {
  late final CaseDetailRepository _repository =
      widget.repository ?? CaseDetailRepository();
  CloudResearchExportDetail? _detail;
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
      final detail = await _repository.loadResearchExport(widget.summary.exportId);
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.summary.exportId)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionPanel(
                  title: 'Export status',
                  subtitle: widget.summary.createdAt.toLocal().toString(),
                  trailing: StatusBadge(
                    label: widget.summary.status,
                    color: Theme.of(context).colorScheme.primary,
                    icon: Icons.dataset_outlined,
                  ),
                  children: [
                    _row('Visit', widget.summary.visitId),
                    _row('Export', widget.summary.exportId),
                  ],
                ),
                if (_detail != null) ...[
                  const SizedBox(height: 12),
                  SectionPanel(
                    title: 'De-identified dataset row',
                    subtitle:
                        'No direct name, phone, or village. Safe for research review.',
                    children: _detail!.data.entries
                        .where((e) => e.value != null)
                        .map(
                          (e) => _row(
                            e.key.replaceAll('_', ' '),
                            e.value.toString(),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
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
}
