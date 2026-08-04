import 'package:flutter/material.dart';

import '../models/job_box_inventory.dart';
import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../services/job_storage_service.dart';
import '../services/production_shift_service.dart';
import '../widgets/app_header.dart';
import 'drillout_cleanout_module_screen.dart';
import 'job_box_inventory_screen.dart';
import 'jsa_screen.dart';
import 'production_dashboard_screen.dart';
import 'production_history_screen.dart';
import 'rate_calculator_screen.dart';

class CompletionsDashboardScreen extends StatefulWidget {
  const CompletionsDashboardScreen({super.key});

  @override
  State<CompletionsDashboardScreen> createState() =>
      _CompletionsDashboardScreenState();
}

class _CompletionsDashboardScreenState
    extends State<CompletionsDashboardScreen> {
  final _jobStorage = JobStorageService();
  final _shiftService = ProductionShiftService();

  ProductionShift _shift = ProductionShift.empty();
  JobSetup? _activeJob;
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
    final shift = await _shiftService.loadActiveShift();
    final activeJob = await _jobStorage.ensureActiveJobLoaded();
    if (!mounted) return;
    setState(() {
      _shift = shift;
      _activeJob = activeJob;
      _loading = false;
    });
  }

  Future<void> _open(BuildContext context, Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _load();
  }

  String _relativeUpdatedText() {
    final diff = DateTime.now().difference(_shift.updatedAt);
    if (diff.inMinutes < 1) return 'Updated just now';
    if (diff.inHours < 1) return 'Updated ${diff.inMinutes} min ago';
    if (diff.inDays < 1) return 'Updated ${diff.inHours} hr ago';
    return 'Updated ${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }

  List<String> get _wells {
    final activeJob = _activeJob;
    final source = activeJob != null && activeJob.resolvedWellNames.isNotEmpty
        ? activeJob.resolvedWellNames
        : _shift.header.wells;
    final wells = <String>[];
    for (final well in source) {
      final trimmed = well.trim();
      if (trimmed.isNotEmpty && !wells.contains(trimmed)) {
        wells.add(trimmed);
      }
    }
    return wells;
  }

  Widget _card({required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.95)),
      ),
      child: child,
    );
  }

  Widget _activeJobBanner() {
    final scheme = Theme.of(context).colorScheme;
    final activeJob = _activeJob;
    final jobTitle = activeJob == null
        ? 'No active job'
        : [activeJob.company.trim(), activeJob.padName.trim()]
            .where((item) => item.isNotEmpty)
            .join(' • ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(context, const ProductionDashboardScreen()),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                  child: Icon(Icons.circle, color: scheme.primary, size: 14),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Active Job',
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        jobTitle.isEmpty ? 'No active job' : jobTitle,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Completions',
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
                          if (_wells.isNotEmpty)
                            _jobChip('Wells', _wells.join(', ')),
                          _jobChip('Checks', '${_shift.hourlyChecks.length}'),
                          _jobChip('Updated', _relativeUpdatedText()),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.primary, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _jobChip(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(
          value,
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _quickAction({
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
      child: _card(
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
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.88,
                children: [
                  _quickAction(
                    icon: Icons.list_alt,
                    label: 'Operations Log',
                    onTap: () => _open(
                      context,
                      const DrilloutCleanoutModuleScreen(),
                    ),
                  ),
                  _quickAction(
                    icon: Icons.speed,
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
                  _quickAction(
                    icon: Icons.fact_check,
                    label: 'JSA',
                    onTap: () => _open(context, const JsaScreen()),
                  ),
                  _quickAction(
                    icon: Icons.inventory_2_outlined,
                    label: 'Job Box',
                    onTap: () => _open(
                      context,
                      const JobBoxInventoryScreen(
                        source: JobBoxInventorySource.completions,
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

  Widget _toolItem({
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
                        fontSize: 17, fontWeight: FontWeight.w800),
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

  Widget _toolsCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Completions Tools',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              _toolItem(
                icon: Icons.text_snippet_outlined,
                title: 'Drillout / Cleanout',
                subtitle:
                    'Operations Log, rate calculator, STS, and shift tools',
                onTap: () =>
                    _open(context, const DrilloutCleanoutModuleScreen()),
              ),
              const Divider(height: 1),
              _toolItem(
                icon: Icons.calculate_outlined,
                title: 'Calculators',
                subtitle:
                    'Gas Accum, Bottoms Up, Multiple Choke, Conversion, and Chlorides',
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
              const Divider(height: 1),
              _toolItem(
                icon: Icons.fact_check_outlined,
                title: 'JSA',
                subtitle:
                    'Prefills from active workflow and active job context',
                onTap: () => _open(context, const JsaScreen()),
              ),
              const Divider(height: 1),
              _toolItem(
                icon: Icons.inventory_2_outlined,
                title: 'Job Box Inventory',
                subtitle: 'Track completions job box inventory and sync drafts',
                onTap: () => _open(
                  context,
                  const JobBoxInventoryScreen(
                    source: JobBoxInventorySource.completions,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomNav() {
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
                label: 'Completions',
                active: true),
            tab(
              icon: Icons.speed_outlined,
              label: 'Calculators',
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
            tab(
              icon: Icons.fact_check_outlined,
              label: 'JSA',
              onTap: () => _open(context, const JsaScreen()),
            ),
            tab(
              icon: Icons.history_outlined,
              label: 'Reports',
              onTap: () => _open(context, const ProductionHistoryScreen()),
            ),
            tab(
              icon: Icons.home_outlined,
              label: 'Production',
              onTap: () => _open(context, const ProductionDashboardScreen()),
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
        appBar: AppHeader(title: 'Completions', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Completions', showBack: true),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              children: [
                _activeJobBanner(),
                _quickActionsCard(),
                _toolsCard(),
                const SizedBox(height: 84),
              ],
            ),
          ),
          _bottomNav(),
        ],
      ),
    );
  }
}
