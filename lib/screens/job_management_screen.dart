import 'package:flutter/material.dart';

import '../models/job_history.dart';
import '../models/job_setup.dart';
import '../services/job_history_service.dart';
import '../services/job_storage_service.dart';
import '../services/jsa_storage_service.dart';
import '../services/production_shift_service.dart';
import '../widgets/app_header.dart';
import 'job_setup_screen.dart';

class JobManagementScreen extends StatefulWidget {
  const JobManagementScreen({super.key});

  @override
  State<JobManagementScreen> createState() => _JobManagementScreenState();
}

class _JobManagementScreenState extends State<JobManagementScreen> {
  final _jobStorage = JobStorageService();
  final _historyService = JobHistoryService();
  final _shiftService = ProductionShiftService();
  final _jsaStorage = JsaStorageService();

  JobSetup? _activeJob;
  List<JobSetup> _jobs = const <JobSetup>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final active = await _jobStorage.loadActiveJob();
    var jobs = await _jobStorage.loadJobs();

    if (active != null && !jobs.any((item) => item.id == active.id)) {
      jobs = <JobSetup>[active, ...jobs];
    }

    if (!mounted) return;
    setState(() {
      _activeJob = active;
      _jobs = jobs;
      _loading = false;
    });
  }

  List<JobSetup> get _nonArchivedJobs {
    return _jobs
        .where((job) => job.status.toLowerCase() != 'archived')
        .toList();
  }

  String _wellsLabel(JobSetup job) {
    final wells = job.wells
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return wells.isEmpty ? '-' : wells.join(' / ');
  }

  Future<void> _openJobSetup({
    required bool startFresh,
    required bool editActive,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobSetupScreen(
          startFreshJob: startFresh,
          editActiveOnOpen: editActive,
        ),
      ),
    );
    await _load();
  }

  Future<void> _changeActiveJob() async {
    final candidates = _nonArchivedJobs;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No available jobs to activate yet.')),
      );
      return;
    }

    final selectedId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Active Job'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final job in candidates)
                ListTile(
                  leading: Icon(
                    _activeJob?.id == job.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: _activeJob?.id == job.id
                        ? const Color(0xFFCDA56A)
                        : Colors.white70,
                  ),
                  title: Text(job.company.trim().isEmpty
                      ? 'Job ${job.id}'
                      : job.company.trim()),
                  subtitle: Text(
                      '${job.padName.trim().isEmpty ? '-' : job.padName.trim()}\n${_wellsLabel(job)}'),
                  onTap: () => Navigator.of(context).pop(job.id),
                  isThreeLine: true,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedId == null || selectedId.isEmpty) return;

    await _jobStorage.setActiveJobById(selectedId);
    await _shiftService.clearActiveShift();
    await _jsaStorage.clearDraft();

    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Active job changed.')),
    );
  }

  Future<void> _archiveJob(JobSetup job) async {
    final isActive = _activeJob?.id == job.id;

    if (isActive) {
      await _historyService.archiveCurrentJobOrShift();
    }

    await _jobStorage.archiveJobById(job.id);

    if (isActive) {
      await _shiftService.clearActiveShift();
      await _jsaStorage.clearDraft();
      await _historyService.clearCurrentLayoutSummary();
    }

    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Job archived.')),
    );
  }

  bool _sameIdentity({required JobSetup left, required ArchivedJob right}) {
    final leftWells = left.wells
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList()
      ..sort();
    final rightWells = right.wells
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList()
      ..sort();
    return left.company.trim().toLowerCase() ==
            right.company.trim().toLowerCase() &&
        left.padName.trim().toLowerCase() ==
            right.padName.trim().toLowerCase() &&
        leftWells.join('|') == rightWells.join('|');
  }

  Future<void> _deleteJob(JobSetup job) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Job?'),
            content: const Text(
              'This will permanently delete Quick Rounds, Production Reports, Text Updates, and saved shift data for this job.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    final wasActive = _activeJob?.id == job.id;
    await _jobStorage.deleteJobById(job.id);

    if (wasActive) {
      await _shiftService.clearActiveShift();
      await _jsaStorage.clearDraft();
      await _historyService.clearCurrentLayoutSummary();
    }

    final history = await _historyService.loadHistory();
    final nextHistory = history
        .where((item) => !_sameIdentity(left: job, right: item))
        .toList();
    if (nextHistory.length != history.length) {
      await _historyService.saveHistory(nextHistory);
    }

    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Job deleted.')),
    );
  }

  Widget _activeJobCard() {
    final activeJob = _activeJob;
    if (activeJob == null) {
      return const Card(
        color: Color(0xFF17130E),
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Active Job',
                style: TextStyle(
                  color: Color(0xFFCDA56A),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'No active job selected',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: const Color(0xFF17130E),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Active Job',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              activeJob.company.trim().isEmpty
                  ? 'Job in progress'
                  : activeJob.company.trim(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              activeJob.padName.trim().isEmpty ? '-' : activeJob.padName.trim(),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _wellsLabel(activeJob),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Job Actions',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    _openJobSetup(startFresh: true, editActive: false),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Create New Job'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _activeJob == null
                    ? null
                    : () => _openJobSetup(startFresh: false, editActive: true),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Active Job'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _changeActiveJob,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Change Active Job'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    _activeJob == null ? null : () => _archiveJob(_activeJob!),
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archive Job'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    _activeJob == null ? null : () => _deleteJob(_activeJob!),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete Job'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobsListCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Existing Jobs',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            if (_jobs.isEmpty)
              const Text('No jobs saved yet.',
                  style: TextStyle(color: Colors.white70)),
            if (_jobs.isNotEmpty)
              for (final job in _jobs)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  color: const Color(0xFF17130E),
                  child: ListTile(
                    title: Text(job.company.trim().isEmpty
                        ? 'Job ${job.id}'
                        : job.company.trim()),
                    subtitle: Text(
                        '${job.padName.trim().isEmpty ? '-' : job.padName.trim()}\n${_wellsLabel(job)}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'setActive') {
                          _jobStorage.setActiveJobById(job.id).then((_) async {
                            await _shiftService.clearActiveShift();
                            await _jsaStorage.clearDraft();
                            await _load();
                          });
                          return;
                        }
                        if (value == 'archive') {
                          _archiveJob(job);
                          return;
                        }
                        if (value == 'delete') {
                          _deleteJob(job);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'setActive',
                          child: Text('Change Active Job'),
                        ),
                        const PopupMenuItem(
                          value: 'archive',
                          child: Text('Archive Job'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete Job'),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
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
        appBar: AppHeader(title: 'Job Management', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Job Management', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _activeJobCard(),
          const SizedBox(height: 10),
          _actionsCard(),
          const SizedBox(height: 10),
          _jobsListCard(),
        ],
      ),
    );
  }
}
