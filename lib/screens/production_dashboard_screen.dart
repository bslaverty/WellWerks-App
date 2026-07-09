import 'package:flutter/material.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';
import '../services/job_storage_service.dart';
import '../services/production_shift_service.dart';
import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';
import 'job_management_screen.dart';
import 'pressure_entry_screen.dart';
import 'job_box_inventory_screen.dart';
import 'production_inventory_screen.dart';
import 'production_history_screen.dart';
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

  ProductionShift _shift = ProductionShift.empty();
  JobSetup? _activeJob;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var shift = await _shiftService.loadActiveShift();
    final resolvedJob = await _jobStorage.resolveProductionActiveJob(shift);
    if (resolvedJob != null && shift.activeJobId != resolvedJob.id) {
      shift = shift.copyWith(activeJobId: resolvedJob.id);
      await _shiftService.saveActiveShift(shift);
    }
    if (!mounted) return;
    setState(() {
      _shift = shift;
      _activeJob = resolvedJob;
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
    final source = activeJob != null && activeJob.wells.isNotEmpty
        ? activeJob.wells
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
    if (!_hasActiveJobContext) {
      return Card(
        color: const Color(0xFF17130E),
        margin: const EdgeInsets.only(bottom: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Active Job',
                style: TextStyle(
                  color: Color(0xFFCDA56A),
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

    final wellsText = _activeWells.isEmpty ? '-' : _activeWells.join(' / ');
    final companyName = _activeCompanyName;
    final padName = _activePadName;
    return Card(
      color: const Color(0xFF17130E),
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Active Job',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
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
          _activeJobCard(context),
          const Text(
            'Production tools for gas rates, tank inventory, quick rounds, and copy/paste updates.',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 14),
          ToolCard(
            icon: Icons.add_circle,
            title: 'Quick Round',
            subtitle: 'Production and pressure readings in one place',
            onTap: () => _open(context, const PressureEntryScreen()),
          ),
          ToolCard(
            icon: Icons.table_chart,
            title: 'Production Report',
            subtitle: 'Read-only saved hourly table for the active shift',
            onTap: () => _open(context, const ShiftReportScreen()),
          ),
          ToolCard(
            icon: Icons.sms,
            title: 'Text Update',
            subtitle: 'Select an hour, preview, and copy the text update',
            onTap: () => _open(context, const TextUpdateScreen()),
          ),
          ToolCard(
            icon: Icons.local_drink,
            title: 'Oil Inventory',
            subtitle: 'Set company, wells, and starting oil inventory',
            onTap: () => _open(context, const ProductionInventoryScreen()),
          ),
          ToolCard(
            icon: Icons.inventory_2_outlined,
            title: 'Job Box Inventory',
            subtitle: 'Track common job box items and copy updates',
            onTap: () => _open(context, const JobBoxInventoryScreen()),
          ),
          ToolCard(
            icon: Icons.history,
            title: 'Production History',
            subtitle:
                'Archived inventory, reports, hourly checks, and text updates',
            onTap: () => _open(context, const ProductionHistoryScreen()),
          ),
          ToolCard(
            icon: Icons.inventory,
            title: 'Production Setup',
            subtitle: 'Company, wells, reports, and production defaults',
            onTap: () => _open(context,
                const ReportTemplateScreen(initialSection: 'inventory')),
          ),
        ],
      ),
    );
  }
}
