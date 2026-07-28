import 'dart:io';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';
import '../models/job_setup.dart';
import '../services/app_settings_service.dart';
import '../services/active_job_share_service.dart';
import '../services/active_workflow_mode_service.dart';
import '../services/job_storage_service.dart';
import '../services/job_setup_qr_service.dart';
import '../services/rate_timer_notification_service.dart';
import '../services/rate_timer_service.dart';
import '../services/recovery_state_service.dart';
import '../services/wellwerks_package_router_service.dart';
import 'module_menu_screen.dart';
import 'rate_calculator_screen.dart';
import 'rate_calculator_menu_screen.dart';
import 'equipment_layout_screen.dart';
import 'rig_up_inventory_screen.dart';
import 'rig_up_history_screen.dart';
import 'jsa_screen.dart';
import 'production_dashboard_screen.dart';
import 'production_history_screen.dart';
import 'gas_accum_screen.dart';
import 'job_setup_qr_scanner_screen.dart';
import 'bottoms_up_screen.dart';
import 'multiple_choke_screen.dart';
import 'chart_reference_screen.dart';
import 'tank_charts_menu_screen.dart';
import 'conversion_calculator_screen.dart';
import 'settings_screen.dart';
import 'about_support_screen.dart';
import 'job_setup_screen.dart';
import 'drillout_shift_change_screen.dart';
import 'drillout_cleanout_module_screen.dart';
import 'flywheel_diesel_tank_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _homeSummaryExpandedKey =
      'wellwerks_home_job_summary_expanded_v1';

  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();
  final _rateTimerService = RateTimerService();
  final _settingsService = AppSettingsService();
  final _rateTimerNotifications = RateTimerNotificationService.instance;
  final _workflowModeService = ActiveWorkflowModeService.instance;
  final _jobShareService = ActiveJobShareService();
  final _jobSetupQrService = const JobSetupQrService();
  final _packageRouter = const WellWerksPackageRouterService();

  JobSetup? _activeJob;
  bool _loading = true;
  bool _activeJobExpanded = false;
  bool _jobShareBusy = false;
  ActiveWorkflowMode _activeWorkflowMode = ActiveWorkflowMode.production;

  @override
  void initState() {
    super.initState();
    _jobStorage.activeJobListenable.addListener(_handleActiveJobChanged);
    _workflowModeService.mode.addListener(_handleWorkflowModeChanged);
    _loadRecovery();
  }

  @override
  void dispose() {
    _jobStorage.activeJobListenable.removeListener(_handleActiveJobChanged);
    _workflowModeService.mode.removeListener(_handleWorkflowModeChanged);
    super.dispose();
  }

  void _handleWorkflowModeChanged() {
    if (!mounted) return;
    setState(() {
      _activeWorkflowMode = _workflowModeService.mode.value;
    });
  }

  void _handleActiveJobChanged() {
    if (!mounted) return;
    setState(() {
      _activeJob = _jobStorage.activeJobListenable.value;
      if (_activeJob == null) {
        _activeJobExpanded = false;
      }
    });
    if (_activeJob == null) {
      _setActiveJobExpanded(false);
    }
  }

  Future<bool> _loadSummaryExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_homeSummaryExpandedKey) ?? false;
  }

  Future<void> _setActiveJobExpanded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_homeSummaryExpandedKey, value);
  }

  Future<void> _loadRecovery() async {
    final activeJob = await _jobStorage.ensureActiveJobLoaded();
    final lastActiveJobId = await _jobStorage.loadLastActiveJobId();
    final workflowMode = await _workflowModeService.ensureLoaded();
    final expanded = await _loadSummaryExpanded();
    final snapshot = await _recoveryState.loadSnapshot(
      lastActiveJobId: lastActiveJobId,
    );
    if (!mounted) return;
    setState(() {
      _activeJob = activeJob != null && snapshot.lastActiveJobId == activeJob.id
          ? activeJob
          : activeJob;
      _activeJobExpanded = activeJob == null ? false : expanded;
      _activeWorkflowMode = workflowMode;
      _loading = false;
    });
    _handlePendingRateTimerAction();
  }

  Future<void> _handlePendingRateTimerAction() async {
    final action = await _rateTimerService.consumePendingAction();
    if (!mounted || action == null) return;
    final calculatorId =
        (action.payload['calculatorId'] as String? ?? '').trim();
    final config = RateCalculatorConfig.fromStorageId(calculatorId);

    if (action.type == RateTimerPendingActionType.stopTimer) {
      final active = await _rateTimerService.loadActiveTimer();
      if (active != null) {
        await _rateTimerNotifications.cancelNotifications(active);
      }
      await _rateTimerService.clearActiveTimer();
      return;
    }

    if (action.type == RateTimerPendingActionType.restartTimer) {
      if (config == null) return;
      final active = await _rateTimerService.loadActiveTimer();
      if (active != null) {
        await _rateTimerNotifications.cancelNotifications(active);
      }
      final durationSeconds =
          (action.payload['durationSeconds'] as num?)?.toInt() ?? 60;
      final fresh = await _rateTimerService.createState(
        calculatorId: calculatorId,
        calculatorTitle:
            (action.payload['calculatorTitle'] as String? ?? config.title),
        wellOrJob: (action.payload['wellOrJob'] as String? ?? '').trim(),
        durationSeconds: durationSeconds,
      );
      await _rateTimerService.saveActiveTimer(fresh);
      final settings = await _settingsService.load();
      await _rateTimerNotifications.scheduleNotifications(
        timer: fresh,
        settings: settings,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RateCalculatorScreen(config: config)),
      );
      if (!mounted) return;
      await _loadRecovery();
      return;
    }

    if (action.type == RateTimerPendingActionType.openCalculator &&
        config != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RateCalculatorScreen(config: config)),
      );
      if (!mounted) return;
      await _loadRecovery();
    }
  }

  Future<void> open(BuildContext context, Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _loadRecovery();
  }

  String get _workflowLabel {
    switch (_activeWorkflowMode) {
      case ActiveWorkflowMode.cleanout:
        return 'Cleanout';
      case ActiveWorkflowMode.drillout:
        return 'Drillout';
      case ActiveWorkflowMode.production:
        return 'Production';
    }
  }

  String _activeJobCompany(JobSetup job) {
    final company = job.company.trim();
    return company.isEmpty ? 'Unknown Company' : company;
  }

  String _activeJobPadOrWell(JobSetup job) {
    final well = job.primaryWell.trim();
    if (well.isNotEmpty) return well;
    final pad = job.padName.trim();
    return pad.isEmpty ? 'Unknown Well/Pad' : pad;
  }

  String _activeJobCollapsedSummary(JobSetup job) {
    final shift = job.shift.trim().isEmpty ? '-' : '${job.shift.trim()} Shift';
    return '${_activeJobPadOrWell(job)} • $_workflowLabel • $shift';
  }

  String _jobStructure(JobSetup job) {
    if (job.isMultiWellJob) {
      final count = job.resolvedWellNames.length;
      return count <= 0 ? 'Multiple Wells' : 'Multiple Wells ($count)';
    }
    return 'Single Well';
  }

  String _jobReadiness(JobSetup job) {
    final hasCompany = job.company.trim().isNotEmpty;
    final hasLocation =
        job.primaryWell.trim().isNotEmpty || job.padName.trim().isNotEmpty;
    final hasShift = job.shift.trim().isNotEmpty;
    return hasCompany && hasLocation && hasShift
        ? 'Active Job Ready'
        : 'Missing Information';
  }

  Future<void> _toggleActiveJobExpanded() async {
    final next = !_activeJobExpanded;
    if (!mounted) return;
    setState(() => _activeJobExpanded = next);
    await _setActiveJobExpanded(next);
  }

  Future<void> _editActiveJob() async {
    if (_activeWorkflowMode == ActiveWorkflowMode.production) {
      await open(context, const JobSetupScreen(editActiveOnOpen: true));
      return;
    }
    await open(
      context,
      DrilloutShiftChangeScreen(initialWorkflow: _activeWorkflowMode),
    );
  }

  Future<void> _startNewJob() async {
    final active = _activeJob;
    if (active == null) {
      await open(context, const JobSetupScreen(startFreshJob: true));
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Start New Job?'),
            content: const Text(
              'The current active job will be ended and preserved in History before the new job setup begins.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Start New Job'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    await _jobStorage.endActiveJob();
    await _settingsService.clearActiveData();
    if (!mounted) return;
    await open(context, const JobSetupScreen(startFreshJob: true));
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

  Future<void> _shareJobSetup() async {
    final activeJob = _activeJob;
    if (activeJob == null || _jobShareBusy) return;

    setState(() => _jobShareBusy = true);
    try {
      final package = await _jobShareService.buildPackage(activeJob: activeJob);
      final encoded = _jobShareService.encodePackage(package);
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final pad =
          activeJob.padName.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final base = pad.isEmpty ? 'job_setup' : pad;
      final file = File('${directory.path}/${base}_$timestamp.wellwerks');
      await file.writeAsString(encoded);

      final exists = await file.exists();
      final size = exists ? await file.length() : 0;
      if (!exists || size <= 0) {
        throw const FormatException(
            'Could not prepare Job Setup file to share.');
      }

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'WellWerks Job Setup',
        text: 'Job setup package for WellWerks import.',
        sharePositionOrigin: _shareOriginRect(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job Setup shared.')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to share Job Setup. ${error.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() => _jobShareBusy = false);
      }
    }
  }

  Future<void> _importJobSetup() async {
    if (_jobShareBusy) return;
    setState(() => _jobShareBusy = true);

    try {
      final picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'WellWerks Job Setup',
            extensions: <String>['wellwerks', 'wwjob', 'json'],
          ),
        ],
      );

      if (picked == null) return;

      final length = await picked.length();
      if (length <= 0) {
        throw const FormatException('Selected file is empty.');
      }

      final raw = await picked.readAsString();
      await _importJobSetupFromRaw(raw);
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to import Job Setup file. ${error.toString()}'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _jobShareBusy = false);
      }
    }
  }

  Future<void> _importJobSetupFromRaw(String raw) async {
    try {
      final header = _packageRouter.decodeHeader(raw);
      if (header.type != WellWerksPackageType.jobSetup) {
        throw const FormatException(
          'This file is not a Job Setup package. Use Share Job Setup on the sender device.',
        );
      }

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

      if (!mounted) return;
      setState(() {
        _activeJob = savedJob;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported Job Setup: ${savedJob.padName.isEmpty ? savedJob.company : savedJob.padName}',
          ),
        ),
      );
      return;
    } on FormatException {
      // Fallback path: older files may contain only JobSetup JSON without envelope metadata.
      final legacy = JobSetup.fromJson(
        Map<String, dynamic>.from(
          (const JsonDecoder().convert(raw) as Map),
        ),
      );
      final normalizedImport = legacy.copyWith(
        workflow:
            legacy.workflow.trim().isEmpty ? 'production' : legacy.workflow,
        status: 'active',
        endedAt: null,
        startedAt: legacy.startedAt ?? DateTime.now(),
      );
      final savedJob = await _jobStorage.saveActiveJob(normalizedImport);
      await _workflowModeService.setMode(_workflowModeForJob(savedJob));
      if (!mounted) return;
      setState(() {
        _activeJob = savedJob;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported legacy Job Setup: ${savedJob.padName.isEmpty ? savedJob.company : savedJob.padName}',
          ),
        ),
      );
    }
  }

  Rect? _shareOriginRect() {
    final object = context.findRenderObject();
    if (object is! RenderBox || !object.hasSize) return null;
    final origin = object.localToGlobal(Offset.zero);
    return origin & object.size;
  }

  Future<void> _showJobSetupQr() async {
    final activeJob = _activeJob;
    if (activeJob == null || _jobShareBusy) return;
    setState(() => _jobShareBusy = true);
    try {
      final package = await _jobShareService.buildPackage(activeJob: activeJob);
      final raw = _jobShareService.encodePackage(package);
      final frames = _jobSetupQrService.encodePayloadFrames(raw);
      if (!mounted) return;

      var frameIndex = 0;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setInnerState) => AlertDialog(
              title: Text(
                frames.length == 1
                    ? 'Job Setup QR'
                    : 'Job Setup QR ${frameIndex + 1}/${frames.length}',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: frames[frameIndex],
                    version: QrVersions.auto,
                    size: 260,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    frames.length == 1
                        ? 'Scan this code from another WellWerks device to import this active Job Setup.'
                        : 'Scan all ${frames.length} QR codes in order on the receiving device.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
              actions: [
                if (frames.length > 1)
                  TextButton(
                    onPressed: frameIndex <= 0
                        ? null
                        : () {
                            setInnerState(() {
                              frameIndex -= 1;
                            });
                          },
                    child: const Text('Previous'),
                  ),
                if (frames.length > 1)
                  TextButton(
                    onPressed: frameIndex >= frames.length - 1
                        ? null
                        : () {
                            setInnerState(() {
                              frameIndex += 1;
                            });
                          },
                    child: const Text('Next'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        },
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to generate Job Setup QR code.')),
      );
    } finally {
      if (mounted) {
        setState(() => _jobShareBusy = false);
      }
    }
  }

  Future<void> _scanJobSetupQr() async {
    if (_jobShareBusy) return;
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const JobSetupQrScannerScreen()),
    );
    if (!mounted || scanned == null || scanned.trim().isEmpty) return;

    setState(() => _jobShareBusy = true);
    try {
      final raw = _jobSetupQrService.decodePayload(scanned);
      await _importJobSetupFromRaw(raw);
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to scan/import Job Setup QR.')),
      );
    } finally {
      if (mounted) {
        setState(() => _jobShareBusy = false);
      }
    }
  }

  Future<void> _endClearActiveJob() async {
    if (_activeJob == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('End Active Job?'),
            content: const Text(
              'This removes the current job from the active context.\n\nSaved History, JSAs, reports, layouts, and completed records will not be deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('End Job'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    await _jobStorage.endActiveJob();
    await _settingsService.clearActiveData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Active job ended. Saved records were preserved.'),
      ),
    );
    await _loadRecovery();
  }

  Widget _activeJobSummaryCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final job = _activeJob;

    return Card(
      color: Theme.of(context).cardColor,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (job == null)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _startNewJob,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No Active Job',
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Create New Job >',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              )
            else ...[
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _toggleActiveJobExpanded,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _activeJobCompany(job),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _activeJobExpanded
                                ? 'Collapse details'
                                : 'Expand details',
                            onPressed: _toggleActiveJobExpanded,
                            icon: Icon(
                              _activeJobExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _activeJobCollapsedSummary(job),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              if (_activeJobExpanded) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _activeJobCompany(job),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _activeJobPadOrWell(job),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _infoLine(context, 'Workflow', _workflowLabel),
                      _infoLine(context, 'Shift', job.shift),
                      _infoLine(context, 'Job Type', _jobStructure(job)),
                      _infoLine(context, 'Readiness', _jobReadiness(job)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _editActiveJob,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit Active Job'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _startNewJob,
                          icon: const Icon(Icons.play_circle_outline),
                          label: const Text('Start New Job'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _endClearActiveJob,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('End/Clear Active Job'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'Job Setup Sharing',
                        style: TextStyle(
                          color: Color(0xFFCDA56A),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _jobShareBusy ? null : _shareJobSetup,
                          icon: const Icon(Icons.ios_share),
                          label: const Text('Share Job Setup'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _jobShareBusy ? null : _importJobSetup,
                          icon: const Icon(Icons.file_open_outlined),
                          label: const Text('Import Job Setup'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _showJobSetupQr,
                          icon: const Icon(Icons.qr_code_2_outlined),
                          label: const Text('Show Job Setup QR'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _scanJobSetupQr,
                          icon: const Icon(Icons.qr_code_scanner_outlined),
                          label: const Text('Scan Job Setup QR'),
                        ),
                      ),
                      if (_jobShareBusy)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoLine(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  Widget _chloridesCalculatorScreen() {
    return const ChartReferenceScreen(
      title: 'Chlorides Chart',
      description:
          'Chlorides reference table from the web app source with Brix to SG conversion.',
      showBrixTool: false,
      showChloridesCalculator: true,
      enableSearch: true,
      sections: [
        ChartSection(
          title: 'Water Weight and Chlorides',
          columns: ['SP.GR.', '#/G', 'CLPPM'],
          rows: [
            ['1.002', '8.36', '1755'],
            ['1.004', '8.38', '3511'],
            ['1.006', '8.40', '5267'],
            ['1.008', '8.41', '7023'],
            ['1.010', '8.43', '8779'],
            ['1.086', '9.06', '75500'],
            ['1.088', '9.08', '77260'],
            ['1.090', '9.10', '79010'],
            ['1.092', '9.11', '80770'],
            ['1.170', '9.76', '149200'],
            ['1.172', '9.78', '151000'],
            ['1.174', '9.80', '152700'],
            ['1.176', '9.81', '154501'],
          ],
        ),
        ChartSection(
          title: 'Brix to SG Reference',
          columns: ['Brix', 'SG'],
          rows: [
            ['0', '1.0000'],
            ['5', '1.0197'],
            ['10', '1.0400'],
            ['15', '1.0607'],
            ['20', '1.0829'],
            ['25', '1.1068'],
            ['30', '1.1325'],
          ],
        ),
      ],
    );
  }

  Widget _moduleCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<ModuleTool> tools,
  }) {
    return ToolCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => open(
        context,
        ModuleMenuScreen(
          title: title,
          tools: tools,
          showHomeButton: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(showBack: false),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppHeader(
        showBack: false,
        trailingActions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => open(context, const SettingsScreen()),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'jobSetup') {
                _editActiveJob();
                return;
              }
              if (value == 'settings') {
                open(context, const SettingsScreen());
                return;
              }
              if (value == 'about') {
                open(context, const AboutSupportScreen());
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'jobSetup',
                child: Text('Job Setup'),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Text('Settings'),
              ),
              PopupMenuItem(
                value: 'about',
                child: Text('About & Support'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _activeJobSummaryCard(context),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'Choose a module for production, completions, charts, layouts, and safety.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 15,
              ),
            ),
          ),
          ToolCard(
            icon: Icons.oil_barrel,
            title: 'Production',
            subtitle: 'Quick Round, reports, text updates, and setup',
            onTap: () => open(context, const ProductionDashboardScreen()),
          ),
          _moduleCard(
            context: context,
            icon: Icons.build,
            title: 'Completions',
            subtitle: 'Field calculators for pumping and choke operations',
            tools: [
              const ModuleTool(
                icon: Icons.speed,
                title: 'Rate Calculator',
                subtitle: 'FS3, SandX, flowback, and production rate tools',
                screen: RateCalculatorMenuScreen(),
              ),
              const ModuleTool(
                icon: Icons.local_fire_department,
                title: 'Gas Accum Calculator',
                subtitle: 'Hourly gas rate from totalizer readings',
                screen: GasAccumScreen(),
              ),
              const ModuleTool(
                icon: Icons.arrow_downward,
                title: 'Bottoms Up Calculator',
                subtitle: 'Pipe volume, lag time, and ETA',
                screen: BottomsUpScreen(),
              ),
              const ModuleTool(
                icon: Icons.tune,
                title: 'Multiple Choke Calculator',
                subtitle: 'Equivalent choke and total flow area',
                screen: MultipleChokeScreen(),
              ),
              const ModuleTool(
                icon: Icons.text_snippet_outlined,
                title: 'Drillout / Cleanout',
                subtitle:
                    'Shared shift update workflow, JSA, preview, and copy',
                screen: DrilloutCleanoutModuleScreen(),
              ),
              const ModuleTool(
                icon: Icons.straighten,
                title: 'Conversion Calculator',
                subtitle: 'Length, volume, pressure, flow, gas, and oilfield',
                screen: ConversionCalculatorScreen(),
              ),
              ModuleTool(
                icon: Icons.science,
                title: 'Chlorides Calculator',
                subtitle: 'Chlorides and salinity calculator and chart lookup',
                screen: _chloridesCalculatorScreen(),
              ),
            ],
          ),
          _moduleCard(
            context: context,
            icon: Icons.bar_chart,
            title: 'Charts',
            subtitle: 'Tank and field chart references',
            tools: [
              const ModuleTool(
                icon: Icons.storage,
                title: 'Tank Charts',
                subtitle:
                    'FS3, SandX, V Bottom, Round Bottom, Gas Tank, and Production Tank',
                screen: TankChartsMenuScreen(),
              ),
              const ModuleTool(
                icon: Icons.local_gas_station,
                title: 'Flywheel Diesel Tank',
                subtitle: '3-compartment diesel fuel calculator',
                screen: FlywheelDieselTankScreen(),
              ),
              ModuleTool(
                icon: Icons.table_chart,
                title: 'Chlorides Chart',
                subtitle: 'Field chloride reference chart',
                screen: _chloridesCalculatorScreen(),
              ),
              const ModuleTool(
                icon: Icons.table_chart,
                title: 'Tubing Chart',
                subtitle: 'Tubing and casing capacity reference',
                screen: ChartReferenceScreen(
                  title: 'Tubing Chart',
                  description:
                      'Tubing and casing dimensional rows captured from the web app tubing sheet.',
                  enableSearch: true,
                  sections: [
                    ChartSection(
                      title: 'Tubing',
                      columns: ['OD', 'Lbs/ft', 'ID'],
                      rows: [
                        ['1.050', '1.2', '0.824'],
                        ['1.050', '1.5', '0.742'],
                        ['1.315', '1.8', '1.049'],
                        ['1.660', '2.4', '1.38'],
                        ['1.900', '2.9', '1.61'],
                        ['2.375', '4.7', '1.995'],
                        ['2.375', '5.95', '1.867'],
                        ['2.875', '6.5', '2.441'],
                        ['2.875', '8.7', '2.259'],
                        ['3.500', '9.3', '2.992'],
                        ['3.500', '12.95', '2.75'],
                        ['4.000', '11', '3.476'],
                        ['4.500', '12.75', '3.958'],
                      ],
                    ),
                    ChartSection(
                      title: 'Casing',
                      columns: ['OD', 'Lbs/ft', 'ID'],
                      rows: [
                        ['5.500', '15.5', '4.95'],
                        ['5.500', '17', '4.892'],
                        ['5.500', '20', '4.778'],
                        ['5.500', '23', '4.67'],
                        ['5.500', '26', '4.548'],
                        ['5.750', '14', '5.29'],
                        ['5.750', '17', '5.19'],
                        ['5.750', '19.5', '5.09'],
                        ['6.000', '15', '5.524'],
                        ['6.000', '20', '5.352'],
                        ['6.625', '13', '6.255'],
                        ['6.625', '20', '6.049'],
                        ['6.625', '32', '5.675'],
                      ],
                    ),
                  ],
                ),
              ),
              const ModuleTool(
                icon: Icons.table_chart,
                title: 'Sand Chart',
                subtitle: 'Sand measurement and weight reference',
                screen: ChartReferenceScreen(
                  title: 'Sand Chart',
                  description:
                      'Sand measurement and weight tables from the web app sand sheet.',
                  enableSearch: true,
                  sections: [
                    ChartSection(
                      title: 'Sand Measurement',
                      columns: ['From', '=', 'To'],
                      rows: [
                        ['1 Gallon', '=', '4 Quarts'],
                        ['1 Quart', '=', '4 Cups'],
                        ['1 Quart', '=', '2 Pints'],
                        ['1 Pint', '=', '2 Cups'],
                        ['1 Cup', '=', '16 Tblsp'],
                        ['1/2 Cup', '=', '8 Tblsp'],
                        ['1/4 Cup', '=', '4 Tblsp'],
                        ['1 Tblsp', '=', '3 Tsp'],
                      ],
                    ),
                    ChartSection(
                      title: 'Sand Weight',
                      columns: ['From', '=', 'Weight'],
                      rows: [
                        ['1 Bbl', '=', '756 lbs'],
                        ['1/2 Bbl', '=', '378 lbs'],
                        ['1/4 Bbl', '=', '189 lbs'],
                        ['1 Gal', '=', '18 lbs'],
                        ['1/2 Gal', '=', '9 lbs'],
                        ['1/4 Gal', '=', '4.5 lbs'],
                        ['1 Pint', '=', '2.3 lbs'],
                        ['1 Cup', '=', '1.1 lbs'],
                        ['1/2 Cup', '=', '0.55 lbs'],
                        ['1 Tblsp', '=', '0.07 lbs'],
                      ],
                    ),
                  ],
                ),
              ),
              const ModuleTool(
                icon: Icons.table_chart,
                title: 'Flanges Chart',
                subtitle: 'Flange pressure, gasket, studs, and wrench sizes',
                screen: ChartReferenceScreen(
                  title: 'Flanges Chart',
                  description:
                      'Flange table rows captured from the web app flange sheet.',
                  enableSearch: true,
                  sections: [
                    ChartSection(
                      title: 'Flanges',
                      columns: [
                        'Flange Size',
                        'Pressure',
                        'Ring Gasket',
                        'No. Studs',
                        'Stud Size',
                        'Nut Size',
                        'Oteco Wrench'
                      ],
                      rows: [
                        [
                          '1-11/16"',
                          '10000',
                          'BX-150',
                          '8',
                          '3/4"',
                          '1-1/4"',
                          '3/4"'
                        ],
                        [
                          '1-11/16"',
                          '15000',
                          'BX-150',
                          '8',
                          '3/4"',
                          '1-1/4"',
                          '3/4"'
                        ],
                        [
                          '1-13/16"',
                          '10000',
                          'BX-151',
                          '8',
                          '3/4"',
                          '1-1/4"',
                          '3/4"'
                        ],
                        [
                          '1-13/16"',
                          '15000',
                          'BX-151',
                          '8',
                          '7/8"',
                          '1-7/16"',
                          '7/8"'
                        ],
                        [
                          '1-13/16"',
                          '20000',
                          'BX-151',
                          '8',
                          '1"',
                          '1-5/8"',
                          '1"'
                        ],
                        [
                          '2-1/16"',
                          '10000',
                          'BX-152',
                          '8',
                          '3/4"',
                          '1-1/4"',
                          '3/4"'
                        ],
                        [
                          '2-1/16"',
                          '15000',
                          'BX-152',
                          '8',
                          '7/8"',
                          '1-7/16"',
                          '7/8"'
                        ],
                        [
                          '2-1/16"',
                          '20000',
                          'BX-152',
                          '8',
                          '1-1/8"',
                          '1-13/16"',
                          '1-1/8"'
                        ],
                        [
                          '2-9/16"',
                          '10000',
                          'BX-153',
                          '8',
                          '7/8"',
                          '1-7/16"',
                          '7/8"'
                        ],
                        [
                          '2-9/16"',
                          '15000',
                          'BX-153',
                          '8',
                          '1"',
                          '1-5/8"',
                          '1"'
                        ],
                        [
                          '2-9/16"',
                          '20000',
                          'BX-153',
                          '8',
                          '1-1/4"',
                          '2"',
                          '1-1/4"'
                        ],
                        [
                          '3-1/16"',
                          '10000',
                          'BX-154',
                          '8',
                          '1"',
                          '1-5/8"',
                          '1"'
                        ],
                        [
                          '3-1/16"',
                          '15000',
                          'BX-154',
                          '8',
                          '1-1/8"',
                          '1-13/16"',
                          '1-1/8"'
                        ],
                        [
                          '3-1/16"',
                          '20000',
                          'BX-154',
                          '8',
                          '1-3/8"',
                          '2-3/16"',
                          '1-3/8"'
                        ],
                        [
                          '4-1/16"',
                          '10000',
                          'BX-155',
                          '8',
                          '1-1/8"',
                          '1-13/16"',
                          '1-1/8"'
                        ],
                        [
                          '4-1/16"',
                          '15000',
                          'BX-155',
                          '8',
                          '1-3/8"',
                          '2-3/16"',
                          '1-3/8"'
                        ],
                        [
                          '4-1/16"',
                          '20000',
                          'BX-155',
                          '8',
                          '1-3/4"',
                          '2-3/4"',
                          '1-3/4"'
                        ],
                        [
                          '7-1/16"',
                          '10000',
                          'BX-156',
                          '12',
                          '1-1/2"',
                          '2-3/8"',
                          '1-1/2"'
                        ],
                        [
                          '7-1/16"',
                          '15000',
                          'BX-156',
                          '16',
                          '1-1/2"',
                          '2-3/8"',
                          '1-1/2"'
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          _moduleCard(
            context: context,
            icon: Icons.account_tree,
            title: 'Rig-Up',
            subtitle: 'Layout Designer, Rig-Up Inventory, and Rig-Up History',
            tools: const [
              ModuleTool(
                icon: Icons.account_tree,
                title: 'Layout Designer',
                subtitle: 'Design rig-up layouts and iron flow paths',
                screen: EquipmentLayoutScreen(),
              ),
              ModuleTool(
                icon: Icons.inventory_2_outlined,
                title: 'Rig-Up Inventory',
                subtitle: 'Track equipment, assign by well, and share summary',
                screen: RigUpInventoryScreen(),
              ),
              ModuleTool(
                icon: Icons.history,
                title: 'Rig-Up History',
                subtitle: 'Open, share, or delete saved rig-up records',
                screen: RigUpHistoryScreen(),
              ),
            ],
          ),
          ToolCard(
            icon: Icons.assignment,
            title: 'JSA',
            subtitle: 'Safety worksheet, crew rows, and signatures',
            onTap: () => open(context, const JsaScreen()),
          ),
          ToolCard(
            icon: Icons.history,
            title: 'History',
            subtitle: 'Search archived jobs and past shift records',
            onTap: () => open(context, const ProductionHistoryScreen()),
          ),
        ],
      ),
    );
  }
}
