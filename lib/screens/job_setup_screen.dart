import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/job_setup.dart';
import '../services/job_storage_service.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

class JobSetupScreen extends StatefulWidget {
  const JobSetupScreen({super.key});

  @override
  State<JobSetupScreen> createState() => _JobSetupScreenState();
}

class _JobSetupScreenState extends State<JobSetupScreen> {
  final _storage = JobStorageService();
  final _page = PageController();
  int _step = 0;

  String company = 'Mach Energy';
  String shift = 'Day';
  final customer = TextEditingController();
  final padName = TextEditingController();
  final leaseName = TextEditingController();
  final county = TextEditingController();
  final state = TextEditingController(text: 'Oklahoma');
  final crew = TextEditingController();
  final dateStarted = TextEditingController(text: DateFormat('MM/dd/yyyy').format(DateTime.now()));
  final wellEntry = TextEditingController();
  final wells = <String>[];

  final sandSeparators = TextEditingController(text: '2');
  final plugCatchers = TextEditingController(text: '1');
  final chokeManifolds = TextEditingController(text: '1');
  final lineHeaters = TextEditingController(text: '1');
  final testUnits = TextEditingController(text: '1');
  final ecds = TextEditingController(text: '1');
  final vrus = TextEditingController(text: '1');
  final flares = TextEditingController(text: '1');
  final transferPumps = TextEditingController(text: '1');

  final oilTanks = TextEditingController(text: '4');
  final oilTankCapacity = TextEditingController(text: '400');
  final waterTanks = TextEditingController(text: '6');
  final waterTankCapacity = TextEditingController(text: '500');
  final productionTankFactor = TextEditingController(text: '1.67');

