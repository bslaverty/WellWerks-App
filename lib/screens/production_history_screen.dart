import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/job_box_inventory.dart';
import '../models/job_history.dart';
import '../models/job_setup.dart';
import '../models/jsa_draft.dart';
import '../models/production_shift.dart';
import '../services/export_service.dart';
import '../services/job_history_service.dart';
import '../services/job_box_inventory_service.dart';
import '../services/job_storage_service.dart';
import '../services/job_serializer.dart';
import '../services/jsa_export_service.dart';
import '../services/jsa_storage_service.dart';
import '../services/production_shift_service.dart';
import '../services/recovery_state_service.dart';
import '../widgets/app_header.dart';
import 'job_box_inventory_screen.dart';
import 'jsa_screen.dart';
import 'pressure_entry_screen.dart';

class ProductionHistoryScreen extends StatefulWidget {
  const ProductionHistoryScreen({super.key});

  @override
  State<ProductionHistoryScreen> createState() =>
      _ProductionHistoryScreenState();
}

enum _HistoryStatusFilter { all, active, ended }

enum _HistorySortOrder { newestFirst, oldestFirst }

enum _HistoryContentFilter { all, jobs, jsa }

enum _HistoryJobAction { duplicate, delete, resume }

class _ProductionHistoryScreenState extends State<ProductionHistoryScreen> {
  final _historyService = JobHistoryService();
  final _jobBoxInventoryService = JobBoxInventoryService();
  final _jobStorage = JobStorageService();
  final _shiftService = ProductionShiftService();
  final _jsaStorage = JsaStorageService();
  final _jsaExportService = const JsaExportService();
  final _recoveryState = RecoveryStateService();

  final _companySearch = TextEditingController();
  final _customerSearch = TextEditingController();
  final _padSearch = TextEditingController();
  final _wellSearch = TextEditingController();

  List<_HistoryJobRecord> _jobs = const [];
  List<JsaDraft> _jsaDrafts = const [];
  List<JobBoxInventoryRecord> _jobBoxInventoryRecords = const [];
  bool _loading = true;
  bool _sharingJsa = false;
  _HistoryContentFilter _contentFilter = _HistoryContentFilter.all;
  _HistoryStatusFilter _statusFilter = _HistoryStatusFilter.all;
  _HistorySortOrder _sortOrder = _HistorySortOrder.newestFirst;

  @override
  void initState() {
    super.initState();
    _recoveryState.saveLastModule(RecoveryModules.history);
    _load();
  }

  @override
  void dispose() {
    _companySearch.dispose();
    _customerSearch.dispose();
    _padSearch.dispose();
    _wellSearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final activeJob = await _jobStorage.loadActiveJob();
    final lastEndedJob = await _jobStorage.loadLastEndedJob();
    final history = await _historyService.loadHistory();
    final jobBoxInventoryRecords =
        await _jobBoxInventoryService.loadAllRecords();
    List<JsaDraft> jsaDrafts = const [];
    try {
      jsaDrafts = await _jsaStorage.loadAllDrafts();
    } catch (_) {
      jsaDrafts = const [];
    }
    final jobs = _buildJobs(
      activeJob: activeJob,
      lastEndedJob: lastEndedJob,
      archivedJobs: history,
    );
    if (!mounted) return;
    setState(() {
      _jobs = jobs;
      _jsaDrafts = jsaDrafts;
      _jobBoxInventoryRecords = jobBoxInventoryRecords;
      _loading = false;
    });
  }

  List<_HistoryJobRecord> _buildJobs({
    required JobSetup? activeJob,
    required JobSetup? lastEndedJob,
    required List<ArchivedJob> archivedJobs,
  }) {
    final jobsByKey = <String, _HistoryJobRecord>{};

    void mergeJob(_HistoryJobRecord job) {
      final existing = jobsByKey[job.identityKey];
      jobsByKey[job.identityKey] = existing == null ? job : existing.merge(job);
    }

    if (activeJob != null) {
      mergeJob(_HistoryJobRecord.fromActiveJob(activeJob));
    }

    if (lastEndedJob != null) {
      mergeJob(_HistoryJobRecord.fromEndedJob(lastEndedJob));
    }

    for (final archived in archivedJobs) {
      mergeJob(_HistoryJobRecord.fromArchivedJob(archived));
    }

    return jobsByKey.values.toList();
  }

  List<_HistoryJobRecord> get _visibleJobs {
    final companyQuery = _companySearch.text.trim().toLowerCase();
    final customerQuery = _customerSearch.text.trim().toLowerCase();
    final padQuery = _padSearch.text.trim().toLowerCase();
    final wellQuery = _wellSearch.text.trim().toLowerCase();

    final visible = _jobs.where((job) {
      final matchesStatus = switch (_statusFilter) {
        _HistoryStatusFilter.all => true,
        _HistoryStatusFilter.active => job.isActive,
        _HistoryStatusFilter.ended => !job.isActive,
      };
      if (!matchesStatus) return false;
      return job.matchesSearch(
        company: companyQuery,
        customer: customerQuery,
        pad: padQuery,
        well: wellQuery,
      );
    }).toList();

    visible.sort((a, b) {
      final dateCompare = _sortOrder == _HistorySortOrder.newestFirst
          ? b.sortAt.compareTo(a.sortAt)
          : a.sortAt.compareTo(b.sortAt);
      if (dateCompare != 0) return dateCompare;
      if (a.isActive != b.isActive) {
        return a.isActive ? -1 : 1;
      }
      return a.companyLabel.compareTo(b.companyLabel);
    });

    return visible;
  }

