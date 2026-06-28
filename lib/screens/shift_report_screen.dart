import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/round_reading.dart';
import '../services/round_storage_service.dart';
import '../widgets/app_header.dart';

class ShiftReportScreen extends StatefulWidget {
  const ShiftReportScreen({super.key});

  @override
  State<ShiftReportScreen> createState() => _ShiftReportScreenState();
}

class _ShiftReportScreenState extends State<ShiftReportScreen> {
  final _storage = RoundStorageService();
  final _wellName = TextEditingController();
  final _choke = TextEditingController();
  String _company = 'Mach Energy';
  RoundReading? _latest;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final readings = await _storage.loadReadings();
    if (!mounted) return;
    setState(() {
      _latest = readings.isEmpty ? null : readings.first;
      _loading = false;
    });
  }

  String get _timeLabel {
    final raw = _latest?.roundLabel.trim() ?? '';
    if (raw.isNotEmpty) return raw.toUpperCase().contains('UPDATE') ? raw : '$raw UPDATE';
    return '${DateFormat('h:mm a').format(DateTime.now())} UPDATE';
  }

  List<String> get _missing {
    final r = _latest;
    if (r == null) return ['No round saved yet'];
    final missing = <String>[];
    if (_wellName.text.trim().isEmpty) missing.add('Well name');
    if (_choke.text.trim().isEmpty) missing.add('Choke');
    if (r.casingPressure.trim().isEmpty) missing.add('CSG');
    if (r.waterRate.trim().isEmpty) missing.add('Water/hr');
    if (r.oilRate.trim().isEmpty) missing.add('Oil/hr');
    if (r.gasRate.trim().isEmpty) missing.add('Gas rate');
    if (_company == 'Continental') {
      if (r.tubingPressure.trim().isEmpty) missing.add('TBG');
      if (r.icp.trim().isEmpty) missing.add('ICP');
      if (r.scp.trim().isEmpty) missing.add('SCP');
      if (r.separatorPressure.trim().isEmpty) missing.add('SP');
      if (r.differentialPressure.trim().isEmpty) missing.add('Diff');
    }
    return missing;
  }

  String _v(String? value, {String fallback = 'N/A'}) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _buildReport() {
    final r = _latest;
    final well = _wellName.text.trim().isEmpty ? 'Well Name' : _wellName.text.trim();
    final choke = _choke.text.trim().isEmpty ? 'N/A' : _choke.text.trim();
    if (r == null) return 'No round saved yet. Enter a Quick Round first.';

    if (_company == 'Continental') {
      return '''$well
$_timeLabel

TBG- ${_v(r.tubingPressure)}
CSG- ${_v(r.casingPressure)} psi
ICP- ${_v(r.icp)} psi
SCP- ${_v(r.scp)} psi
Chk- $choke
H2O- ${_v(r.waterRate)} bbls/hr
Oil- ${_v(r.oilRate)} bbls/hr
Sales RT - ${_v(r.gasRate)} mcf/d
Diff - ${_v(r.differentialPressure)}”
SP - ${_v(r.separatorPressure)} psi${r.notes.trim().isEmpty ? '' : '\n\nNotes- ${r.notes.trim()}'}''';
    }

    return '''$well
$_timeLabel

Choke $choke
Csg ${_v(r.casingPressure)}
Water/hr ${_v(r.waterRate)}
Oil ${_v(r.oilRate)}
${_v(r.gasRate)} 24/hr gas rate${r.notes.trim().isEmpty ? '' : '\nNotes ${r.notes.trim()}'}''';
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _buildReport()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report copied')));
  }

  @override
  void dispose() {
    _wellName.dispose();
    _choke.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = _buildReport();
    final missing = _missing;
    return Scaffold(
      appBar: const AppHeader(title: 'Shift Report', showBack: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                DropdownButtonFormField<String>(
                  value: _company,
                  decoration: const InputDecoration(labelText: 'Company Profile'),
                  items: const [
                    DropdownMenuItem(value: 'Mach Energy', child: Text('Mach Energy')),
                    DropdownMenuItem(value: 'Continental', child: Text('Continental')),
                    DropdownMenuItem(value: 'Custom', child: Text('Custom')),
                  ],
                  onChanged: (value) => setState(() => _company = value ?? 'Mach Energy'),
                ),
                const SizedBox(height: 12),
                TextField(controller: _wellName, decoration: const InputDecoration(labelText: 'Well Name'), onChanged: (_) => setState(() {})),
                const SizedBox(height: 12),
                TextField(controller: _choke, keyboardType: TextInputType.text, decoration: const InputDecoration(labelText: 'Choke'), onChanged: (_) => setState(() {})),
                const SizedBox(height: 16),
                Card(
                  color: missing.isEmpty ? const Color(0xFF12351F) : const Color(0xFF3A3115),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      missing.isEmpty ? '✅ Ready to copy' : 'Missing: ${missing.join(', ')}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Preview', style: TextStyle(color: Color(0xFFCDA56A), fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(report, style: const TextStyle(height: 1.35)),
                  ),
                ),
                FilledButton.icon(onPressed: _copy, icon: const Icon(Icons.copy), label: const Text('Copy Report')),
              ],
            ),
    );
  }
}
