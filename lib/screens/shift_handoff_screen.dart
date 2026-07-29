import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
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
import '../services/wellwerks_qr_transfer_service.dart';
import '../widgets/app_header.dart';
import 'package:intl/intl.dart';
import 'wellwerks_qr_scanner_screen.dart';

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
  final _qrTransferService = const WellWerksQrTransferService();
  final _imagePicker = ImagePicker();

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

  bool get _isDrilloutCleanoutWorkflow {
    return _workflowMode == ActiveWorkflowMode.drillout ||
        _workflowMode == ActiveWorkflowMode.cleanout;
  }

  String _activeHandoffWorkflowLabel([JobSetup? job]) {
    final workflow =
        (job?.workflow ?? _activeJob?.workflow ?? '').trim().toLowerCase();
    if (workflow == 'cleanout') return 'Cleanout';
    return 'Drillout';
  }

  Future<void> _showShareQrDialog({
    required String title,
    required String qrValue,
    required Future<void> Function(BuildContext shareContext) onShare,
  }) async {
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
              style: TextStyle(color: Colors.white70),
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
                  await onShare(buttonContext);
                } catch (error, stackTrace) {
                  debugPrint(
                    '[ShiftHandoff] Failed to share QR image: $error\n$stackTrace',
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

  Future<void> _shareQrImage({
    required String qrValue,
    required String fileName,
    required String subject,
    required BuildContext shareContext,
  }) async {
    final result = await _qrTransferService.shareQrPng(
      qrValue: qrValue,
      fileName: fileName,
      shareContext: shareContext,
      subject: subject,
    );
    if (result.status == ShareResultStatus.dismissed) {
      return;
    }
  }

  Future<String?> _chooseImportMethod(String title) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop('photos'),
            child: const Text('Choose QR from Photos'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('scan'),
            child: const Text('Scan QR'),
          ),
        ],
      ),
    );
  }

  Future<String?> _scanQrFromCamera(String title) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WellWerksQrScannerScreen(
          title: title,
          prompt: 'Center the handoff QR code in view.',
        ),
      ),
    );
  }

  Future<String?> _scanQrFromPhotos() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    return _qrTransferService.decodeFirstQrFromImagePath(picked.path);
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
              title: const Text('Resolve Import Conflicts'),
              content: SizedBox(
                width: 520,
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
                              setInnerState(() {
                                selectedImported.clear();
                              });
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
      final qrValue = _qrTransferService.encodeStructuredPayload(encoded);
      _qrTransferService.ensureSingleQrCapacity(qrValue);
      _qrTransferService.decodeStructuredPayload(qrValue);

      final pad = (_activeJob?.padName ?? _shift.header.pad)
          .trim()
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final base = pad.isEmpty ? 'job' : pad;

      if (!mounted) return;
      await _showShareQrDialog(
        title: 'Share Production Handoff',
        qrValue: qrValue,
        onShare: (shareContext) => _shareQrImage(
          qrValue: qrValue,
          fileName:
              'WellWerks_Production_Handoff_${_qrTransferService.sanitizeFilePart(base)}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.png',
          subject: 'WellWerks Production Handoff - $base',
          shareContext: shareContext,
        ),
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
        const SnackBar(content: Text('Production handoff QR ready.')),
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
        const SnackBar(content: Text('The QR image could not be shared.')),
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
      final method = await _chooseImportMethod('Import Production Handoff');
      if (!mounted || method == null) return;

      final scanned = method == 'scan'
          ? await _scanQrFromCamera('Scan Production Handoff QR')
          : await _scanQrFromPhotos();
      if (scanned == null || scanned.trim().isEmpty) {
        if (method == 'photos') {
          throw const FormatException('No QR code was found in that image.');
        }
        return;
      }

      final raw = _qrTransferService.decodeStructuredPayload(scanned);
      final header = _packageRouter.decodeHeader(raw);
      if (header.type != WellWerksPackageType.productionHandoff) {
        throw const FormatException(
            'This is a Job Setup QR. Open Import Job Setup to use it.');
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
        const SnackBar(content: Text('This QR code is incomplete or damaged.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportWorkflowHandoff() async {
    final activeJob = _activeJob;
    if (activeJob == null || _busy) return;
    setState(() => _busy = true);
    try {
      final package = await _drilloutHandoffService.buildPackage(
        activeJob: activeJob,
      );
      final encoded = _drilloutHandoffService.encodePackage(package);
      final qrValue = _qrTransferService.encodeStructuredPayload(encoded);
      _qrTransferService.ensureSingleQrCapacity(qrValue);
      _qrTransferService.decodeStructuredPayload(qrValue);

      final pad =
          activeJob.padName.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final base = pad.isEmpty ? 'job' : pad;
      final workflowLabel = _activeHandoffWorkflowLabel(activeJob);
      final workflowSlug = _qrTransferService.sanitizeFilePart(workflowLabel);

      if (!mounted) return;
      await _showShareQrDialog(
        title: 'Share $workflowLabel Handoff',
        qrValue: qrValue,
        onShare: (shareContext) => _shareQrImage(
          qrValue: qrValue,
          fileName:
              'WellWerks_${workflowSlug}_Handoff_${_qrTransferService.sanitizeFilePart(base)}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.png',
          subject: 'WellWerks $workflowLabel Handoff - $base',
          shareContext: shareContext,
        ),
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
        SnackBar(content: Text('$workflowLabel handoff QR ready.')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The QR image could not be shared.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importWorkflowHandoff() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final method = await _chooseImportMethod('Import Handoff');
      if (!mounted || method == null) return;

      final scanned = method == 'scan'
          ? await _scanQrFromCamera('Scan Handoff QR')
          : await _scanQrFromPhotos();
      if (scanned == null || scanned.trim().isEmpty) {
        if (method == 'photos') {
          throw const FormatException('No QR code was found in that image.');
        }
        return;
      }

      final raw = _qrTransferService.decodeStructuredPayload(scanned);
      final header = _packageRouter.decodeHeader(raw);
      if (header.type != WellWerksPackageType.drilloutHandoff) {
        throw const FormatException(
          'This is a Production Handoff QR. Open Import Production Handoff to use it.',
        );
      }

      final package = _drilloutHandoffService.decodePackage(raw);
      final packageWorkflow = package.workflow.trim().toLowerCase();
      final expectedWorkflow =
          (_activeJob?.workflow ?? '').trim().toLowerCase();
      if (expectedWorkflow == 'drillout' && packageWorkflow == 'cleanout') {
        throw const FormatException(
          'This is a Cleanout handoff. Open Handoff from a Cleanout job to import it.',
        );
      }
      if (expectedWorkflow == 'cleanout' && packageWorkflow == 'drillout') {
        throw const FormatException(
          'This is a Drillout handoff. Open Handoff from a Drillout job to import it.',
        );
      }

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
            'Imported ${_activeHandoffWorkflowLabel(savedJob)} handoff for ${savedJob.padName.isEmpty ? savedJob.company : savedJob.padName}.',
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
        const SnackBar(content: Text('This QR code is incomplete or damaged.')),
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
                  : 'Handoff Package',
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
                  ? 'Share and import use one WellWerks QR package format. Import still merges by entryId and lets you choose local or imported conflict values.'
                  : 'Share and import use one WellWerks QR package format for drillout/cleanout handoff context.',
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
        return 'Handoff Export';
      case 'drillout_import':
        return 'Handoff Import';
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
        title: _isProductionWorkflow ? 'Production Handoff' : 'Handoff',
        showBack: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (_isDrilloutCleanoutWorkflow && _activeJob == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Select or create an active Drillout or Cleanout job in Job Setup before using Handoff.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          if (_isDrilloutCleanoutWorkflow && _activeJob == null)
            const SizedBox(height: 8),
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
                      : (_activeJob == null ? null : _exportWorkflowHandoff)),
              icon: const Icon(Icons.ios_share),
              label: Text(
                _isProductionWorkflow
                    ? 'Share Production Handoff'
                    : 'Share Handoff',
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
                      : _importWorkflowHandoff),
              icon: const Icon(Icons.file_open_outlined),
              label: Text(
                _isProductionWorkflow
                    ? 'Import Production Handoff'
                    : 'Import Handoff',
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
