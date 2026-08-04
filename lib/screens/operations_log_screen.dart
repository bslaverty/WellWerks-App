import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/job_setup.dart';
import '../services/drillout_cleanout_field_definitions.dart';
import '../models/operations_log_entry.dart';
import '../services/operations_sts_reminder_service.dart';
import '../services/job_storage_service.dart';
import '../services/operations_log_field_config_service.dart';
import '../services/operations_log_service.dart';
import '../services/rate_timer_notification_service.dart';
import '../services/wellwerks_qr_transfer_service.dart';
import '../widgets/app_header.dart';
import '../widgets/sts_date_time_selector_sheet.dart';
import 'operations_log_entry_form_screen.dart';
import 'operations_log_sts_entry_screen.dart';
import 'wellwerks_qr_scanner_screen.dart';

class OperationsLogScreen extends StatefulWidget {
  const OperationsLogScreen({
    super.key,
    this.workflow,
    this.title = 'Operations Log',
    this.openAddStsOnLoad = false,
  });

  final OperationsLogWorkflow? workflow;
  final String title;
  final bool openAddStsOnLoad;

  @override
  State<OperationsLogScreen> createState() => _OperationsLogScreenState();
}

enum _OperationsLogViewMode {
  timeline,
  data,
  focus,
  charts,
}

enum _OperationsSmartFilter {
  all,
  manual,
  textUpdates,
  shiftChanges,
  reports,
  sts,
  rates,
  pressureChanges,
  chokeChanges,
  stageChanges,
}

enum _DataSortMode {
  newest,
  oldest,
  highest,
  lowest,
}

enum _FocusCategory {
  pump,
  pressures,
  tanks,
  gas,
  sweep,
  stage,
  choke,
  sts,
}

enum _ChartMetric {
  pumpRate,
  returnsRate,
  manifoldPsi,
  casingPsi,
  tubingPsi,
  waterRate,
  oilRate,
  gasRate,
  sweep,
  sand,
  tankLevels,
  stsPerformance,
}

enum _ReportDataSource {
  latest,
  selected,
  lastThree,
  entireShift,
}

enum _AddEntryAction {
  sts,
  manualReading,
  pumpChange,
  note,
}

class _OperationsLogScreenState extends State<OperationsLogScreen> {
  static const Color _wwGold = Color(0xFFD9A63C);
  static const Color _wwBlack = Color(0xFF0F0F0F);
  static const Color _wwPanel = Color(0xFF171717);
  static const Color _wwPanelSoft = Color(0xFF1F1F1F);

  final _jobStorage = JobStorageService();
  final _logService = OperationsLogService();
  final _fieldConfigService = OperationsLogFieldConfigService();
  final _qrTransferService = const WellWerksQrTransferService();
  final _stsReminderService = OperationsStsReminderService();
  final _notificationService = RateTimerNotificationService.instance;
  final _imagePicker = ImagePicker();

  JobSetup? _activeJob;
  List<OperationsLogEntry> _entries = const [];
  Set<String> _selectedEntryIds = <String>{};
  Set<String> _enabledFieldIds =
      DrilloutCleanoutFieldDefinitions.defaultEnabledFieldIds;
  bool _loading = true;
  bool _timelineNewestFirst = true;
  bool _multiSelectMode = false;
  _OperationsLogViewMode _viewMode = _OperationsLogViewMode.timeline;
  _OperationsSmartFilter _smartFilter = _OperationsSmartFilter.all;
  _DataSortMode _dataSortMode = _DataSortMode.newest;
  _FocusCategory _focusCategory = _FocusCategory.pump;
  _ChartMetric _chartMetric = _ChartMetric.pumpRate;
  String _dataSortField = 'pump';
  DateTime? _dateFilter;
  String _shiftFilter = 'all';
  Set<String> _expandedEntryIds = <String>{};
  String _lastFinalizedReportKey = '';
  DateTime _clockNow = DateTime.now();
  DateTime? _reportTimeOverride;
  bool _includeTankInventoryInDrilloutTextUpdate = true;
  Timer? _clockTicker;
  bool _didAutoOpenSts = false;

