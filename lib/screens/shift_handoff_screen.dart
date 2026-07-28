import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../services/active_job_share_service.dart';
import '../services/active_workflow_mode_service.dart';
import '../services/shift_handoff_history_service.dart';
import '../services/job_storage_service.dart';
import '../services/production_shift_service.dart';
import '../services/shift_handoff_service.dart';
import '../widgets/app_header.dart';
import 'package:intl/intl.dart';

class ShiftHandoffScreen extends StatefulWidget {
  const ShiftHandoffScreen({super.key});

  @override
  State<ShiftHandoffScreen> createState() => _ShiftHandoffScreenState();
}

class _ShiftHandoffScreenState extends State<ShiftHandoffScreen> {
  final _shiftService = ProductionShiftService();
  final _jobStorage = JobStorageService();
  final _handoffService = ShiftHandoffService();
  final _historyService = ShiftHandoffHistoryService();
  final _jobShareService = ActiveJobShareService();
  final _workflowModeService = ActiveWorkflowModeService.instance;

  ProductionShift _shift = ProductionShift.empty();
  JobSetup? _activeJob;
  List<ShiftHandoffHistoryEntry> _history = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _jobStorage.activeJobListenable.addListener(_handleActiveJobChanged);
    _load();
  }

  @override
  void dispose() {
    _jobStorage.activeJobListenable.removeListener(_handleActiveJobChanged);
    super.dispose();
  }

  void _handleActiveJobChanged() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    var shift = await _shiftService.loadActiveShift();
    final activeJob = await _jobStorage.ensureActiveJobLoaded();
    if (activeJob != null && shift.activeJobId != activeJob.id) {
      shift = shift.copyWith(activeJobId: activeJob.id);
      await _shiftService.saveActiveShift(shift);
    }
    final history = await _historyService.loadHistory();
    if (!mounted) return;
    setState(() {
      _shift = shift;
      _activeJob = activeJob;
      _history = history;
      _loading = false;
    });
  }

  List<ProductionReportRow> get _rows {
    if (_shift.inventory.productionRows.isNotEmpty) {
      return _shift.inventory.productionRows;
    }
    return _shift.savedRows;
  }

  ActiveWorkflowMode _workflowModeForJob(JobSetup job) {
    final workflow = job.workflow.trim().toLowerCase();
    if (workflow == 'drillout') {
      return ActiveWorkflowMode.drillout;
    }
    if (workflow == 'cleanout') {
      return ActiveWorkflowMode.cleanout;
    }
    return ActiveWorkflowMode.production;
  }

  Future<void> _exportActiveJobInfo() async {
    final activeJob = _activeJob;
    if (activeJob == null || _busy) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active job to share yet.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final package = await _jobShareService.buildPackage(activeJob: activeJob);
      final encoded = _jobShareService.encodePackage(package);
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final pad =
          activeJob.padName.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final base = pad.isEmpty ? 'active_job' : pad;
      final file = File('${directory.path}/${base}_$timestamp.wwjob');
      await file.writeAsString(encoded);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'WellWerks Active Job',
        text: 'Active job package for WellWerks import.',
      );

      await _historyService.appendEntry(
        ShiftHandoffHistoryEntry(
          action: 'job_export',
          timestampIso: DateTime.now().toIso8601String(),
          handoffId: activeJob.id,
          sourceJobId: activeJob.id,
          entriesAdded: activeJob.resolvedWellNames.length,
          duplicatesSkipped: 0,
          conflictCount: 0,
          importedConflictChoices: 0,
        ),
      );

      if (!mounted) return;
      final history = await _historyService.loadHistory();
      if (!mounted) return;
      setState(() => _history = history);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Active job shared: ${file.path}')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to share active job.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importActiveJobInfo() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'WellWerks Active Job',
            extensions: <String>['wwjob', 'json'],
          ),
        ],
      );
      if (picked == null) return;

      final raw = await picked.readAsString();
      final package = _jobShareService.decodePackage(raw);
      final importedJob = JobSetup.fromJson(package.jobData);
      final normalizedImport = importedJob.copyWith(
        workflow: importedJob.workflow.trim().isEmpty
            ? package.workflow
            : importedJob.workflow,
        status: 'active',
        endedAt: null,
        startedAt: importedJob.startedAt ?? DateTime.now(),
      );
      final savedJob = await _jobStorage.saveActiveJob(normalizedImport);
      await _workflowModeService.setMode(_workflowModeForJob(savedJob));

      final updatedShift = _shift.copyWith(activeJobId: savedJob.id);
      await _shiftService.saveActiveShift(updatedShift);

      await _historyService.appendEntry(
        ShiftHandoffHistoryEntry(
          action: 'job_import',
          timestampIso: DateTime.now().toIso8601String(),
          handoffId: package.sourceJobId,
          sourceJobId: savedJob.id,
          entriesAdded: savedJob.resolvedWellNames.length,
          duplicatesSkipped: 0,
          conflictCount: 0,
          importedConflictChoices: 0,
        ),
      );

      if (!mounted) return;
      final history = await _historyService.loadHistory();
      if (!mounted) return;
      setState(() {
        _activeJob = savedJob;
        _shift = updatedShift;
        _history = history;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported active job: ${savedJob.padName.isEmpty ? savedJob.company : savedJob.padName} (${savedJob.workflow})',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to import active job file.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _conflictValueSummary(ProductionReportRow row) {
    return 'Oil ${row.oilProduction.toStringAsFixed(1)} | Water ${row.waterProduction.toStringAsFixed(1)} | Gas ${row.hourlyGas.toStringAsFixed(1)}';
  }

  Future<Set<String>?> _chooseConflictResolutions(
    List<ShiftHandoffConflict> conflicts,
  ) async {
    if (conflicts.isEmpty) return const <String>{};
    final selectedImported = <String>{};

    final chosen = await showDialog<Set<String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setInnerState) {
            return AlertDialog(
              title: Text('Resolve ${conflicts.length} Conflict(s)'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose which entries should use imported values. Unselected conflicts keep local values.',
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () {
                              setInnerState(() {
                                selectedImported
                                  ..clear()
                                  ..addAll(conflicts
                                      .map((item) => item.entryId)
                                      .where((id) => id.trim().isNotEmpty));
                              });
                            },
                            child: const Text('Select All Imported'),
                          ),
                          TextButton(
                            onPressed: () {
                              setInnerState(selectedImported.clear);
                            },
                            child: const Text('Keep All Local'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: conflicts.length,
                        itemBuilder: (context, index) {
                          final conflict = conflicts[index];
                          final id = conflict.entryId.trim();
                          final selected = selectedImported.contains(id);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${conflict.local.time} • ${conflict.local.well}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Local: ${_conflictValueSummary(conflict.local)}',
                                    style:
                                        const TextStyle(color: Colors.white70),
                                  ),
                                  Text(
                                    'Imported: ${_conflictValueSummary(conflict.imported)}',
                                    style:
                                        const TextStyle(color: Colors.white70),
                                  ),
                                  if (conflict.local.notes.trim().isNotEmpty ||
                                      conflict.imported.notes.trim().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Notes L/I: ${conflict.local.notes.isEmpty ? '-' : conflict.local.notes} / ${conflict.imported.notes.isEmpty ? '-' : conflict.imported.notes}',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Use imported entry'),
                                    value: selected,
                                    onChanged: (_) {
                                      setInnerState(() {
                                        if (selected) {
                                          selectedImported.remove(id);
                                        } else {
                                          selectedImported.add(id);
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel Import'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context)
                      .pop(Set<String>.from(selectedImported)),
                  child: const Text('Apply Resolutions'),
                ),
              ],
            );
          },
        );
      },
    );

    return chosen;
  }

  Future<void> _exportHandoff() async {
    if (_rows.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final package = await _handoffService.buildPackage(
        shift: _shift,
        activeJob: _activeJob,
      );
      final encoded = _handoffService.encodePackage(package);
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final pad = (_activeJob?.padName ?? _shift.header.pad)
          .trim()
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final base = pad.isEmpty ? 'job' : pad;
      final file = File('${directory.path}/${base}_$timestamp.wellwerks');
      await file.writeAsString(encoded);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'WellWerks Shift Handoff',
        text: 'Shift handoff package for import into WellWerks.',
      );
      await _historyService.appendEntry(
        ShiftHandoffHistoryEntry(
          action: 'export',
          timestampIso: DateTime.now().toIso8601String(),
          handoffId: package.handoffId,
          sourceJobId: package.sourceJobId,
          entriesAdded: package.productionRows.length,
          duplicatesSkipped: 0,
          conflictCount: 0,
          importedConflictChoices: 0,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Shift handoff exported: ${file.path}')),
      );
      final history = await _historyService.loadHistory();
      if (!mounted) return;
      setState(() {
        _history = history;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to export shift handoff.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmMismatchedJob(String sourceJobId) async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Continue Handoff Job'),
        content: Text(
          'This handoff belongs to job id $sourceJobId. Import will switch/create that active job and continue there instead of merging into your current job.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue Handoff'),
          ),
        ],
      ),
    );
    return decision == true;
  }

  String _nextShiftLabel(String current) {
    final normalized = current.trim().toLowerCase();
    if (normalized == 'day') return 'Night';
    if (normalized == 'night') return 'Day';
    return 'Night';
  }

  Future<(JobSetup, ProductionShift)> _activateHandoffJobContext(
    ShiftHandoffPackage package,
  ) async {
    final importedShift = ProductionShift.fromJson(package.productionShift);
    final sourceJobId = package.sourceJobId.trim();

    JobSetup? targetJob;
    if (sourceJobId.isNotEmpty) {
      targetJob = await _jobStorage.loadJobById(sourceJobId);
      if (targetJob != null) {
        await _jobStorage.setActiveJobById(sourceJobId);
        targetJob = await _jobStorage.ensureActiveJobLoaded();
      }
    }

    if (targetJob == null) {
      final wells = importedShift.header.wells;
      final wellIds = importedShift.header.wellIds;
      final wellEntries = <JobSetupWell>[];
      for (var i = 0; i < wells.length; i++) {
        final name = wells[i].trim();
        if (name.isEmpty) continue;
        final id = i < wellIds.length && wellIds[i].trim().isNotEmpty
            ? wellIds[i].trim()
            : JobSetup.legacyWellId(name, i);
        wellEntries.add(JobSetupWell(id: id, name: name));
      }

      final nextShift = _nextShiftLabel(_activeJob?.shift ?? 'Day');
      final created = await _jobStorage.saveActiveJob(
        JobSetup(
          id: sourceJobId,
          workflow: 'production',
          company: package.customer.trim().isEmpty
              ? importedShift.header.company
              : package.customer,
          customer: package.customer,
          padName: package.jobName.trim().isEmpty
              ? importedShift.header.pad
              : package.jobName,
          shift: nextShift,
          wells: wellEntries.map((item) => item.name).toList(growable: false),
          wellEntries: wellEntries,
          dateStarted: DateFormat('MM/dd/yyyy').format(DateTime.now()),
        ),
      );
      targetJob = created;
    }

    final shifted = importedShift.copyWith(
      activeJobId: targetJob.id,
    );

    return (targetJob, shifted);
  }

  Future<void> _importHandoff() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'WellWerks Shift Handoff',
            extensions: <String>['wellwerks', 'json'],
          ),
        ],
      );
      if (picked == null) return;

      final raw = await picked.readAsString();
      final package = _handoffService.decodePackage(raw);

      final localJobId = (_activeJob?.id ?? _shift.activeJobId).trim();
      final sourceJobId = package.sourceJobId.trim();
      final jobMismatch = sourceJobId.isNotEmpty && sourceJobId != localJobId;

      JobSetup? importJob = _activeJob;
      ProductionShift importShift = _shift;
      if (jobMismatch) {
        final proceed = await _confirmMismatchedJob(sourceJobId);
        if (!proceed) return;
        final context = await _activateHandoffJobContext(package);
        importJob = context.$1;
        importShift = context.$2;
      }

      var merged = _handoffService.mergePackage(
        localShift: importShift,
        activeJob: importJob,
        package: package,
      );

      if (merged.jobIdMismatch) {
        final proceed = await _confirmMismatchedJob(sourceJobId);
        if (!proceed) return;
        final context = await _activateHandoffJobContext(package);
        importJob = context.$1;
        importShift = context.$2;
        merged = _handoffService.mergePackage(
          localShift: importShift,
          activeJob: importJob,
          package: package,
          allowJobIdMismatch: false,
        );
      }

      ProductionShift finalShift = merged.mergedShift;
      var importedConflictChoices = 0;
      if (merged.conflicts.isNotEmpty) {
        final selectedImportedIds =
            await _chooseConflictResolutions(merged.conflicts);
        if (selectedImportedIds == null) return;
        importedConflictChoices = selectedImportedIds.length;
        finalShift = _handoffService.applyConflictResolutions(
          mergeResult: merged,
          preferImportedEntryIds: selectedImportedIds,
        );
      }

      await _shiftService.saveActiveShift(finalShift);
      await _historyService.appendEntry(
        ShiftHandoffHistoryEntry(
          action: 'import',
          timestampIso: DateTime.now().toIso8601String(),
          handoffId: package.handoffId,
          sourceJobId: package.sourceJobId,
          entriesAdded: merged.entriesAdded,
          duplicatesSkipped: merged.duplicatesSkipped,
          conflictCount: merged.conflicts.length,
          importedConflictChoices: importedConflictChoices,
        ),
      );
      if (!mounted) return;
      final history = await _historyService.loadHistory();
      if (!mounted) return;
      setState(() {
        _shift = finalShift;
        _activeJob = importJob;
        _history = history;
      });

      final conflictCount = merged.conflicts.length;
      final details = conflictCount == 0
          ? ''
          : '\nConflicts: $conflictCount (imported chosen: $importedConflictChoices, local kept: ${conflictCount - importedConflictChoices})';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${merged.entriesAdded} new entries, skipped ${merged.duplicatesSkipped} duplicates.$details',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to import shift handoff file.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _summaryCard() {
    final company = (_activeJob?.company ?? _shift.header.company).trim();
    final pad = (_activeJob?.padName ?? _shift.header.pad).trim();
    final activeJobId = (_activeJob?.id ?? _shift.activeJobId).trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Handoff Package',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text('Company: ${company.isEmpty ? '-' : company}'),
            Text('Pad/Job: ${pad.isEmpty ? '-' : pad}'),
            Text('Job ID: ${activeJobId.isEmpty ? '-' : activeJobId}'),
            Text('Saved Entries: ${_rows.length}'),
            const SizedBox(height: 8),
            const Text(
              'Export creates a .wellwerks file. Import merges by entryId and lets you choose local or imported values for conflicts.',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  String _historyTitle(ShiftHandoffHistoryEntry entry) {
    switch (entry.action) {
      case 'export':
        return 'Shift Export';
      case 'import':
        return 'Shift Import';
      case 'job_export':
        return 'Job Export';
      case 'job_import':
        return 'Job Import';
      default:
        return 'Handoff';
    }
  }

  String _historySubtitle(ShiftHandoffHistoryEntry entry) {
    if (entry.action == 'export') {
      return 'Rows in shift package: ${entry.entriesAdded}';
    }
    if (entry.action == 'job_export' || entry.action == 'job_import') {
      return 'Shared wells: ${entry.entriesAdded}';
    }
    return 'Added ${entry.entriesAdded}, Duplicates ${entry.duplicatesSkipped}, Conflicts ${entry.conflictCount}, Imported choices ${entry.importedConflictChoices}';
  }

  Widget _activeJobShareCard() {
    final workflow = (_activeJob?.workflow ?? 'production').trim();
    final label = workflow.isEmpty ? 'production' : workflow;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Active Job Share (All Workflows)',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text('Current workflow: $label'),
            const SizedBox(height: 8),
            const Text(
              'Share/import full active job setup including drillout configuration, wells, and workflow mode.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _exportActiveJobInfo,
                icon: const Icon(Icons.group_add),
                label: const Text('Share Active Job File'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _importActiveJobInfo,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Import Active Job File'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyCard() {
    if (_history.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Handoff History',
                style: TextStyle(
                  color: Color(0xFFCDA56A),
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'No handoff history yet.',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    final visible = _history.take(8).toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Handoff History',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final entry in visible)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${_historyTitle(entry)} • ${entry.handoffId.isEmpty ? '-' : entry.handoffId}',
                ),
                subtitle: Text(
                  '${DateFormat('MMM d, h:mm a').format(DateTime.tryParse(entry.timestampIso)?.toLocal() ?? DateTime.now())}\n${_historySubtitle(entry)}\nJob: ${entry.sourceJobId.isEmpty ? '-' : entry.sourceJobId}',
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
        appBar: AppHeader(title: 'Shift Handoff', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Shift Handoff', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _activeJobShareCard(),
          const SizedBox(height: 8),
          _summaryCard(),
          const SizedBox(height: 8),
          _historyCard(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _rows.isEmpty || _busy ? null : _exportHandoff,
              icon: const Icon(Icons.ios_share),
              label: const Text('Create & Share Handoff File'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _importHandoff,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import Handoff File'),
            ),
          ),
          const SizedBox(height: 8),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
