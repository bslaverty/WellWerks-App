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
      notes: _notes.text.trim(),
    );
    await _storage.saveReading(reading);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Round reading saved')));
    Navigator.of(context).pop();
  }

  Widget _field(String label, TextEditingController controller, {String? previous}) {
    return WwNumberField(
      label: label,
      controller: controller,
      helperText: previous == null || previous.isEmpty ? null : 'Previous: $previous',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Quick Round', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: _round,
            decoration: const InputDecoration(labelText: 'Round / Update Time', helperText: 'Example: 6:00 AM, 9:00 AM, Noon'),
          ),
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
          const _BlockTitle('Notes'),
          TextField(
            controller: _notes,
            maxLines: 3,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(labelText: 'Notes / comments'),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Finish Round'),
          ),
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
