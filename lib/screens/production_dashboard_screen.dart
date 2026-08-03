import 'package:flutter/material.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../services/active_workflow_mode_service.dart';
import '../services/job_storage_service.dart';
import '../services/production_shift_service.dart';
import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';
import 'job_management_screen.dart';
import 'pressure_entry_screen.dart';
import 'production_inventory_screen.dart';
import 'production_history_screen.dart';
import 'production_rate_calculator_menu_screen.dart';
import 'report_template_screen.dart';
import 'shift_report_screen.dart';

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

  Widget _activeJobCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_hasActiveJobContext) {
      return Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Active Job',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'No active job selected',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _open(context, const JobManagementScreen()),
                  icon: const Icon(Icons.build_circle_outlined),
                  label: const Text('Manage Job >'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final companyName = _activeCompanyName;
    final padName = _activePadName;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              companyName.isEmpty
                  ? 'Production ready'
                  : 'Production ready • $companyName${padName.isEmpty ? '' : ' • $padName'}',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => _open(context, const JobManagementScreen()),
              icon: const Icon(Icons.build_circle_outlined),
              label: const Text('Open Job Management >'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            Color.lerp(scheme.surface, scheme.primary, 0.16) ?? scheme.surface,
            Color.lerp(scheme.surface, scheme.primary, 0.08) ?? scheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.oil_barrel,
              color: scheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Production Hub',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Run rounds, reports, inventory, and production rate tracking from one workflow.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
        ),
      ),
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
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _hero(context),
          if (_workflowMode == ActiveWorkflowMode.production)
            _activeJobCard(context),
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Production Workflow',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. Enter production data in Quick Round.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '2. Review current shift production in Production Report.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '3. Generate production outputs from Production Report actions.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _sectionLabel('PRIMARY WORKFLOW'),
          ToolCard(
            icon: Icons.add_circle,
            title: 'Quick Round',
            subtitle:
                'Primary production entry: gauges, hauled, pumped, and interval hours',
            onTap: () => _open(context, const PressureEntryScreen()),
          ),
          ToolCard(
            icon: Icons.table_chart,
            title: 'Production Report',
            subtitle:
                'Central reporting workspace for the current active shift and output actions',
            onTap: () => _open(context, const ShiftReportScreen()),
          ),
          ToolCard(
            icon: Icons.local_drink,
            title: 'Tank Inventory',
            subtitle: 'Tank levels, running totals, and production inventory',
            onTap: () => _open(context, const ProductionInventoryScreen()),
          ),
          ToolCard(
            icon: Icons.speed,
            title: 'Rate Calculator',
            subtitle:
                'Production-only tank rates and logs (excludes SandX / FS3)',
            onTap: () =>
                _open(context, const ProductionRateCalculatorMenuScreen()),
          ),
          const SizedBox(height: 10),
          _sectionLabel('SECONDARY'),
          ToolCard(
            icon: Icons.inventory,
            title: 'Production Setup',
            subtitle: 'Company, wells, report layout, and production defaults',
            onTap: () => _open(context,
                const ReportTemplateScreen(initialSection: 'inventory')),
          ),
          ToolCard(
            icon: Icons.history,
            title: 'Production History',
            subtitle:
                'Archived production reports, hourly checks, text updates, and JSA records',
            onTap: () => _open(context, const ProductionHistoryScreen()),
          ),
        ],
      ),
    );
  }
}
