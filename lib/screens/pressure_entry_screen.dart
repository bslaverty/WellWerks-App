import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/round_reading.dart';
import '../services/round_storage_service.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

class PressureEntryScreen extends StatefulWidget {
  const PressureEntryScreen({super.key});

  @override
  State<PressureEntryScreen> createState() => _PressureEntryScreenState();
}

class _PressureEntryScreenState extends State<PressureEntryScreen> {
  final _storage = RoundStorageService();
  final _round = TextEditingController(text: DateFormat('h:mm a').format(DateTime.now()));
  final _oil = TextEditingController();
  final _water = TextEditingController();
  final _gas = TextEditingController();
  final _tbg = TextEditingController();
  final _csg = TextEditingController();
  final _icp = TextEditingController();
  final _scp = TextEditingController();
  final _sp = TextEditingController();
  final _diff = TextEditingController();
  final _gasTemp = TextEditingController();
  final _whTemp = TextEditingController();
  final _waterTemp = TextEditingController();
  final _ecdTemp = TextEditingController();
  final _prop = TextEditingController();
  final _biocide = TextEditingController();
  int? _chokeSize;
  String _chokeStyle = 'adj';
  final _notes = TextEditingController();
  RoundReading? _last;

  @override
  void initState() {
    super.initState();
    _loadLast();
  }

  Future<void> _loadLast() async {
    final readings = await _storage.loadReadings();
    if (!mounted || readings.isEmpty) return;
    setState(() => _last = readings.first);
  }


  void _clearRound() {
    setState(() {
      for (final controller in [
        _oil,
        _water,
        _gas,
        _tbg,
        _csg,
        _icp,
        _scp,
        _sp,
        _diff,
        _gasTemp,
        _whTemp,
        _waterTemp,
        _ecdTemp,
        _prop,
        _biocide,
        _notes,
      ]) {
        controller.clear();
      }
      _chokeSize = null;
      _chokeStyle = 'adj';
    });
  }