  final reportTimes = <String>['6:00 AM', '9:00 AM', '12:00 PM', '3:00 PM', '6:00 PM'];
  final reportTimeEntry = TextEditingController();

  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  void _next() {
    if (_step >= 5) return;
    setState(() => _step++);
    _page.animateToPage(_step, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  void _backStep() {
    if (_step == 0) return;
    setState(() => _step--);
    _page.animateToPage(_step, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Future<void> _save() async {
    final job = JobSetup(
      company: company,
      customer: customer.text.trim(),
      padName: padName.text.trim(),
      leaseName: leaseName.text.trim(),
      county: county.text.trim(),
      state: state.text.trim(),
      crew: crew.text.trim(),
      shift: shift,
      dateStarted: dateStarted.text.trim(),
      wells: List<String>.from(wells),
      sandSeparators: _i(sandSeparators),
      plugCatchers: _i(plugCatchers),
      chokeManifolds: _i(chokeManifolds),
      lineHeaters: _i(lineHeaters),
      testUnits: _i(testUnits),
      ecds: _i(ecds),
      vrus: _i(vrus),
      flares: _i(flares),
      transferPumps: _i(transferPumps),
      oilTanks: _i(oilTanks),
      oilTankCapacity: oilTankCapacity.text.trim(),
      waterTanks: _i(waterTanks),
      waterTankCapacity: waterTankCapacity.text.trim(),
      productionTankFactor: productionTankFactor.text.trim().isEmpty ? '1.67' : productionTankFactor.text.trim(),
      reportTimes: List<String>.from(reportTimes),
    );
    await _storage.saveActiveJob(job);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job setup saved')));
    Navigator.of(context).pop();
  }

  Widget _navButtons({bool finish = false}) => Row(
        children: [
          if (_step > 0) Expanded(child: OutlinedButton(onPressed: _backStep, child: const Text('Back'))),
          if (_step > 0) const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: finish ? _save : _next, child: Text(finish ? 'Start Job' : 'Next'))),
        ],
      );

  @override
  void dispose() {
    _page.dispose();
    for (final c in [customer, padName, leaseName, county, state, crew, dateStarted, wellEntry, sandSeparators, plugCatchers, chokeManifolds, lineHeaters, testUnits, ecds, vrus, flares, transferPumps, oilTanks, oilTankCapacity, waterTanks, waterTankCapacity, productionTankFactor, reportTimeEntry]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'New Job', showBack: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: LinearProgressIndicator(value: (_step + 1) / 6),
          ),
          Expanded(
            child: PageView(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _StepPage(title: '1. Company', children: [
                  DropdownButtonFormField<String>(
                    value: company,
                    decoration: const InputDecoration(labelText: 'Company'),
                    items: const [
                      DropdownMenuItem(value: 'Mach Energy', child: Text('Mach Energy')),
                      DropdownMenuItem(value: 'Continental', child: Text('Continental')),
                      DropdownMenuItem(value: 'Custom', child: Text('Custom')),
                    ],
                    onChanged: (v) => setState(() => company = v ?? 'Mach Energy'),
                  ),
                  const SizedBox(height: 14),
                  TextField(controller: customer, decoration: const InputDecoration(labelText: 'Customer / Operator')),
                  const SizedBox(height: 20),
                  const Text('This loads the matching report profile and report times.', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 24),
                  _navButtons(),
                ]),
                _StepPage(title: '2. Job Info', children: [
                  TextField(controller: padName, decoration: const InputDecoration(labelText: 'Pad Name')),
                  const SizedBox(height: 12),
                  TextField(controller: leaseName, decoration: const InputDecoration(labelText: 'Lease Name')),
                  const SizedBox(height: 12),
                  TextField(controller: county, decoration: const InputDecoration(labelText: 'County')),
                  const SizedBox(height: 12),
                  TextField(controller: state, decoration: const InputDecoration(labelText: 'State')),
                  const SizedBox(height: 12),
                  TextField(controller: crew, decoration: const InputDecoration(labelText: 'Crew')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(value: shift, decoration: const InputDecoration(labelText: 'Shift'), items: const [DropdownMenuItem(value: 'Day', child: Text('Day')), DropdownMenuItem(value: 'Night', child: Text('Night'))], onChanged: (v) => setState(() => shift = v ?? 'Day')),
                  const SizedBox(height: 12),
                  TextField(controller: dateStarted, decoration: const InputDecoration(labelText: 'Date Started')),
                  const SizedBox(height: 24),
                  _navButtons(),
                ]),
                _StepPage(title: '3. Wells', children: [
                  Row(children: [
                    Expanded(child: TextField(controller: wellEntry, decoration: const InputDecoration(labelText: 'Well Name'))),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      onPressed: () {
                        final name = wellEntry.text.trim();
                        if (name.isEmpty) return;
                        setState(() { wells.add(name); wellEntry.clear(); });
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  if (wells.isEmpty) const Text('Add each well on this pad.', style: TextStyle(color: Colors.white70)),
                  ...wells.map((w) => Card(child: ListTile(title: Text(w), trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () => setState(() => wells.remove(w))))),
                  const SizedBox(height: 24),
                  _navButtons(),
                ]),
                _StepPage(title: '4. Equipment', children: [
                  _countField('Sand Separators', sandSeparators),
                  _countField('Plug Catchers', plugCatchers),
                  _countField('Choke Manifolds', chokeManifolds),
                  _countField('Line Heaters', lineHeaters),
                  _countField('Test Units', testUnits),
                  _countField('ECDs', ecds),
                  _countField('VRUs', vrus),
                  _countField('Flares', flares),
                  _countField('Transfer Pumps', transferPumps),
                  const SizedBox(height: 24),
                  _navButtons(),
                ]),
                _StepPage(title: '5. Tanks', children: [
                  _countField('Oil Tanks', oilTanks),
                  WwNumberField(label: 'Oil Tank Capacity', controller: oilTankCapacity),
                  _countField('Water Tanks', waterTanks),
                  WwNumberField(label: 'Water Tank Capacity', controller: waterTankCapacity),
                  WwNumberField(label: 'Production Tank Factor (BBL/In)', controller: productionTankFactor, allowDecimal: true),
                  const Text('Default tank factor stays 1.67 unless you change it.', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 24),
                  _navButtons(),
                ]),
                _StepPage(title: '6. Reports', children: [
                  const Text('Edit report times for this job only.', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextField(controller: reportTimeEntry, decoration: const InputDecoration(labelText: 'Add Time, ex: 7:00 AM'))),
                    const SizedBox(width: 10),
                    IconButton.filled(onPressed: () { final t = reportTimeEntry.text.trim(); if (t.isNotEmpty) setState(() { reportTimes.add(t); reportTimeEntry.clear(); }); }, icon: const Icon(Icons.add)),
                  ]),
                  const SizedBox(height: 12),
                  ...reportTimes.map((t) => Card(child: ListTile(title: Text(t), trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () => setState(() => reportTimes.remove(t))))),
                  const SizedBox(height: 18),
                  Card(child: Padding(padding: const EdgeInsets.all(14), child: Text('Summary\n$company\n${padName.text.trim().isEmpty ? 'No pad entered' : padName.text.trim()}\n${wells.length} well(s)\n${_i(sandSeparators) + _i(plugCatchers) + _i(chokeManifolds) + _i(lineHeaters) + _i(testUnits) + _i(ecds) + _i(vrus) + _i(flares) + _i(transferPumps)} equipment item(s)\n${_i(oilTanks) + _i(waterTanks)} tank(s)'))),
                  const SizedBox(height: 24),
                  _navButtons(finish: true),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _countField(String label, TextEditingController controller) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: WwNumberField(label: label, controller: controller, allowDecimal: false),
      );
}

class _StepPage extends StatelessWidget {
  const _StepPage({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(title, style: const TextStyle(color: Color(0xFFCDA56A), fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...children,
        ],
      );
}