  JobSetup? _linkedJobForDraft(JsaDraft draft) {
    final id = draft.activeJobId.trim();
    if (id.isEmpty) return null;
    for (final job in _jobs) {
      final setup = job.preferredJobSetup;
      if (setup != null && setup.id == id) {
        return setup;
      }
    }
    return null;
  }

  DateTime _draftSortAt(JsaDraft draft) {
    final date = draft.date.trim();
    final time = draft.time.trim();
    final stamp = '$date $time'.trim();
    return DateTime.tryParse(stamp.replaceFirst(' ', 'T')) ??
        DateTime.tryParse(date) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<JsaDraft> get _visibleJsas {
    final companyQuery = _companySearch.text.trim().toLowerCase();
    final customerQuery = _customerSearch.text.trim().toLowerCase();
    final padQuery = _padSearch.text.trim().toLowerCase();
    final wellQuery = _wellSearch.text.trim().toLowerCase();

    final visible = _jsaDrafts.where((draft) {
      final linkedJob = _linkedJobForDraft(draft);
      final company = draft.company.trim().toLowerCase();
      final customer = (linkedJob?.customer ?? '').trim().toLowerCase();
      final pad = (linkedJob?.padName ?? '').trim().toLowerCase();
      final location = draft.location.trim().toLowerCase();
      final well = draft.wellName.trim().toLowerCase();

      final matchesCompany =
          companyQuery.isEmpty || company.contains(companyQuery);
      final matchesCustomer =
          customerQuery.isEmpty || customer.contains(customerQuery);
      final matchesPad = padQuery.isEmpty ||
          pad.contains(padQuery) ||
          location.contains(padQuery);
      final matchesWell = wellQuery.isEmpty || well.contains(wellQuery);
      return matchesCompany && matchesCustomer && matchesPad && matchesWell;
    }).toList();

    visible.sort((a, b) {
      final aTime = _draftSortAt(a);
      final bTime = _draftSortAt(b);
      final dateCompare = _sortOrder == _HistorySortOrder.newestFirst
          ? bTime.compareTo(aTime)
          : aTime.compareTo(bTime);
      if (dateCompare != 0) return dateCompare;
      return a.company.compareTo(b.company);
    });

    return visible;
  }

  bool get _hasSearchOrFilter {
    return _companySearch.text.trim().isNotEmpty ||
        _customerSearch.text.trim().isNotEmpty ||
        _padSearch.text.trim().isNotEmpty ||
        _wellSearch.text.trim().isNotEmpty ||
        _statusFilter != _HistoryStatusFilter.all ||
        _contentFilter != _HistoryContentFilter.all;
  }

  Future<void> _openJsaDraft(JsaDraft draft) async {
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

  Future<void> _shareJsaDraft(JsaDraft draft) async {
    if (_sharingJsa) return;
    setState(() => _sharingJsa = true);
    try {
      final linkedJob = _linkedJobForDraft(draft);
      final exported = await _jsaExportService.exportPdf(
        draft: draft,
        activeJob: linkedJob,
      );
      await Share.shareXFiles(
        [XFile(exported.filePath, mimeType: 'application/pdf')],
        subject: 'WellWerks JSA',
        text: 'Saved JSA exported from WellWerks.',
      );
    } finally {
      if (mounted) {
        setState(() => _sharingJsa = false);
      }
    }
  }

  Future<void> _openJobBoxInventory(JobBoxInventoryRecord? record) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobBoxInventoryScreen(initialRecordId: record?.id),
      ),
    );
    await _load();
  }

  Future<void> _deleteJobBoxInventory(JobBoxInventoryRecord record) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Job Box Inventory?'),
            content: Text(
                'Delete the saved inventory record for ${record.date.isEmpty ? 'this date' : record.date}?'),
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
    await _jobBoxInventoryService.deleteRecord(record.id);
    await _load();
  }

  Future<void> _handleJobAction(
    _HistoryJobRecord job,
    _HistoryJobAction action,
  ) async {
    switch (action) {
      case _HistoryJobAction.resume:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PressureEntryScreen()),
        );
        await _load();
        return;
      case _HistoryJobAction.duplicate:
        await _duplicateJob(job);
        return;
      case _HistoryJobAction.delete:
        await _deleteJob(job);
        return;
    }
  }

  Future<void> _duplicateJob(_HistoryJobRecord job) async {
    final activeJob = await _jobStorage.loadActiveJob();
    if (!mounted) return;

    if (activeJob != null) {
      final shouldReplace = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Start New Active Job?'),
              content: const Text(
                'This will replace the current active workflow with a new job using this setup. Production data, reports, JSAs, and layouts will not be copied.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ) ??
          false;
      if (!shouldReplace) return;
    }

    await _shiftService.clearActiveShift();
    await _jsaStorage.clearDraft();
    await _historyService.clearCurrentLayoutSummary();
    await _jobStorage.duplicateJobForNewJob(job.buildDuplicateSource());

    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('New active job created from saved setup')),
    );
  }

  Future<void> _deleteJob(_HistoryJobRecord job) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Job?'),
            content: Text(
              'Delete ${job.companyLabel} ${job.well.isEmpty ? 'job' : 'for ${job.well}'} and permanently remove all associated local records?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete Job'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    final history = await _historyService.loadHistory();
    final nextHistory = history
        .where(
          (item) =>
              _HistoryJobRecord.identityKeyForArchivedJob(item) !=
              job.identityKey,
        )
        .toList();
    await _historyService.saveHistory(nextHistory);

    final activeJob = await _jobStorage.loadActiveJob();
    if (activeJob != null &&
        _HistoryJobRecord.identityKeyForJob(activeJob) == job.identityKey) {
      await _jobStorage.clearActiveJob();
      await _shiftService.clearActiveShift();
      await _jsaStorage.clearDraft();
      await _historyService.clearCurrentLayoutSummary();
    }

    final lastEndedJob = await _jobStorage.loadLastEndedJob();
    if (lastEndedJob != null &&
        _HistoryJobRecord.identityKeyForJob(lastEndedJob) == job.identityKey) {
      await _jobStorage.clearLastEndedJob();
    }

    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Job deleted from local History')),
    );
  }

  Widget _searchField({
    required TextEditingController controller,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    controller.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close),
                ),
        ),
      ),
    );
  }

  Widget _controlsCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        title: const Text(
          'Search & Filter',
          style: TextStyle(
            color: Color(0xFFCDA56A),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: const Text(
          'Tap to refine jobs and JSA records',
          style: TextStyle(color: Colors.white70),
        ),
        children: [
          _searchField(controller: _companySearch, label: 'Search Company'),
          _searchField(
            controller: _customerSearch,
            label: 'Search Customer',
          ),
          _searchField(controller: _padSearch, label: 'Search Pad'),
          _searchField(controller: _wellSearch, label: 'Search Well'),
          const SizedBox(height: 4),
          const Text(
            'Show',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _contentChip(_HistoryContentFilter.all, 'All'),
              _contentChip(_HistoryContentFilter.jobs, 'Jobs'),
              _contentChip(_HistoryContentFilter.jsa, 'JSA'),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Job Filter',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _filterChip(_HistoryStatusFilter.all, 'All Jobs'),
              _filterChip(_HistoryStatusFilter.active, 'Active Jobs'),
              _filterChip(_HistoryStatusFilter.ended, 'Ended Jobs'),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<_HistorySortOrder>(
            initialValue: _sortOrder,
            decoration: const InputDecoration(labelText: 'Sort Order'),
            items: const [
              DropdownMenuItem(
                value: _HistorySortOrder.newestFirst,
                child: Text('Newest first'),
              ),
              DropdownMenuItem(
                value: _HistorySortOrder.oldestFirst,
                child: Text('Oldest first'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _sortOrder = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _contentChip(_HistoryContentFilter value, String label) {
    final colors = Theme.of(context).colorScheme;
    final selected = _contentFilter == value;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => setState(() => _contentFilter = value),
      selectedColor: colors.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.black : Colors.white,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(color: colors.primary),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _filterChip(_HistoryStatusFilter value, String label) {
    final colors = Theme.of(context).colorScheme;
    final selected = _statusFilter == value;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => setState(() => _statusFilter = value),
      selectedColor: colors.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.black : Colors.white,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(color: colors.primary),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _emptyState() {
    final message = (_jobs.isEmpty && _jsaDrafts.isEmpty)
        ? 'No saved jobs or JSAs yet. Save activity to build local History.'
        : _hasSearchOrFilter
            ? 'No history items match the current search or filter. Adjust the fields above to see more results.'
            : 'No history items available right now.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          message,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  Widget _jobCard(_HistoryJobRecord job) {
    final colors = Theme.of(context).colorScheme;
    final borderColor = Theme.of(context).dividerColor;
    final statusColor = job.isActive ? colors.primary : borderColor;
    final companyTitle = <String?>[
      job.activeJob?.company,
      job.endedJob?.company,
      job.archivedJob?.company,
      job.archivedJob?.jobSetup?.company,
      job.companyLabel,
    ]
        .map((value) => (value ?? '').trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => 'Job');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: job.isActive ? colors.primary.withValues(alpha: 0.08) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _HistoryJobDetailScreen(job: job),
            ),
          );
          await _load();
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
                          companyTitle,
                          style: TextStyle(
                            color: colors.primary,
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
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      PopupMenuButton<_HistoryJobAction>(
                        tooltip: 'Job Actions',
                        onSelected: (action) => _handleJobAction(job, action),
                        itemBuilder: (context) {
                          final items = <PopupMenuEntry<_HistoryJobAction>>[
                            const PopupMenuItem(
                              value: _HistoryJobAction.duplicate,
                              child: Text('Duplicate Job'),
                            ),
                            const PopupMenuItem(
                              value: _HistoryJobAction.delete,
                              child: Text('Delete Job'),
                            ),
                          ];
                          if (job.isActive) {
                            items.insert(
                              0,
                              const PopupMenuItem(
                                value: _HistoryJobAction.resume,
                                child: Text('Resume Job'),
                              ),
                            );
                          }
                          return items;
                        },
                        icon: const Icon(Icons.more_vert),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color:
                              job.isActive ? statusColor : Colors.transparent,
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
                ],
              ),
              const SizedBox(height: 14),
              _infoLine('Pad', job.pad),
              _infoLine('Well', job.well),
              _infoLine('Shift', job.shift),
              _infoLine('Date Started', job.startedDisplay),
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

  Widget _jsaSectionCard(List<JsaDraft> drafts) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'JSA Records',
              style: TextStyle(
                color: colors.primary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              drafts.isEmpty
                  ? 'No saved JSAs found.'
                  : '${drafts.length} saved JSA${drafts.length == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            if (drafts.isEmpty)
              const Text(
                'Save a JSA to see it here in Home History.',
                style: TextStyle(color: Colors.white70),
              )
            else
              for (final draft in drafts) _jsaCard(draft),
          ],
        ),
      ),
    );
  }

  Widget _jobBoxInventorySectionCard(List<JobBoxInventoryRecord> records) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Job Box Inventory Records',
              style: TextStyle(
                color: colors.primary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              records.isEmpty
                  ? 'No saved Job Box Inventory records found.'
                  : '${records.length} saved Job Box Inventory record${records.length == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            if (records.isEmpty)
              const Text(
                'Open Job Box Inventory and save a record to see it here in History.',
                style: TextStyle(color: Colors.white70),
              )
            else
              for (final record in records) _jobBoxInventoryCard(record),
          ],
        ),
      ),
    );
  }

  Widget _jobBoxInventoryCard(JobBoxInventoryRecord record) {
    final colors = Theme.of(context).colorScheme;
    final borderColor = Theme.of(context).dividerColor;
    final visibleItems = record.visibleItems;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            record.date.trim().isEmpty
                ? 'Inventory Record'
                : record.date.trim(),
            style: TextStyle(
              color: colors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _infoLine('Well(s)', record.wellNames),
          _infoLine('Job Box', record.jobBoxNumber),
          _infoLine('Visible Items', '${visibleItems.length}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _openJobBoxInventory(record),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Open / Edit'),
              ),
              OutlinedButton.icon(
                onPressed: () => _deleteJobBoxInventory(record),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _jsaCard(JsaDraft draft) {
    final colors = Theme.of(context).colorScheme;
    final borderColor = Theme.of(context).dividerColor;
    final linkedJob = _linkedJobForDraft(draft);
    final customer = (linkedJob?.customer ?? '').trim();
    final company = draft.company.trim();
    final location = draft.location.trim();
    final pad = (linkedJob?.padName ?? '').trim();
    final well = draft.wellName.trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            draft.date.trim().isEmpty ? 'JSA Record' : draft.date.trim(),
            style: TextStyle(
              color: colors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _infoLine('Customer', customer),
          _infoLine('Company', company),
          _infoLine('Location', location),
          _infoLine('Job / Pad', pad),
          _infoLine('Well', well),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _openJsaDraft(draft),
                icon: const Icon(Icons.description_outlined),
                label: const Text('Open / Edit'),
              ),
              OutlinedButton.icon(
                onPressed: _sharingJsa ? null : () => _shareJsaDraft(draft),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share / Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
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
          Expanded(child: Text(value)),
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

    final visibleJobs = _visibleJobs;
    final visibleJsas = _visibleJsas;
    final visibleJobBoxInventoryRecords = _jobBoxInventoryRecords;
    final showJobs = _contentFilter == _HistoryContentFilter.all ||
        _contentFilter == _HistoryContentFilter.jobs;
    final showJsas = _contentFilter == _HistoryContentFilter.all ||
        _contentFilter == _HistoryContentFilter.jsa;
    final hasVisibleContent = (showJobs && visibleJobs.isNotEmpty) ||
        (showJsas && visibleJsas.isNotEmpty) ||
        visibleJobBoxInventoryRecords.isNotEmpty;

    return Scaffold(
      appBar: const AppHeader(title: 'History', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _controlsCard(),
          if (!hasVisibleContent) _emptyState(),
          if (showJobs) ...[
            for (final job in visibleJobs) _jobCard(job),
          ],
          if (showJsas) _jsaSectionCard(visibleJsas),
          _jobBoxInventorySectionCard(visibleJobBoxInventoryRecords),
        ],
      ),
    );
  }
}

class _HistoryJobDetailScreen extends StatefulWidget {
  const _HistoryJobDetailScreen({required this.job});

  final _HistoryJobRecord job;

  @override
  State<_HistoryJobDetailScreen> createState() =>
      _HistoryJobDetailScreenState();
}

class _HistoryJobDetailScreenState extends State<_HistoryJobDetailScreen> {
  final _exportService = ExportService();
  final _historyService = JobHistoryService();
  final _jobStorage = JobStorageService();
  final _shiftService = ProductionShiftService();
  final _jsaStorage = JsaStorageService();

  bool _exporting = false;
  bool _loading = true;
  late _HistoryJobDetailData _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    ArchivedJob? archivedJob = widget.job.archivedJob;
    if (archivedJob == null) {
      final history = await _historyService.loadHistory();
      for (final item in history) {
        if (_HistoryJobRecord.identityKeyForArchivedJob(item) ==
            widget.job.identityKey) {
          archivedJob = item;
          break;
        }
      }
    }

    JobSetup? activeJob = widget.job.activeJob;
    final liveActive = await _jobStorage.loadActiveJob();
    if (liveActive != null &&
        _HistoryJobRecord.identityKeyForJob(liveActive) ==
            widget.job.identityKey) {
      activeJob = liveActive;
    }

    final liveShift = await _shiftService.loadActiveShift();
    final includesLiveShift =
        activeJob != null && liveShift.activeJobId == activeJob.id;

    final reportText = includesLiveShift
        ? await _historyService.buildProductionReportTextForShift(liveShift)
        : '';
    final textUpdates = includesLiveShift
        ? await _historyService.buildTextUpdatesForShift(liveShift)
        : const <ArchivedTextUpdate>[];

    final jsaDraft = includesLiveShift
        ? await _jsaStorage.loadDraft(
            activeJobId: activeJob.id,
            date: liveShift.header.date.trim().isEmpty
                ? DateTime.now().toIso8601String().split('T').first
                : liveShift.header.date.trim(),
          )
        : null;
    final matchingJsa = (jsaDraft != null &&
            (jsaDraft.activeJobId.isEmpty ||
                jsaDraft.activeJobId == activeJob?.id))
        ? jsaDraft
        : null;
    final layoutSummary = includesLiveShift
        ? await _historyService.loadCurrentLayoutSummary()
        : null;

    _detail = _HistoryJobDetailData(
      job: widget.job.merge(
        _HistoryJobRecord(
          identityKey: widget.job.identityKey,
          activeJob: activeJob,
          archivedJob: archivedJob,
          endedJob: widget.job.endedJob,
        ),
      ),
      liveShift: includesLiveShift ? liveShift : null,
      liveReportText: reportText,
      liveTextUpdates: textUpdates,
      liveJsa: matchingJsa,
      liveLayout: layoutSummary,
    );

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _exportJob() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final exported = await _exportService.exportJobPackage(
        JobExportSnapshot(
          identityKey: _detail.job.identityKey,
          status: _detail.job.statusLabel,
          company: _detail.job.company,
          customer: _detail.job.customer,
          pad: _detail.job.pad,
          well: _detail.job.well,
          shift: _detail.job.shift,
          startedDisplay: _detail.job.startedDisplay,
          endedDisplay: _detail.job.endedDisplay,
          activeJob: _detail.job.activeJob,
          endedJob: _detail.job.endedJob,
          archivedJob: _detail.job.archivedJob,
          liveShift: _detail.liveShift,
          liveReportText: _detail.liveReportText,
          liveTextUpdates: _detail.liveTextUpdates,
          liveJsa: _detail.liveJsa,
          liveLayout: _detail.liveLayout,
          archivedShifts: _detail.archivedShifts,
        ),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Job Exported'),
          content: Text(
            'Saved locally as ${exported.fileName}.\n\nLocation:\n${exported.filePath}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await Share.shareXFiles(
                  [XFile(exported.filePath)],
                  text: 'WellWerks Job Package',
                );
              },
              child: const Text('Share'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Widget _headerCard() {
    final job = _detail.job;
    final statusColor =
        job.isActive ? const Color(0xFFCDA56A) : const Color(0xFF5E646C);

    return Card(
      color: job.isActive ? const Color(0xFF17130E) : null,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    job.companyLabel,
                    style: const TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: job.isActive ? statusColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    job.statusLabel,
                    style: TextStyle(
                      color: job.isActive ? Colors.black : statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _detailRow('Customer', job.customer),
            _detailRow('Pad', job.pad),
            _detailRow('Well', job.well),
            _detailRow('Shift', job.shift),
            _detailRow('Started', job.startedDisplay),
            if (job.endedDisplay.isNotEmpty)
              _detailRow('Ended', job.endedDisplay),
            _detailRow('Status', job.statusLabel),
            const SizedBox(height: 18),
            if (job.isActive) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCDA56A),
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(56),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PressureEntryScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume Job'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _exporting ? null : _exportJob,
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share),
                label: Text(_exporting ? 'Exporting...' : 'Export Job'),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
            child: Text(value.trim().isEmpty ? '-' : value.trim()),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required int count,
    required String emptyMessage,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: const Color(0xFFCDA56A),
          collapsedIconColor: const Color(0xFFCDA56A),
          title: Text(
            title,
            style: const TextStyle(
              color: Color(0xFFCDA56A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            count == 0
                ? 'No saved items'
                : '$count saved item${count == 1 ? '' : 's'}',
            style: const TextStyle(color: Colors.white70),
          ),
          children: children.isEmpty
              ? [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1D20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      emptyMessage,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ]
              : children,
        ),
      ),
    );
  }

  Widget _itemCard({
    required String title,
    String? subtitle,
    List<Widget> details = const [],
    Widget? footer,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2E33)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...details,
          ],
          if (footer != null) ...[
            const SizedBox(height: 10),
            footer,
          ],
        ],
      ),
    );
  }

  Widget _labelValue(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white, height: 1.35),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: value.trim().isEmpty ? '-' : value.trim()),
          ],
        ),
      ),
    );
  }

  List<Widget> _quickRoundItems() {
    final items = <Widget>[];
    if (_detail.liveShift != null) {
      final liveShift = _detail.liveShift!;
      items.add(
        _itemCard(
          title: 'Current Active Shift',
          subtitle: _formatDateTime(liveShift.updatedAt) == '-'
              ? null
              : 'Last updated ${_formatDateTime(liveShift.updatedAt)}',
          details: [
            _labelValue(
              'Date',
              _detail.job.startedDateLabel(liveShift.header.date),
            ),
            _labelValue('Checks Saved', '${liveShift.hourlyChecks.length}'),
            _labelValue('Saved Report Rows', '${liveShift.savedRows.length}'),
            _labelValue('Wells', _joinWells(liveShift.header.wells)),
          ],
        ),
      );
    }
    for (final shift in _detail.archivedShifts) {
      items.add(
        _itemCard(
          title:
              shift.date.trim().isEmpty ? 'Archived Shift' : shift.date.trim(),
          subtitle: 'Archived ${_formatDateTime(shift.archivedAt)}',
          details: [
            _labelValue(
              'Checks Saved',
              '${shift.productionShift.hourlyChecks.length}',
            ),
            _labelValue(
              'Saved Report Rows',
              '${shift.productionShift.savedRows.length}',
            ),
            _labelValue(
              'Wells',
              _joinWells(shift.productionShift.header.wells),
            ),
          ],
        ),
      );
    }
    return items;
  }

  List<Widget> _productionReportItems() {
    final items = <Widget>[];
    if (_detail.liveShift != null && _detail.liveReportText.trim().isNotEmpty) {
      items.add(
        _itemCard(
          title: 'Current Active Shift Report',
          subtitle: _detail.liveShift!.savedRows.isEmpty
              ? 'No saved report rows yet'
              : '${_detail.liveShift!.savedRows.length} saved row${_detail.liveShift!.savedRows.length == 1 ? '' : 's'}',
          footer: SelectableText(
            _detail.liveReportText,
            style: const TextStyle(fontSize: 13.5, height: 1.35),
          ),
        ),
      );
    }
    for (final shift in _detail.archivedShifts) {
      items.add(
        _itemCard(
          title:
              shift.date.trim().isEmpty ? 'Archived Report' : shift.date.trim(),
          subtitle:
              '${shift.productionShift.savedRows.length} saved row${shift.productionShift.savedRows.length == 1 ? '' : 's'}',
          footer: SelectableText(
            shift.productionReportText.trim().isEmpty
                ? 'No saved Production Report rows yet. Save hours in Quick Round first.'
                : shift.productionReportText,
            style: const TextStyle(fontSize: 13.5, height: 1.35),
          ),
        ),
      );
    }
    return items;
  }

  List<Widget> _textUpdateItems() {
    final items = <Widget>[];
    for (final update in _detail.liveTextUpdates) {
      items.add(
        _itemCard(
          title:
              'Current Shift ${update.time.trim().isEmpty ? 'Text Update' : update.time.trim()}',
          subtitle: 'Hour ${update.hourIndex + 1}',
          footer: SelectableText(
            update.content.trim().isEmpty ? '-' : update.content,
            style: const TextStyle(fontSize: 13.5, height: 1.35),
          ),
        ),
      );
    }
    for (final shift in _detail.archivedShifts) {
      for (final update in shift.textUpdates) {
        items.add(
          _itemCard(
            title: shift.date.trim().isEmpty
                ? (update.time.trim().isEmpty
                    ? 'Archived Text Update'
                    : update.time.trim())
                : '${shift.date.trim()} • ${update.time.trim().isEmpty ? 'Text Update' : update.time.trim()}',
            subtitle: 'Hour ${update.hourIndex + 1}',
            footer: SelectableText(
              update.content.trim().isEmpty ? '-' : update.content,
              style: const TextStyle(fontSize: 13.5, height: 1.35),
            ),
          ),
        );
      }
    }
    return items;
  }

  List<Widget> _jsaItems() {
    final items = <Widget>[];
    if (_detail.liveJsa != null) {
      items.add(_jsaItemCard(
        title: 'Current Active JSA',
        draft: _detail.liveJsa!,
      ));
    }
    for (final shift in _detail.archivedShifts) {
      final draft = shift.jsaDraft;
      if (draft == null) continue;
      items.add(_jsaItemCard(
        title: shift.date.trim().isEmpty ? 'Archived JSA' : shift.date.trim(),
        draft: draft,
      ));
    }
    return items;
  }

  Widget _jsaItemCard({required String title, required JsaDraft draft}) {
    final tasks = draft.tasks.where((item) => item.trim().isNotEmpty).toList();
    final employees =
        draft.employees.where((item) => item.name.trim().isNotEmpty).toList();
    return _itemCard(
      title: title,
      subtitle: tasks.isEmpty ? 'No task entered' : tasks.join(', '),
      details: [
        _labelValue('Company', draft.company),
        _labelValue('Date', draft.date),
        _labelValue('Time', draft.time),
        _labelValue('Location', draft.location),
        _labelValue('Well', draft.wellName),
        _labelValue(
          'Steps',
          '${draft.steps.where((item) => item.trim().isNotEmpty).length}',
        ),
        _labelValue(
          'Hazards',
          '${draft.hazards.where((item) => item.trim().isNotEmpty).length}',
        ),
        _labelValue(
          'Recommendations',
          '${draft.recommendations.where((item) => item.trim().isNotEmpty).length}',
        ),
        _labelValue(
          'Employees',
          employees.isEmpty
              ? '-'
              : employees.map((item) => item.name.trim()).join(', '),
        ),
        if (draft.notes.trim().isNotEmpty) _labelValue('Notes', draft.notes),
      ],
    );
  }

  List<Widget> _layoutItems() {
    final items = <Widget>[];
    if (_detail.liveLayout != null) {
      items.add(_layoutItemCard(
        title: 'Current Active Layout',
        layout: _detail.liveLayout!,
      ));
    }
    final archivedLayout = _detail.archivedLayout;
    if (archivedLayout != null) {
      items.add(_layoutItemCard(
        title: 'Archived Layout',
        layout: archivedLayout,
      ));
    }
    return items;
  }

  Widget _layoutItemCard({
    required String title,
    required ArchivedLayoutSummary layout,
  }) {
    return _itemCard(
      title: title,
      subtitle:
          layout.name.trim().isEmpty ? 'Saved Layout' : layout.name.trim(),
      details: [
        _labelValue('Items', '${layout.itemCount}'),
        _labelValue(
          'Saved Data',
          layout.hasLayoutData ? 'Available' : 'Summary only',
        ),
      ],
    );
  }

  String _joinWells(List<String> wells) {
    final filtered = wells.where((item) => item.trim().isNotEmpty).toList();
    return filtered.isEmpty ? '-' : filtered.join(', ');
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('M/d/yyyy h:mm a').format(value);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Job Detail', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final quickRounds = _quickRoundItems();
    final reports = _productionReportItems();
    final textUpdates = _textUpdateItems();
    final jsas = _jsaItems();
    final layouts = _layoutItems();

    return Scaffold(
      appBar: const AppHeader(title: 'Job Detail', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _headerCard(),
          _sectionCard(
            title: 'Quick Rounds',
            count: quickRounds.length,
            emptyMessage: 'No Quick Rounds saved for this job yet.',
            children: quickRounds,
            initiallyExpanded: true,
          ),
          _sectionCard(
            title: 'Production Reports',
            count: reports.length,
            emptyMessage: 'No Production Reports saved for this job yet.',
            children: reports,
          ),
          _sectionCard(
            title: 'Text Updates',
            count: textUpdates.length,
            emptyMessage: 'No Text Updates saved for this job yet.',
            children: textUpdates,
          ),
          _sectionCard(
            title: 'JSAs',
            count: jsas.length,
            emptyMessage: 'No JSA saved for this job yet.',
            children: jsas,
          ),
          _sectionCard(
            title: 'Layout Drawings',
            count: layouts.length,
            emptyMessage: 'No Layout Drawing saved for this job yet.',
            children: layouts,
          ),
        ],
      ),
    );
  }
}

