import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/job_setup.dart';
import '../services/job_storage_service.dart';
import '../services/recovery_state_service.dart';
import '../services/rig_up_inventory_service.dart';
import '../widgets/app_header.dart';
import 'equipment_layout_screen.dart';
import 'rig_up_history_screen.dart';
import 'rig_up_inventory_screen.dart';
import 'settings_screen.dart';

class RigUpDashboardScreen extends StatefulWidget {
  const RigUpDashboardScreen({super.key});

  @override
  State<RigUpDashboardScreen> createState() => _RigUpDashboardScreenState();
}

class _RigUpDashboardScreenState extends State<RigUpDashboardScreen> {
  static const Color _gold = Color(0xFFCDA56A);

  final _jobStorage = JobStorageService();
  final _inventoryService = RigUpInventoryService();
  final _recoveryState = RecoveryStateService();

  JobSetup? _activeJob;
  List<Map<String, dynamic>> _records = const [];
  Map<String, dynamic>? _latestRecord;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _recoveryState.saveLastModule(RecoveryModules.layoutDesigner);
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
    final records = await _inventoryService.loadAllRecords();
    if (!mounted) return;
    setState(() {
      _activeJob = activeJob;
      _records = records;
      _latestRecord = records.isEmpty ? null : records.first;
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
    if (company.isEmpty && pad.isEmpty) return 'Active rig-up';
    if (company.isEmpty) return pad;
    if (pad.isEmpty) return company;
    return '$company • $pad';
  }

  String _statusText() {
    return _activeJob == null ? 'No active rig-up' : 'Ready to Rig Up';
  }

  String _updatedText() {
    final updatedAt = _latestRecord?['updatedAt']?.toString().trim() ?? '';
    if (updatedAt.isNotEmpty) {
      final parsed = DateTime.tryParse(updatedAt);
      if (parsed != null) {
        final now = DateTime.now();
        final sameDay = parsed.year == now.year &&
            parsed.month == now.month &&
            parsed.day == now.day;
        if (sameDay) {
          return 'Last Updated: Today • ${DateFormat('h:mm a').format(parsed)}';
        }
        return 'Last Updated: ${DateFormat('MMM d').format(parsed)} • ${DateFormat('h:mm a').format(parsed)}';
      }
    }
    return 'Last Updated: Just now';
  }

  List<String> get _wells {
    final activeJob = _activeJob;
    final source = activeJob != null && activeJob.resolvedWellNames.isNotEmpty
        ? activeJob.resolvedWellNames
        : List<String>.from(_latestRecord?['wells'] as List? ?? const []);
    final wells = <String>[];
    for (final well in source) {
      final trimmed = well.trim();
      if (trimmed.isNotEmpty && !wells.contains(trimmed)) {
        wells.add(trimmed);
      }
    }
    return wells;
  }

  int _equipmentCount() {
    final counts = Map<String, dynamic>.from(
      _latestRecord?['counts'] as Map? ?? const <String, dynamic>{},
    );
    var total = 0;
    for (final value in counts.values) {
      if (value is int) {
        total += value;
      } else if (value is num) {
        total += value.toInt();
      } else {
        total += int.tryParse(value.toString()) ?? 0;
      }
    }
    return total;
  }

  String _ironSizeLabel() {
    final counts = Map<String, dynamic>.from(
      _latestRecord?['counts'] as Map? ?? const <String, dynamic>{},
    );

    int groupTotal(String prefix) {
      var total = 0;
      for (final entry in counts.entries) {
        if (!entry.key.startsWith(prefix)) continue;
        final value = entry.value;
        if (value is int) {
          total += value;
        } else if (value is num) {
          total += value.toInt();
        } else {
          total += int.tryParse(value.toString()) ?? 0;
        }
      }
      return total;
    }

    final twoInch = groupTotal('iron2');
    final threeInch = groupTotal('iron3');
    final fourInch = groupTotal('iron4');

    if (threeInch >= twoInch && threeInch >= fourInch && threeInch > 0) {
      return '3"';
    }
    if (twoInch >= threeInch && twoInch >= fourInch && twoInch > 0) {
      return '2"';
    }
    if (fourInch > 0) return '4"';
    return '--';
  }

  int _completionPercent() {
    final counts = Map<String, dynamic>.from(
      _latestRecord?['counts'] as Map? ?? const <String, dynamic>{},
    );
    if (counts.isEmpty) return 0;
    final total = counts.length;
    final missing = _missingCount();
    final complete = (total - missing).clamp(0, total);
    return ((complete / total) * 100).round();
  }

  int _missingCount() {
    final counts = Map<String, dynamic>.from(
      _latestRecord?['counts'] as Map? ?? const <String, dynamic>{},
    );
    return counts.values.where((value) {
      if (value is int) return value <= 0;
      if (value is num) return value <= 0;
      return (int.tryParse(value.toString()) ?? 0) <= 0;
    }).length;
  }

  int _assignedCount() {
    final raw = _latestRecord?['assignedByWell'];
    if (raw is! Map) return 0;
    var total = 0;
    for (final entry in raw.values) {
      if (entry is! Map) continue;
      for (final value in entry.values) {
        if (value is int) {
          total += value;
        } else if (value is num) {
          total += value.toInt();
        } else {
          total += int.tryParse(value.toString()) ?? 0;
        }
      }
    }
    return total;
  }

  String _lastOpenedText() {
    final customer = (_latestRecord?['customer']?.toString() ?? '').trim();
    final pad = (_latestRecord?['pad']?.toString() ?? '').trim();
    if (customer.isEmpty && pad.isEmpty) return 'No saved layout yet';
    if (customer.isEmpty) return pad;
    if (pad.isEmpty) return customer;
    return '$customer • $pad';
  }

  Future<void> _shareLatestRecord() async {
    final text = _latestRecord?['inventoryText']?.toString().trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save a rig-up inventory first.')),
      );
      return;
    }
    await Share.share(text, subject: 'Rig-Up Inventory');
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

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.green.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.green,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _metric({required String value, required String label}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _statusCard() {
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
                    'RIG-UP STATUS',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _open(context, const RigUpInventoryScreen()),
                    icon: const Icon(Icons.chevron_right, size: 18),
                    label: const Text('View Summary'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _statusText(),
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.account_tree_outlined,
                      color: scheme.primary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _jobTitle(),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Rig-Up',
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _metric(value: '${_wells.length}', label: 'Wells'),
                  ),
                  Container(
                    width: 1,
                    height: 48,
                    color: scheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                  Expanded(
                    child: _metric(
                      value: '${_equipmentCount()}',
                      label: 'Equipment',
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 48,
                    color: scheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                  Expanded(
                    child: _metric(value: _ironSizeLabel(), label: 'Iron Size'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _chip('Layout Complete'),
                  _chip('Inventory Assigned'),
                  _chip('Flow Path Verified'),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _updatedText(),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () =>
                        _open(context, const EquipmentLayoutScreen()),
                    child: const Text('Open Active Rig-Up'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _workflowCard() {
    final scheme = Theme.of(context).colorScheme;
    const steps = [
      ('Design Layout', 'Create rig-up layout and flow paths'),
      ('Assign Equipment', 'Build inventory and assign by well'),
      ('Save & Share', 'Review, export, and share rig-up'),
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
                'RIG-UP WORKFLOW',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _workflowStep('1', steps[0].$1, steps[0].$2)),
                  const Icon(Icons.arrow_forward, color: _gold),
                  Expanded(child: _workflowStep('2', steps[1].$1, steps[1].$2)),
                  const Icon(Icons.arrow_forward, color: _gold),
                  Expanded(child: _workflowStep('3', steps[2].$1, steps[2].$2)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _workflowStep(String number, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: _gold,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _featureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String metaLeft,
    required String metaRight,
    required VoidCallback onTap,
    Widget? rightWidget,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: scheme.primary, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              metaLeft,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              metaRight,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (rightWidget != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: rightWidget,
                  )
                else
                  Icon(Icons.chevron_right, color: scheme.primary, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickActionsCard() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'QUICK ACTIONS',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
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
                  _quickAction(
                    icon: Icons.add_circle_outline,
                    label: 'New Layout',
                    onTap: () => _open(context, const EquipmentLayoutScreen()),
                  ),
                  _quickAction(
                    icon: Icons.photo_outlined,
                    label: 'Import Photo',
                    onTap: () => _open(context, const EquipmentLayoutScreen()),
                  ),
                  _quickAction(
                    icon: Icons.share_outlined,
                    label: 'Share Rig-Up',
                    onTap: _shareLatestRecord,
                  ),
                  _quickAction(
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'Export PDF',
                    onTap: () => _open(context, const EquipmentLayoutScreen()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
                icon: Icons.account_tree_outlined,
                label: 'Rig-Up',
                active: true),
            tab(
              icon: Icons.history,
              label: 'Reports',
              onTap: () => _open(context, const RigUpHistoryScreen()),
            ),
            tab(
              icon: Icons.inventory_2_outlined,
              label: 'Equipment',
              onTap: () => _open(context, const RigUpInventoryScreen()),
            ),
            tab(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () => _open(context, const SettingsScreen()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _completionRing() {
    final percent = _completionPercent();
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 74,
      height: 74,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: (percent.clamp(0, 100)) / 100,
            strokeWidth: 7,
            backgroundColor: scheme.outlineVariant.withValues(alpha: 0.35),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
          ),
          Text(
            '$percent%',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(
            title: 'Rig-Up', showBack: true, showActiveJobBanner: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const AppHeader(
        title: 'Rig-Up',
        showBack: true,
        showActiveJobBanner: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _statusCard(),
          _workflowCard(),
          _featureCard(
            icon: Icons.account_tree_outlined,
            title: 'Layout Designer',
            subtitle: 'Current Layout',
            metaLeft: '${_wells.length} Wells',
            metaRight: '${_equipmentCount()} Equipment',
            onTap: () => _open(context, const EquipmentLayoutScreen()),
          ),
          _featureCard(
            icon: Icons.inventory_2_outlined,
            title: 'Rig-Up Inventory',
            subtitle: 'Equipment Assigned',
            metaLeft: '${_assignedCount()}',
            metaRight: '${_missingCount()} Missing',
            onTap: () => _open(context, const RigUpInventoryScreen()),
            rightWidget: _completionRing(),
          ),
          _featureCard(
            icon: Icons.history,
            title: 'Rig-Up History',
            subtitle: 'Saved Layouts',
            metaLeft: '${_records.length}',
            metaRight: _lastOpenedText(),
            onTap: () => _open(context, const RigUpHistoryScreen()),
          ),
          _quickActionsCard(),
          const SizedBox(height: 6),
        ],
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }
}
