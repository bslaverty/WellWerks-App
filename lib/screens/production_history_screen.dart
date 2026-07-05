import 'package:flutter/material.dart';

import '../models/job_history.dart';
import '../models/job_setup.dart';
import '../services/job_history_service.dart';
import '../services/job_storage_service.dart';
import '../widgets/app_header.dart';

class ProductionHistoryScreen extends StatefulWidget {
  const ProductionHistoryScreen({super.key});

  @override
  State<ProductionHistoryScreen> createState() =>
      _ProductionHistoryScreenState();
}

class _ProductionHistoryScreenState extends State<ProductionHistoryScreen> {
  final _historyService = JobHistoryService();
  final _jobStorage = JobStorageService();

  List<_HistoryJobCardData> _jobs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final activeJob = await _jobStorage.loadActiveJob();
    final lastEndedJob = await _jobStorage.loadLastEndedJob();
    final history = await _historyService.loadHistory();
    final jobs = _buildJobs(
      activeJob: activeJob,
      lastEndedJob: lastEndedJob,
      archivedJobs: history,
    );
    if (!mounted) return;
    setState(() {
      _jobs = jobs;
      _loading = false;
    });
  }

  List<_HistoryJobCardData> _buildJobs({
    required JobSetup? activeJob,
    required JobSetup? lastEndedJob,
    required List<ArchivedJob> archivedJobs,
  }) {
    final jobsByKey = <String, _HistoryJobCardData>{};

    void addJob(_HistoryJobCardData job) {
      final existing = jobsByKey[job.identityKey];
      if (existing == null || job.priority > existing.priority) {
        jobsByKey[job.identityKey] = job;
      }
    }

    if (activeJob != null) {
      addJob(_HistoryJobCardData.fromActiveJob(activeJob));
    }

    if (lastEndedJob != null) {
      addJob(_HistoryJobCardData.fromEndedJob(lastEndedJob));
    }

    for (final archived in archivedJobs) {
      addJob(_HistoryJobCardData.fromArchivedJob(archived));
    }

    final jobs = jobsByKey.values.toList()
      ..sort((a, b) {
        if (a.isActive != b.isActive) {
          return a.isActive ? -1 : 1;
        }
        return b.sortAt.compareTo(a.sortAt);
      });
    return jobs;
  }

  Widget _emptyState() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Text(
          'No jobs yet. Start a job or archive a completed job to build local History.',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  Widget _jobCard(_HistoryJobCardData job) {
    final statusColor =
        job.isActive ? const Color(0xFFCDA56A) : const Color(0xFF5E646C);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: job.isActive ? const Color(0xFF17130E) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _HistoryJobDetailPlaceholderScreen(job: job),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.company.isEmpty ? 'Job' : job.company,
                          style: const TextStyle(
                            color: Color(0xFFCDA56A),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (job.customer.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Customer: ${job.customer}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: job.isActive ? statusColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      job.statusLabel,
                      style: TextStyle(
                        color: job.isActive ? Colors.black : statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _infoLine('Pad', job.pad),
              _infoLine('Well', job.well),
              _infoLine('Shift', job.shift),
              _infoLine('Date Started', job.dateStarted),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.chevron_right, color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(value.isEmpty ? '-' : value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'History', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'History', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (_jobs.isEmpty) _emptyState(),
          for (final job in _jobs) _jobCard(job),
        ],
      ),
    );
  }
}

class _HistoryJobDetailPlaceholderScreen extends StatelessWidget {
  const _HistoryJobDetailPlaceholderScreen({required this.job});

  final _HistoryJobCardData job;

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(value.isEmpty ? '-' : value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Job Detail', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Full job detail is coming in the next task. This placeholder confirms History navigation is wired.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.company.isEmpty ? 'Job' : job.company,
                    style: const TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _detailRow('Status', job.statusLabel),
                  if (job.customer.isNotEmpty)
                    _detailRow('Customer', job.customer),
                  _detailRow('Pad', job.pad),
                  _detailRow('Well', job.well),
                  _detailRow('Shift', job.shift),
                  _detailRow('Date Started', job.dateStarted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryJobCardData {
  const _HistoryJobCardData({
    required this.identityKey,
    required this.company,
    required this.customer,
    required this.pad,
    required this.well,
    required this.shift,
    required this.dateStarted,
    required this.statusLabel,
    required this.isActive,
    required this.priority,
    required this.sortAt,
  });

  final String identityKey;
  final String company;
  final String customer;
  final String pad;
  final String well;
  final String shift;
  final String dateStarted;
  final String statusLabel;
  final bool isActive;
  final int priority;
  final DateTime sortAt;

  factory _HistoryJobCardData.fromActiveJob(JobSetup job) {
    final startedAt = job.startedAt ?? DateTime.now();
    return _HistoryJobCardData(
      identityKey: _identityKeyForJob(job),
      company: job.company.trim(),
      customer: job.customer.trim(),
      pad: job.padName.trim(),
      well: job.primaryWell.trim(),
      shift: job.shift.trim(),
      dateStarted: job.dateStarted.trim(),
      statusLabel: 'Active',
      isActive: true,
      priority: 3,
      sortAt: startedAt,
    );
  }

  factory _HistoryJobCardData.fromEndedJob(JobSetup job) {
    final endedAt = job.endedAt ?? job.startedAt ?? DateTime.now();
    return _HistoryJobCardData(
      identityKey: _identityKeyForJob(job),
      company: job.company.trim(),
      customer: job.customer.trim(),
      pad: job.padName.trim(),
      well: job.primaryWell.trim(),
      shift: job.shift.trim(),
      dateStarted: job.dateStarted.trim(),
      statusLabel: 'Ended',
      isActive: false,
      priority: 2,
      sortAt: endedAt,
    );
  }

  factory _HistoryJobCardData.fromArchivedJob(ArchivedJob job) {
    final setup = job.jobSetup;
    return _HistoryJobCardData(
      identityKey: _identityKeyForArchivedJob(job),
      company: (setup?.company.trim().isNotEmpty ?? false)
          ? setup!.company.trim()
          : job.company.trim(),
      customer: setup?.customer.trim() ?? '',
      pad: (setup?.padName.trim().isNotEmpty ?? false)
          ? setup!.padName.trim()
          : job.padName.trim(),
      well: setup?.primaryWell.trim().isNotEmpty == true
          ? setup!.primaryWell.trim()
          : (job.wells.isEmpty ? '' : job.wells.first.trim()),
      shift: setup?.shift.trim() ?? '',
      dateStarted: setup?.dateStarted.trim().isNotEmpty == true
          ? setup!.dateStarted.trim()
          : job.dateRangeStart.trim(),
      statusLabel: 'Ended',
      isActive: false,
      priority: 1,
      sortAt: job.updatedAt,
    );
  }

  static String _identityKeyForJob(JobSetup job) {
    if (job.id.trim().isNotEmpty) {
      return 'job:${job.id.trim()}';
    }
    return 'fallback:${job.company.trim().toLowerCase()}|${job.padName.trim().toLowerCase()}|${job.primaryWell.trim().toLowerCase()}|${job.dateStarted.trim().toLowerCase()}';
  }

  static String _identityKeyForArchivedJob(ArchivedJob job) {
    final setup = job.jobSetup;
    if (setup != null && setup.id.trim().isNotEmpty) {
      return 'job:${setup.id.trim()}';
    }
    final well = job.wells.isEmpty ? '' : job.wells.first.trim().toLowerCase();
    return 'fallback:${job.company.trim().toLowerCase()}|${job.padName.trim().toLowerCase()}|$well|${job.dateRangeStart.trim().toLowerCase()}';
  }
}