class _HistoryJobDetailData {
  const _HistoryJobDetailData({
    required this.job,
    required this.liveShift,
    required this.liveReportText,
    required this.liveTextUpdates,
    required this.liveJsa,
    required this.liveLayout,
  });

  final _HistoryJobRecord job;
  final ProductionShift? liveShift;
  final String liveReportText;
  final List<ArchivedTextUpdate> liveTextUpdates;
  final JsaDraft? liveJsa;
  final ArchivedLayoutSummary? liveLayout;

  List<ArchivedShiftEntry> get archivedShifts {
    final shifts =
        List<ArchivedShiftEntry>.from(job.archivedJob?.shifts ?? const [])
          ..sort((a, b) => b.archivedAt.compareTo(a.archivedAt));
    return shifts;
  }

  ArchivedLayoutSummary? get archivedLayout => job.archivedJob?.layoutSummary;
}

class _HistoryJobRecord {
  const _HistoryJobRecord({
    required this.identityKey,
    this.activeJob,
    this.endedJob,
    this.archivedJob,
  });

  final String identityKey;
  final JobSetup? activeJob;
  final JobSetup? endedJob;
  final ArchivedJob? archivedJob;

  _HistoryJobRecord merge(_HistoryJobRecord other) {
    return _HistoryJobRecord(
      identityKey: identityKey,
      activeJob: other.activeJob ?? activeJob,
      endedJob: other.endedJob ?? endedJob,
      archivedJob: other.archivedJob ?? archivedJob,
    );
  }

