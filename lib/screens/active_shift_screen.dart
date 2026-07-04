import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/round_reading.dart';
import '../services/round_storage_service.dart';
import '../widgets/app_header.dart';
import 'pressure_entry_screen.dart';
import 'production_inventory_screen.dart';
import 'equipment_screen.dart';
import 'shift_report_screen.dart';

class ActiveShiftScreen extends StatefulWidget {
  const ActiveShiftScreen({super.key});

  @override
  State<ActiveShiftScreen> createState() => _ActiveShiftScreenState();
}

class _ActiveShiftScreenState extends State<ActiveShiftScreen> {
  final _storage = RoundStorageService();
  List<RoundReading> _readings = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final readings = await _storage.loadReadings();
    if (!mounted) return;
    setState(() => _readings = readings);
  }


  Future<void> _openScreen(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _reload();
  }

  void _showQuickActions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17181A),
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Quick Actions', style: TextStyle(color: Color(0xFFCDA56A), fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _ActionButton(icon: Icons.add_circle, label: 'New Round', onTap: () => _openFromSheet(const PressureEntryScreen())),
              _ActionButton(icon: Icons.inventory, label: 'Inventory / Tank Check', onTap: () => _openFromSheet(const ProductionInventoryScreen())),
              _ActionButton(icon: Icons.precision_manufacturing, label: 'Equipment Event', onTap: () => _openFromSheet(const EquipmentScreen())),
              _ActionButton(icon: Icons.message, label: 'Shift Report', onTap: () => _openFromSheet(const ShiftReportScreen())),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFromSheet(Widget screen) async {
    Navigator.of(context).pop();
    await _openScreen(screen);
  }

  List<_AttentionItem> _attentionItems(RoundReading? latest) {
    final items = <_AttentionItem>[];
    if (latest == null) {
      items.add(const _AttentionItem('No round saved', 'Tap Quick Round to enter the first readings.', Icons.assignment_late, Color(0xFFFFD45D)));
      return items;
    }
    if (latest.casingPressure.trim().isEmpty) {
      items.add(const _AttentionItem('CSG missing', 'Casing pressure is needed for most reports.', Icons.warning, Color(0xFFFFD45D)));
    }
    if (latest.oilRate.trim().isEmpty || latest.waterRate.trim().isEmpty || latest.gasRate.trim().isEmpty) {
      items.add(const _AttentionItem('Production incomplete', 'Oil, water, and gas are not all entered.', Icons.speed, Color(0xFFFFD45D)));
    }
    if (latest.separatorPressure.trim().isEmpty) {
      items.add(const _AttentionItem('SP missing', 'Separator pressure is blank.', Icons.speed, Color(0xFFFFD45D)));
    }
    if (items.isEmpty) {
      items.add(const _AttentionItem('Shift looks current', 'Production and core pressures are entered.', Icons.check_circle, Color(0xFF55D980)));
    }
    return items;
  }

  Future<void> _openQuickRound() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PressureEntryScreen()));
    await _reload();
  }

  String _value(String value, String fallback) => value.trim().isEmpty ? fallback : value.trim();

  String _chokeValue(RoundReading? reading) {
    if (reading == null || reading.choke.trim().isEmpty) return '—';
    final saved = reading.choke.trim();
    final lower = saved.toLowerCase();
    final style = reading.chokeStyle.trim();
    if (style.isEmpty || lower.contains(' adj') || lower.contains(' pos')) return saved;
    return '$saved $style';
  }

  @override
  Widget build(BuildContext context) {
    final latest = _readings.isEmpty ? null : _readings.first;
    final lastUpdated = latest == null ? 'No rounds saved yet' : DateFormat('h:mm a').format(latest.timestamp);

    return Scaffold(
      appBar: const AppHeader(title: 'Active Shift', showBack: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showQuickActions,
        icon: const Icon(Icons.add),
        label: const Text('Actions'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            color: const Color(0xFF17181A),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Current Shift', style: TextStyle(color: Color(0xFFCDA56A), fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Last updated: $lastUpdated', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _StatusTile(label: 'Oil', value: _value(latest?.oilRate ?? '', '—'), unit: 'BBL/hr')),
                    Expanded(child: _StatusTile(label: 'Water', value: _value(latest?.waterRate ?? '', '—'), unit: 'BBL/hr')),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _StatusTile(label: 'Gas', value: _value(latest?.gasRate ?? '', '—'), unit: 'MCFD')),
                    Expanded(child: _StatusTile(label: 'CSG', value: _value(latest?.casingPressure ?? '', '—'), unit: 'psi')),
                  ]),
                  const SizedBox(height: 12),
                  _Line(label: 'Choke', value: _chokeValue(latest)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _InfoCard(
            title: 'What needs attention',
            children: _attentionItems(latest).map((item) => _AttentionRow(item)).toList(),
          ),
          const SizedBox(height: 16),
          _InfoCard(
            title: 'Pressures',
            children: [
              _Line(label: 'TBG', value: _value(latest?.tubingPressure ?? '', '—')),
              _Line(label: 'CSG', value: _value(latest?.casingPressure ?? '', '—')),
              _Line(label: 'ICP', value: _value(latest?.icp ?? '', '—')),
              _Line(label: 'SCP', value: _value(latest?.scp ?? '', '—')),
              _Line(label: 'SP', value: _value(latest?.separatorPressure ?? '', '—')),
              _Line(label: 'Diff', value: _value(latest?.differentialPressure ?? '', '—')),
            ],
          ),
          const SizedBox(height: 16),
          _InfoCard(
            title: 'Temps & Chemicals',
            children: [
              _Line(label: 'Gas TMP', value: _value(latest?.gasTemp ?? '', '—')),
              _Line(label: 'WH TMP', value: _value(latest?.wellheadTemp ?? '', '—')),
              _Line(label: 'H2O TMP', value: _value(latest?.waterTemp ?? '', '—')),
              _Line(label: 'ECD TMP', value: _value(latest?.ecdTemp ?? '', '—')),
              _Line(label: 'Prop', value: _value(latest?.propRate ?? '', '—')),
              _Line(label: 'Biocide', value: _value(latest?.biocideRate ?? '', '—')),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Round History', style: TextStyle(color: Color(0xFFCDA56A), fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_readings.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No rounds saved yet. Tap Quick Round to enter your first set of readings.'))),
          ..._readings.take(10).map((r) => Card(
                color: const Color(0xFF17181A),
                child: ListTile(
                  title: Text(r.roundLabel.isEmpty ? DateFormat('h:mm a').format(r.timestamp) : r.roundLabel),
                  subtitle: Text('Oil ${_value(r.oilRate, '—')} • Water ${_value(r.waterRate, '—')} • Gas ${_value(r.gasRate, '—')} • CSG ${_value(r.casingPressure, '—')}'),
                ),
              )),
          const SizedBox(height: 90),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _InfoCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF17181A),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Color(0xFFCDA56A), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _StatusTile({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Color(0xFFCDA56A), fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        Text(unit, style: const TextStyle(color: Colors.white54)),
      ]),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  const _Line({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}


class _AttentionItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  const _AttentionItem(this.title, this.subtitle, this.icon, this.color);
}

class _AttentionRow extends StatelessWidget {
  final _AttentionItem item;
  const _AttentionRow(this.item);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: item.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: TextStyle(color: item.color, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(item.subtitle, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FilledButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label)),
    );
  }
}
