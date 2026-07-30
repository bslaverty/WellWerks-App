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
import 'operations_log_entry_form_screen.dart';
import 'operations_log_sts_entry_screen.dart';
import 'wellwerks_qr_scanner_screen.dart';

class OperationsLogScreen extends StatefulWidget {
  const OperationsLogScreen({
    super.key,
    this.workflow,
    this.title = 'Operations Log',
  });

  final OperationsLogWorkflow? workflow;
  final String title;

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
  Timer? _clockTicker;

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

  String get _currentWellName {
    final job = _activeJob;
    if (job == null) return 'No active job';
    return job.primaryWell.isNotEmpty ? job.primaryWell : job.padName;
  }

  String get _currentStage {
    final job = _activeJob;
    if (job == null) return '';
    final setup = job.drilloutSetup;
    return (setup['status'] as String? ?? setup['stage'] as String? ?? '')
        .trim();
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
    return _sortedEntries.where(_matchesFilter).toList(growable: false);
  }

  String _entryTypeValue(OperationsLogEntry entry) {
    final raw = entry.entryType.trim();
    if (raw.isNotEmpty) return raw;
    if (entry.isImported) return 'qrImport';
    return 'manualReading';
  }

  String _entryTypeLabel(OperationsLogEntry entry) {
    switch (_entryTypeValue(entry)) {
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
        return type == 'manualReading';
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
            initialSelectedWellId:
                _resolvedWells.isNotEmpty ? _resolvedWells.first.id : '',
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

  OperationsLogEntry? _oldestOpenEstimatedStsEntry() {
    final open = _sortedEntries
        .where((entry) => entry.estimatedSts != null && entry.sts == null)
        .toList(growable: false)
      ..sort((a, b) {
        final byEstimated = a.estimatedSts!.compareTo(b.estimatedSts!);
        if (byEstimated != 0) return byEstimated;
        return a.entryTime.compareTo(b.entryTime);
      });
    if (open.isEmpty) return null;
    return open.first;
  }

  double? _parseNumericValue(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(trimmed);
    if (match == null) return null;
    return double.tryParse(match.group(0) ?? '');
  }

  double? _mostRecentAverageReturnRate() {
    for (final item in _sortedEntries.reversed) {
      final parsed = _parseNumericValue(item.returnsRate);
      if (parsed != null) return parsed;
    }
    return null;
  }

  double? _averageReturnRateForStsEntry(OperationsLogEntry entry) {
    final fromStructured = entry.structuredData['stsAverageReturnRate'];
    if (fromStructured is num) return fromStructured.toDouble();
    final parsed = _parseNumericValue(entry.returnsRate);
    if (parsed != null) return parsed;
    return _mostRecentAverageReturnRate();
  }

  double? _estimatedStsDurationMinutes(OperationsLogEntry entry) {
    if (entry.estimatedSts == null) return null;
    final seconds = entry.estimatedSts!.difference(entry.entryTime).inSeconds;
    if (seconds <= 0) return null;
    return seconds / 60;
  }

  double? _actualStsDurationMinutes(
    OperationsLogEntry entry,
    DateTime actualSts,
  ) {
    final seconds = actualSts.difference(entry.entryTime).inSeconds;
    if (seconds <= 0) return null;
    return seconds / 60;
  }

  double? _storedAdjustedAverageReturnRate(OperationsLogEntry entry) {
    final raw = entry.structuredData['stsAdjustedAverageReturnRate'];
    if (raw is num) return raw.toDouble();
    return null;
  }

  Future<void> _completeStsEntry({
    required OperationsLogEntry entry,
    required DateTime actualSts,
    required String notes,
    required double? averageReturnRate,
  }) async {
    final job = _activeJob;
    if (job == null) return;

    final estimatedDuration = _estimatedStsDurationMinutes(entry);
    final actualDuration = _actualStsDurationMinutes(entry, actualSts);
    double? adjusted;
    if (averageReturnRate != null &&
        estimatedDuration != null &&
        actualDuration != null &&
        actualDuration > 0) {
      adjusted = averageReturnRate * (estimatedDuration / actualDuration);
    }

    final structured = Map<String, dynamic>.from(entry.structuredData);
    if (averageReturnRate != null) {
      structured['stsAverageReturnRate'] = averageReturnRate;
    }
    if (estimatedDuration != null) {
      structured['stsEstimatedDurationMinutes'] = estimatedDuration;
    }
    if (actualDuration != null) {
      structured['stsActualDurationMinutes'] = actualDuration;
    }
    if (adjusted != null) {
      structured['stsAdjustedAverageReturnRate'] = adjusted;
    }

    var updated = entry.copyWith(
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
    await _load();
  }

  Future<void> _addSts() async {
    final target = _oldestOpenEstimatedStsEntry();
    if (target == null || target.estimatedSts == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending STS entries are available.')),
      );
      return;
    }

    final pumpRate = target.pumpRate.trim().isEmpty
        ? _latestKnownValue((entry) => entry.pumpRate)
        : target.pumpRate.trim();
    final averageReturns = _averageReturnRateForStsEntry(target);
    final result = await Navigator.of(context).push<OperationsLogStsEntryResult>(
      MaterialPageRoute(
        builder: (_) => OperationsLogStsEntryScreen(
          estimatedSts: target.estimatedSts!,
          pumpRate: pumpRate,
          averageReturnRate: averageReturns,
          initialActualSts: DateTime.now(),
          initialNotes: target.notes,
        ),
      ),
    );
    if (result == null) return;

    await _completeStsEntry(
      entry: target,
      actualSts: result.actualSts,
      notes: result.notes,
      averageReturnRate: averageReturns,
    );
  }

  Future<void> _showEntryDetails(OperationsLogEntry entry) async {
    final rows = <Widget>[
      Text('Entry Time: ${entry.entryTime.toLocal()}'),
      Text('Logged At: ${entry.loggedAt.toLocal()}'),
      if ((entry.structuredData['sharedVia'] as String? ?? '')
          .trim()
          .isNotEmpty)
        Text('Shared Via: ${entry.structuredData['sharedVia']}'),
      if (_enabledFieldIds.contains('operationStage') &&
          entry.operationStage.isNotEmpty)
        Text('Operation: ${entry.operationStage}'),
      if (_enabledFieldIds.contains('pumpRate') && entry.pumpRate.isNotEmpty)
        Text('Pump rate: ${entry.pumpRate}'),
      if (_enabledFieldIds.contains('returnsRate') &&
          entry.returnsRate.isNotEmpty)
        Text('Returns: ${_returnsDisplay(entry.returnsRate)}'),
      if (_enabledFieldIds.contains('casingPressure') &&
          entry.casingPressure.isNotEmpty)
        Text('Casing pressure: ${entry.casingPressure}'),
      if (_enabledFieldIds.contains('tubingPressure') &&
          _manifoldPsiValue(entry).isNotEmpty)
        Text('Manifold PSI: ${_manifoldPsiValue(entry)}'),
      if (_enabledFieldIds.contains('pumpPressure') &&
          entry.pumpPressure.isNotEmpty &&
          !_isLegacyManifoldFallback(entry))
        Text('Pump PSI: ${entry.pumpPressure}'),
      if (_enabledFieldIds.contains('notes') && entry.notes.isNotEmpty)
        Text('Notes: ${entry.notes}'),
      if (_enabledFieldIds.contains('gas') && entry.gas.isNotEmpty)
        Text('Gas: ${entry.gas}'),
      if (_enabledFieldIds.contains('waterHauled') &&
          entry.waterHauled.isNotEmpty)
        Text('Water Hauled: ${entry.waterHauled}'),
      if (_enabledFieldIds.contains('oilHauled') && entry.oilHauled.isNotEmpty)
        Text('Oil Hauled: ${entry.oilHauled}'),
      if (_enabledFieldIds.contains('sandOrSolids') &&
          entry.sandOrSolids.isNotEmpty)
        Text('Sand / Solids: ${entry.sandOrSolids}'),
      if (_enabledFieldIds.contains('choke') && entry.choke.isNotEmpty)
        Text('Choke: ${entry.choke}'),
      if (_enabledFieldIds.contains('estimatedSts') &&
          entry.estimatedSts != null)
        Text(
          'Estimated STS: ${_formatFieldTime(entry.estimatedSts!, readingTimestamp: entry.entryTime)}',
        ),
      if (_enabledFieldIds.contains('sts') && entry.sts != null)
        Text(
          'STS: ${_formatFieldTime(entry.sts!, readingTimestamp: entry.entryTime)}',
        ),
      if (entry.sweepInformation.isNotEmpty)
        Text('Legacy Sweep Information: ${entry.sweepInformation}'),
      if (_enabledFieldIds.contains('tankLevel') && entry.tankLevel.isNotEmpty)
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
      if (entry.generatedText.trim().isNotEmpty) {
        lines.add(entry.generatedText.trim());
      }
      lines.add('');
    }
    return lines.join('\n').trim();
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
      wellId: latest?.persistentWellId ??
          (job.wellIds.isEmpty ? '' : job.wellIds.first),
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

  Future<void> _previewAndFinalizeReport({
    required String reportType,
    required List<OperationsLogEntry> entries,
    required _ReportDataSource source,
  }) async {
    final reportText =
        _buildReportPreview(reportType: reportType, entries: entries);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$reportType Preview'),
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
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await Clipboard.setData(ClipboardData(text: reportText));
              await _finalizeReportAction(
                reportType: reportType,
                shareMethod: 'copyText',
                reportText: reportText,
                source: source,
              );
            },
            child: const Text('Copy Text'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await Share.share(reportText, subject: '$reportType - WellWerks');
              await _finalizeReportAction(
                reportType: reportType,
                shareMethod: 'message',
                reportText: reportText,
                source: source,
              );
            },
            child: const Text('Message'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _finalizeReportAction(
                reportType: reportType,
                shareMethod: 'qr',
                reportText: reportText,
                source: source,
              );
            },
            child: const Text('Share QR'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateReportMenu() async {
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Create Report',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('Choose output from current operations readings.'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Shift Change Report'),
              onTap: () => Navigator.of(sheetContext).pop('shift'),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Text Update'),
              onTap: () => Navigator.of(sheetContext).pop('text'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Operations Report'),
              onTap: () => Navigator.of(sheetContext).pop('operations'),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('QR Handoff'),
              onTap: () => Navigator.of(sheetContext).pop('handoff'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    if (_entries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('At least one reading is required to create a report.'),
        ),
      );
      return;
    }

    final source = await _chooseReportDataSource();
    if (source == null) return;
    final sourceEntries = _entriesForReportSource(source);

    switch (choice) {
      case 'shift':
        await _previewAndFinalizeReport(
          reportType: 'Shift Change Report',
          entries: sourceEntries,
          source: source,
        );
        break;
      case 'text':
        await _previewAndFinalizeReport(
          reportType: 'Text Update',
          entries: sourceEntries,
          source: source,
        );
        break;
      case 'operations':
        await _previewAndFinalizeReport(
          reportType: 'Operations Report',
          entries: sourceEntries,
          source: source,
        );
        break;
      case 'handoff':
        await _previewAndFinalizeReport(
          reportType: 'QR Handoff',
          entries: sourceEntries,
          source: source,
        );
        break;
    }
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
    if (entry.estimatedSts == null) return;
    final averageReturns = _averageReturnRateForStsEntry(entry);
    final result = await Navigator.of(context).push<OperationsLogStsEntryResult>(
      MaterialPageRoute(
        builder: (_) => OperationsLogStsEntryScreen(
          estimatedSts: entry.estimatedSts!,
          pumpRate: entry.pumpRate,
          averageReturnRate: averageReturns,
          initialActualSts: entry.sts ?? DateTime.now(),
          initialNotes: entry.notes,
        ),
      ),
    );
    if (result == null) return;
    await _completeStsEntry(
      entry: entry,
      actualSts: result.actualSts,
      notes: result.notes,
      averageReturnRate: averageReturns,
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
      parts.add('Legacy Sweep ${entry.sweepInformation}');
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

  String _latestKnownValue(String Function(OperationsLogEntry entry) selector) {
    for (final item in _sortedEntries.reversed) {
      final value = selector(item).trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
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
    final estimated = entry.estimatedSts;
    final actual = entry.sts;
    if (estimated == null || actual == null) return null;
    return actual.difference(estimated).inMinutes;
  }

  String _stsVarianceLabel(OperationsLogEntry entry) {
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
    final stage = _currentStage.trim().isEmpty ? '--' : _currentStage;
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
              field('Stage', stage),
              field('Job Status', status.trim().isEmpty ? '--' : status.trim()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _foundationCards() {
    final latest = _sortedEntries.isEmpty ? null : _sortedEntries.last;
    final latestKnownManifold =
        _latestKnownValue((entry) => _manifoldPsiValue(entry));
    final latestKnownChoke = _latestKnownValue((entry) => entry.choke);
    final latestKnownReturns = _latestKnownValue((entry) => entry.returnsRate);
    final latestTextUpdate = _sortedEntries.reversed
        .where((entry) => _entryTypeValue(entry) == 'textUpdate')
        .toList(growable: false);
    final cards = <({String title, String value})>[
      (
        title: 'Current Pump',
        value:
            latest?.pumpRate.trim().isNotEmpty == true ? latest!.pumpRate : '--'
      ),
      (
        title: 'Current Manifold',
        value: latestKnownManifold.isEmpty ? '--' : latestKnownManifold
      ),
      (
        title: 'Current Returns',
        value: latestKnownReturns.isEmpty
            ? '--'
            : _returnsDisplay(latestKnownReturns)
      ),
      (
        title: 'Current Stage',
        value: latest?.operationStage.trim().isNotEmpty == true
            ? latest!.operationStage
            : '--'
      ),
      (
        title: 'Current Choke',
        value: latestKnownChoke.isEmpty ? '--' : latestKnownChoke
      ),
      (
        title: 'Current STS Status',
        value: latest == null ? '--' : _liveStsLabel(latest)
      ),
      (
        title: 'Current Tank Status',
        value: latest?.tankLevel.trim().isNotEmpty == true
            ? latest!.tankLevel
            : '--'
      ),
      (
        title: 'Latest Reading',
        value: latest == null
            ? '--'
            : '${TimeOfDay.fromDateTime(latest.entryTime).format(context)} ${latest.wellName}'
      ),
      (
        title: 'Latest Text Update',
        value: latestTextUpdate.isEmpty
            ? '--'
            : (latestTextUpdate.first.generatedText.trim().isEmpty
                ? '--'
                : latestTextUpdate.first.generatedText.trim().split('\n').first)
      ),
    ];

    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final card = cards[index];
          return Container(
            width: 220,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _wwPanel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Text(
                    card.value,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: cards.length,
      ),
    );
  }

  Widget _buildTimelineItem(OperationsLogEntry entry) {
    final expanded = _expandedEntryIds.contains(entry.entryId);
    final iconColor = _eventColor(entry);
    final lines = _importantLines(entry);
    final detailRows = <({String label, String value})>[
      if (entry.operationStage.trim().isNotEmpty)
        (label: 'Stage', value: entry.operationStage.trim()),
      if (entry.pumpRate.trim().isNotEmpty)
        (label: 'Pump', value: entry.pumpRate.trim()),
      if (entry.choke.trim().isNotEmpty)
        (label: 'Choke', value: entry.choke.trim()),
      if (entry.returnsRate.trim().isNotEmpty)
        (label: 'Returns', value: _returnsDisplay(entry.returnsRate)),
      if (_manifoldPsiValue(entry).isNotEmpty)
        (label: 'Manifold', value: _manifoldPsiValue(entry)),
      if (entry.pumpPressure.trim().isNotEmpty &&
          !_isLegacyManifoldFallback(entry))
        (label: 'Pump PSI', value: entry.pumpPressure.trim()),
      if (entry.casingPressure.trim().isNotEmpty)
        (label: 'Casing', value: entry.casingPressure.trim()),
      if (entry.gas.trim().isNotEmpty) (label: 'Gas', value: entry.gas.trim()),
      if (entry.sandOrSolids.trim().isNotEmpty)
        (label: 'Sand / Solids', value: entry.sandOrSolids.trim()),
      if (entry.waterHauled.trim().isNotEmpty)
        (label: 'Water', value: entry.waterHauled.trim()),
      if (entry.oilHauled.trim().isNotEmpty)
        (label: 'Oil', value: entry.oilHauled.trim()),
      if (entry.tankLevel.trim().isNotEmpty)
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
      if (entry.sweepInformation.trim().isNotEmpty)
        (label: 'Sweep', value: entry.sweepInformation.trim()),
      if (entry.equipmentStatus.trim().isNotEmpty)
        (label: 'Equipment', value: entry.equipmentStatus.trim()),
      if (entry.downtime.trim().isNotEmpty)
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
                                      Expanded(
                                        child: Text(
                                          'Adj Avg ${_storedAdjustedAverageReturnRate(entry)?.toStringAsFixed(2) ?? '--'} bbl/min',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
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
                _foundationCards(),
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
                      FilledButton(
                        onPressed: _openCreateReportMenu,
                        child: const Text('Create Report'),
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
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _wwGold,
                          foregroundColor: Colors.black,
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        onPressed: _addReading,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Reading'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _wwGold,
                          foregroundColor: Colors.black,
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        onPressed: _addSts,
                        icon: const Icon(Icons.timer_outlined),
                        label: const Text('Add STS'),
                      ),
                    ),
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
