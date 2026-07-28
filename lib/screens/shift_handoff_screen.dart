import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../services/active_workflow_mode_service.dart';
import '../services/drillout_handoff_service.dart';
import '../services/shift_handoff_history_service.dart';
import '../services/job_storage_service.dart';
import '../services/production_shift_service.dart';
import '../services/shift_handoff_service.dart';
import '../services/wellwerks_package_router_service.dart';
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
  final _drilloutHandoffService = DrilloutHandoffService();
  final _historyService = ShiftHandoffHistoryService();
  final _packageRouter = const WellWerksPackageRouterService();
  final _workflowModeService = ActiveWorkflowModeService.instance;

  ProductionShift _shift = ProductionShift.empty();
  JobSetup? _activeJob;
  List<ShiftHandoffHistoryEntry> _history = const [];
  ActiveWorkflowMode _workflowMode = ActiveWorkflowMode.production;
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
    final workflowMode = await _workflowModeService.ensureLoaded();
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
      _workflowMode = workflowMode;
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

  bool get _isProductionWorkflow {
    return _workflowMode == ActiveWorkflowMode.production;
  }

  Future<void> _shareFileWithChecks({
    required String encoded,
    required String base,
    required String subject,
    required String text,
  }) async {
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${directory.path}/${base}_$timestamp.wellwerks');
    await file.writeAsString(encoded);

    final exists = await file.exists();
    final size = exists ? await file.length() : 0;
    if (!exists || size <= 0) {
      throw const FormatException('Could not prepare handoff file to share.');
    }

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: subject,
      text: text,
    );
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
      final pad = (_activeJob?.padName ?? _shift.header.pad)
          .trim()
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final base = pad.isEmpty ? 'job' : pad;
      await _shareFileWithChecks(
        encoded: encoded,
        base: '${base}_production_handoff',
        subject: 'WellWerks Production Handoff',
        text: 'Production handoff package for import into WellWerks.',
      );
      await _historyService.appendEntry(
        ShiftHandoffHistoryEntry(
          action: 'production_export',
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
        const SnackBar(content: Text('Production handoff shared.')),
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

      final length = await picked.length();
      if (length <= 0) {
        throw const FormatException('Selected file is empty.');
      }

      final raw = await picked.readAsString();
      final header = _packageRouter.decodeHeader(raw);
      if (header.type != WellWerksPackageType.productionHandoff) {
        throw const FormatException(
          'This file is not a Production Handoff package.',
        );
      }
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
          action: 'production_import',
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

  Future<void> _exportDrilloutHandoff() async {
    final activeJob = _activeJob;
    if (activeJob == null || _busy) return;
    setState(() => _busy = true);
    try {
      final package = await _drilloutHandoffService.buildPackage(
        activeJob: activeJob,
      );
      final encoded = _drilloutHandoffService.encodePackage(package);
      final pad =
          activeJob.padName.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final base = pad.isEmpty ? 'job' : pad;

      await _shareFileWithChecks(
        encoded: encoded,
        base: '${base}_drillout_handoff',
        subject: 'WellWerks Drillout Handoff',
        text: 'Drillout handoff package for import into WellWerks.',
      );

      await _historyService.appendEntry(
        ShiftHandoffHistoryEntry(
          action: 'drillout_export',
          timestampIso: DateTime.now().toIso8601String(),
          handoffId: package.handoffId,
          sourceJobId: package.sourceJobId,
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
        const SnackBar(content: Text('Drillout handoff shared.')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to export drillout handoff.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importDrilloutHandoff() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'WellWerks Drillout Handoff',
            extensions: <String>['wellwerks', 'json'],
          ),
        ],
      );
      if (picked == null) return;

      final length = await picked.length();
      if (length <= 0) {
        throw const FormatException('Selected file is empty.');
      }

      final raw = await picked.readAsString();
      final header = _packageRouter.decodeHeader(raw);
      if (header.type != WellWerksPackageType.drilloutHandoff) {
        throw const FormatException(
          'This file is not a Drillout Handoff package.',
        );
      }

      final package = _drilloutHandoffService.decodePackage(raw);
      final importedJob = _drilloutHandoffService.importAsActiveJob(package);
      final savedJob = await _jobStorage.saveActiveJob(importedJob);
      await _workflowModeService.setMode(_workflowModeForJob(savedJob));

      await _historyService.appendEntry(
        ShiftHandoffHistoryEntry(
          action: 'drillout_import',
          timestampIso: DateTime.now().toIso8601String(),
          handoffId: package.handoffId,
          sourceJobId: package.sourceJobId,
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
        _workflowMode = _workflowModeForJob(savedJob);
        _history = history;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported Drillout handoff for ${savedJob.padName.isEmpty ? savedJob.company : savedJob.padName}.',
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
        const SnackBar(content: Text('Failed to import drillout handoff.')),
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
            Text(
              _isProductionWorkflow
                  ? 'Production Handoff Package'
                  : 'Drillout Handoff Package',
              style: const TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text('Company: ${company.isEmpty ? '-' : company}'),
            Text('Pad/Job: ${pad.isEmpty ? '-' : pad}'),
            Text('Job ID: ${activeJobId.isEmpty ? '-' : activeJobId}'),
            Text(
              _isProductionWorkflow
                  ? 'Saved Entries: ${_rows.length}'
                  : 'Shared Wells: ${_activeJob?.resolvedWellNames.length ?? 0}',
            ),
            const SizedBox(height: 8),
            Text(
              _isProductionWorkflow
                  ? 'Export creates a .wellwerks file. Import merges by entryId and lets you choose local or imported values for conflicts.'
                  : 'Export creates a .wellwerks file containing drillout/cleanout active job context and text update setup.',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  String _historyTitle(ShiftHandoffHistoryEntry entry) {
    switch (entry.action) {
      case 'production_export':
        return 'Production Export';
      case 'production_import':
        return 'Production Import';
      case 'drillout_export':
        return 'Drillout Export';
      case 'drillout_import':
        return 'Drillout Import';
      default:
        return 'Handoff';
    }
  }

  String _historySubtitle(ShiftHandoffHistoryEntry entry) {
    if (entry.action == 'production_export') {
      return 'Rows in shift package: ${entry.entriesAdded}';
    }
    if (entry.action == 'drillout_export' ||
        entry.action == 'drillout_import') {
      return 'Shared wells: ${entry.entriesAdded}';
    }
    return 'Added ${entry.entriesAdded}, Duplicates ${entry.duplicatesSkipped}, Conflicts ${entry.conflictCount}, Imported choices ${entry.importedConflictChoices}';
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
        appBar: AppHeader(title: 'Handoff', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppHeader(
        title:
            _isProductionWorkflow ? 'Production Handoff' : 'Drillout Handoff',
        showBack: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _summaryCard(),
          const SizedBox(height: 8),
          _historyCard(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy
                  ? null
                  : (_isProductionWorkflow
                      ? (_rows.isEmpty ? null : _exportHandoff)
                      : (_activeJob == null ? null : _exportDrilloutHandoff)),
              icon: const Icon(Icons.ios_share),
              label: Text(
                _isProductionWorkflow
                    ? 'Create & Share Production Handoff'
                    : 'Create & Share Drillout Handoff',
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : (_isProductionWorkflow
                      ? _importHandoff
                      : _importDrilloutHandoff),
              icon: const Icon(Icons.file_open_outlined),
              label: Text(
                _isProductionWorkflow
                    ? 'Import Production Handoff'
                    : 'Import Drillout Handoff',
              ),
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
