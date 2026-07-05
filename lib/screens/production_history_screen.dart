import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/job_history.dart';
import '../services/job_history_service.dart';
import '../widgets/app_header.dart';

class ProductionHistoryScreen extends StatefulWidget {
  const ProductionHistoryScreen({super.key});

  @override
  State<ProductionHistoryScreen> createState() =>
      _ProductionHistoryScreenState();
}

class _ProductionHistoryScreenState extends State<ProductionHistoryScreen> {
  final _service = JobHistoryService();
  final _company = TextEditingController();
  final _pad = TextEditingController();
  final _well = TextEditingController();
  final _date = TextEditingController();

  List<ArchivedJob> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _company.dispose();
    _pad.dispose();
    _well.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final history = await _service.loadHistory();
    if (!mounted) return;
    setState(() {
      _history = history;
      _loading = false;
    });
  }

  bool _matches(ArchivedJob item) {
    final companyQuery = _company.text.trim().toLowerCase();
    final padQuery = _pad.text.trim().toLowerCase();
    final wellQuery = _well.text.trim().toLowerCase();
    final dateQuery = _date.text.trim().toLowerCase();

    final companyMatch = companyQuery.isEmpty ||
        item.company.toLowerCase().contains(companyQuery);
    final padMatch =
        padQuery.isEmpty || item.padName.toLowerCase().contains(padQuery);
    final wellMatch = wellQuery.isEmpty ||
        item.wells.any((well) => well.toLowerCase().contains(wellQuery));
    final dateMatch = dateQuery.isEmpty ||
        item.dateRangeStart.toLowerCase().contains(dateQuery) ||
        item.dateRangeEnd.toLowerCase().contains(dateQuery) ||
        item.shifts
            .any((shift) => shift.date.toLowerCase().contains(dateQuery));
    return companyMatch && padMatch && wellMatch && dateMatch;
  }

  Widget _searchField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'History', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final filtered = _history.where(_matches).toList();

    return Scaffold(
      appBar: const AppHeader(title: 'History', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _searchField('Search Company', _company),
                  _searchField('Search Pad', _pad),
                  _searchField('Search Well', _well),
                  _searchField('Search Date', _date),
                ],
              ),
            ),
          ),
          if (filtered.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No archived jobs yet. Use Archive Current Job / Shift in Production Inventory to save a local snapshot.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          for (final job in filtered)
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: ListTile(
                title: Text(
                  job.company.isEmpty ? 'Archived Job' : job.company,
                  style: const TextStyle(
                    color: Color(0xFFCDA56A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  [
                    job.padName,
                    '${job.dateRangeStart}${job.dateRangeEnd.isNotEmpty && job.dateRangeEnd != job.dateRangeStart ? ' → ${job.dateRangeEnd}' : ''}',
                    '${job.shifts.length} shift(s)',
                  ].where((item) => item.trim().isNotEmpty).join(' • '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ArchivedJobDetailScreen(job: job),
                    ),
                  );
                  await _load();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class ArchivedJobDetailScreen extends StatelessWidget {
  const ArchivedJobDetailScreen({super.key, required this.job});

  final ArchivedJob job;

  Future<void> _copy(BuildContext context, String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied.')),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete History Item?'),
            content: const Text(
              'This removes the archived job from local History only.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await JobHistoryService().deleteArchivedJob(job.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _duplicate(BuildContext context) async {
    await JobHistoryService().duplicateArchivedJobToActive(job);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Archived job duplicated into active job.')),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFCDA56A),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _jobHeaderCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Job Header'),
            Text('Company: ${job.company.isEmpty ? '-' : job.company}'),
            Text('Pad: ${job.padName.isEmpty ? '-' : job.padName}'),
            Text(
              'Date Range: ${job.dateRangeStart.isEmpty ? '-' : job.dateRangeStart}${job.dateRangeEnd.isNotEmpty && job.dateRangeEnd != job.dateRangeStart ? ' → ${job.dateRangeEnd}' : ''}',
            ),
            Text('Wells: ${job.wells.isEmpty ? '-' : job.wells.join(', ')}'),
            if (job.jobSetup != null && job.jobSetup!.crew.trim().isNotEmpty)
              Text('Crew: ${job.jobSetup!.crew}'),
            if (job.layoutSummary != null)
              Text(
                'Layout Summary: ${job.layoutSummary!.name.isEmpty ? 'Saved Layout' : job.layoutSummary!.name} • ${job.layoutSummary!.itemCount} item(s)',
              ),
          ],
        ),
      ),
    );
  }

  Widget _shiftCard(BuildContext context, ArchivedShiftEntry shift) {
    final production = shift.productionShift;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        title: Text(
          shift.date.isEmpty
              ? shift.archivedAt.toIso8601String().split('T').first
              : shift.date,
          style: const TextStyle(
            color: Color(0xFFCDA56A),
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '${production.savedRows.length} report row(s) • ${production.hourlyChecks.length} quick round entr${production.hourlyChecks.length == 1 ? 'y' : 'ies'}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copy(
                    context,
                    shift.productionReportText,
                    'Archived Production Report',
                  ),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy Archived Production Report'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: shift.textUpdates.isEmpty
                      ? null
                      : () => _copy(
                            context,
                            shift.textUpdates
                                .map((item) => item.content)
                                .join('\n\n'),
                            'Archived Text Update',
                          ),
                  icon: const Icon(Icons.copy_all),
                  label: const Text('Copy Archived Text Update'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionLabel('Starting Inventory'),
          Text(
              'Date: ${production.header.date.isEmpty ? '-' : production.header.date}'),
          Text(
              'Company: ${production.header.company.isEmpty ? '-' : production.header.company}'),
          Text(
              'Pad: ${production.header.pad.isEmpty ? '-' : production.header.pad}'),
          Text('Wells: ${production.header.wells.join(', ')}'),
          for (final tank in production.inventory.waterTanks)
            Text(
                'Water Tank: ${tank.name} • ${tank.gaugeEntry.entryText()} • ${tank.bblPerInch} BBL/in'),
          for (final tank in production.inventory.oilTanks)
            Text(
                'Oil Tank: ${tank.name} • ${tank.gaugeEntry.entryText()} • ${tank.bblPerInch} BBL/in'),
          Text(
              'Starting Gas Accum: ${production.inventory.startingGasAccum.isEmpty ? '-' : production.inventory.startingGasAccum}'),
          const SizedBox(height: 12),
          _sectionLabel('Quick Round Entries'),
          if (production.hourlyChecks.isEmpty)
            const Text(
              'No quick round entries archived.',
              style: TextStyle(color: Colors.white70),
            ),
          for (final check in production.hourlyChecks)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${check.time} • ${check.well} • CHK ${check.choke.isEmpty ? '-' : check.choke} • TBG ${check.tbg.isEmpty ? '-' : check.tbg} • CSG ${check.csg.isEmpty ? '-' : check.csg}',
              ),
            ),
          const SizedBox(height: 12),
          _sectionLabel('Production Report'),
          SelectableText(shift.productionReportText),
          const SizedBox(height: 12),
          _sectionLabel('Text Updates'),
          if (shift.textUpdates.isEmpty)
            const Text(
              'No archived text updates.',
              style: TextStyle(color: Colors.white70),
            ),
          for (final update in shift.textUpdates)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SelectableText(update.content),
            ),
          const SizedBox(height: 12),
          _sectionLabel('JSA Summary'),
          if (shift.jsaDraft == null)
            const Text(
              'No JSA archived for this shift.',
              style: TextStyle(color: Colors.white70),
            )
          else ...[
            Text(
                'Company: ${shift.jsaDraft!.company.isEmpty ? '-' : shift.jsaDraft!.company}'),
            Text(
                'Location: ${shift.jsaDraft!.location.isEmpty ? '-' : shift.jsaDraft!.location}'),
            Text(
                'Well: ${shift.jsaDraft!.wellName.isEmpty ? '-' : shift.jsaDraft!.wellName}'),
            Text(
                'Task: ${shift.jsaDraft!.tasks.isEmpty ? (shift.jsaDraft!.task.isEmpty ? '-' : shift.jsaDraft!.task) : shift.jsaDraft!.tasks.join(', ')}'),
            Text('Employees: ${shift.jsaDraft!.employees.length}'),
            if (shift.jsaDraft!.notes.trim().isNotEmpty)
              Text('Notes: ${shift.jsaDraft!.notes}'),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Archived Job', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _jobHeaderCard(),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _duplicate(context),
                  icon: const Icon(Icons.copy_all),
                  label: const Text('Duplicate Into Active Job'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _delete(context),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete History Item'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final shift in job.shifts) _shiftCard(context, shift),
        ],
      ),
    );
  }
}