  @override
  void initState() {
    super.initState();
    _jobStorage.activeJobListenable.addListener(_reload);
    _clockTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() => _clockNow = DateTime.now());
    });
    _load();
  }

  @override
  void dispose() {
    _jobStorage.activeJobListenable.removeListener(_reload);
    _clockTicker?.cancel();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    final job = await _jobStorage.ensureActiveJobLoaded();
    final workflow = _resolveWorkflow(job);
    final entries = await _logService.loadEntries(
      workflow: workflow,
      jobId: job?.id ?? '',
    );
    final config = await _fieldConfigService.load(
      workflow: workflow,
      jobId: job?.id ?? '',
    );
    if (!mounted) return;
    setState(() {
      _activeJob = job;
      _entries = entries;
      _enabledFieldIds = config.enabledFieldIds;
      _selectedEntryIds = _selectedEntryIds
          .where((entryId) => entries.any((item) => item.entryId == entryId))
          .toSet();
      _expandedEntryIds = _expandedEntryIds
          .where((entryId) => entries.any((item) => item.entryId == entryId))
          .toSet();
      _loading = false;
    });

    if (widget.openAddStsOnLoad && !_didAutoOpenSts) {
      _didAutoOpenSts = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _addSts();
      });
    }
  }

  OperationsLogWorkflow _resolveWorkflow(JobSetup? job) {
    if (widget.workflow != null) return widget.workflow!;
    final activeWorkflow = (job?.workflow ?? '').trim().toLowerCase();
    if (activeWorkflow == OperationsLogWorkflow.cleanout.name) {
      return OperationsLogWorkflow.cleanout;
    }
    return OperationsLogWorkflow.drillout;
  }

  OperationsLogWorkflow get _workflow => _resolveWorkflow(_activeJob);

  String get _activeWellId {
    final job = _activeJob;
    if (job == null) return '';
    final preferred = job.activeWellId.trim();
    if (preferred.isNotEmpty) return preferred;
    final wells = job.resolvedWellEntries;
    if (wells.isEmpty) return '';
    return wells.first.id.trim();
  }

  String get _currentWellName {
    final job = _activeJob;
    if (job == null) return 'No active job';
    return job.activeWellName.isNotEmpty ? job.activeWellName : job.padName;
  }

  String get _currentStage {
    final job = _activeJob;
    if (job == null) return '';
    final setup = job.drilloutSetup;
    return (setup['status'] as String? ?? setup['stage'] as String? ?? '')
        .trim();
  }

  String get _activeStatusForCard {
    final activeWellId = _activeWellId.trim();
    for (final entry in _sortedEntries.reversed) {
      if (_entryTypeValue(entry) != 'manualReading') continue;
      if (activeWellId.isNotEmpty) {
        final entryWellId = entry.persistentWellId.trim();
        if (entryWellId.isNotEmpty && entryWellId != activeWellId) {
          continue;
        }
      }
      final stage = entry.operationStage.trim();
      if (stage.isNotEmpty) return stage;
    }
    return _currentStage;
  }

  List<OperationsLogEntry> get _sortedEntries {
    final items = List<OperationsLogEntry>.from(_entries);
    items.sort((a, b) => a.entryTime.compareTo(b.entryTime));
    return items;
  }

  List<OperationsLogEntry> get _timelineEntries {
    final items = List<OperationsLogEntry>.from(_visibleEntries);
    items.sort((a, b) => a.entryTime.compareTo(b.entryTime));
    if (_timelineNewestFirst) {
      return items.reversed.toList(growable: false);
    }
    return items;
  }

  List<OperationsLogEntry> get _visibleEntries {
    final activeWellId = _activeWellId;
    return _sortedEntries.where((entry) {
      if (!_matchesFilter(entry)) return false;
      if (activeWellId.isEmpty) return true;
      final entryWellId = entry.persistentWellId.trim();
      if (entryWellId.isEmpty) return true;
      return entryWellId == activeWellId;
    }).toList(growable: false);
  }

  String _entryTypeValue(OperationsLogEntry entry) {
    final raw = entry.entryType.trim();
    if (raw.isNotEmpty) return raw;
    if (entry.isImported) return 'qrImport';
    return 'manualReading';
  }

  String _entryTypeLabel(OperationsLogEntry entry) {
    switch (_entryTypeValue(entry)) {
      case 'pumpChange':
        return 'Pump Change';
      case 'note':
        return 'Note';
      case 'textUpdate':
        return 'Text Update';
      case 'shiftChange':
        return 'Shift Change';
      case 'handoffImport':
        return 'Handoff Import';
      case 'qrImport':
        return 'QR Import';
      case 'jobStarted':
        return 'Job Started';
      case 'jobEnded':
        return 'Job Ended';
      case 'stageChange':
        return 'Stage Change';
      case 'stsReminder':
        return 'STS Reminder';
      case 'stsReached':
        return 'STS Reached';
      default:
        return 'Manual Reading';
    }
  }

  bool _matchesFilter(OperationsLogEntry entry) {
    final type = _entryTypeValue(entry);
    final date = _dateFilter;
    if (date != null) {
      final local = entry.entryTime.toLocal();
      if (local.year != date.year ||
          local.month != date.month ||
          local.day != date.day) {
        return false;
      }
    }

    if (_shiftFilter != 'all') {
      final shiftValue =
          (entry.structuredData['shift'] as String? ?? _activeJob?.shift ?? '')
              .trim()
              .toLowerCase();
      if (shiftValue != _shiftFilter) return false;
    }

    bool changed(String Function(OperationsLogEntry e) selector) {
      final ordered = _sortedEntries;
      final index = ordered.indexWhere((item) => item.entryId == entry.entryId);
      if (index <= 0) return false;
      final prev = selector(ordered[index - 1]).trim();
      final now = selector(entry).trim();
      return now.isNotEmpty && prev != now;
    }

    switch (_smartFilter) {
      case _OperationsSmartFilter.all:
        return true;
      case _OperationsSmartFilter.manual:
        return type == 'manualReading' ||
            type == 'pumpChange' ||
            type == 'note';
      case _OperationsSmartFilter.textUpdates:
        return type == 'textUpdate';
      case _OperationsSmartFilter.shiftChanges:
        return type == 'shiftChange';
      case _OperationsSmartFilter.reports:
        return (entry.structuredData['reportType'] as String? ?? '')
                .trim()
                .isNotEmpty ||
            type == 'report';
      case _OperationsSmartFilter.sts:
        return entry.estimatedSts != null ||
            entry.sts != null ||
            type == 'stsReached';
      case _OperationsSmartFilter.rates:
        return changed((e) => '${e.pumpRate}|${e.returnsRate}');
      case _OperationsSmartFilter.pressureChanges:
        return changed(
            (e) => '${e.pumpPressure}|${e.casingPressure}|${e.tubingPressure}');
      case _OperationsSmartFilter.chokeChanges:
        return changed((e) => e.choke);
      case _OperationsSmartFilter.stageChanges:
        return changed((e) => e.operationStage);
    }
  }

  List<JobSetupWell> get _resolvedWells {
    final job = _activeJob;
    if (job == null) return const <JobSetupWell>[];
    final entries = job.resolvedWellEntries;
    if (entries.isNotEmpty) return entries;

    final fallbackWell = _currentWellName.trim();
    if (fallbackWell.isEmpty || fallbackWell == 'No active job') {
      return const <JobSetupWell>[];
    }
    final fallbackId = job.wellIds.isNotEmpty ? job.wellIds.first : '';
    return <JobSetupWell>[JobSetupWell(id: fallbackId, name: fallbackWell)];
  }

  Future<void> _addReading() async {
    final job = _activeJob;
    if (job == null) {
      debugPrint(
        '[OperationsLog] Add Reading blocked: no active job for ${_workflow.name}.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set an active job before adding a reading.'),
        ),
      );
      return;
    }

    try {
      final savedEntry = await Navigator.of(context).push<OperationsLogEntry>(
        MaterialPageRoute(
          builder: (_) => OperationsLogEntryFormScreen(
            workflow: _workflow,
            title: widget.title,
            activeJob: job,
            defaultWells: _resolvedWells,
            initialSelectedWellId: _activeWellId,
            initialSelectedWellName: _currentWellName,
            initialStage: _currentStage,
            initialReadingTimestamp: DateTime.now(),
            stageOptions: DrilloutCleanoutFieldDefinitions.stageOptions,
            enabledFieldIds: _enabledFieldIds,
            logService: _logService,
            existingEntries: _entries,
          ),
        ),
      );
      if (savedEntry == null) return;
      await _load();
    } catch (error, stackTrace) {
      debugPrint(
        '[OperationsLog] Failed to open Add Reading form for ${_workflow.name}: $error\n$stackTrace',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open the reading form right now.'),
        ),
      );
    }
  }

  bool _isStsEntry(OperationsLogEntry entry) {
    final type = _entryTypeValue(entry);
    final recordType =
        (entry.structuredData['stsRecordType'] as String? ?? '').trim();
    return type == 'stsReached' || recordType == 'manualSts';
  }

  double? _parseNumericValue(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(trimmed);
    if (match == null) return null;
    return double.tryParse(match.group(0) ?? '');
  }

  double? _averageReturnRateForStsEntry(OperationsLogEntry entry) {
    final fromStructured = entry.structuredData['stsAverageReturnRate'];
    if (fromStructured is num) return fromStructured.toDouble();
    return _parseNumericValue(entry.returnsRate);
  }

  String _stsEarlyLateLabelFromVariance(int varianceMinutes) {
    if (varianceMinutes == 0) return 'On time';
    if (varianceMinutes > 0) return '${varianceMinutes.abs()} min Late';
    return '${varianceMinutes.abs()} min Early';
  }

  String _stsPumpRateValue(OperationsLogEntry entry) {
    final fromStructured =
        (entry.structuredData['stsPumpRate'] as String? ?? '').trim();
    if (fromStructured.isNotEmpty) return fromStructured;
    return entry.pumpRate.trim();
  }

  Future<void> _saveStsEntry({
    required OperationsLogEntry entry,
    required String pumpRate,
    required double averageReturnRate,
    required DateTime estimatedSts,
    required DateTime actualSts,
    required String notes,
  }) async {
    final job = _activeJob;
    if (job == null) return;

    final varianceMinutes = actualSts.difference(estimatedSts).inMinutes;
    final earlyLateLabel = _stsEarlyLateLabelFromVariance(varianceMinutes);

    final structured = Map<String, dynamic>.from(entry.structuredData);
    structured['stsRecordType'] = 'manualSts';
    structured['stsPumpRate'] = pumpRate.trim();
    structured['stsAverageReturnRate'] = averageReturnRate;
    structured['stsVarianceMinutes'] = varianceMinutes;
    structured['stsEarlyLateLabel'] = earlyLateLabel;

    var updated = entry.copyWith(
      entryType: 'stsReached',
      pumpRate: pumpRate.trim(),
      returnsRate: averageReturnRate.toStringAsFixed(2),
      estimatedSts: estimatedSts,
      sts: actualSts,
      notes: notes.trim(),
      structuredData: structured,
    );

    final sweepId = entry.sweepId.trim();
    if (sweepId.isNotEmpty) {
      try {
        await _stsReminderService.cancelBySweepId(sweepId);
      } catch (_) {
        // Keep save resilient when notification services are unavailable.
      }
      updated = updated.copyWith(
        estimatedStsNotificationStatus: 'actualStsRecorded',
        estimatedStsCancellationReason: 'actualStsRecorded',
      );
    }

    await _logService.upsertEntry(
      workflow: _workflow,
      jobId: job.id,
      entry: updated,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('STS saved to Operations Log.')),
      );
    }
    await _load();
  }

  Future<void> _addSts() async {
    final job = _activeJob;
    if (job == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set an active job before adding STS.')),
      );
      return;
    }

    final result =
        await Navigator.of(context).push<OperationsLogStsEntryResult>(
      MaterialPageRoute(
        builder: (_) => const OperationsLogStsEntryScreen(),
      ),
    );
    if (result == null) return;

    final latest = _sortedEntries.isEmpty ? null : _sortedEntries.last;
    final entry = await _logService.createLocalEntry(
      workflow: _workflow,
      jobId: job.id,
      wellId: latest?.persistentWellId ?? _activeWellId,
      wellName: latest?.wellName ?? _currentWellName,
      readingTimestamp: DateTime.now(),
      entryType: 'stsReached',
      generatedText: 'STS entry recorded.',
      structuredData: const <String, dynamic>{'stsRecordType': 'manualSts'},
      operationStage: latest?.operationStage ?? _currentStage,
      notes: result.notes,
    );

    await _saveStsEntry(
      entry: entry,
      pumpRate: result.pumpRate,
      averageReturnRate: result.averageReturnRate,
      estimatedSts: result.estimatedSts,
      actualSts: result.actualSts,
      notes: result.notes,
    );
  }

  Future<void> _openAddEntryMenu() async {
    final choice = await showModalBottomSheet<_AddEntryAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Add Entry',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('Save directly to the Operations Log timeline.'),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('STS'),
              subtitle: const Text('Record estimated and actual STS data.'),
              onTap: () => Navigator.of(sheetContext).pop(_AddEntryAction.sts),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Manual Reading'),
              subtitle: const Text('Open full reading form for shift values.'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_AddEntryAction.manualReading),
            ),
            ListTile(
              leading: const Icon(Icons.speed_outlined),
              title: const Text('Pump Change'),
              subtitle: const Text('Log a pump-rate change quickly.'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_AddEntryAction.pumpChange),
            ),
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: const Text('Note'),
              subtitle: const Text('Add an operational note to the timeline.'),
              onTap: () => Navigator.of(sheetContext).pop(_AddEntryAction.note),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;
    switch (choice) {
      case _AddEntryAction.sts:
        await _addSts();
        break;
      case _AddEntryAction.manualReading:
        await _addReading();
        break;
      case _AddEntryAction.pumpChange:
        await _addPumpChangeEntry();
        break;
      case _AddEntryAction.note:
        await _addNoteEntry();
        break;
    }
  }

  Future<void> _addPumpChangeEntry() async {
    final job = _activeJob;
    if (job == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set an active job before logging a pump change.'),
        ),
      );
      return;
    }

    final latest = _sortedEntries.isEmpty ? null : _sortedEntries.last;
    final pumpController = TextEditingController(text: latest?.pumpRate ?? '');
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Pump Change'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pumpController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Pump Rate'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Save'),
              ),
            ],
          ),
        ) ??
        false;

    final pumpRate = pumpController.text.trim();
    final notes = notesController.text.trim();
    if (!confirmed || pumpRate.isEmpty) return;

    await _logService.appendEventEntry(
      workflow: _workflow,
      jobId: job.id,
      wellId: latest?.persistentWellId ?? _activeWellId,
      wellName: latest?.wellName ?? _currentWellName,
      entryType: 'pumpChange',
      timestamp: DateTime.now(),
      generatedText: 'Pump Change\nPump Rate: $pumpRate',
      operationStage: latest?.operationStage ?? _currentStage,
      pumpRate: pumpRate,
      notes: notes,
      structuredData: const <String, dynamic>{
        'source': 'operationsLogAddEntry',
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pump change saved to Operations Log.')),
    );
    await _load();
  }

  Future<void> _addNoteEntry() async {
    final job = _activeJob;
    if (job == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set an active job before adding a note.'),
        ),
      );
      return;
    }

    final latest = _sortedEntries.isEmpty ? null : _sortedEntries.last;
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Add Note'),
            content: TextField(
              controller: noteController,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Save'),
              ),
            ],
          ),
        ) ??
        false;

    final note = noteController.text.trim();
    if (!confirmed || note.isEmpty) return;

    await _logService.appendEventEntry(
      workflow: _workflow,
      jobId: job.id,
      wellId: latest?.persistentWellId ?? _activeWellId,
      wellName: latest?.wellName ?? _currentWellName,
      entryType: 'note',
      timestamp: DateTime.now(),
      generatedText: 'Operations Note\n$note',
      operationStage: latest?.operationStage ?? _currentStage,
      notes: note,
      structuredData: const <String, dynamic>{
        'source': 'operationsLogAddEntry',
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Note saved to Operations Log.')),
    );
    await _load();
  }

  Future<void> _showEntryDetails(OperationsLogEntry entry) async {
    final isStsEntry = _isStsEntry(entry);
    final averageReturns = _averageReturnRateForStsEntry(entry);
    final rows = <Widget>[
      Text('Entry Time: ${entry.entryTime.toLocal()}'),
      Text('Logged At: ${entry.loggedAt.toLocal()}'),
      if ((entry.structuredData['sharedVia'] as String? ?? '')
          .trim()
          .isNotEmpty)
        Text('Shared Via: ${entry.structuredData['sharedVia']}'),
      if (isStsEntry && _stsPumpRateValue(entry).isNotEmpty)
        Text('Pump Rate: ${_stsPumpRateValue(entry)}'),
      if (isStsEntry && averageReturns != null)
        Text(
            'Average Return Rate: ${averageReturns.toStringAsFixed(2)} bbl/min'),
      if (isStsEntry && entry.estimatedSts != null)
        Text(
          'Estimated STS: ${_formatFieldTime(entry.estimatedSts!, readingTimestamp: entry.entryTime)}',
        ),
      if (isStsEntry && entry.sts != null)
        Text(
          'Actual STS: ${_formatFieldTime(entry.sts!, readingTimestamp: entry.entryTime)}',
        ),
      if (isStsEntry) Text('Early/Late: ${_stsVarianceLabel(entry)}'),
      if (!isStsEntry &&
          _enabledFieldIds.contains('operationStage') &&
          entry.operationStage.isNotEmpty)
        Text('Operation: ${entry.operationStage}'),
      if (!isStsEntry &&
          _enabledFieldIds.contains('pumpRate') &&
          entry.pumpRate.isNotEmpty)
        Text('Pump rate: ${entry.pumpRate}'),
      if (!isStsEntry &&
          _enabledFieldIds.contains('returnsRate') &&
          entry.returnsRate.isNotEmpty)
        Text('Returns: ${_returnsDisplay(entry.returnsRate)}'),
      if (!isStsEntry &&
          _enabledFieldIds.contains('casingPressure') &&
          entry.casingPressure.isNotEmpty)
        Text('Casing pressure: ${entry.casingPressure}'),
      if (!isStsEntry &&
          _enabledFieldIds.contains('tubingPressure') &&
          _manifoldPsiValue(entry).isNotEmpty)
        Text('Manifold PSI: ${_manifoldPsiValue(entry)}'),
      if (!isStsEntry &&
          _enabledFieldIds.contains('pumpPressure') &&
          entry.pumpPressure.isNotEmpty &&
          !_isLegacyManifoldFallback(entry))
        Text('Pump PSI: ${entry.pumpPressure}'),
      if (_enabledFieldIds.contains('notes') && entry.notes.isNotEmpty)
        Text('Notes: ${entry.notes}'),
      if (!isStsEntry &&
          _enabledFieldIds.contains('gas') &&
          entry.gas.isNotEmpty)
        Text('Gas: ${entry.gas}'),
      if (!isStsEntry &&
          _enabledFieldIds.contains('waterHauled') &&
          entry.waterHauled.isNotEmpty)
        Text('Water Hauled: ${entry.waterHauled}'),
      if (!isStsEntry &&
          _enabledFieldIds.contains('oilHauled') &&
          entry.oilHauled.isNotEmpty)
        Text('Oil Hauled: ${entry.oilHauled}'),
      if (!isStsEntry &&
          _enabledFieldIds.contains('sandOrSolids') &&
          entry.sandOrSolids.isNotEmpty)
        Text('Sand / Solids: ${entry.sandOrSolids}'),
      if (!isStsEntry &&
          _enabledFieldIds.contains('choke') &&
          entry.choke.isNotEmpty)
        Text('Choke: ${entry.choke}'),
      if (!isStsEntry &&
          _enabledFieldIds.contains('estimatedSts') &&
          entry.estimatedSts != null)
        Text(
          'Estimated STS: ${_formatFieldTime(entry.estimatedSts!, readingTimestamp: entry.entryTime)}',
        ),
      if (!isStsEntry && _enabledFieldIds.contains('sts') && entry.sts != null)
        Text(
          'STS: ${_formatFieldTime(entry.sts!, readingTimestamp: entry.entryTime)}',
        ),
      if (!isStsEntry && entry.sweepInformation.isNotEmpty)
        Text('Coil Depth: ${entry.sweepInformation}'),
      if (!isStsEntry &&
          _enabledFieldIds.contains('tankLevel') &&
          entry.tankLevel.isNotEmpty)
        Text('Tank Information: ${entry.tankLevel}'),
    ];

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              entry.wellName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      ),
    );
  }

  Future<void> _deleteEntry(OperationsLogEntry entry) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Reading?'),
            content: Text('Delete the reading for ${entry.wellName}?'),
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
    final job = _activeJob;
    if (job == null) return;
    await _logService.deleteEntry(
      workflow: _workflow,
      jobId: job.id,
      entryId: entry.entryId,
    );
    await _load();
  }

  Future<void> _shareSelectedReadings() async {
    final job = _activeJob;
    final selectedEntries = _entries
        .where((entry) => _selectedEntryIds.contains(entry.entryId))
        .toList(growable: false);
    if (job == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set an active job before sharing.')),
      );
      return;
    }
    if (selectedEntries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one reading to share.')),
      );
      return;
    }
    try {
      final packageType = _workflow == OperationsLogWorkflow.drillout
          ? OperationsLogPackageType.drilloutReadingBatch
          : OperationsLogPackageType.cleanoutReadingBatch;
      final package = await _logService.buildPackage(
        packageType: packageType,
        persistentJobId: job.id,
        entries: selectedEntries,
      );
      final encoded = _logService.encodePackage(package);
      await _showShareQrDialog(encoded, '${widget.title} QR');
    } catch (error, stackTrace) {
      debugPrint(
        '[OperationsLog] Failed to share selected readings: $error\n$stackTrace',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to share selected readings.')),
      );
    }
  }

  Future<_ReportDataSource?> _chooseReportDataSource() async {
    return showModalBottomSheet<_ReportDataSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Choose Data Source',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              title: const Text('Latest Reading'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ReportDataSource.latest),
            ),
            ListTile(
              title: const Text('Selected Reading'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ReportDataSource.selected),
            ),
            ListTile(
              title: const Text('Last 3 Readings'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ReportDataSource.lastThree),
            ),
            ListTile(
              title: const Text('Entire Shift'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ReportDataSource.entireShift),
            ),
          ],
        ),
      ),
    );
  }

  List<OperationsLogEntry> _entriesForReportSource(_ReportDataSource source) {
    final ordered = _sortedEntries;
    if (ordered.isEmpty) return const <OperationsLogEntry>[];
    switch (source) {
      case _ReportDataSource.latest:
        return [ordered.last];
      case _ReportDataSource.selected:
        final selected = ordered
            .where((entry) => _selectedEntryIds.contains(entry.entryId))
            .toList(growable: false);
        if (selected.isNotEmpty) return selected;
        return [ordered.last];
      case _ReportDataSource.lastThree:
        final start = ordered.length > 3 ? ordered.length - 3 : 0;
        return ordered.sublist(start);
      case _ReportDataSource.entireShift:
        return ordered;
    }
  }

  String _reportSourceLabel(_ReportDataSource source) {
    switch (source) {
      case _ReportDataSource.latest:
        return 'latestReading';
      case _ReportDataSource.selected:
        return 'selectedReading';
      case _ReportDataSource.lastThree:
        return 'last3Readings';
      case _ReportDataSource.entireShift:
        return 'entireShift';
    }
  }

  String _buildReportPreview({
    required String reportType,
    required List<OperationsLogEntry> entries,
  }) {
    if (entries.isEmpty) return 'No readings are available for this report.';

    if (_workflow == OperationsLogWorkflow.drillout ||
        _workflow == OperationsLogWorkflow.cleanout) {
      return _buildCompletionsStyleReportPreview(
        reportType: reportType,
        entries: entries,
        reportTime: _reportTimeOverride,
      );
    }

    final lines = <String>[
      reportType,
      'Well: $_currentWellName',
      '',
    ];
    for (final entry in entries) {
      lines.add(
        '${TimeOfDay.fromDateTime(entry.entryTime).format(context)} • ${entry.wellName} • ${_entryTypeLabel(entry)}',
      );
      final subtitle = _entrySubtitle(entry);
      if (subtitle.trim().isNotEmpty) {
        lines.add(subtitle);
      }
      final generated = entry.generatedText.trim();
      if (generated.isNotEmpty &&
          (subtitle.trim().isEmpty || !generated.contains(subtitle.trim()))) {
        lines.add(generated);
      }
      lines.add('');
    }
    return lines.join('\n').trim();
  }

  String _buildCompletionsStyleReportPreview({
    required String reportType,
    required List<OperationsLogEntry> entries,
    DateTime? reportTime,
  }) {
    final anchor = entries.last;
    final modeLabel = reportType == 'Text Update' ? 'Update' : 'Shift Change';
    final workflowLabel =
        _workflow == OperationsLogWorkflow.cleanout ? 'Cleanout' : 'Drillout';
    final resolvedTime = reportTime ?? anchor.entryTime;
    final timeLabel = TimeOfDay.fromDateTime(resolvedTime).format(context);

    final header = <String>[
      '$timeLabel $workflowLabel $modeLabel',
      if (_activeJob?.company.trim().isNotEmpty ?? false)
        _activeJob!.company.trim(),
      if (reportType != 'Text Update' &&
          (_activeJob?.padName.trim().isNotEmpty ?? false))
        _activeJob!.padName.trim(),
      if (anchor.wellName.trim().isNotEmpty) anchor.wellName.trim(),
    ];

    String carry(String Function(OperationsLogEntry entry) selector) {
      return _carryForwardValueForEntry(anchor, selector).trim();
    }

    String withFeet(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return trimmed;
      final lower = trimmed.toLowerCase();
      if (lower.endsWith('ft') || lower.endsWith('feet')) {
        return trimmed;
      }
      return '$trimmed ft';
    }

    final details = <String>[];
    final stage = carry((entry) => entry.operationStage);
    if (stage.isNotEmpty) details.add('Status: $stage');

    final plug = carry((entry) => entry.plugNumber);
    if (plug.isNotEmpty) details.add('Plug #: $plug');

    final coilDepth = carry((entry) => entry.sweepInformation);
    if (coilDepth.isNotEmpty) details.add('Coil Depth: ${withFeet(coilDepth)}');

    final gas = carry((entry) => entry.gas);
    if (gas.isNotEmpty) details.add('Gas: $gas');

    final sand = carry((entry) => entry.sandOrSolids);
    if (sand.isNotEmpty) details.add('Sand: $sand');

    final choke = carry((entry) => entry.choke);
    if (choke.isNotEmpty) details.add('Choke: $choke');

    final rate = carry((entry) => entry.pumpRate);
    if (rate.isNotEmpty) details.add('Rate: $rate BBL/min');

    final returns = carry((entry) => entry.returnsRate);
    if (returns.isNotEmpty) {
      details.add('Returns: ${_returnsDisplay(returns)}');
    }

    final manifold = carry((entry) => _manifoldPsiValue(entry));
    if (manifold.isNotEmpty) details.add('Manifold PSI: $manifold');

    final casing = carry((entry) => entry.casingPressure);
    if (casing.isNotEmpty) details.add('Casing PSI: $casing');

    final pumpPsi = carry((entry) => entry.pumpPressure);
    if (pumpPsi.isNotEmpty) details.add('Pump PSI: $pumpPsi');

    final surfaceTotalFluid = carry((entry) => entry.surfaceTotalFluid);
    if (surfaceTotalFluid.isNotEmpty) {
      details.add('Surface Total Fluid: $surfaceTotalFluid bbl');
    }

    final waterHauled = carry((entry) => entry.waterHauled);
    if (waterHauled.isNotEmpty) details.add('Water Hauled: $waterHauled bbl');

    final oilHauled = carry((entry) => entry.oilHauled);
    if (oilHauled.isNotEmpty) details.add('Oil Hauled: $oilHauled bbl');

    final includeTankInventory = reportType != 'Text Update' ||
        _workflow != OperationsLogWorkflow.drillout ||
        _includeTankInventoryInDrilloutTextUpdate;
    final tankInventoryBlock =
        includeTankInventory ? _resolveTankInventoryBlock(anchor) : '';

    final estimatedSts = anchor.estimatedSts;
    if (estimatedSts != null) {
      details.add(
        'Estimated STS: ${_formatFieldTime(estimatedSts, readingTimestamp: anchor.entryTime)}',
      );
    }

    final actualSts = anchor.sts;
    if (actualSts != null) {
      details.add(
        'STS: ${_formatFieldTime(actualSts, readingTimestamp: anchor.entryTime)}',
      );
    }

    final notes = anchor.notes.trim();
    if (notes.isNotEmpty) details.add('Notes: $notes');

    final blocks = <String>[
      header.where((line) => line.trim().isNotEmpty).join('\n'),
      if (details.isNotEmpty) details.join('\n'),
      if (tankInventoryBlock.isNotEmpty) tankInventoryBlock,
    ];

    return blocks.where((block) => block.trim().isNotEmpty).join('\n\n');
  }

  String _resolveTankInventoryBlock(OperationsLogEntry anchor) {
    final structuredBlock = _carryForwardTankInventoryBlockForEntry(anchor);
    if (structuredBlock.isNotEmpty) return structuredBlock;

    final generated = anchor.generatedText;
    if (generated.trim().isNotEmpty) {
      final match = RegExp(
        r'Tank Inventory[\s\S]*?(?=\n\nNotes:|\z)',
        caseSensitive: false,
      ).firstMatch(generated);
      if (match != null) {
        final block = (match.group(0) ?? '').trim();
        if (block.isNotEmpty) return block;
      }
    }

    final tankInformation = _carryForwardValueForEntry(
      anchor,
      (entry) => entry.tankLevel,
    ).trim();
    if (tankInformation.isEmpty) return '';
    return 'Tank Inventory\n\nTank Information: $tankInformation';
  }

  String _carryForwardTankInventoryBlockForEntry(OperationsLogEntry target) {
    String latest = '';
    for (final entry in _sortedEntries) {
      final block = _tankInventoryBlockFromStructuredData(entry);
      if (block.isNotEmpty) {
        latest = block;
      }
      if (entry.entryId == target.entryId) {
        break;
      }
    }
    return latest;
  }

  String _tankInventoryBlockFromStructuredData(OperationsLogEntry entry) {
    final raw = entry.structuredData['tankInventoryV1'];
    if (raw is! List || raw.isEmpty) return '';

    final lines = <String>['Tank Inventory', ''];
    var total = 0;
    var hasRow = false;
    for (final item in raw) {
      if (item is! Map) continue;
      final label = (item['label'] as String? ?? '').trim();
      final gauge = (item['gauge'] as String? ?? '').trim();
      final barrelsValue = item['barrels'];
      final barrels = barrelsValue is num ? barrelsValue.toInt() : null;
      final gaugeText = gauge.isEmpty ? '-' : '$gauge"';
      final bblText = barrels == null ? '-' : '$barrels bbl';
      lines.add('${label.isEmpty ? 'Tank' : label}: $gaugeText - $bblText');
      if (barrels != null) {
        total += barrels;
      }
      hasRow = true;
    }
    if (!hasRow) return '';
    lines.add('');
    lines.add('Total On Location: $total bbl');
    return lines.join('\n').trim();
  }

  String _reportTimeLabel() {
    final value = _reportTimeOverride;
    if (value == null) return 'Current Time';
    final dateLabel =
        MaterialLocalizations.of(context).formatCompactDate(value);
    final timeLabel = TimeOfDay.fromDateTime(value).format(context);
    return '$dateLabel $timeLabel';
  }

  Future<void> _editReportTime() async {
    final base = _reportTimeOverride ?? DateTime.now();
    final selection = await showStsDateTimeSelectorSheet(
      context,
      title: 'Text Timestamp',
      helperText:
          'Set the time shown in Shift Change Text and Text Update outputs.',
      readingTimestamp: base,
      initialValue: base,
    );
    if (!mounted || selection == null) return;
    setState(() {
      _reportTimeOverride = selection.cleared ? null : selection.value;
    });
  }

  Future<void> _finalizeReportAction({
    required String reportType,
    required String shareMethod,
    required String reportText,
    required _ReportDataSource source,
  }) async {
    final job = _activeJob;
    if (job == null) return;
    final key =
        '$reportType|$shareMethod|${_reportSourceLabel(source)}|${reportText.hashCode}';
    if (_lastFinalizedReportKey == key) return;

    final latest = _sortedEntries.isEmpty ? null : _sortedEntries.last;
    final entry = await _logService.appendEventEntry(
      workflow: _workflow,
      jobId: job.id,
      wellId: latest?.persistentWellId ?? _activeWellId,
      wellName: latest?.wellName ?? _currentWellName,
      entryType: reportType == 'Text Update' ? 'textUpdate' : 'shiftChange',
      timestamp: DateTime.now(),
      generatedText: reportText,
      structuredData: <String, dynamic>{
        'source': 'operationsLogCreateReport',
        'reportType': reportType,
        'sharedVia': shareMethod,
        'dataSource': _reportSourceLabel(source),
      },
      operationStage: latest?.operationStage ?? _currentStage,
      pumpRate: latest?.pumpRate ?? '',
      choke: latest?.choke ?? '',
      notes: '$reportType finalized via $shareMethod.',
    );
    _lastFinalizedReportKey = key;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$reportType $shareMethod logged.')),
    );
    await _load();

    if (shareMethod == 'qr') {
      final packageType = _workflow == OperationsLogWorkflow.cleanout
          ? OperationsLogPackageType.cleanoutReading
          : OperationsLogPackageType.drilloutReading;
      final package = await _logService.buildPackage(
        packageType: packageType,
        persistentJobId: job.id,
        entries: [entry],
      );
      final encoded = _logService.encodePackage(package);
      if (!mounted) return;
      await _showShareQrDialog(encoded, '$reportType QR');
    }
  }

  Future<void> _generateShiftUpdateAction() async {
    if (_entries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one entry first.')),
      );
      return;
    }
    final source = await _chooseReportDataSource();
    if (source == null) return;
    final sourceEntries = _entriesForReportSource(source);
    final reportText = _buildReportPreview(
      reportType: 'Shift Update',
      entries: sourceEntries,
    );
    await _finalizeReportAction(
      reportType: 'Shift Update',
      shareMethod: 'generated',
      reportText: reportText,
      source: source,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Shift Change Text Preview'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(reportText),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _previewTextAction() async {
    if (_entries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one entry first.')),
      );
      return;
    }
    final source = await _chooseReportDataSource();
    if (source == null) return;
    final sourceEntries = _entriesForReportSource(source);
    final reportText = _buildReportPreview(
      reportType: 'Text Update',
      entries: sourceEntries,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Text Update Preview'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(reportText),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyUpdateAction() async {
    if (_entries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one entry first.')),
      );
      return;
    }
    final source = await _chooseReportDataSource();
    if (source == null) return;
    final sourceEntries = _entriesForReportSource(source);
    final reportText = _buildReportPreview(
      reportType: 'Text Update',
      entries: sourceEntries,
    );
    await Clipboard.setData(ClipboardData(text: reportText));
    await _finalizeReportAction(
      reportType: 'Text Update',
      shareMethod: 'copyText',
      reportText: reportText,
      source: source,
    );
  }

  Future<void> _shareUpdateAction() async {
    if (_entries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one entry first.')),
      );
      return;
    }
    final source = await _chooseReportDataSource();
    if (source == null) return;
    final sourceEntries = _entriesForReportSource(source);
    final reportText = _buildReportPreview(
      reportType: 'Text Update',
      entries: sourceEntries,
    );
    await Share.share(reportText, subject: 'Text Update - WellWerks');
    await _finalizeReportAction(
      reportType: 'Text Update',
      shareMethod: 'message',
      reportText: reportText,
      source: source,
    );
  }

  Future<void> _exportTimelineAction() async {
    final job = _activeJob;
    if (job == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set an active job before exporting.')),
      );
      return;
    }
    if (_entries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one entry first.')),
      );
      return;
    }

    final source = await _chooseReportDataSource();
    if (source == null) return;
    final sourceEntries = _entriesForReportSource(source);
    final reportText = _buildReportPreview(
      reportType: 'Shift Update',
      entries: sourceEntries,
    );

    final exported = await _logService.exportShiftReportPdf(
      workflow: _workflow,
      jobName: job.padName,
      wellName: _currentWellName,
      stage: _currentStage,
      entries: sourceEntries,
      enabledFieldIds: _enabledFieldIds,
      baseFileName: 'operations_log_shift_update',
    );
    await Share.shareXFiles(
      [XFile(exported.filePath, mimeType: 'application/pdf')],
      subject: 'Operations Log Shift Update',
      text: 'Exported from WellWerks Operations Log.',
    );
    await _finalizeReportAction(
      reportType: 'Shift Update',
      shareMethod: 'exportPdf',
      reportText: reportText,
      source: source,
    );
  }

  void _toggleSelectedEntry(String entryId, bool selected) {
    setState(() {
      final next = Set<String>.from(_selectedEntryIds);
      if (selected) {
        next.add(entryId);
      } else {
        next.remove(entryId);
      }
      _selectedEntryIds = next;
    });
  }

  Future<void> _shareReading(OperationsLogEntry entry) async {
    final job = _activeJob;
    if (job == null) return;
    final packageType = _workflow == OperationsLogWorkflow.drillout
        ? OperationsLogPackageType.drilloutReading
        : OperationsLogPackageType.cleanoutReading;
    final package = await _logService.buildPackage(
      packageType: packageType,
      persistentJobId: job.id,
      entries: [entry],
    );
    final encoded = _logService.encodePackage(package);
    await _showShareQrDialog(encoded, 'Share Reading QR');
  }

  void _toggleExpandedEntry(String entryId) {
    setState(() {
      final next = Set<String>.from(_expandedEntryIds);
      if (next.contains(entryId)) {
        next.remove(entryId);
      } else {
        next.add(entryId);
      }
      _expandedEntryIds = next;
    });
  }

  Future<void> _copyEntryAgain(OperationsLogEntry entry) async {
    final fallback = _entrySubtitle(entry);
    final text = entry.generatedText.trim().isEmpty
        ? '$fallback\n${entry.notes.trim()}'
        : entry.generatedText;
    await Clipboard.setData(ClipboardData(text: text.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Entry copied to clipboard.')),
    );
  }

  Future<void> _recordStsForEntry(OperationsLogEntry entry) async {
    final averageReturns = _averageReturnRateForStsEntry(entry);
    final result =
        await Navigator.of(context).push<OperationsLogStsEntryResult>(
      MaterialPageRoute(
        builder: (_) => OperationsLogStsEntryScreen(
          title: 'Edit STS',
          initialPumpRate: _stsPumpRateValue(entry),
          initialAverageReturnRate: averageReturns,
          initialEstimatedSts: entry.estimatedSts,
          initialActualSts: entry.sts ?? DateTime.now(),
          initialNotes: entry.notes,
        ),
      ),
    );
    if (result == null) return;
    await _saveStsEntry(
      entry: entry,
      pumpRate: result.pumpRate,
      averageReturnRate: result.averageReturnRate,
      estimatedSts: result.estimatedSts,
      actualSts: result.actualSts,
      notes: result.notes,
    );
  }

  Future<void> _editEntry(OperationsLogEntry entry) async {
    final type = _entryTypeValue(entry);
    if (entry.estimatedSts != null ||
        entry.sts != null ||
        type == 'stsReached') {
      await _recordStsForEntry(entry);
      return;
    }

    if (type == 'manualReading') {
      final job = _activeJob;
      if (job == null) return;
      final updated = await Navigator.of(context).push<OperationsLogEntry>(
        MaterialPageRoute(
          builder: (_) => OperationsLogEntryFormScreen(
            workflow: _workflow,
            title: widget.title,
            activeJob: job,
            defaultWells: _resolvedWells,
            initialSelectedWellId: entry.persistentWellId,
            initialSelectedWellName: entry.wellName,
            initialStage: entry.operationStage,
            initialReadingTimestamp: entry.entryTime,
            stageOptions: DrilloutCleanoutFieldDefinitions.stageOptions,
            enabledFieldIds: _enabledFieldIds,
            logService: _logService,
            existingEntries: _entries,
            existingEntry: entry,
          ),
        ),
      );
      if (updated == null) return;
      await _load();
      return;
    }

    final generatedController =
        TextEditingController(text: entry.generatedText);
    final notesController = TextEditingController(text: entry.notes);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Edit Timeline Entry'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: generatedController,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Generated Text',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Notes'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Save'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    final job = _activeJob;
    if (job == null) return;
    await _logService.upsertEntry(
      workflow: _workflow,
      jobId: job.id,
      entry: entry.copyWith(
        generatedText: generatedController.text.trim(),
        notes: notesController.text.trim(),
      ),
    );
    await _load();
  }

  Future<void> _duplicateEntry(OperationsLogEntry entry) async {
    final job = _activeJob;
    if (job == null) return;
    final duplicate = await _logService.createLocalEntry(
      workflow: _workflow,
      jobId: job.id,
      wellId: entry.persistentWellId,
      wellName: entry.wellName,
      readingTimestamp: DateTime.now(),
      entryType: _entryTypeValue(entry),
      generatedText: entry.generatedText,
      structuredData: entry.structuredData,
      operationStage: entry.operationStage,
      choke: entry.choke,
      casingPressure: entry.casingPressure,
      tubingPressure: entry.tubingPressure,
      pumpPressure: entry.pumpPressure,
      pumpRate: entry.pumpRate,
      gas: entry.gas,
      plugNumber: entry.plugNumber,
      surfaceTotalFluid: entry.surfaceTotalFluid,
      waterHauled: entry.waterHauled,
      oilHauled: entry.oilHauled,
      returnsRate: entry.returnsRate,
      waterRate: entry.waterRate,
      flowRate: entry.flowRate,
      estimatedSts: entry.estimatedSts,
      sts: entry.sts,
      tankLevel: entry.tankLevel,
      sweepInformation: entry.sweepInformation,
      sandOrSolids: entry.sandOrSolids,
      equipmentStatus: entry.equipmentStatus,
      downtime: entry.downtime,
      notes: entry.notes,
    );
    await _logService.upsertEntry(
        workflow: _workflow, jobId: job.id, entry: duplicate);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Timeline entry duplicated.')),
    );
    await _load();
  }

  String _compactMetrics(OperationsLogEntry entry) {
    final values = <String>[];
    if (entry.pumpRate.trim().isNotEmpty) {
      values.add('Pump ${entry.pumpRate.trim()}');
    }
    if (entry.choke.trim().isNotEmpty) {
      values.add('Choke ${entry.choke.trim()}');
    }
    if (entry.operationStage.trim().isNotEmpty) {
      values.add('Stage ${entry.operationStage.trim()}');
    }
    if (entry.estimatedSts != null) {
      values.add(
        'Est. STS ${_formatFieldTime(entry.estimatedSts!, readingTimestamp: entry.entryTime)}',
      );
    }
    if (entry.sts != null) {
      values.add(
        'STS ${_formatFieldTime(entry.sts!, readingTimestamp: entry.entryTime)}',
      );
    }
    if (values.isEmpty) return 'No key metrics';
    return values.join(' • ');
  }

  Future<void> _showShareQrDialog(String qrValue, String title) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: qrValue,
              version: QrVersions.auto,
              errorCorrectionLevel: QrErrorCorrectLevel.L,
              size: 280,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 10),
            const Text(
              'Scan this QR nearby or tap Share QR to send it as an image.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
          Builder(
            builder: (buttonContext) => FilledButton(
              onPressed: () async {
                try {
                  final result = await _qrTransferService.shareQrPng(
                    qrValue: qrValue,
                    fileName: title,
                    shareContext: buttonContext,
                    subject: title,
                  );
                  if (!mounted || !buttonContext.mounted) return;
                  if (result.status == ShareResultStatus.dismissed) {
                    return;
                  }
                } catch (error, stackTrace) {
                  debugPrint(
                    '[OperationsLog] Failed to share QR image: $error\n$stackTrace',
                  );
                  if (!mounted || !buttonContext.mounted) return;
                  ScaffoldMessenger.of(buttonContext).showSnackBar(
                    const SnackBar(
                      content: Text('The QR image could not be shared.'),
                    ),
                  );
                }
              },
              child: const Text('Share QR'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importReading() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Reading'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop('scan'),
            child: const Text('Scan QR'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop('photos'),
            child: const Text('Choose QR from Photos'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (!mounted) return;
    if (choice == 'scan') {
      final scanned = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => const WellWerksQrScannerScreen(
            title: 'Scan QR',
            prompt: 'Center the operations log QR code in view.',
          ),
        ),
      );
      if (scanned != null && scanned.trim().isNotEmpty) {
        await _importFromRaw(scanned);
      }
    } else if (choice == 'photos') {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        final raw = await _qrTransferService.decodeFirstQrFromImagePath(
          picked.path,
        );
        if (raw != null && raw.trim().isNotEmpty) {
          await _importFromRaw(raw);
        }
      }
    }
  }

  Future<void> _importFromRaw(String rawValue) async {
    final job = _activeJob;
    if (job == null) return;
    try {
      final package = _logService.decodePackage(rawValue);
      if (package.entries.isEmpty) return;
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Import Preview'),
              content: Text(
                package.entries.length == 1
                    ? '1 reading from ${package.workflow} for ${job.padName}.\n${package.entries.first.wellName} at ${package.entries.first.entryTime.toLocal()}'
                    : '${package.entries.length} readings from ${package.workflow} for ${job.padName}.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    package.entries.length == 1
                        ? 'Add Reading'
                        : 'Add Readings',
                  ),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
      final result = await _logService.importEntries(
        workflow: _workflow,
        jobId: job.id,
        package: package,
        existingEntries: _entries,
      );
      await _scheduleImportedEstimatedStsReminders(
        jobId: job.id,
        entries: result.added,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.added.length} readings imported successfully.',
          ),
        ),
      );
      await _load();
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _scheduleImportedEstimatedStsReminders({
    required String jobId,
    required List<OperationsLogEntry> entries,
  }) async {
    if (entries.isEmpty) return;
    final withEstimated = entries
        .where((entry) => entry.estimatedSts != null)
        .toList(growable: false);
    if (withEstimated.isEmpty) return;

    final settings = await _stsReminderService.loadSettings();
    if (!settings.estimatedStsReminderEnabled) return;

    final prompted =
        await _notificationService.hasPromptedEstimatedStsPermission();
    var permissionGranted = false;
    if (prompted) {
      permissionGranted =
          await _notificationService.requestNotificationPermission();
    }

    final updated = <OperationsLogEntry>[];
    for (final incoming in withEstimated) {
      final seededSweepId = incoming.sweepId.trim().isEmpty
          ? 'sweep_${incoming.entryId}'
          : incoming.sweepId;
      final normalized = incoming.copyWith(sweepId: seededSweepId);
      final sync = await _stsReminderService.syncForSavedEntry(
        entry: normalized,
        remindersEnabled: settings.estimatedStsReminderEnabled,
        defaultLeadMinutes: settings.estimatedStsReminderLeadMinutes,
        permissionGranted: permissionGranted,
      );
      updated.add(sync.entry);
    }

    if (updated.isEmpty) return;
    for (final entry in updated) {
      await _logService.upsertEntry(
        workflow: _workflow,
        jobId: jobId,
        entry: entry,
      );
    }
  }

  Future<void> _customizeFields() async {
    final job = _activeJob;
    if (job == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set an active job before customizing fields.'),
        ),
      );
      return;
    }

    final selected = Set<String>.from(_enabledFieldIds);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Customize Fields'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Well, date, and time are always required. Choose additional fields to show in Add Reading and reports.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final field
                      in OperationsLogFieldConfigService.configurableFields)
                    CheckboxListTile(
                      dense: true,
                      value: selected.contains(field.id),
                      title: Text(field.label),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() {
                          if (value ?? false) {
                            selected.add(field.id);
                          } else {
                            selected.remove(field.id);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final config = OperationsLogFieldConfig(enabledFieldIds: selected);
    await _fieldConfigService.save(
      workflow: _workflow,
      jobId: job.id,
      config: config,
    );
    if (!mounted) return;
    setState(() => _enabledFieldIds = selected);
  }

  String _entrySubtitle(OperationsLogEntry entry) {
    final parts = <String>[];
    if (_enabledFieldIds.contains('operationStage') &&
        entry.operationStage.isNotEmpty) {
      parts.add(entry.operationStage);
    }
    if (_enabledFieldIds.contains('pumpRate') && entry.pumpRate.isNotEmpty) {
      parts.add('Pump ${entry.pumpRate}');
    }
    if (_enabledFieldIds.contains('returnsRate') &&
        entry.returnsRate.isNotEmpty) {
      parts.add('Returns ${_returnsDisplay(entry.returnsRate)}');
    }
    if (_enabledFieldIds.contains('casingPressure') &&
        entry.casingPressure.isNotEmpty) {
      parts.add('CSG ${entry.casingPressure}');
    }
    if (_enabledFieldIds.contains('tubingPressure') &&
        _manifoldPsiValue(entry).isNotEmpty) {
      parts.add('Manifold ${_manifoldPsiValue(entry)}');
    }
    if (_enabledFieldIds.contains('pumpPressure') &&
        entry.pumpPressure.isNotEmpty &&
        !_isLegacyManifoldFallback(entry)) {
      parts.add('Pump PSI ${entry.pumpPressure}');
    }
    if (_enabledFieldIds.contains('notes') && entry.notes.isNotEmpty) {
      parts.add(entry.notes);
    }
    if (_enabledFieldIds.contains('gas') && entry.gas.isNotEmpty) {
      parts.add('Gas ${entry.gas}');
    }
    if (_enabledFieldIds.contains('waterHauled') &&
        entry.waterHauled.isNotEmpty) {
      parts.add('Water ${entry.waterHauled}');
    }
    if (_enabledFieldIds.contains('oilHauled') && entry.oilHauled.isNotEmpty) {
      parts.add('Oil ${entry.oilHauled}');
    }
    if (_enabledFieldIds.contains('sandOrSolids') &&
        entry.sandOrSolids.isNotEmpty) {
      parts.add('Sand ${entry.sandOrSolids}');
    }
    if (_enabledFieldIds.contains('choke') && entry.choke.isNotEmpty) {
      parts.add('Choke ${entry.choke}');
    }
    if (_enabledFieldIds.contains('estimatedSts') &&
        entry.estimatedSts != null) {
      parts.add(
        'Est. STS ${_formatFieldTime(entry.estimatedSts!, readingTimestamp: entry.entryTime)}',
      );
    }
    if (_enabledFieldIds.contains('sts') && entry.sts != null) {
      parts.add(
        'STS ${_formatFieldTime(entry.sts!, readingTimestamp: entry.entryTime)}',
      );
    }
    if (entry.sweepInformation.isNotEmpty) {
      parts.add('Coil Depth ${entry.sweepInformation}');
    }
    return parts.join(' • ');
  }

  String _returnsDisplay(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return '';
    if (_workflow == OperationsLogWorkflow.drillout) {
      return '$trimmed bbl/min';
    }
    return trimmed;
  }

  String _manifoldPsiValue(OperationsLogEntry entry) {
    final tubing = entry.tubingPressure.trim();
    if (tubing.isNotEmpty) return tubing;
    return entry.pumpPressure.trim();
  }

  bool _isLegacyManifoldFallback(OperationsLogEntry entry) {
    return entry.tubingPressure.trim().isEmpty &&
        entry.pumpPressure.trim().isNotEmpty;
  }

  List<({String label, String key})> _dataColumns() {
    final columns = <({String label, String key})>[
      (label: 'Time', key: 'time')
    ];

    void addIfEnabled(String fieldId, String label, String key) {
      if (_enabledFieldIds.contains(fieldId)) {
        columns.add((label: label, key: key));
      }
    }

    addIfEnabled('operationStage', 'Stage', 'stage');
    addIfEnabled('pumpRate', 'Pump', 'pump');
    addIfEnabled('returnsRate', 'Returns', 'returns');
    addIfEnabled('tubingPressure', 'Manifold', 'manifold');
    addIfEnabled('casingPressure', 'Casing', 'casing');
    addIfEnabled('pumpPressure', 'Pump PSI', 'pumpPsi');
    addIfEnabled('choke', 'Choke', 'choke');
    addIfEnabled('waterHauled', 'Water', 'water');
    addIfEnabled('oilHauled', 'Oil', 'oil');
    addIfEnabled('gas', 'Gas', 'gas');
    addIfEnabled('sandOrSolids', 'Sand', 'sand');
    addIfEnabled('sweepInformation', 'Coil Depth', 'sweep');
    addIfEnabled('estimatedSts', 'Estimated STS', 'estimatedSts');
    addIfEnabled('sts', 'Actual STS', 'actualSts');
    addIfEnabled('notes', 'Notes', 'notes');

    return columns;
  }

  String _effectiveDataSortField(List<({String label, String key})> columns) {
    final allowed = columns
        .where((col) => col.key != 'time')
        .map((col) => col.key)
        .toList(growable: false);
    if (allowed.isEmpty) return 'time';
    if (allowed.contains(_dataSortField)) return _dataSortField;
    return allowed.first;
  }

  String _carryForwardValueForEntry(
    OperationsLogEntry target,
    String Function(OperationsLogEntry entry) selector,
  ) {
    String latest = '';
    for (final item in _sortedEntries) {
      final value = selector(item).trim();
      if (value.isNotEmpty) {
        latest = value;
      }
      if (item.entryId == target.entryId) {
        break;
      }
    }
    return latest;
  }

  String _formatFieldTime(
    DateTime value, {
    required DateTime readingTimestamp,
  }) {
    final local = value.toLocal();
    final readingDate = DateTime(
      readingTimestamp.year,
      readingTimestamp.month,
      readingTimestamp.day,
    );
    final selectedDate = DateTime(local.year, local.month, local.day);
    final timeLabel = TimeOfDay.fromDateTime(local).format(context);
    if (selectedDate == readingDate) {
      return timeLabel;
    }
    if (selectedDate == readingDate.add(const Duration(days: 1))) {
      return 'Tomorrow $timeLabel';
    }
    final dateLabel =
        MaterialLocalizations.of(context).formatCompactDate(local);
    return '$dateLabel $timeLabel';
  }

  String _eventTitle(OperationsLogEntry entry) {
    final type = _entryTypeValue(entry);
    if ((entry.structuredData['reportType'] as String? ?? '')
        .trim()
        .isNotEmpty) {
      return 'Report';
    }
    if (entry.estimatedSts != null ||
        entry.sts != null ||
        type == 'stsReached') {
      return 'STS';
    }
    switch (type) {
      case 'pumpChange':
        return 'Pump Change';
      case 'note':
        return 'Note';
      case 'manualReading':
        return 'Manual Reading';
      case 'textUpdate':
        return 'Text Update';
      case 'shiftChange':
        return 'Shift Change';
      case 'qrImport':
        return 'QR Import';
      case 'handoffImport':
        return 'Handoff';
      case 'jobStarted':
      case 'jobEnded':
      case 'stageChange':
        return 'Job Event';
      default:
        return _entryTypeLabel(entry);
    }
  }

  IconData _eventIcon(OperationsLogEntry entry) {
    final type = _entryTypeValue(entry);
    if ((entry.structuredData['reportType'] as String? ?? '')
        .trim()
        .isNotEmpty) {
      return Icons.description_outlined;
    }
    if (entry.estimatedSts != null ||
        entry.sts != null ||
        type == 'stsReached') {
      return Icons.timer_outlined;
    }
    switch (type) {
      case 'pumpChange':
        return Icons.speed_outlined;
      case 'note':
        return Icons.sticky_note_2_outlined;
      case 'manualReading':
        return Icons.edit_note;
      case 'textUpdate':
        return Icons.sms_outlined;
      case 'shiftChange':
        return Icons.swap_horiz;
      case 'qrImport':
        return Icons.qr_code_scanner_outlined;
      case 'handoffImport':
        return Icons.hub_outlined;
      case 'jobStarted':
        return Icons.play_arrow_rounded;
      case 'jobEnded':
        return Icons.stop_rounded;
      default:
        return Icons.timeline;
    }
  }

  Color _eventColor(OperationsLogEntry entry) {
    final type = _entryTypeValue(entry);
    if (entry.sts != null) return _stsStatusColor(entry);
    switch (type) {
      case 'pumpChange':
        return Colors.cyanAccent;
      case 'note':
        return Colors.white70;
      case 'manualReading':
        return _wwGold;
      case 'textUpdate':
        return Colors.lightBlueAccent;
      case 'shiftChange':
        return Colors.amberAccent;
      case 'qrImport':
      case 'handoffImport':
        return Colors.tealAccent;
      case 'jobEnded':
        return Colors.redAccent;
      default:
        return Colors.white70;
    }
  }

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    final now = _clockNow;
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) return 'Today';
    return MaterialLocalizations.of(context).formatCompactDate(local);
  }

  List<String> _importantLines(OperationsLogEntry entry) {
    final type = _entryTypeValue(entry);
    final reportType =
        (entry.structuredData['reportType'] as String? ?? '').trim();

    if (reportType.isNotEmpty) {
      return <String>['Type $reportType'];
    }

    if (type == 'textUpdate') {
      final lines = <String>[];
      final shift = (entry.structuredData['shift'] as String? ?? '').trim();
      if (shift.isNotEmpty) {
        lines.add('Shift ${shift[0].toUpperCase()}${shift.substring(1)}');
      }
      final wells =
          (entry.structuredData['wellsIncluded'] as String? ?? '').trim();
      if (wells.isNotEmpty) {
        lines.add('Wells $wells');
      } else if (entry.wellName.trim().isNotEmpty) {
        lines.add('Well ${entry.wellName.trim()}');
      }
      if (lines.isNotEmpty) return lines;
    }

    if (_isStsEntry(entry)) {
      final lines = <String>[];
      final pumpRate = _stsPumpRateValue(entry);
      final averageReturns = _averageReturnRateForStsEntry(entry);
      if (pumpRate.isNotEmpty) {
        lines.add('Pump $pumpRate');
      }
      if (averageReturns != null) {
        lines.add('Avg Return ${averageReturns.toStringAsFixed(2)} bbl/min');
      }
      if (entry.sts != null) {
        lines.add(_stsVarianceLabel(entry));
      }
      if (lines.isNotEmpty) {
        return lines.take(4).toList(growable: false);
      }
    }

    if (entry.estimatedSts != null ||
        entry.sts != null ||
        type == 'stsReached') {
      final lines = <String>[];
      if (entry.estimatedSts != null) {
        lines.add(
          'Estimated ${_formatFieldTime(entry.estimatedSts!, readingTimestamp: entry.entryTime)}',
        );
      }
      if (entry.sts != null) {
        lines.add(
          'Actual ${_formatFieldTime(entry.sts!, readingTimestamp: entry.entryTime)}',
        );
        lines.add(_stsVarianceLabel(entry));
      } else {
        lines.add('STS Pending');
      }
      return lines;
    }

    if (_workflow == OperationsLogWorkflow.drillout) {
      final lines = <String>[];
      void add(String value) {
        if (value.trim().isEmpty || lines.length >= 4) return;
        lines.add(value.trim());
      }

      final stage = entry.operationStage.trim();
      final choke = _carryForwardValueForEntry(entry, (item) => item.choke);
      final returns =
          _carryForwardValueForEntry(entry, (item) => item.returnsRate);
      final manifold =
          _carryForwardValueForEntry(entry, (item) => _manifoldPsiValue(item));

      add(stage.isEmpty ? '' : 'Stage $stage');
      add(choke.isEmpty ? '' : 'Choke $choke');
      add(returns.isEmpty ? '' : 'Returns ${_returnsDisplay(returns)}');

      if (manifold.isNotEmpty) {
        add('Manifold $manifold');
      } else if (entry.sweepInformation.trim().isNotEmpty) {
        add('Sweep ${entry.sweepInformation.trim()}');
      } else if (entry.estimatedSts != null) {
        add(
          'Estimated STS ${_formatFieldTime(entry.estimatedSts!, readingTimestamp: entry.entryTime)}',
        );
      }

      if (lines.isNotEmpty) {
        return lines;
      }
    }

    final lines = <String>[];
    void add(String value) {
      if (value.trim().isEmpty || lines.length >= 2) return;
      lines.add(value.trim());
    }

    add(entry.pumpRate.trim().isEmpty ? '' : 'Pump ${entry.pumpRate.trim()}');
    add(entry.operationStage.trim().isEmpty
        ? ''
        : 'Stage ${entry.operationStage.trim()}');
    add(entry.choke.trim().isEmpty ? '' : 'Choke ${entry.choke.trim()}');
    add(_manifoldPsiValue(entry).isEmpty
        ? ''
        : 'Manifold ${_manifoldPsiValue(entry)}');
    if (entry.estimatedSts != null && entry.sts == null) {
      add(_liveStsLabel(entry));
    }
    if (entry.sts != null) {
      add(_stsVarianceLabel(entry));
    }
    if (lines.isEmpty) {
      final compact = _compactMetrics(entry);
      if (compact.trim().isNotEmpty) {
        lines.addAll(compact.split(' • ').take(2));
      }
    }
    return lines;
  }

  int? _stsVarianceMinutes(OperationsLogEntry entry) {
    final fromStructured = entry.structuredData['stsVarianceMinutes'];
    if (fromStructured is num) return fromStructured.toInt();
    final estimated = entry.estimatedSts;
    final actual = entry.sts;
    if (estimated == null || actual == null) return null;
    return actual.difference(estimated).inMinutes;
  }

  String _stsVarianceLabel(OperationsLogEntry entry) {
    final fromStructured =
        (entry.structuredData['stsEarlyLateLabel'] as String? ?? '').trim();
    if (fromStructured.isNotEmpty) return fromStructured;
    final variance = _stsVarianceMinutes(entry);
    if (variance == null) return 'STS pending';
    if (variance == 0) return 'On time';
    if (variance > 0) return '+${variance.abs()} min Late';
    return '${variance.abs()} min Early';
  }

  Color _stsStatusColor(OperationsLogEntry entry) {
    final variance = _stsVarianceMinutes(entry);
    if (variance == null) return Colors.white60;
    final absValue = variance.abs();
    if (absValue <= 5) return Colors.greenAccent.shade400;
    if (absValue <= 15) return Colors.amberAccent;
    return Colors.redAccent;
  }

  String _liveStsLabel(OperationsLogEntry entry) {
    final estimated = entry.estimatedSts;
    if (estimated == null) return 'STS pending';
    if (entry.sts != null) return 'STS Complete • ${_stsVarianceLabel(entry)}';
    final minutes = estimated.difference(_clockNow).inMinutes;
    if (minutes > 0) return '$minutes min to STS';
    return '${minutes.abs()} min past STS';
  }

  Map<String, String> _stsDashboard() {
    final rows = _sortedEntries
        .where((entry) => entry.estimatedSts != null && entry.sts != null)
        .toList(growable: false);
    if (rows.isEmpty) {
      return const {
        'Total STS Events': '0',
        'Average Variance': '--',
        'Average Early': '--',
        'Average Late': '--',
        'Best Estimate': '--',
        'Worst Estimate': '--',
        'Within ±5 Minutes': '0',
        'Within ±10 Minutes': '0',
      };
    }
    final variances =
        rows.map((entry) => _stsVarianceMinutes(entry) ?? 0).toList();
    final early = variances.where((value) => value < 0).toList();
    final late = variances.where((value) => value > 0).toList();
    final absValues = variances.map((value) => value.abs()).toList();
    final best = absValues.reduce((a, b) => a < b ? a : b);
    final worst = absValues.reduce((a, b) => a > b ? a : b);
    final avgVariance = variances.reduce((a, b) => a + b) / variances.length;
    final avgEarly = early.isEmpty
        ? null
        : early.reduce((a, b) => a + b).abs() / early.length;
    final avgLate =
        late.isEmpty ? null : late.reduce((a, b) => a + b) / late.length;
    return {
      'Total STS Events': '${rows.length}',
      'Average Variance': '${avgVariance.round()} min',
      'Average Early': avgEarly == null ? '--' : '${avgEarly.round()} min',
      'Average Late': avgLate == null ? '--' : '${avgLate.round()} min',
      'Best Estimate': '$best min',
      'Worst Estimate': '$worst min',
      'Within ±5 Minutes': '${absValues.where((value) => value <= 5).length}',
      'Within ±10 Minutes': '${absValues.where((value) => value <= 10).length}',
    };
  }

  double? _parseValue(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(trimmed);
    if (match == null) return null;
    return double.tryParse(match.group(0) ?? '');
  }

  String _valueForColumn(OperationsLogEntry entry, String key) {
    switch (key) {
      case 'time':
        return TimeOfDay.fromDateTime(entry.entryTime).format(context);
      case 'stage':
        return entry.operationStage;
      case 'pump':
        return entry.pumpRate;
      case 'returns':
        return _returnsDisplay(entry.returnsRate);
      case 'manifold':
        return _manifoldPsiValue(entry);
      case 'casing':
        return entry.casingPressure;
      case 'pumpPsi':
        return _isLegacyManifoldFallback(entry) ? '' : entry.pumpPressure;
      case 'tubing':
        return entry.tubingPressure;
      case 'choke':
        return entry.choke;
      case 'sweep':
        return entry.sweepInformation;
      case 'water':
        return entry.waterHauled;
      case 'oil':
        return entry.oilHauled;
      case 'gas':
        return entry.gas;
      case 'sand':
        return entry.sandOrSolids;
      case 'estimatedSts':
        return entry.estimatedSts == null
            ? ''
            : _formatFieldTime(
                entry.estimatedSts!,
                readingTimestamp: entry.entryTime,
              );
      case 'actualSts':
        return entry.sts == null
            ? ''
            : _formatFieldTime(
                entry.sts!,
                readingTimestamp: entry.entryTime,
              );
      case 'notes':
        return entry.notes;
      default:
        return '';
    }
  }

  List<OperationsLogEntry> _dataEntries(
      List<({String label, String key})> columns) {
    final selectedKeys = columns
        .where((column) => column.key != 'time')
        .map((column) => column.key)
        .toList(growable: false);
    final list = List<OperationsLogEntry>.from(_visibleEntries);
    if (selectedKeys.isNotEmpty) {
      list.removeWhere((entry) {
        for (final key in selectedKeys) {
          if (_valueForColumn(entry, key).trim().isNotEmpty) {
            return false;
          }
        }
        return true;
      });
    }
    final sortField = _effectiveDataSortField(columns);
    switch (_dataSortMode) {
      case _DataSortMode.newest:
        list.sort((a, b) => b.entryTime.compareTo(a.entryTime));
        break;
      case _DataSortMode.oldest:
        list.sort((a, b) => a.entryTime.compareTo(b.entryTime));
        break;
      case _DataSortMode.highest:
      case _DataSortMode.lowest:
        list.sort((a, b) {
          final av = _parseValue(_valueForColumn(a, sortField)) ?? -999999;
          final bv = _parseValue(_valueForColumn(b, sortField)) ?? -999999;
          return _dataSortMode == _DataSortMode.highest
              ? bv.compareTo(av)
              : av.compareTo(bv);
        });
        break;
    }
    return list;
  }

  List<({String time, String value})> _focusRows() {
    final rows = <({String time, String value})>[];
    for (final entry in _visibleEntries) {
      final time = TimeOfDay.fromDateTime(entry.entryTime).format(context);
      String value = '';
      switch (_focusCategory) {
        case _FocusCategory.pump:
          value = entry.pumpRate;
          break;
        case _FocusCategory.pressures:
          value =
              'M ${_manifoldPsiValue(entry)} | C ${entry.casingPressure} | P ${_isLegacyManifoldFallback(entry) ? '' : entry.pumpPressure}';
          break;
        case _FocusCategory.tanks:
          value = entry.tankLevel;
          break;
        case _FocusCategory.gas:
          value = entry.gas;
          break;
        case _FocusCategory.sweep:
          value = entry.sweepInformation;
          break;
        case _FocusCategory.stage:
          value = entry.operationStage;
          break;
        case _FocusCategory.choke:
          value = entry.choke;
          break;
        case _FocusCategory.sts:
          value = entry.sts == null
              ? _liveStsLabel(entry)
              : _stsVarianceLabel(entry);
          break;
      }
      if (value.trim().isEmpty || value.trim() == 'M  | C  | T') continue;
      rows.add((time: time, value: value.trim()));
    }
    return rows;
  }

  double? _chartValue(OperationsLogEntry entry, _ChartMetric metric) {
    switch (metric) {
      case _ChartMetric.pumpRate:
        return _parseValue(entry.pumpRate);
      case _ChartMetric.returnsRate:
        return _parseValue(entry.returnsRate);
      case _ChartMetric.manifoldPsi:
        return _parseValue(_manifoldPsiValue(entry));
      case _ChartMetric.casingPsi:
        return _parseValue(entry.casingPressure);
      case _ChartMetric.tubingPsi:
        return _parseValue(entry.tubingPressure);
      case _ChartMetric.waterRate:
        return _parseValue(entry.waterRate);
      case _ChartMetric.oilRate:
        return _parseValue(entry.oilHauled);
      case _ChartMetric.gasRate:
        return _parseValue(entry.gas);
      case _ChartMetric.sweep:
        return _parseValue(entry.sweepInformation);
      case _ChartMetric.sand:
        return _parseValue(entry.sandOrSolids);
      case _ChartMetric.tankLevels:
        return _parseValue(entry.tankLevel);
      case _ChartMetric.stsPerformance:
        return (_stsVarianceMinutes(entry) ?? 0).toDouble();
    }
  }

  String _chartMetricLabel(_ChartMetric metric) {
    switch (metric) {
      case _ChartMetric.pumpRate:
        return 'Pump Rate';
      case _ChartMetric.returnsRate:
        return 'Returns';
      case _ChartMetric.manifoldPsi:
        return 'Manifold PSI';
      case _ChartMetric.casingPsi:
        return 'Casing PSI';
      case _ChartMetric.tubingPsi:
        return 'Tubing PSI';
      case _ChartMetric.waterRate:
        return 'Water Rate';
      case _ChartMetric.oilRate:
        return 'Oil Rate';
      case _ChartMetric.gasRate:
        return 'Gas Rate';
      case _ChartMetric.sweep:
        return 'Sweep';
      case _ChartMetric.sand:
        return 'Sand';
      case _ChartMetric.tankLevels:
        return 'Tank Levels';
      case _ChartMetric.stsPerformance:
        return 'STS Performance';
    }
  }

  Future<void> _toggleMultiSelectMode() async {
    setState(() {
      _multiSelectMode = !_multiSelectMode;
      if (!_multiSelectMode) {
        _selectedEntryIds.clear();
      }
    });
  }

  Future<void> _pickDateFilter() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateFilter ?? _clockNow,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() => _dateFilter = selected);
  }

  Future<void> _pickShiftFilter() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('All'),
              onTap: () => Navigator.of(sheetContext).pop('all'),
            ),
            ListTile(
              title: const Text('Day'),
              onTap: () => Navigator.of(sheetContext).pop('day'),
            ),
            ListTile(
              title: const Text('Night'),
              onTap: () => Navigator.of(sheetContext).pop('night'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    setState(() => _shiftFilter = selected);
  }

  String _lastUpdatedText() {
    if (_entries.isEmpty) return 'Updated: --';
    final latest = _sortedEntries.last.loggedAt;
    return 'Updated: ${TimeOfDay.fromDateTime(latest).format(context)}';
  }

  Widget _activeJobHeader(JobSetup? job) {
    Widget field(String label, String value) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _wwPanelSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }

    final customer = (job?.company ?? '').trim().isEmpty ? '--' : job!.company;
    final well = _currentWellName.trim().isEmpty ? '--' : _currentWellName;
    final activeStatus = _activeStatusForCard;
    final stage = activeStatus.trim().isEmpty ? '--' : activeStatus;
    final status =
        (job?.drilloutSetup['jobStatus'] as String? ?? job?.shift ?? '--')
            .toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _wwPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _wwGold.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Active Job',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: _wwGold,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.4,
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            children: [
              field('Customer', customer),
              field('Well', well),
              field('Status', stage),
              field('Job Status', status.trim().isEmpty ? '--' : status.trim()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(OperationsLogEntry entry) {
    final expanded = _expandedEntryIds.contains(entry.entryId);
    final isStsEntry = _isStsEntry(entry);
    final iconColor = _eventColor(entry);
    final lines = _importantLines(entry);
    final detailRows = <({String label, String value})>[
      if (!isStsEntry && entry.operationStage.trim().isNotEmpty)
        (label: 'Stage', value: entry.operationStage.trim()),
      if (isStsEntry && _stsPumpRateValue(entry).isNotEmpty)
        (label: 'Pump', value: _stsPumpRateValue(entry)),
      if (!isStsEntry && entry.pumpRate.trim().isNotEmpty)
        (label: 'Pump', value: entry.pumpRate.trim()),
      if (isStsEntry && _averageReturnRateForStsEntry(entry) != null)
        (
          label: 'Average Return',
          value:
              '${_averageReturnRateForStsEntry(entry)!.toStringAsFixed(2)} bbl/min',
        ),
      if (!isStsEntry && entry.choke.trim().isNotEmpty)
        (label: 'Choke', value: entry.choke.trim()),
      if (!isStsEntry && entry.returnsRate.trim().isNotEmpty)
        (label: 'Returns', value: _returnsDisplay(entry.returnsRate)),
      if (!isStsEntry && _manifoldPsiValue(entry).isNotEmpty)
        (label: 'Manifold', value: _manifoldPsiValue(entry)),
      if (!isStsEntry &&
          entry.pumpPressure.trim().isNotEmpty &&
          !_isLegacyManifoldFallback(entry))
        (label: 'Pump PSI', value: entry.pumpPressure.trim()),
      if (!isStsEntry && entry.casingPressure.trim().isNotEmpty)
        (label: 'Casing', value: entry.casingPressure.trim()),
      if (!isStsEntry && entry.gas.trim().isNotEmpty)
        (label: 'Gas', value: entry.gas.trim()),
      if (!isStsEntry && entry.sandOrSolids.trim().isNotEmpty)
        (label: 'Sand / Solids', value: entry.sandOrSolids.trim()),
      if (!isStsEntry && entry.waterHauled.trim().isNotEmpty)
        (label: 'Water', value: entry.waterHauled.trim()),
      if (!isStsEntry && entry.oilHauled.trim().isNotEmpty)
        (label: 'Oil', value: entry.oilHauled.trim()),
      if (!isStsEntry && entry.tankLevel.trim().isNotEmpty)
        (label: 'Tank', value: entry.tankLevel.trim()),
      if (entry.estimatedSts != null)
        (
          label: 'Estimated STS',
          value: _formatFieldTime(
            entry.estimatedSts!,
            readingTimestamp: entry.entryTime,
          ),
        ),
      if (entry.sts != null)
        (
          label: 'Actual STS',
          value: _formatFieldTime(
            entry.sts!,
            readingTimestamp: entry.entryTime,
          ),
        ),
      if (isStsEntry) (label: 'Early/Late', value: _stsVarianceLabel(entry)),
      if (!isStsEntry && entry.sweepInformation.trim().isNotEmpty)
        (label: 'Sweep', value: entry.sweepInformation.trim()),
      if (!isStsEntry && entry.equipmentStatus.trim().isNotEmpty)
        (label: 'Equipment', value: entry.equipmentStatus.trim()),
      if (!isStsEntry && entry.downtime.trim().isNotEmpty)
        (label: 'Downtime', value: entry.downtime.trim()),
    ];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
      decoration: BoxDecoration(
        color: _wwPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Stack(
              children: [
                Positioned(
                  left: 17,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Colors.white12),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _wwBlack,
                        border: Border.all(color: iconColor, width: 2),
                      ),
                      child:
                          Icon(_eventIcon(entry), size: 18, color: iconColor),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      TimeOfDay.fromDateTime(entry.entryTime).format(context),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      _dateLabel(entry.entryTime),
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_multiSelectMode)
                      Checkbox(
                        value: _selectedEntryIds.contains(entry.entryId),
                        onChanged: (value) =>
                            _toggleSelectedEntry(entry.entryId, value ?? false),
                      ),
                    Expanded(
                      child: Text(
                        _eventTitle(entry),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _toggleExpandedEntry(entry.entryId),
                      icon: AnimatedRotation(
                        duration: const Duration(milliseconds: 220),
                        turns: expanded ? 0.25 : 0,
                        child: const Icon(Icons.chevron_right),
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'share') {
                          _shareReading(entry);
                        } else if (value == 'details') {
                          _showEntryDetails(entry);
                        } else if (value == 'delete') {
                          _deleteEntry(entry);
                        } else if (value == 'edit') {
                          _editEntry(entry);
                        } else if (value == 'duplicate') {
                          _duplicateEntry(entry);
                        } else if (value == 'copy') {
                          _copyEntryAgain(entry);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'details', child: Text('View Details')),
                        PopupMenuItem(
                            value: 'share', child: Text('Share Reading')),
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                            value: 'duplicate', child: Text('Duplicate')),
                        PopupMenuItem(value: 'copy', child: Text('Copy Again')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      line,
                      style:
                          const TextStyle(fontSize: 15, color: Colors.white70),
                    ),
                  ),
                if (entry.estimatedSts != null && entry.sts == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 2),
                    child: FilledButton.icon(
                      onPressed: () => _recordStsForEntry(entry),
                      icon: const Icon(Icons.timer_outlined),
                      label: const Text('Record STS'),
                    ),
                  ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  child: expanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (entry.estimatedSts != null)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _stsStatusColor(entry)
                                          .withValues(alpha: 0.55),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Estimated ${entry.estimatedSts == null ? '--' : TimeOfDay.fromDateTime(entry.estimatedSts!).format(context)}',
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          'Actual ${entry.sts == null ? '--' : TimeOfDay.fromDateTime(entry.sts!).format(context)}',
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          _stsVarianceLabel(entry),
                                          style: TextStyle(
                                            color: _stsStatusColor(entry),
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (detailRows.isNotEmpty)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    for (final row in detailRows)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black26,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border:
                                              Border.all(color: Colors.white12),
                                        ),
                                        child: Text(
                                          '${row.label}: ${row.value}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                  ],
                                ),
                              if (entry.generatedText.trim().isNotEmpty)
                                SelectableText(
                                  entry.generatedText,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12.5,
                                  ),
                                ),
                              if (entry.notes.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text('Notes: ${entry.notes.trim()}'),
                                ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewBody() {
    if (_visibleEntries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: Text('No Operations Log readings are available.')),
      );
    }

    switch (_viewMode) {
      case _OperationsLogViewMode.timeline:
        return Column(
          children: [
            for (final entry in _timelineEntries) _buildTimelineItem(entry)
          ],
        );
      case _OperationsLogViewMode.data:
        final columns = _dataColumns();
        final rows = _dataEntries(columns);
        final sortField = _effectiveDataSortField(columns);
        final sortableColumns = columns
            .where((column) => column.key != 'time')
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                DropdownButton<_DataSortMode>(
                  value: _dataSortMode,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _dataSortMode = value);
                  },
                  items: const [
                    DropdownMenuItem(
                        value: _DataSortMode.newest, child: Text('Newest')),
                    DropdownMenuItem(
                        value: _DataSortMode.oldest, child: Text('Oldest')),
                    DropdownMenuItem(
                        value: _DataSortMode.highest, child: Text('Highest')),
                    DropdownMenuItem(
                        value: _DataSortMode.lowest, child: Text('Lowest')),
                  ],
                ),
                if (sortableColumns.isNotEmpty)
                  DropdownButton<String>(
                    value: sortField,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _dataSortField = value);
                    },
                    items: [
                      for (final col in sortableColumns)
                        DropdownMenuItem(
                            value: col.key, child: Text(col.label)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Text('No rows match selected fields and current filters.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(_wwPanelSoft),
                  columns: [
                    for (final col in columns)
                      DataColumn(label: Text(col.label))
                  ],
                  rows: [
                    for (final entry in rows)
                      DataRow(
                        onSelectChanged: (_) => _showEntryDetails(entry),
                        cells: [
                          for (final col in columns)
                            DataCell(
                              Text(
                                _valueForColumn(entry, col.key),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        );
      case _OperationsLogViewMode.focus:
        final rows = _focusRows();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<_FocusCategory>(
              value: _focusCategory,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _focusCategory = value);
              },
              items: const [
                DropdownMenuItem(
                    value: _FocusCategory.pump, child: Text('Pump')),
                DropdownMenuItem(
                    value: _FocusCategory.pressures, child: Text('Pressures')),
                DropdownMenuItem(
                    value: _FocusCategory.tanks, child: Text('Tanks')),
                DropdownMenuItem(value: _FocusCategory.gas, child: Text('Gas')),
                DropdownMenuItem(
                    value: _FocusCategory.sweep, child: Text('Sweep')),
                DropdownMenuItem(
                    value: _FocusCategory.stage, child: Text('Stage')),
                DropdownMenuItem(
                    value: _FocusCategory.choke, child: Text('Choke')),
                DropdownMenuItem(value: _FocusCategory.sts, child: Text('STS')),
              ],
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Text('No values available for this focus category.')
            else
              Container(
                decoration: BoxDecoration(
                  color: _wwPanel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    for (final row in rows)
                      ListTile(
                        title: Text(
                          row.time,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(row.value),
                      ),
                  ],
                ),
              ),
          ],
        );
      case _OperationsLogViewMode.charts:
        final spots = <FlSpot>[];
        var index = 0;
        for (final entry in _visibleEntries) {
          final value = _chartValue(entry, _chartMetric);
          if (value == null) continue;
          spots.add(FlSpot(index.toDouble(), value));
          index += 1;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<_ChartMetric>(
              value: _chartMetric,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _chartMetric = value);
              },
              items: [
                for (final metric in _ChartMetric.values)
                  DropdownMenuItem(
                    value: metric,
                    child: Text(_chartMetricLabel(metric)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (spots.isEmpty)
              const Text('No numeric data available for this chart yet.')
            else
              Container(
                height: 280,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _wwPanel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: LineChart(
                  LineChartData(
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: _wwGold,
                        barWidth: 3,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: _wwGold.withValues(alpha: 0.18),
                        ),
                      ),
                    ],
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(color: Colors.white10),
                    ),
                    gridData:
                        const FlGridData(show: true, drawVerticalLine: false),
                    titlesData: const FlTitlesData(
                      rightTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                  ),
                ),
              ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _activeJob;
    final stats = _stsDashboard();
    return Scaffold(
      appBar: AppHeader(title: widget.title, showBack: true),
      backgroundColor: _wwBlack,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _activeJobHeader(job),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _wwPanel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _toggleMultiSelectMode,
                        icon: Icon(
                            _multiSelectMode ? Icons.close : Icons.checklist),
                        label:
                            Text(_multiSelectMode ? 'Exit Select' : 'Select'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _shareSelectedReadings,
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('Share Selected'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _importReading,
                        icon: const Icon(Icons.import_export),
                        label: const Text('Import Reading'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: const Key('operations-log-customize-fields-button'),
                    onPressed: _customizeFields,
                    child: const Text('Customize Fields'),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<_OperationsLogViewMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _OperationsLogViewMode.timeline,
                      label: Text('Timeline'),
                    ),
                    ButtonSegment(
                      value: _OperationsLogViewMode.data,
                      label: Text('Data'),
                    ),
                    ButtonSegment(
                      value: _OperationsLogViewMode.focus,
                      label: Text('Focus'),
                    ),
                    ButtonSegment(
                      value: _OperationsLogViewMode.charts,
                      label: Text('Charts'),
                    ),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (selection) {
                    setState(() => _viewMode = selection.first);
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in _OperationsSmartFilter.values)
                      ChoiceChip(
                        selected: _smartFilter == filter,
                        label: Text(
                          switch (filter) {
                            _OperationsSmartFilter.all => 'All',
                            _OperationsSmartFilter.manual => 'Manual',
                            _OperationsSmartFilter.textUpdates =>
                              'Text Updates',
                            _OperationsSmartFilter.shiftChanges =>
                              'Shift Changes',
                            _OperationsSmartFilter.reports => 'Reports',
                            _OperationsSmartFilter.sts => 'STS',
                            _OperationsSmartFilter.rates => 'Rates',
                            _OperationsSmartFilter.pressureChanges =>
                              'Pressure Changes',
                            _OperationsSmartFilter.chokeChanges =>
                              'Choke Changes',
                            _OperationsSmartFilter.stageChanges =>
                              'Stage Changes',
                          },
                        ),
                        onSelected: (_) =>
                            setState(() => _smartFilter = filter),
                      ),
                    OutlinedButton(
                      onPressed: _pickDateFilter,
                      child: Text(
                        _dateFilter == null
                            ? 'Date'
                            : MaterialLocalizations.of(context)
                                .formatCompactDate(_dateFilter!),
                      ),
                    ),
                    if (_dateFilter != null)
                      OutlinedButton(
                        onPressed: () => setState(() => _dateFilter = null),
                        child: const Text('Clear Date'),
                      ),
                    OutlinedButton(
                      onPressed: _pickShiftFilter,
                      child: Text(
                          'Shift: ${_shiftFilter == 'all' ? 'All' : _shiftFilter}'),
                    ),
                    DropdownButton<bool>(
                      value: _timelineNewestFirst,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _timelineNewestFirst = value);
                      },
                      items: const [
                        DropdownMenuItem<bool>(
                          value: true,
                          child: Text('Newest First'),
                        ),
                        DropdownMenuItem<bool>(
                          value: false,
                          child: Text('Oldest First'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_viewMode == _OperationsLogViewMode.charts)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _wwPanel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final item in stats.entries)
                          Container(
                            width: 170,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.key,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white60,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.value,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _viewBody(),
                ),
                const SizedBox(height: 96),
              ],
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: _wwPanel,
          border:
              Border(top: BorderSide(color: _wwGold.withValues(alpha: 0.25))),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_lastUpdatedText()} • ${_visibleEntries.length} entries',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  key: const Key('operations-log-add-entry-button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _wwGold,
                    foregroundColor: Colors.black,
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  onPressed: _openAddEntryMenu,
                  icon: const Icon(Icons.add),
                  label: const Text('+ Add Entry'),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Text Time: ${_reportTimeLabel()}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  OutlinedButton.icon(
                    key: const Key('operations-log-action-edit-text-time'),
                    onPressed: _editReportTime,
                    icon: const Icon(Icons.schedule),
                    label: const Text('Edit Time'),
                  ),
                  if (_reportTimeOverride != null)
                    OutlinedButton(
                      key: const Key('operations-log-action-clear-text-time'),
                      onPressed: () =>
                          setState(() => _reportTimeOverride = null),
                      child: const Text('Use Current'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (_workflow == OperationsLogWorkflow.drillout)
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Include Tank Inventory in Text Update',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    Switch(
                      key: const Key(
                          'operations-log-toggle-drillout-tank-inventory'),
                      value: _includeTankInventoryInDrilloutTextUpdate,
                      onChanged: (value) {
                        setState(() {
                          _includeTankInventoryInDrilloutTextUpdate = value;
                        });
                      },
                    ),
                  ],
                ),
              if (_workflow == OperationsLogWorkflow.drillout)
                const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    key: const Key(
                        'operations-log-action-generate-shift-update'),
                    onPressed: _generateShiftUpdateAction,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Shift Change Text'),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('operations-log-action-preview-text'),
                    onPressed: _previewTextAction,
                    icon: const Icon(Icons.preview_outlined),
                    label: const Text('Preview Text Update'),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('operations-log-action-copy-update'),
                    onPressed: _copyUpdateAction,
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy Text Update'),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('operations-log-action-share'),
                    onPressed: _shareUpdateAction,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share Text Update'),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('operations-log-action-export'),
                    onPressed: _exportTimelineAction,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Export PDF'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
