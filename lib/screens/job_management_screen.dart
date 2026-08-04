import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/job_history.dart';
import '../models/job_setup.dart';
import '../models/jsa_draft.dart';
import '../models/production_shift.dart';
import '../services/active_job_share_service.dart';
import '../services/active_workflow_mode_service.dart';
import '../services/job_history_service.dart';
import '../services/job_setup_import_service.dart';
import '../services/job_storage_service.dart';
import '../services/jsa_export_service.dart';
import '../services/jsa_storage_service.dart';
import '../services/production_shift_service.dart';
import '../services/wellwerks_package_router_service.dart';
import '../services/wellwerks_qr_transfer_service.dart';
import '../widgets/app_header.dart';
import 'jsa_history_screen.dart';
import 'jsa_screen.dart';
import 'job_setup_qr_scanner_screen.dart';
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
  final _jsaExportService = JsaExportService();
  final _jobShareService = const ActiveJobShareService();
  final _jobImportService = const JobSetupImportService();
  final _workflowModeService = ActiveWorkflowModeService.instance;
  final _packageRouter = const WellWerksPackageRouterService();
  final _qrTransferService = const WellWerksQrTransferService();
  final _imagePicker = ImagePicker();

  ProductionShift _shift = ProductionShift.empty();
  JobSetup? _activeJob;
  JsaDraft? _todayJsa;
  List<JobSetup> _jobs = const <JobSetup>[];
  bool _loading = true;
  bool _qrBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var shift = await _shiftService.loadActiveShift();
    final active = await _jobStorage.resolveProductionActiveJob(shift);
    if (active != null && shift.activeJobId != active.id) {
      shift = shift.copyWith(activeJobId: active.id);
      await _shiftService.saveActiveShift(shift);
    }
    var jobs = await _jobStorage.loadJobs();

    if (active != null && !jobs.any((item) => item.id == active.id)) {
      jobs = <JobSetup>[active, ...jobs];
    }

    final todayJsa = active == null
        ? null
        : await _jsaStorage.loadDraft(
            activeJobId: active.id,
            date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
          );

    if (!mounted) return;
    setState(() {
      _shift = shift;
      _activeJob = active;
      _todayJsa = todayJsa;
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

  List<String> get _activeWells {
    final source = _shift.header.wells.any((item) => item.trim().isNotEmpty)
        ? _shift.header.wells
        : (_activeJob?.wells ?? const <String>[]);
    final wells = <String>[];
    for (final well in source) {
      final trimmed = well.trim();
      if (trimmed.isNotEmpty && !wells.contains(trimmed)) {
        wells.add(trimmed);
      }
    }
    return wells;
  }

  bool get _hasActiveShiftLink {
    final summary = [_shift.header.company, _shift.header.pad]
        .where((item) => item.trim().isNotEmpty)
        .join(' • ');
    return _shift.activeJobId.trim().isNotEmpty || summary.isNotEmpty;
  }

  String get _activeCompanyName {
    final fromJob = _activeJob?.company.trim() ?? '';
    if (fromJob.isNotEmpty) return fromJob;
    return _shift.header.company.trim();
  }

  String get _activePadName {
    final fromJob = _activeJob?.padName.trim() ?? '';
    if (fromJob.isNotEmpty) return fromJob;
    return _shift.header.pad.trim();
  }

  String get _activeStatusLabel {
    final status = _activeJob?.status.trim() ?? '';
    if (status.isNotEmpty) {
      return status.toUpperCase();
    }
    return _hasActiveShiftLink ? 'ACTIVE' : 'INACTIVE';
  }

  int get _savedHourCount {
    final hours = <int>{};
    for (final row in _shift.savedRows) {
      hours.add(row.hourIndex);
    }
    return hours.length;
  }

  int get _savedRowCount => _shift.savedRows.length;

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
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

  Future<void> _openTodayJsa() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const JsaScreen()),
    );
    await _load();
  }

  Future<void> _shareTodayJsa() async {
    final activeJob = _activeJob;
    final draft = _todayJsa;
    if (activeJob == null || draft == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No JSA saved for today yet.')),
      );
      return;
    }

    final exported = await _jsaExportService.exportPdf(
      draft: draft,
      activeJob: activeJob,
    );
    await Share.shareXFiles(
      [XFile(exported.filePath)],
      subject: 'WellWerks JSA',
      text: 'Today\'s JSA exported from WellWerks.',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Today\'s JSA shared.')),
    );
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

  ActiveWorkflowMode _workflowModeForJob(JobSetup job) {
    final workflow = job.workflow.trim().toLowerCase();
    if (workflow == 'drillout') return ActiveWorkflowMode.drillout;
    if (workflow == 'cleanout') return ActiveWorkflowMode.cleanout;
    return ActiveWorkflowMode.production;
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
                } catch (_) {
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

  Future<String?> _chooseImportMethod() {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Job Setup'),
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

  Future<String?> _scanQrFromCamera() {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const JobSetupQrScannerScreen(),
      ),
    );
  }

  Future<String?> _scanQrFromPhotos() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    return _qrTransferService.decodeFirstQrFromImagePath(picked.path);
  }

  Future<String?> _chooseImportTarget(JobSetupImportPreview preview) {
    final workflow = ActiveWorkflowModeService.labelFor(
      _workflowModeForJob(preview.job),
    );
    final company =
        preview.job.company.trim().isEmpty ? '-' : preview.job.company.trim();
    final pad = preview.job.padName.trim().isEmpty ? '-' : preview.job.padName;

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Job Setup'),
        content: Text(
          preview.hasMatchingJob
              ? 'Detected $workflow job setup for $company - $pad.\n\nA matching job id already exists. Do you want to update the existing job or import as a new job?'
              : 'Detected $workflow job setup for $company - $pad.\n\nImport as your active job?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (preview.hasMatchingJob)
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop('update'),
              child: const Text('Update Existing'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('new'),
            child: Text(preview.hasMatchingJob ? 'Import As New' : 'Import'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareActiveJobSetupQr() async {
    final activeJob = _activeJob;
    if (activeJob == null || _qrBusy) {
      if (activeJob == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active job selected.')),
        );
      }
      return;
    }

    setState(() => _qrBusy = true);
    try {
      final package = await _jobShareService.buildPackage(activeJob: activeJob);
      final encoded = _jobShareService.encodePackage(package);
      final qrValue = _qrTransferService.encodeStructuredPayload(encoded);
      _qrTransferService.ensureSingleQrCapacity(qrValue);
      _qrTransferService.decodeStructuredPayload(qrValue);

      if (!mounted) return;
      final base = _qrTransferService.sanitizeFilePart(
        activeJob.padName.trim().isEmpty
            ? activeJob.company
            : activeJob.padName,
      );
      await _showShareQrDialog(
        title: 'Share Active Job Setup QR',
        qrValue: qrValue,
        onShare: (shareContext) => _shareQrImage(
          qrValue: qrValue,
          fileName:
              'WellWerks_Job_Setup_${base}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.png',
          subject: 'WellWerks Job Setup - $base',
          shareContext: shareContext,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Active job setup QR ready.')),
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
      if (mounted) setState(() => _qrBusy = false);
    }
  }

  Future<void> _importJobSetupQr() async {
    if (_qrBusy) return;
    setState(() => _qrBusy = true);
    try {
      final method = await _chooseImportMethod();
      if (!mounted || method == null) return;

      final scanned = method == 'scan'
          ? await _scanQrFromCamera()
          : await _scanQrFromPhotos();
      if (scanned == null || scanned.trim().isEmpty) {
        if (method == 'photos') {
          throw const FormatException('No QR code was found in that image.');
        }
        return;
      }

      final raw = _qrTransferService.decodeStructuredPayload(scanned);
      final header = _packageRouter.decodeHeader(raw);
      if (header.type != WellWerksPackageType.jobSetup) {
        if (header.type == WellWerksPackageType.productionHandoff) {
          throw const FormatException(
            'This is a Production Handoff QR. Open Shift Handoff to import it.',
          );
        }
        if (header.type == WellWerksPackageType.drilloutHandoff) {
          throw const FormatException(
            'This is a Drillout/Cleanout Handoff QR. Open Shift Handoff to import it.',
          );
        }
        if (header.type == WellWerksPackageType.operationsLog) {
          throw const FormatException(
            'This is an Operations Log QR, not a Job Setup QR.',
          );
        }
      }

      final preview =
          _jobImportService.decodePreview(raw: raw, localJobs: _jobs);
      final action = await _chooseImportTarget(preview);
      if (action == null) return;

      final imported = action == 'update'
          ? _jobImportService.buildImportAsUpdate(preview)
          : _jobImportService.buildImportAsNew(preview, localJobs: _jobs);
      final saved = await _jobStorage.saveActiveJob(imported);
      await _workflowModeService.setMode(_workflowModeForJob(saved));
      await _shiftService.clearActiveShift();
      await _jsaStorage.clearDraft();

      await _load();
      if (!mounted) return;
      final workflowLabel = ActiveWorkflowModeService.labelFor(
        _workflowModeForJob(saved),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported $workflowLabel job setup and set it active.'),
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
      if (mounted) setState(() => _qrBusy = false);
    }
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
    await _jsaStorage.deleteDraftsForJob(job.id);

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
    if (activeJob == null && !_hasActiveShiftLink) {
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

    final companyName = _activeCompanyName;
    final padName = _activePadName;
    final wellsText = _activeWells.isEmpty ? '-' : _activeWells.join(' / ');

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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCDA56A),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _activeStatusLabel,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_savedRowCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFCDA56A)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$_savedHourCount hr • $_savedRowCount rows',
                      style: const TextStyle(
                        color: Color(0xFFCDA56A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              companyName.isEmpty ? 'Job in progress' : companyName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              padName.isEmpty ? '-' : padName,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              wellsText,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            _detailLine('Company', companyName),
            _detailLine('Pad', padName),
            _detailLine('Wells', wellsText),
            _detailLine('Status', _activeStatusLabel),
            _detailLine('Saved Hours', _savedHourCount.toString()),
            _detailLine('Saved Rows', _savedRowCount.toString()),
            if (activeJob == null && _hasActiveShiftLink) ...[
              const SizedBox(height: 6),
              const Text(
                'Using active shift job link.',
                style: TextStyle(color: Colors.white70),
              ),
            ],
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
                onPressed: _nonArchivedJobs.isEmpty ? null : _changeActiveJob,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Change Active Job'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _activeJob == null || _qrBusy
                    ? null
                    : _shareActiveJobSetupQr,
                icon: const Icon(Icons.qr_code_2_outlined),
                label:
                    Text(_qrBusy ? 'Working...' : 'Share Active Job Setup QR'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _qrBusy ? null : _importJobSetupQr,
                icon: const Icon(Icons.qr_code_scanner_outlined),
                label: Text(_qrBusy ? 'Working...' : 'Import Job Setup QR'),
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

  Widget _jobSetupTransferCard() {
    final hasActiveJob = _activeJob != null;
    return Card(
      color: const Color(0xFF111A20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Job Setup Transfer (QR)',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasActiveJob
                  ? 'Share your active job setup as a QR code, or import a setup from QR.'
                  : 'Import a job setup from QR, or create/select an active job to enable sharing.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    hasActiveJob && !_qrBusy ? _shareActiveJobSetupQr : null,
                icon: const Icon(Icons.qr_code_2_outlined),
                label:
                    Text(_qrBusy ? 'Working...' : 'Share Active Job Setup QR'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _qrBusy ? null : _importJobSetupQr,
                icon: const Icon(Icons.qr_code_scanner_outlined),
                label: Text(_qrBusy ? 'Working...' : 'Import Job Setup QR'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _todayJsaCard() {
    final hasActiveJob = _activeJob != null || _hasActiveShiftLink;
    final hasJsa = _todayJsa != null;
    final statusColor =
        hasJsa ? const Color(0xFF7EDC8C) : const Color(0xFFCDA56A);
    return Card(
      color: hasJsa ? const Color(0xFF142015) : const Color(0xFF241B10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Today\'s JSA',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              hasJsa ? 'JSA COMPLETE' : 'JSA NOT COMPLETE',
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasJsa
                  ? 'Today\'s JSA is saved and ready to reopen or share.'
                  : 'No JSA exists for today under the active job.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: hasActiveJob ? _openTodayJsa : null,
                icon:
                    Icon(hasJsa ? Icons.description_outlined : Icons.add_task),
                label:
                    Text(hasJsa ? 'Open Today\'s JSA' : 'Create Today\'s JSA'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: hasJsa ? _shareTodayJsa : null,
                icon: const Icon(Icons.share_outlined),
                label: const Text('Export / Share Today\'s JSA'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const JsaHistoryScreen()),
                  );
                },
                icon: const Icon(Icons.history_outlined),
                label: const Text('JSA History'),
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
          _jobSetupTransferCard(),
          const SizedBox(height: 10),
          _todayJsaCard(),
          const SizedBox(height: 10),
          _actionsCard(),
          const SizedBox(height: 10),
          _jobsListCard(),
        ],
      ),
    );
  }
}
