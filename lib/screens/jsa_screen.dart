import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';

import '../models/jsa_draft.dart';
import '../services/jsa_storage_service.dart';
import '../widgets/app_header.dart';

class JsaScreen extends StatefulWidget {
  const JsaScreen({super.key});

  @override
  State<JsaScreen> createState() => _JsaScreenState();
}

class _JsaScreenState extends State<JsaScreen> {
  static const gold = Color(0xFFCDA56A);

  final _storage = JsaStorageService();
  final _location = TextEditingController();
  final _wellName = TextEditingController();
  final _notes = TextEditingController();

  final _employeeNames = List.generate(6, (_) => TextEditingController());
  final _employeeCompanies = List.generate(6, (_) => TextEditingController());
  final _signatures = List.generate(
    6,
    (_) => SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.white,
      exportBackgroundColor: const Color(0xFF111111),
    ),
  );

  String _company = 'Mach Energy';
  String _task = 'Flowback';
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();

  final _companies = const [
    'Mach Energy',
    'Continental',
    'Devon',
    'XTO',
    'Custom',
  ];

  final Map<String, Map<String, List<String>>> _taskLibrary = const {
    'Flowback': {
      'steps': ['Monitor well flow', 'Check pressures', 'Check tanks', 'Record readings'],
      'hazards': ['High pressure', 'H2S/gas exposure', 'Slips/trips', 'Hot surfaces'],
      'recommendations': ['Wear PPE', 'Stay out of line of fire', 'Verify valves before operating', 'Communicate changes'],
    },
    'Dump Sand': {
      'steps': ['Confirm safe position', 'Isolate equipment', 'Bleed off PSI', 'Dump sand'],
      'hazards': ['Stored pressure', 'Flying debris', 'Pinch points', 'Heavy sand discharge'],
      'recommendations': ['Stand in safe position', 'Isolate and bleed off PSI', 'Use face shield', 'Keep hands clear'],
    },
    'Fixing Leaks': {
      'steps': ['Identify leak', 'Notify crew', 'Isolate equipment', 'Bleed off PSI', 'Repair leak'],
      'hazards': ['High pressure leak', 'Chemical exposure', 'Hot work area', 'Pinch points'],
      'recommendations': ['Do not tighten under pressure', 'Isolate and bleed off PSI', 'Use correct tools', 'Verify repair before returning to service'],
    },
    'Rig Up': {
      'steps': ['Spot equipment', 'Connect iron', 'Secure lines', 'Pressure test'],
      'hazards': ['Suspended loads', 'Pinch points', 'High pressure', 'Backing equipment'],
      'recommendations': ['Use spotters', 'Stay clear of suspended loads', 'Inspect iron', 'Confirm pressure test'],
    },
    'Rig Down': {
      'steps': ['Shut in/secure well', 'Bleed off lines', 'Disconnect iron', 'Load equipment'],
      'hazards': ['Residual pressure', 'Heavy equipment', 'Pinch points', 'Slips/trips'],
      'recommendations': ['Verify zero energy', 'Use proper lifting', 'Keep work area clean', 'Communicate all lifts'],
    },
  };

  List<String> get _steps => _taskLibrary[_task]?['steps'] ?? const [];
  List<String> get _hazards => _taskLibrary[_task]?['hazards'] ?? const [];
  List<String> get _recommendations => _taskLibrary[_task]?['recommendations'] ?? const [];

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    final draft = await _storage.loadDraft();
    if (draft == null || !mounted) return;
    setState(() {
      _company = _companies.contains(draft.company) ? draft.company : 'Custom';
      _task = _taskLibrary.containsKey(draft.task) ? draft.task : 'Flowback';
      _location.text = draft.location;
      _wellName.text = draft.wellName;
      _notes.text = draft.notes;
      _date = DateTime.tryParse(draft.date) ?? DateTime.now();
      final parts = draft.time.split(':');
      if (parts.length >= 2) {
        _time = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
      }
      for (var i = 0; i < draft.employees.length && i < 6; i++) {
        _employeeNames[i].text = draft.employees[i].name;
        _employeeCompanies[i].text = draft.employees[i].company;
      }
    });
  }

  @override
  void dispose() {
    _location.dispose();
    _wellName.dispose();
    _notes.dispose();
    for (final controller in _employeeNames) controller.dispose();
    for (final controller in _employeeCompanies) controller.dispose();
    for (final controller in _signatures) controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<JsaDraft> _buildDraft() async {
    final employees = <JsaEmployee>[];
    for (var i = 0; i < 6; i++) {
      final png = await _signatures[i].toPngBytes();
      employees.add(JsaEmployee(
        name: _employeeNames[i].text.trim(),
        company: _employeeCompanies[i].text.trim(),
        signaturePngBase64: png == null ? null : base64Encode(png),
      ));
    }
    return JsaDraft(
      company: _company,
      date: DateFormat('yyyy-MM-dd').format(_date),
      time: '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      location: _location.text.trim(),
      wellName: _wellName.text.trim(),
      task: _task,
      steps: _steps,
      hazards: _hazards,
      recommendations: _recommendations,
      employees: employees,
      notes: _notes.text.trim(),
    );
  }

  Future<void> _saveDraft() async {
    await _storage.saveDraft(await _buildDraft());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSA draft saved')));
  }

  Future<void> _exportPlaceholder() async {
    await _saveDraft();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PDF export foundation is ready. Full PDF layout is next.')),
    );
  }

  Future<void> _clearDraft() async {
    await _storage.clearDraft();
    if (!mounted) return;
    setState(() {
      _location.clear();
      _wellName.clear();
      _notes.clear();
      for (final c in _employeeNames) c.clear();
      for (final c in _employeeCompanies) c.clear();
      for (final s in _signatures) s.clear();
      _company = 'Mach Energy';
      _task = 'Flowback';
      _date = DateTime.now();
      _time = TimeOfDay.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('MM/dd/yyyy').format(_date);
    final timeText = _time.format(context);

    return Scaffold(
      appBar: const AppHeader(title: 'JSA', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _section('Job Info'),
          DropdownButtonFormField<String>(
            value: _company,
            items: _companies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _company = v ?? _company),
            decoration: const InputDecoration(labelText: 'Company'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _location, decoration: const InputDecoration(labelText: 'Location / Pad')),
          const SizedBox(height: 12),
          TextField(controller: _wellName, decoration: const InputDecoration(labelText: 'Well Name')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: _pickDate, child: Text('Date: $dateText'))),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton(onPressed: _pickTime, child: Text('Time: $timeText'))),
            ],
          ),
          const SizedBox(height: 18),
          _section('Task'),
          DropdownButtonFormField<String>(
            value: _task,
            items: _taskLibrary.keys.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) => setState(() => _task = v ?? _task),
            decoration: const InputDecoration(labelText: 'Select Job / Task'),
          ),
          const SizedBox(height: 18),
          _infoCard('Basic Steps', _steps),
          _infoCard('Hazards', _hazards),
          _infoCard('Recommendations', _recommendations),
          _section('Notes'),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Additional notes'),
          ),
          const SizedBox(height: 18),
          _section('Employees & Signatures'),
          for (var i = 0; i < 6; i++) _employeeCard(i),
          const SizedBox(height: 18),
          FilledButton(onPressed: _saveDraft, child: const Text('Save JSA Draft')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _exportPlaceholder, child: const Text('Export PDF')),
          const SizedBox(height: 10),
          TextButton(onPressed: _clearDraft, child: const Text('Clear JSA')),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title, style: const TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
      );

  Widget _infoCard(String title, List<String> items) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final item in items) Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $item'),
              ),
            ],
          ),
        ),
      );

  Widget _employeeCard(int index) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Employee ${index + 1}', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextField(controller: _employeeNames[index], decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(controller: _employeeCompanies[index], decoration: const InputDecoration(labelText: 'Company')),
              const SizedBox(height: 12),
              Container(
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Signature(controller: _signatures[index], backgroundColor: const Color(0xFF111111)),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => _signatures[index].clear(), child: const Text('Clear Signature')),
              ),
            ],
          ),
        ),
      );
}