  factory _HistoryJobRecord.fromActiveJob(JobSetup job) {
    return _HistoryJobRecord(
      identityKey: identityKeyForJob(job),
      activeJob: job,
    );
  }

  factory _HistoryJobRecord.fromEndedJob(JobSetup job) {
    return _HistoryJobRecord(
      identityKey: identityKeyForJob(job),
      endedJob: job,
    );
  }

  factory _HistoryJobRecord.fromArchivedJob(ArchivedJob job) {
    return _HistoryJobRecord(
      identityKey: identityKeyForArchivedJob(job),
      archivedJob: job,
    );
  }

  JobSetup? get preferredJobSetup =>
      activeJob ?? endedJob ?? archivedJob?.jobSetup;

  String get company {
    final setup = preferredJobSetup;
    if (setup != null && setup.company.trim().isNotEmpty) {
      return setup.company.trim();
    }
    return archivedJob?.company.trim() ?? '';
  }

  String get companyLabel => company.isEmpty ? 'Job' : company;

  String get customer {
    final setup = preferredJobSetup;
    if (setup != null && setup.customer.trim().isNotEmpty) {
      return setup.customer.trim();
    }
    return '';
  }

  String get pad {
    final setup = preferredJobSetup;
    if (setup != null && setup.padName.trim().isNotEmpty) {
      return setup.padName.trim();
    }
    return archivedJob?.padName.trim() ?? '';
  }

