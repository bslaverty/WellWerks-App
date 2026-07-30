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

enum _OperationsEntryFilter {
  all,
  manualReadings,
  textUpdates,
  shiftChanges,
  imports,
  handoffs,
}

enum _ReportDataSource {
  latest,
  selected,
  lastThree,
  entireShift,
}

class _OperationsLogScreenState extends State<OperationsLogScreen> {
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
  bool _newestFirst = false;
  bool _expandedTimeline = false;
  _OperationsEntryFilter _entryFilter = _OperationsEntryFilter.all;
  Set<String> _expandedEntryIds = <String>{};
  String _lastFinalizedReportKey = '';

  @override
  void initState() {
    super.initState();
    _jobStorage.activeJobListenable.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    _jobStorage.activeJobListenable.removeListener(_reload);
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
    items.sort((a, b) {
      final compare = a.entryTime.compareTo(b.entryTime);
      return _newestFirst ? -compare : compare;
    });
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
    switch (_entryFilter) {
      case _OperationsEntryFilter.all:
        return true;
      case _OperationsEntryFilter.manualReadings:
        return type == 'manualReading';
      case _OperationsEntryFilter.textUpdates:
        return type == 'textUpdate';
      case _OperationsEntryFilter.shiftChanges:
        return type == 'shiftChange';
      case _OperationsEntryFilter.imports:
        return type == 'qrImport' || entry.isImported;
      case _OperationsEntryFilter.handoffs:
        return type == 'handoffImport';
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
        Text('Returns rate: ${entry.returnsRate}'),
      if (_enabledFieldIds.contains('casingPressure') &&
          entry.casingPressure.isNotEmpty)
        Text('Casing pressure: ${entry.casingPressure}'),
      if (_enabledFieldIds.contains('pumpPressure') &&
          entry.pumpPressure.isNotEmpty)
        Text('Pump pressure: ${entry.pumpPressure}'),
      if (_enabledFieldIds.contains('tubingPressure') &&
          entry.tubingPressure.isNotEmpty)
        Text('Tubing pressure: ${entry.tubingPressure}'),
      if (_enabledFieldIds.contains('notes') && entry.notes.isNotEmpty)
        Text('Notes: ${entry.notes}'),
      if (_enabledFieldIds.contains('gas') && entry.gas.isNotEmpty)
        Text('Gas: ${entry.gas}'),
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

  Future<void> _editEntry(OperationsLogEntry entry) async {
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
      parts.add('Returns ${entry.returnsRate}');
    }
    if (_enabledFieldIds.contains('casingPressure') &&
        entry.casingPressure.isNotEmpty) {
      parts.add('CSG ${entry.casingPressure}');
    }
    if (_enabledFieldIds.contains('pumpPressure') &&
        entry.pumpPressure.isNotEmpty) {
      parts.add('PMP ${entry.pumpPressure}');
    }
    if (_enabledFieldIds.contains('notes') && entry.notes.isNotEmpty) {
      parts.add(entry.notes);
    }
    if (_enabledFieldIds.contains('gas') && entry.gas.isNotEmpty) {
      parts.add('Gas ${entry.gas}');
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

  @override
  Widget build(BuildContext context) {
    final job = _activeJob;
    return Scaffold(
      appBar: AppHeader(title: widget.title, showBack: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _infoCard(
                  'Current job',
                  job?.padName.isNotEmpty == true
                      ? job!.padName
                      : 'No active job',
                ),
                _infoCard('Selected well', _currentWellName),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _addReading,
                        child: const Text('Add Reading'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _shareSelectedReadings,
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('Share Selected'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _openCreateReportMenu,
                  child: const Text('Create Report'),
                ),
                const SizedBox(height: 12),
                if (_currentStage.isNotEmpty)
                  _infoCard('Current stage', _currentStage),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _customizeFields,
                    icon: const Icon(Icons.tune),
                    label: const Text('Customize Fields'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _importReading,
                    icon: const Icon(Icons.import_export),
                    label: const Text('Import Reading'),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _newestFirst,
                  onChanged: (value) => setState(() => _newestFirst = value),
                  title: const Text('Newest first'),
                  subtitle: const Text('Turn off for oldest first.'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _expandedTimeline,
                  onChanged: (value) =>
                      setState(() => _expandedTimeline = value),
                  title: const Text('Expanded timeline cards'),
                  subtitle: const Text('Turn off for compact cards.'),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      selected: _entryFilter == _OperationsEntryFilter.all,
                      label: const Text('All Entries'),
                      onSelected: (_) => setState(
                          () => _entryFilter = _OperationsEntryFilter.all),
                    ),
                    ChoiceChip(
                      selected:
                          _entryFilter == _OperationsEntryFilter.manualReadings,
                      label: const Text('Manual Readings'),
                      onSelected: (_) => setState(
                        () => _entryFilter =
                            _OperationsEntryFilter.manualReadings,
                      ),
                    ),
                    ChoiceChip(
                      selected:
                          _entryFilter == _OperationsEntryFilter.textUpdates,
                      label: const Text('Text Updates'),
                      onSelected: (_) => setState(
                        () => _entryFilter = _OperationsEntryFilter.textUpdates,
                      ),
                    ),
                    ChoiceChip(
                      selected:
                          _entryFilter == _OperationsEntryFilter.shiftChanges,
                      label: const Text('Shift Changes'),
                      onSelected: (_) => setState(
                        () =>
                            _entryFilter = _OperationsEntryFilter.shiftChanges,
                      ),
                    ),
                    ChoiceChip(
                      selected: _entryFilter == _OperationsEntryFilter.imports,
                      label: const Text('Imports'),
                      onSelected: (_) => setState(
                        () => _entryFilter = _OperationsEntryFilter.imports,
                      ),
                    ),
                    ChoiceChip(
                      selected: _entryFilter == _OperationsEntryFilter.handoffs,
                      label: const Text('Handoffs'),
                      onSelected: (_) => setState(
                        () => _entryFilter = _OperationsEntryFilter.handoffs,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 16),
                if (_visibleEntries.isEmpty)
                  const Text('No Operations Log readings are available.')
                else
                  ..._visibleEntries.map(
                    (entry) => Card(
                      child: InkWell(
                        onTap: () => _toggleExpandedEntry(entry.entryId),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Checkbox(
                                    value: _selectedEntryIds
                                        .contains(entry.entryId),
                                    onChanged: (value) => _toggleSelectedEntry(
                                      entry.entryId,
                                      value ?? false,
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${TimeOfDay.fromDateTime(entry.entryTime).format(context)} • ${_entryTypeLabel(entry)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _compactMetrics(entry),
                                            maxLines:
                                                _expandedTimeline ? null : 2,
                                            overflow: _expandedTimeline
                                                ? TextOverflow.visible
                                                : TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
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
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'details',
                                        child: Text('View Details'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'share',
                                        child: Text('Share Reading'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (_expandedTimeline ||
                                  _expandedEntryIds.contains(entry.entryId))
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(48, 2, 10, 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (entry.generatedText.trim().isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: SelectableText(
                                            entry.generatedText,
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ),
                                      if (entry.notes.trim().isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: Text(
                                              'Notes: ${entry.notes.trim()}'),
                                        ),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: () => _editEntry(entry),
                                            icon:
                                                const Icon(Icons.edit_outlined),
                                            label: const Text('Edit'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: () =>
                                                _duplicateEntry(entry),
                                            icon: const Icon(Icons.copy_all),
                                            label: const Text('Duplicate'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: () =>
                                                _deleteEntry(entry),
                                            icon: const Icon(
                                                Icons.delete_outline),
                                            label: const Text('Delete'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: () =>
                                                _shareReading(entry),
                                            icon: const Icon(Icons.qr_code_2),
                                            label: const Text('Share QR'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: () =>
                                                _copyEntryAgain(entry),
                                            icon:
                                                const Icon(Icons.copy_outlined),
                                            label: const Text('Copy Again'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _infoCard(String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(value),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
