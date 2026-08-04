import 'package:flutter/material.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../services/active_workflow_mode_service.dart';
import '../services/job_storage_service.dart';
import '../services/production_shift_service.dart';
import '../widgets/app_header.dart';
import 'job_management_screen.dart';
import 'pressure_entry_screen.dart';
import 'production_inventory_screen.dart';
import 'production_history_screen.dart';
import 'rate_calculator_screen.dart';
import 'report_template_screen.dart';
import 'shift_report_screen.dart';
import 'text_update_screen.dart';

class ProductionDashboardScreen extends StatefulWidget {
  const ProductionDashboardScreen({super.key});

  @override
  State<ProductionDashboardScreen> createState() =>
      _ProductionDashboardScreenState();
}

class _ProductionDashboardScreenState extends State<ProductionDashboardScreen> {
  final _jobStorage = JobStorageService();
  final _shiftService = ProductionShiftService();
  final _workflowModeService = ActiveWorkflowModeService.instance;

  ProductionShift _shift = ProductionShift.empty();
  JobSetup? _activeJob;
  ActiveWorkflowMode _workflowMode = ActiveWorkflowMode.production;
  bool _loading = true;

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
    final resolvedJob =
        activeJob ?? await _jobStorage.resolveProductionActiveJob(shift);
    if (resolvedJob != null && shift.activeJobId != resolvedJob.id) {
      shift = shift.copyWith(activeJobId: resolvedJob.id);
      await _shiftService.saveActiveShift(shift);
    }
    if (!mounted) return;
    setState(() {
      _shift = shift;
      _activeJob = resolvedJob;
      _workflowMode = workflowMode;
      _loading = false;
    });
  }

  Future<void> _open(BuildContext context, Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _load();
  }

  List<String> get _activeWells {
    final wells = <String>[];
    final activeJob = _activeJob;
    final source = activeJob != null && activeJob.resolvedWellNames.isNotEmpty
        ? activeJob.resolvedWellNames
        : _shift.header.wells;
    for (final well in source) {
      final trimmed = well.trim();
      if (trimmed.isNotEmpty && !wells.contains(trimmed)) {
        wells.add(trimmed);
      }
    }
    return wells;
  }

  bool get _hasActiveJobContext {
    return _activeJob != null ||
        _shift.activeJobId.trim().isNotEmpty ||
        _shift.header.company.trim().isNotEmpty ||
        _shift.header.pad.trim().isNotEmpty ||
        _activeWells.isNotEmpty;
  }

  String get _activeCompanyName {
    final fromJob = _activeJob?.company.trim() ?? '';
    if (fromJob.isNotEmpty) return fromJob;
    final fromShift = _shift.header.company.trim();
    return fromShift;
  }

  String get _activePadName {
    final fromJob = _activeJob?.padName.trim() ?? '';
    if (fromJob.isNotEmpty) return fromJob;
    return _shift.header.pad.trim();
  }

  String get _activeJobTitle {
    final company = _activeCompanyName;
    final pad = _activePadName;
    if (company.isEmpty && pad.isEmpty) return 'No active job';
    if (company.isEmpty) return pad;
    if (pad.isEmpty) return company;
    return '$company • $pad';
  }

  String _relativeUpdatedText() {
    final diff = DateTime.now().difference(_shift.updatedAt);
    if (diff.inMinutes < 1) return 'Updated just now';
    if (diff.inHours < 1) return 'Updated ${diff.inMinutes} min ago';
    if (diff.inDays < 1) return 'Updated ${diff.inHours} hr ago';
    return 'Updated ${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }

  Widget _dashboardCard({required Widget child}) {
    return Container(
      decoration: _homeCardDecoration(context),
      child: child,
    );
  }

  Widget _activeJobBanner() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: _homeCardDecoration(context),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(context, const JobManagementScreen()),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.circle, color: scheme.primary, size: 14),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hasActiveJobContext ? 'Active Job' : 'No active job',
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _activeJobTitle,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _workflowMode == ActiveWorkflowMode.production
                          ? 'Production'
                          : 'Completions',
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      children: [
                        if (_activeJob?.resolvedWellNames.isNotEmpty ?? false)
                          _jobMetaChip(
                            icon: Icons.place,
                            text: _activeJob!.resolvedWellNames.join(', '),
                          ),
                        _jobMetaChip(
                          icon: Icons.oil_barrel_outlined,
                          text: _activeWells.isEmpty
                              ? '0 wells'
                              : '${_activeWells.length} wells',
                        ),
                        _jobMetaChip(
                          icon: Icons.schedule,
                          text: _relativeUpdatedText(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.primary, size: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _jobMetaChip({
    required IconData icon,
    required String text,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: scheme.primary, size: 16),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.9)),
          color: Theme.of(context).cardColor,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: scheme.primary, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionsCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _dashboardCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.flash_on,
                      color: Theme.of(context).colorScheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Quick Actions',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                childAspectRatio: 0.82,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                children: [
                  _quickActionButton(
                    icon: Icons.add_circle_outline,
                    label: 'Quick Round',
                    onTap: () => _open(context, const PressureEntryScreen()),
                  ),
                  _quickActionButton(
                    icon: Icons.table_chart_outlined,
                    label: 'Production Report',
                    onTap: () => _open(context, const ShiftReportScreen()),
                  ),
                  _quickActionButton(
                    icon: Icons.speed_outlined,
                    label: 'Rate Calculator',
                    onTap: () => _open(
                      context,
                      const RateCalculatorScreen(
                        config: RateCalculatorConfig.chart(
                          'Flowback Tank (V-Bottom)',
                          'flowback500',
                          storageId: 'production_flowback500',
                          allowOperationsLogAutoSave: false,
                          rateLogEnabledByDefault: true,
                        ),
                        homeMultiMode: true,
                        availableConfigs: kProductionRateCalculatorConfigs,
                      ),
                    ),
                  ),
                  _quickActionButton(
                    icon: Icons.chat_bubble_outline,
                    label: 'Text Update',
                    onTap: () => _open(context, const TextUpdateScreen()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: scheme.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _productionSectionsCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _dashboardCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Production Sections',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              _sectionItem(
                icon: Icons.inventory_2_outlined,
                title: 'Tank Inventory',
                subtitle:
                    'Tank levels, running totals, and production inventory',
                onTap: () => _open(context, const ProductionInventoryScreen()),
              ),
              const Divider(height: 1),
              _sectionItem(
                icon: Icons.history_outlined,
                title: 'Production History',
                subtitle: 'Archived reports, checks, and text updates',
                onTap: () => _open(context, const ProductionHistoryScreen()),
              ),
              const Divider(height: 1),
              _sectionItem(
                icon: Icons.sticky_note_2_outlined,
                title: 'Notes',
                subtitle: 'Text updates and production notes',
                onTap: () => _open(context, const TextUpdateScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomTabBar() {
    final scheme = Theme.of(context).colorScheme;

    Widget tab({
      required IconData icon,
      required String label,
      bool active = false,
      VoidCallback? onTap,
    }) {
      final color = active ? scheme.primary : scheme.onSurfaceVariant;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.9)),
        ),
        child: Row(
          children: [
            tab(
                icon: Icons.dashboard_outlined,
                label: 'Production',
                active: true),
            tab(
              icon: Icons.article_outlined,
              label: 'Reports',
              onTap: () => _open(context, const ProductionHistoryScreen()),
            ),
            tab(
              icon: Icons.chat_bubble_outline,
              label: 'Text Updates',
              onTap: () => _open(context, const TextUpdateScreen()),
            ),
            tab(
              icon: Icons.settings_outlined,
              label: 'Setup',
              onTap: () => _open(
                context,
                const ReportTemplateScreen(initialSection: 'inventory'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _homeCardDecoration(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: Theme.of(context).cardColor,
      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.95)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Production', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Production', showBack: true),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              children: [
                _activeJobBanner(),
                _quickActionsCard(),
                _productionSectionsCard(),
                const SizedBox(height: 84),
              ],
            ),
          ),
          _bottomTabBar(),
        ],
      ),
    );
  }
}
