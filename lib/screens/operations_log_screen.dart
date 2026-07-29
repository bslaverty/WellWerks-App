import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/job_setup.dart';
import '../models/operations_log_entry.dart';
import '../services/job_storage_service.dart';
import '../services/operations_log_service.dart';
import '../services/wellwerks_qr_transfer_service.dart';
import '../widgets/app_header.dart';
import 'operations_log_entry_form_screen.dart';
import 'wellwerks_qr_scanner_screen.dart';

class OperationsLogScreen extends StatefulWidget {
  const OperationsLogScreen({
    super.key,
    required this.workflow,
    required this.title,
  });

  final OperationsLogWorkflow workflow;
  final String title;

  @override
  State<OperationsLogScreen> createState() => _OperationsLogScreenState();
}

class _OperationsLogScreenState extends State<OperationsLogScreen> {
  final _jobStorage = JobStorageService();
  final _logService = OperationsLogService();
  final _qrTransferService = const WellWerksQrTransferService();
  final _imagePicker = ImagePicker();

  JobSetup? _activeJob;
  List<OperationsLogEntry> _entries = const [];
  Set<String> _selectedEntryIds = <String>{};
  bool _loading = true;
  bool _newestFirst = false;

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
    final entries = await _logService.loadEntries(
      workflow: widget.workflow,
      jobId: job?.id ?? '',
    );
    if (!mounted) return;
    setState(() {
      _activeJob = job;
      _entries = entries;
      _selectedEntryIds = _selectedEntryIds
          .where((entryId) => entries.any((item) => item.entryId == entryId))
          .toSet();
      _loading = false;
    });
  }

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
      final compare = a.readingTimestamp.compareTo(b.readingTimestamp);
      return _newestFirst ? -compare : compare;
    });
    return items;
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
        '[OperationsLog] Add Reading blocked: no active job for ${widget.workflow.name}.',
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
            workflow: widget.workflow,
            title: widget.title,
            activeJob: job,
            defaultWells: _resolvedWells,
            initialSelectedWellId:
                _resolvedWells.isNotEmpty ? _resolvedWells.first.id : '',
            initialSelectedWellName: _currentWellName,
            initialStage: _currentStage,
            initialReadingTimestamp: DateTime.now(),
            logService: _logService,
          ),
        ),
      );
      if (savedEntry == null) return;
      await _load();
    } catch (error, stackTrace) {
      debugPrint(
        '[OperationsLog] Failed to open Add Reading form for ${widget.workflow.name}: $error\n$stackTrace',
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
            Text('Time: ${entry.readingTimestamp.toLocal()}'),
            Text('Operation: ${entry.operationStage}'),
            Text('Pump rate: ${entry.pumpRate}'),
            Text('Notes: ${entry.notes}'),
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
      workflow: widget.workflow,
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
    if (job == null || selectedEntries.isEmpty) return;
    final packageType = widget.workflow == OperationsLogWorkflow.drillout
        ? OperationsLogPackageType.drilloutReadingBatch
        : OperationsLogPackageType.cleanoutReadingBatch;
    final package = await _logService.buildPackage(
      packageType: packageType,
      persistentJobId: job.id,
      entries: selectedEntries,
    );
    final encoded = _logService.encodePackage(package);
    await _showShareQrDialog(encoded, '${widget.title} QR');
  }

  Future<void> _createShiftReport() async {
    final job = _activeJob;
    if (job == null || _entries.isEmpty) return;
    final exported = await _logService.exportShiftReportPdf(
      workflow: widget.workflow,
      jobName: job.padName,
      wellName: _currentWellName,
      stage: _currentStage,
      entries: _entries,
      baseFileName:
          '${job.padName.isNotEmpty ? job.padName : widget.workflow.name}_shift_report',
    );
    await Share.shareXFiles(
      [XFile(exported.filePath)],
      subject: '${widget.title} Shift Report',
      text: '${widget.title} shift report for ${job.padName}.',
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
    final packageType = widget.workflow == OperationsLogWorkflow.drillout
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
          FilledButton(
            onPressed: () async {
              final bytes = await _qrTransferService.buildQrPngBytes(qrValue);
              final directory = await getTemporaryDirectory();
              final file = File('${directory.path}/operations_log.png');
              await file.writeAsBytes(bytes, flush: true);
              await Share.shareXFiles([XFile(file.path)]);
            },
            child: const Text('Share QR'),
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
                    ? '1 reading from ${package.workflow} for ${job.padName}.\n${package.entries.first.wellName} at ${package.entries.first.readingTimestamp.toLocal()}'
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
        workflow: widget.workflow,
        jobId: job.id,
        package: package,
        existingEntries: _entries,
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
                if (_currentStage.isNotEmpty)
                  _infoCard('Current stage', _currentStage),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _addReading,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Reading'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectedEntryIds.isEmpty
                            ? null
                            : _shareSelectedReadings,
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('Share Selected Readings'),
                      ),
                    ),
                  ],
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
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _entries.isEmpty ? null : _createShiftReport,
                  child: const Text('Create Shift Report'),
                ),
                if (_entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'At least one reading is required to create a shift report.',
                    ),
                  ),
                const SizedBox(height: 16),
                if (_sortedEntries.isEmpty)
                  const Text('No readings recorded yet.')
                else
                  ..._sortedEntries.map(
                    (entry) => Card(
                      child: ListTile(
                        leading: Checkbox(
                          value: _selectedEntryIds.contains(entry.entryId),
                          onChanged: (value) => _toggleSelectedEntry(
                            entry.entryId,
                            value ?? false,
                          ),
                        ),
                        title: Text(
                          '${TimeOfDay.fromDateTime(entry.readingTimestamp).format(context)} • ${entry.wellName}',
                        ),
                        subtitle: Text([
                          if (entry.operationStage.isNotEmpty)
                            entry.operationStage,
                          if (entry.pumpRate.isNotEmpty)
                            'Rate ${entry.pumpRate}',
                          if (entry.casingPressure.isNotEmpty)
                            'CSG ${entry.casingPressure}',
                        ].join(' • ')),
                        onTap: () => _showEntryDetails(entry),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'share') {
                              _shareReading(entry);
                            } else if (value == 'delete') {
                              _deleteEntry(entry);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'share',
                              child: Text('Share Reading'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
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