  void _copyStableValues() {
    final last = _last;
    if (last == null) return;
    setState(() {
      _prop.text = last.propRate;
      _biocide.text = last.biocideRate;
      _notes.text = last.notes;
      final rawChoke = last.choke.replaceAll('/64', '').trim();
      _chokeSize = int.tryParse(rawChoke);
      _chokeStyle = last.chokeStyle.trim().isEmpty ? 'adj' : last.chokeStyle.trim();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stable values copied. Fresh readings still stay blank.')),
    );
  }

  Future<void> _save() async {
    final now = DateTime.now();
    final reading = RoundReading(
      id: now.microsecondsSinceEpoch.toString(),
      timestamp: now,
      roundLabel: _round.text.trim(),
      oilRate: _oil.text.trim(),
      waterRate: _water.text.trim(),
      gasRate: _gas.text.trim(),
      tubingPressure: _tbg.text.trim(),
      casingPressure: _csg.text.trim(),
      icp: _icp.text.trim(),
      scp: _scp.text.trim(),
      separatorPressure: _sp.text.trim(),
      differentialPressure: _diff.text.trim(),
      gasTemp: _gasTemp.text.trim(),
      wellheadTemp: _whTemp.text.trim(),
      waterTemp: _waterTemp.text.trim(),
      ecdTemp: _ecdTemp.text.trim(),
      propRate: _prop.text.trim(),
      biocideRate: _biocide.text.trim(),
      choke: _chokeSize == null ? '' : '${_chokeSize}/64',
      chokeStyle: _chokeSize == null ? '' : _chokeStyle,
      notes: _notes.text.trim(),
    );
    await _storage.saveReading(reading);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Round saved')));
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    for (final controller in [
      _round,
      _oil,
      _water,
      _gas,
      _tbg,
      _csg,
      _icp,
      _scp,
      _sp,
      _diff,
      _gasTemp,
      _whTemp,
      _waterTemp,
      _ecdTemp,
      _prop,
      _biocide,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(String label, TextEditingController controller, {String? previous}) {
    return WwNumberField(
      label: label,
      controller: controller,
      helperText: previous == null || previous.isEmpty ? null : 'Previous: $previous',
      autofocus: label == 'Oil (BBL/hr)',
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _textField(String label, TextEditingController controller, {String? previous}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          helperText: previous == null || previous.isEmpty ? null : 'Previous: $previous',
        ),
      ),
    );
  }


  Widget _chokePicker() {
    final previousChoke = _last == null || _last!.choke.trim().isEmpty
        ? null
        : 'Previous: ${_last!.choke.trim()} ${_last!.chokeStyle.trim()}'.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choke', style: TextStyle(color: Color(0xFFCDA56A), fontWeight: FontWeight.bold)),
            if (previousChoke != null) ...[
              const SizedBox(height: 4),
              Text(previousChoke, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _chokeSize,
              decoration: const InputDecoration(labelText: 'Choke Size'),
              hint: const Text('Select 0/64 - 128/64'),
              items: List.generate(
                129,
                (index) => DropdownMenuItem(value: index, child: Text('$index/64')),
              ),
              onChanged: (value) => setState(() => _chokeSize = value),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'adj', label: Text('adj')),
                ButtonSegment(value: 'pos', label: Text('pos')),
              ],
              selected: {_chokeStyle},
              onSelectionChanged: (values) => setState(() => _chokeStyle = values.first),
            ),
            const SizedBox(height: 6),
            const Text('adj = adjustable, pos = positive', style: TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final missing = <String>[
      if (_oil.text.trim().isEmpty) 'Oil',
      if (_water.text.trim().isEmpty) 'Water',
      if (_gas.text.trim().isEmpty) 'Gas',
      if (_csg.text.trim().isEmpty) 'CSG',
    ];

    return Scaffold(
      appBar: const AppHeader(title: 'Quick Round', showBack: true),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_circle),
            label: const Text('Finish Round'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: _round,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Round / Update Time', helperText: 'Example: 6:00 AM, 9:00 AM, Noon'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          Card(
            color: missing.isEmpty ? const Color(0xFF12351F) : const Color(0xFF3A3115),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                missing.isEmpty ? '✅ Report ready from this round' : 'Missing for basic report: ${missing.join(', ')}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (_last != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _copyStableValues,
              icon: const Icon(Icons.copy),
              label: const Text('Copy Stable Values'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _clearRound,
              icon: const Icon(Icons.clear),
              label: const Text('Clear Round'),
            ),
          ],
          const SizedBox(height: 18),
          const _BlockTitle('Production'),
          _field('Oil (BBL/hr)', _oil, previous: _last?.oilRate),
          _field('Water (BBL/hr)', _water, previous: _last?.waterRate),
          _field('Gas (MCFD)', _gas, previous: _last?.gasRate),
          const _BlockTitle('Pressures'),
          _field('TBG', _tbg, previous: _last?.tubingPressure),
          _field('CSG', _csg, previous: _last?.casingPressure),
          _field('ICP', _icp, previous: _last?.icp),
          _field('SCP', _scp, previous: _last?.scp),
          _field('Separator Pressure', _sp, previous: _last?.separatorPressure),
          _field('Differential', _diff, previous: _last?.differentialPressure),
          const _BlockTitle('Choke'),
          _chokePicker(),
          const _BlockTitle('Temperatures'),
          _field('Gas Temp (°)', _gasTemp, previous: _last?.gasTemp),
          _field('WH Temp (°)', _whTemp, previous: _last?.wellheadTemp),
          _field('H2O Temp (°)', _waterTemp, previous: _last?.waterTemp),
          _field('ECD Temp (°)', _ecdTemp, previous: _last?.ecdTemp),
          const _BlockTitle('Chemicals'),
          _field('Prop (gal/hr)', _prop, previous: _last?.propRate),
          _field('Biocide (gal/day)', _biocide, previous: _last?.biocideRate),
          const _BlockTitle('Notes'),
          TextField(
            controller: _notes,
            maxLines: 3,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(labelText: 'Notes / comments'),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _BlockTitle extends StatelessWidget {
  final String text;
  const _BlockTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(color: Color(0xFFCDA56A), fontWeight: FontWeight.w900, letterSpacing: .8),
      ),
    );
  }
}
