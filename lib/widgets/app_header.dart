import 'package:flutter/material.dart';

import '../models/job_setup.dart';
import '../screens/settings_screen.dart';
import '../services/active_workflow_mode_service.dart';
import '../services/job_storage_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final job = _jobStorage.activeJobListenable.value;
    if (job == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 38,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            'Job',
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _jobSummary(job),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          PopupMenuButton<ActiveWorkflowMode>(
            padding: EdgeInsets.zero,
            onSelected: (mode) => _workflowMode.setMode(mode),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: ActiveWorkflowMode.production,
                child: Text('Production'),
              ),
              PopupMenuItem(
                value: ActiveWorkflowMode.drillout,
                child: Text('Drillout'),
              ),
              PopupMenuItem(
                value: ActiveWorkflowMode.cleanout,
                child: Text('Cleanout'),
              ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ActiveWorkflowModeService.labelFor(_workflowMode.mode.value),
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: colors.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
