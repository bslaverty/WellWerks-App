import 'package:flutter/material.dart';

import '../models/job_setup.dart';
import '../models/operations_log_entry.dart';
import '../services/job_storage_service.dart';
import '../services/operations_log_service.dart';
import '../services/production_shift_service.dart';
import '../widgets/app_header.dart';
import 'jsa_screen.dart';
import 'operations_log_screen.dart';
import 'production_dashboard_screen.dart';
import 'production_history_screen.dart';
import 'production_rate_calculator_menu_screen.dart';

class DrilloutCleanoutModuleScreen extends StatefulWidget {
  const DrilloutCleanoutModuleScreen({super.key});

  @override
  State<DrilloutCleanoutModuleScreen> createState() =>
      _DrilloutCleanoutModuleScreenState();
}

class _DrilloutCleanoutModuleScreenState
    extends State<DrilloutCleanoutModuleScreen> {
  final _jobStorage = JobStorageService();
  final _shiftService = ProductionShiftService();
  final _logService = OperationsLogService();

  JobSetup? _activeJob;
  List<OperationsLogEntry> _recentEntries = const [];
  DateTime? _shiftUpdatedAt;
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
    final activeJob = await _jobStorage.ensureActiveJobLoaded();
    final shift = await _shiftService.loadActiveShift();
    final jobId = activeJob?.id.trim() ?? shift.activeJobId.trim();
    final recentEntries = jobId.isEmpty
        ? const <OperationsLogEntry>[]
        : await _logService.loadEntries(
            workflow: OperationsLogWorkflow.drillout,
            jobId: jobId,
          );
    if (!mounted) return;
    setState(() {
      _activeJob = activeJob;
      _recentEntries = recentEntries.reversed.take(5).toList();
      _shiftUpdatedAt = shift.updatedAt;
      _loading = false;
    });
  }

  Future<void> _open(BuildContext context, Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _load();
  }

  String _jobTitle() {
    final activeJob = _activeJob;
    if (activeJob == null) return 'No active job';
    final company = activeJob.company.trim();
    final pad = activeJob.padName.trim();
    if (company.isEmpty && pad.isEmpty) return 'Active job';
    if (company.isEmpty) return pad;
    if (pad.isEmpty) return company;
    return '$company • $pad';
  }

  String _updatedText() {
    final updatedAt = _shiftUpdatedAt;
    if (updatedAt == null) return 'Updated just now';
    final diff = DateTime.now().difference(updatedAt);
    if (diff.inMinutes < 1) return 'Updated just now';
    if (diff.inHours < 1) return 'Updated ${diff.inMinutes} min ago';
    if (diff.inDays < 1) return 'Updated ${diff.inHours} hr ago';
    return 'Updated ${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
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

  Widget _headerBanner() {
    final scheme = Theme.of(context).colorScheme;
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
                        _jobTitle(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Production',
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.place, color: scheme.primary, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _activeJob?.padName.trim().isEmpty ?? true
                                  ? 'No pad selected'
                                  : _activeJob!.padName.trim(),
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            _updatedText(),
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
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

  Widget _workflowOverview() {
    final scheme = Theme.of(context).colorScheme;
    const steps = [
      ('Log Operations', 'Record drillout and cleanup activities'),
      ('Calculate Rates', 'Use rate calculator and other tools'),
      ('Shift Tools', 'Generate handoffs and text updates'),
      ('Review & Share', 'Export, share, or save to history'),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Workflow Overview',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              for (var index = 0; index < steps.length; index++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              steps[index].$1,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              steps[index].$2,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (index < steps.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 13),
                    child:
                        Container(width: 2, height: 10, color: scheme.primary),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickAccessTile({
    required IconData icon,
    required String title,
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
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAccess() {
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
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Quick Access',
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
                childAspectRatio: 0.88,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                children: [
                  _quickAccessTile(
                    icon: Icons.list_alt,
                    title: 'Operations Log',
                    onTap: () => _open(
                      context,
                      const OperationsLogScreen(
                        workflow: OperationsLogWorkflow.drillout,
                        title: 'Drillout Log',
                      ),
                    ),
                  ),
                  _quickAccessTile(
                    icon: Icons.speed,
                    title: 'Rate Calculator',
                    onTap: () => _open(
                      context,
                      const ProductionRateCalculatorMenuScreen(),
                    ),
                  ),
                  _quickAccessTile(
                    icon: Icons.tune,
                    title: 'Shift Tools & Updates',
                    onTap: () => _open(
                      context,
                      const ProductionHistoryScreen(),
                    ),
                  ),
                  _quickAccessTile(
                    icon: Icons.fact_check,
                    title: 'JSA',
                    onTap: () => _open(context, const JsaScreen()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentEntriesCard() {
    final scheme = Theme.of(context).colorScheme;
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
                  Text(
                    'Recent Entries',
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _open(
                      context,
                      const OperationsLogScreen(
                        workflow: OperationsLogWorkflow.drillout,
                        title: 'Drillout Log',
                      ),
                    ),
                    child: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (_recentEntries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'No recent drillout entries yet.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              else
                ..._recentEntries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _open(
                        context,
                        const OperationsLogScreen(
                          workflow: OperationsLogWorkflow.drillout,
                          title: 'Drillout Log',
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.timeline,
                              color: scheme.primary,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${entry.readingTimestamp.hour.toString().padLeft(2, '0')}:${entry.readingTimestamp.minute.toString().padLeft(2, '0')} • ${entry.wellName}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  entry.operationStage.isEmpty
                                      ? entry.entryType
                                      : entry.operationStage,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Completed',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.chevron_right, color: scheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _open(
                    context,
                    const OperationsLogScreen(
                      workflow: OperationsLogWorkflow.drillout,
                      title: 'Drillout Log',
                    ),
                  ),
                  child: const Text('Add Entry'),
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
              onTap: () => _open(context, const ProductionDashboardScreen()),
            ),
            tab(icon: Icons.list_alt, label: 'Log', active: true),
            tab(
              icon: Icons.speed_outlined,
              label: 'Calculator',
              onTap: () => _open(
                context,
                const ProductionRateCalculatorMenuScreen(),
              ),
            ),
            tab(
              icon: Icons.fact_check_outlined,
              label: 'JSA',
              onTap: () => _open(context, const JsaScreen()),
            ),
            tab(
              icon: Icons.history_outlined,
              label: 'History',
              onTap: () => _open(context, const ProductionHistoryScreen()),
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
        appBar: AppHeader(title: 'Drillout / Cleanout', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Drillout / Cleanout', showBack: true),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              children: [
                _headerBanner(),
                _workflowOverview(),
                _quickAccess(),
                _recentEntriesCard(),
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
