import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/job_setup.dart';
import '../models/jsa_draft.dart';
import '../services/jsa_export_service.dart';
import '../services/job_storage_service.dart';
import '../services/jsa_storage_service.dart';
import '../widgets/app_header.dart';
import 'jsa_screen.dart';

class JsaHistoryScreen extends StatefulWidget {
  const JsaHistoryScreen({super.key});

  @override
  State<JsaHistoryScreen> createState() => _JsaHistoryScreenState();
}

class _JsaHistoryScreenState extends State<JsaHistoryScreen> {
  final _jsaStorage = JsaStorageService();
  final _jobStorage = JobStorageService();
  final _exportService = const JsaExportService();
  final _dateFilter = TextEditingController();
  final _companyFilter = TextEditingController();
  final _jobPadFilter = TextEditingController();

  List<JsaDraft> _drafts = const <JsaDraft>[];
  Map<String, JobSetup> _jobsById = const <String, JobSetup>{};
  JobSetup? _activeJob;
  bool _loading = true;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dateFilter.dispose();
    _companyFilter.dispose();
    _jobPadFilter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final drafts = await _jsaStorage.loadAllDrafts();
    final jobs = await _jobStorage.loadJobs();
    final activeJob = await _jobStorage.loadActiveJob();
    if (!mounted) return;
    setState(() {
      _drafts = drafts;
      _jobsById = {for (final job in jobs) job.id: job};
      _activeJob = activeJob;
      _loading = false;
    });
  }

  String _todayText() {
    final now = DateTime.now();
    final local = DateTime(now.year, now.month, now.day);
    return local.toIso8601String().split('T').first;
  }

  bool get _todayJsaComplete {
    final activeJob = _activeJob;
    if (activeJob == null) return false;
    return _drafts.any(
      (draft) =>
          draft.activeJobId == activeJob.id &&
          draft.date.trim() == _todayText(),
    );
  }

  List<JsaDraft> get _filteredDrafts {
    final dateQuery = _dateFilter.text.trim().toLowerCase();
    final companyQuery = _companyFilter.text.trim().toLowerCase();
    final jobPadQuery = _jobPadFilter.text.trim().toLowerCase();
    return _drafts.where((draft) {
      final linkedJob = _jobsById[draft.activeJobId];
      final pad = linkedJob?.padName.trim().toLowerCase() ?? '';
      final company = draft.company.trim().toLowerCase();
      final date = draft.date.trim().toLowerCase();
      final location = draft.location.trim().toLowerCase();
      final matchesDate = dateQuery.isEmpty || date.contains(dateQuery);
      final matchesCompany =
          companyQuery.isEmpty || company.contains(companyQuery);
      final matchesJobPad = jobPadQuery.isEmpty ||
          location.contains(jobPadQuery) ||
          pad.contains(jobPadQuery);
      return matchesDate && matchesCompany && matchesJobPad;
    }).toList();
  }

  Future<void> _openDraft(JsaDraft draft) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JsaScreen(
          initialActiveJobId: draft.activeJobId,
          initialDate: draft.date,
        ),
      ),
    );
    await _load();
  }

  Future<void> _shareDraft(JsaDraft draft) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final linkedJob = draft.activeJobId.trim().isEmpty
          ? null
          : await _jobStorage.loadJobById(draft.activeJobId);
      final exported = await _exportService.exportPdf(
        draft: draft,
        activeJob: linkedJob,
      );
      await Share.shareXFiles(
        [XFile(exported.filePath)],
        subject: 'WellWerks JSA',
        text: 'Saved JSA exported from WellWerks.',
      );
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
    }
  }

  Widget _filterField({
    required String label,
    required TextEditingController controller,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _statusCard() {
    final activeJob = _activeJob;
    final complete = _todayJsaComplete;
    return Card(
      color: complete ? const Color(0xFF142015) : const Color(0xFF241B10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Today\'s JSA Status',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              complete ? 'JSA COMPLETE' : 'JSA NOT COMPLETE',
              style: TextStyle(
                color: complete
                    ? const Color(0xFF7EDC8C)
                    : const Color(0xFFCDA56A),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            if (activeJob != null) ...[
              const SizedBox(height: 6),
              Text(
                '${activeJob.company.trim().isEmpty ? 'Active Job' : activeJob.company.trim()} • ${activeJob.padName.trim().isEmpty ? 'Pad not entered' : activeJob.padName.trim()}',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            if (!complete) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: activeJob == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const JsaScreen()),
                          ),
                  icon: const Icon(Icons.add_task),
                  label: const Text('Create Today\'s JSA'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _historyItem(JsaDraft draft) {
    final linkedJob = _jobsById[draft.activeJobId];
    final padName = linkedJob?.padName.trim() ?? '';
    final customer = linkedJob?.customer.trim() ?? '';
    final company = draft.company.trim();
    final location = draft.location.trim();
    final wellName = draft.wellName.trim();
    return Card(
      color: const Color(0xFF17130E),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    draft.date.trim().isEmpty ? '-' : draft.date.trim(),
                    style: const TextStyle(
                      color: Color(0xFFCDA56A),
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                const Text(
                  'JSA COMPLETE',
                  style: TextStyle(
                    color: Color(0xFF7EDC8C),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              customer.isNotEmpty
                  ? 'Customer: $customer'
                  : (company.isEmpty ? 'Company: -' : 'Company: $company'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Location: ${location.isEmpty ? '-' : location}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              'Job / Pad: ${padName.isEmpty ? '-' : padName}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              'Well: ${wellName.isEmpty ? '-' : wellName}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _openDraft(draft),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Open Saved JSA'),
                ),
                OutlinedButton.icon(
                  onPressed: _sharing ? null : () => _shareDraft(draft),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Export / Share'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'JSA History', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final drafts = _filteredDrafts;
    return Scaffold(
      appBar: const AppHeader(title: 'JSA History', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _statusCard(),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _filterField(label: 'Date', controller: _dateFilter),
                  _filterField(label: 'Company', controller: _companyFilter),
                  _filterField(label: 'Job / Pad', controller: _jobPadFilter),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (drafts.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No saved JSAs found.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          for (final draft in drafts) _historyItem(draft),
        ],
      ),
    );
  }
}