  String get well {
    final setup = preferredJobSetup;
    if (setup != null && setup.primaryWell.trim().isNotEmpty) {
      return setup.primaryWell.trim();
    }
    final wells = archivedJob?.wells ?? const [];
    return wells.isEmpty ? '' : wells.first.trim();
  }

  String get shift => preferredJobSetup?.shift.trim() ?? '';

  bool get isActive => activeJob != null;

  String get statusLabel => isActive ? 'Active' : 'Ended';

  DateTime get sortAt {
    return activeJob?.startedAt ??
        endedJob?.endedAt ??
        endedJob?.startedAt ??
        archivedJob?.updatedAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  String get startedDisplay {
    final setup = preferredJobSetup;
    if (setup?.startedAt != null) {
      return DateFormat('M/d/yyyy h:mm a').format(setup!.startedAt!);
    }
    final text = setup?.dateStarted.trim() ?? '';
    if (text.isNotEmpty) return text;
    return archivedJob?.dateRangeStart.trim() ?? '';
  }

  String get endedDisplay {
    final endedAt = endedJob?.endedAt ?? archivedJob?.jobSetup?.endedAt;
    if (endedAt != null) {
      return DateFormat('M/d/yyyy h:mm a').format(endedAt);
    }
    if (activeJob != null) return '';
    final text = archivedJob?.dateRangeEnd.trim() ?? '';
    if (text.isNotEmpty && text != archivedJob?.dateRangeStart.trim()) {
      return text;
    }
    return '';
  }

  String startedDateLabel(String fallback) {
    if (fallback.trim().isNotEmpty) return fallback.trim();
    final setup = preferredJobSetup;
    if (setup?.dateStarted.trim().isNotEmpty == true) {
      return setup!.dateStarted.trim();
    }
    return archivedJob?.dateRangeStart.trim() ?? '';
  }

  bool matchesSearch({
    required String company,
    required String customer,
    required String pad,
    required String well,
  }) {
    final companyMatch =
        company.isEmpty || this.company.toLowerCase().contains(company);
    final customerMatch =
        customer.isEmpty || this.customer.toLowerCase().contains(customer);
    final padMatch = pad.isEmpty || this.pad.toLowerCase().contains(pad);
    final wellMatch = well.isEmpty || this.well.toLowerCase().contains(well);
    return companyMatch && customerMatch && padMatch && wellMatch;
  }

  JobSetup buildDuplicateSource() {
    final setup = preferredJobSetup;
    if (setup != null) {
      return setup.copyWith(
        id: '',
        status: 'active',
        startedAt: DateTime.now(),
        endedAt: null,
      );
    }
    return JobSetup(
      company: company.isEmpty ? 'Mach Energy' : company,
      customer: customer,
      padName: pad,
      shift: shift.isEmpty ? 'Day' : shift,
      dateStarted: '',
      wells: well.isEmpty ? const [] : [well],
    );
  }

  static String identityKeyForJob(JobSetup job) {
    if (job.id.trim().isNotEmpty) {
      return 'job:${job.id.trim()}';
    }
    return 'fallback:${job.company.trim().toLowerCase()}|${job.padName.trim().toLowerCase()}|${job.primaryWell.trim().toLowerCase()}|${job.dateStarted.trim().toLowerCase()}';
  }

  static String identityKeyForArchivedJob(ArchivedJob job) {
    final setup = job.jobSetup;
    if (setup != null && setup.id.trim().isNotEmpty) {
      return 'job:${setup.id.trim()}';
    }
    final well = job.wells.isEmpty ? '' : job.wells.first.trim().toLowerCase();
    return 'fallback:${job.company.trim().toLowerCase()}|${job.padName.trim().toLowerCase()}|$well|${job.dateRangeStart.trim().toLowerCase()}';
  }
}
