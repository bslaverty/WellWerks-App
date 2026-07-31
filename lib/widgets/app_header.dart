import 'package:flutter/material.dart';

import '../models/job_setup.dart';
import '../screens/drillout_cleanout_module_screen.dart';
import '../screens/job_management_screen.dart';
import '../screens/job_setup_screen.dart';
import '../screens/production_dashboard_screen.dart';
import '../screens/shift_handoff_screen.dart';
import '../screens/settings_screen.dart';
import '../services/active_workflow_mode_service.dart';
import '../services/job_storage_service.dart';
import '../services/jsa_storage_service.dart';
import '../services/production_shift_service.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBack;
  final bool showHomeAction;
  final List<Widget>? trailingActions;
  final bool showActiveJobBanner;

  const AppHeader({
    super.key,
    this.title = 'WellWerks Toolbox',
    this.showBack = false,
    this.showHomeAction = false,
    this.trailingActions,
    this.showActiveJobBanner = true,
  });

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _goHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      elevation: 0,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            )
          : IconButton(
              icon: const Icon(Icons.home),
              onPressed: () => _goHome(context),
            ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          Image.asset('assets/images/app-icon.png',
              width: 34,
              height: 34,
              errorBuilder: (_, __, ___) => const SizedBox()),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(color: colors.primary, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: trailingActions ??
          [
            if (showBack || showHomeAction)
              IconButton(
                icon: const Icon(Icons.home),
                onPressed: () => _goHome(context),
              )
            else
              const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () => _openSettings(context),
            ),
          ],
      bottom: showActiveJobBanner
          ? const PreferredSize(
              preferredSize: Size.fromHeight(38),
              child: _ActiveJobModeBanner(),
            )
          : null,
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (showActiveJobBanner ? 38 : 0));
}

class _ActiveJobModeBanner extends StatefulWidget {
  const _ActiveJobModeBanner();

  @override
  State<_ActiveJobModeBanner> createState() => _ActiveJobModeBannerState();
}

class _ActiveJobModeBannerState extends State<_ActiveJobModeBanner> {
  final _jobStorage = JobStorageService();
  final _workflowMode = ActiveWorkflowModeService.instance;
  final _shiftService = ProductionShiftService();
  final _jsaStorage = JsaStorageService();

  @override
  void initState() {
    super.initState();
    _workflowMode.mode.addListener(_handleModeChanged);
    _jobStorage.activeJobListenable.addListener(_handleJobChanged);
    _hydrate();
  }

  Future<void> _hydrate() async {
    await _jobStorage.ensureActiveJobLoaded();
    await _workflowMode.ensureLoaded();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _workflowMode.mode.removeListener(_handleModeChanged);
    _jobStorage.activeJobListenable.removeListener(_handleJobChanged);
    super.dispose();
  }

  void _handleModeChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleJobChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _jobSummary(JobSetup job) {
    final company = job.company.trim().isEmpty ? '-' : job.company.trim();
    final well = job.primaryWell.trim();
    final pad = job.padName.trim();
    final middle = well.isNotEmpty ? well : (pad.isNotEmpty ? pad : '-');
    return '$company • $middle';
  }

  String _workflowLabel(JobSetup? job) {
    final raw = (job?.workflow ?? '').trim().toLowerCase();
    if (raw == 'drillout') return 'Drillout';
    if (raw == 'cleanout') return 'Cleanout';
    return 'Production';
  }

  Future<void> _openActiveJobHub() async {
    final activeJob = _jobStorage.activeJobListenable.value;
    final jobs = await _jobStorage.loadJobs();
    final switchableJobs = jobs
        .where((item) => item.status.trim().toLowerCase() != 'archived')
        .toList(growable: false);

    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: const Text(
                  'Active Job Hub',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  activeJob == null
                      ? 'No active job selected'
                      : _jobSummary(activeJob),
                ),
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.build_circle_outlined),
                title: const Text('Job Setup'),
                onTap: () => Navigator.of(sheetContext).pop('jobSetup'),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Start New Job'),
                onTap: () => Navigator.of(sheetContext).pop('startNew'),
              ),
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('Resume Job'),
                enabled: activeJob != null,
                onTap: activeJob == null
                    ? null
                    : () => Navigator.of(sheetContext).pop('resume'),
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Switch Active Job'),
                enabled: switchableJobs.isNotEmpty,
                onTap: switchableJobs.isEmpty
                    ? null
                    : () => Navigator.of(sheetContext).pop('switch'),
              ),
              ListTile(
                leading: const Icon(Icons.stop_circle_outlined),
                title: const Text('End Active Job'),
                enabled: activeJob != null,
                onTap: activeJob == null
                    ? null
                    : () => Navigator.of(sheetContext).pop('end'),
              ),
              ListTile(
                leading: const Icon(Icons.compare_arrows),
                title: const Text('Handoff'),
                onTap: () => Navigator.of(sheetContext).pop('handoff'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'jobSetup':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => JobSetupScreen(
              startFreshJob: false,
              editActiveOnOpen: activeJob != null,
            ),
          ),
        );
        break;
      case 'startNew':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const JobSetupScreen(startFreshJob: true),
          ),
        );
        break;
      case 'resume':
        final current = _jobStorage.activeJobListenable.value;
        if (current == null) break;
        final workflow = current.workflow.trim().toLowerCase();
        if (workflow == 'drillout') {
          await _workflowMode.setMode(ActiveWorkflowMode.drillout);
          if (!mounted) break;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const DrilloutCleanoutModuleScreen(),
            ),
          );
        } else if (workflow == 'cleanout') {
          await _workflowMode.setMode(ActiveWorkflowMode.cleanout);
          if (!mounted) break;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const DrilloutCleanoutModuleScreen(),
            ),
          );
        } else {
          await _workflowMode.setMode(ActiveWorkflowMode.production);
          if (!mounted) break;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ProductionDashboardScreen(),
            ),
          );
        }
        break;
      case 'switch':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const JobManagementScreen()),
        );
        break;
      case 'end':
        final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('End Active Job?'),
                content: const Text(
                  'This will end the active job and clear active shift context.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('End Job'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirmed) break;
        await _jobStorage.endActiveJob();
        await _shiftService.clearActiveShift();
        await _jsaStorage.clearDraft();
        if (!mounted) break;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Active job ended.')),
        );
        break;
      case 'handoff':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ShiftHandoffScreen()),
        );
        break;
    }

    await _hydrate();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final job = _jobStorage.activeJobListenable.value;

    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
      child: InkWell(
        onTap: _openActiveJobHub,
        child: Container(
          height: 38,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                'Active Job',
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  job == null ? 'No active job selected' : _jobSummary(job),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _workflowLabel(job),
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
