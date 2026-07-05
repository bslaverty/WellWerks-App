import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';

import '../models/job_setup.dart';
import '../models/jsa_draft.dart';
import '../services/job_storage_service.dart';
import '../services/jsa_storage_service.dart';
import '../services/recovery_state_service.dart';
import '../widgets/app_header.dart';

class JsaScreen extends StatefulWidget {
  const JsaScreen({super.key});

  @override
  State<JsaScreen> createState() => _JsaScreenState();
}

class _JsaScreenState extends State<JsaScreen> {
  static const gold = Color(0xFFCDA56A);

  final _storage = JsaStorageService();
  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();
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
  JobSetup? _activeJob;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  final Set<String> _selectedTasks = {'Flowback'};

  final _companies = const [
    'Mach Energy',
    'Continental',
    'Devon',
    'XTO',
    'Custom',
  ];

  final Map<String, Map<String, List<String>>> _taskLibrary = const {
    'Flowback': {
      'steps': [
        'Monitor well flow',
        'Check pressures',
        'Check tanks',
        'Record readings'
      ],
      'hazards': [
        'High pressure',
        'H2S/gas exposure',
        'Slips/trips',
        'Hot surfaces'
      ],
      'recommendations': [
        'Wear PPE',
        'Stay out of line of fire',
        'Verify valves before operating',
        'Communicate changes'
      ],
    },
    'Dump Sand': {
      'steps': [
        'Confirm safe position',
        'Isolate equipment',
        'Bleed off PSI',
        'Dump sand'
      ],
      'hazards': [
        'Stored pressure',
        'Flying debris',
        'Pinch points',
        'Heavy sand discharge'
      ],
      'recommendations': [
        'Stand in safe position',
        'Isolate and bleed off PSI',
        'Use face shield',
        'Keep hands clear'
      ],
    },
    'Fixing Leaks': {
      'steps': [
        'Identify leak',
        'Notify crew',
        'Isolate equipment',
        'Bleed off PSI',
        'Repair leak'
      ],
      'hazards': [
        'High pressure leak',
        'Chemical exposure',
        'Hot work area',
        'Pinch points'
      ],
      'recommendations': [
        'Do not tighten under pressure',
        'Isolate and bleed off PSI',
        'Use correct tools',
        'Verify repair before returning to service'
      ],
    },
    'Rig Up': {
      'steps': [
        'Spot equipment',
        'Connect iron',
        'Secure lines',
        'Pressure test'
      ],
      'hazards': [
        'Suspended loads',
        'Pinch points',
        'High pressure',
        'Backing equipment'
      ],
      'recommendations': [
        'Use spotters',
        'Stay clear of suspended loads',
        'Inspect iron',
        'Confirm pressure test'
      ],
    },
    'Rig Down': {
      'steps': [
        'Shut in/secure well',
        'Bleed off lines',
        'Disconnect iron',
        'Load equipment'
      ],
      'hazards': [
        'Residual pressure',
        'Heavy equipment',
        'Pinch points',
        'Slips/trips'
      ],
      'recommendations': [
        'Verify zero energy',
        'Use proper lifting',
        'Keep work area clean',
        'Communicate all lifts'
      ],
    },
    'Change Choke': {
      'steps': [
        'Notify crew',
        'Verify choke position',
        'Make controlled adjustment',
        'Monitor pressures'
      ],
      'hazards': [
        'Pressure change',
        'Line of fire',
        'Pinch points',
        'Unexpected flow change'
      ],
      'recommendations': [
        'Communicate before adjustment',
        'Stand clear of pressure points',
        'Use proper tools',
        'Record change and response'
      ],
    },
    'Pressure Test': {
      'steps': [
        'Inspect connections',
        'Clear test area',
        'Bring pressure up slowly',
        'Monitor for leaks',
        'Bleed down safely'
      ],
      'hazards': [
        'High pressure',
        'Failed iron',
        'Flying debris',
        'Stored energy'
      ],
      'recommendations': [
        'Use rated iron',
        'Keep non-essential personnel clear',
        'Never stand in line of fire',
        'Confirm bleed down before work'
      ],
    },
  };

  List<String> get _tasks => _selectedTasks.toList()..sort();

  List<String> _combined(String key) {
    final out = <String>[];
    for (final task in _tasks) {
      for (final item in _taskLibrary[task]?[key] ?? const <String>[]) {
        if (!out.contains(item)) out.add(item);
      }
    }
    return out;
  }

  List<String> get _steps => _combined('steps');
  List<String> get _hazards => _combined('hazards');
  List<String> get _recommendations => _combined('recommendations');

  @override
  void initState() {
    super.initState();
    _recoveryState.saveLastModule(RecoveryModules.jsa);
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    final activeJob = await _jobStorage.loadActiveJob();
    final draft = await _storage.loadDraft();
    if (!mounted) return;
    setState(() {
      _activeJob = activeJob;
      if (draft != null) {
        _company =
            _companies.contains(draft.company) ? draft.company : 'Custom';
        _selectedTasks
          ..clear()
          ..addAll(draft.tasks.where(_taskLibrary.containsKey));
        if (_selectedTasks.isEmpty && _taskLibrary.containsKey(draft.task)) {
          _selectedTasks.add(draft.task);
        }
        if (_selectedTasks.isEmpty) _selectedTasks.add('Flowback');
        _location.text = draft.location;
        _wellName.text = draft.wellName;
        _notes.text = draft.notes;
        _date = DateTime.tryParse(draft.date) ?? DateTime.now();
        final parts = draft.time.split(':');
        if (parts.length >= 2) {
          _time = TimeOfDay(
              hour: int.tryParse(parts[0]) ?? 0,
              minute: int.tryParse(parts[1]) ?? 0);
        }
        for (var i = 0; i < draft.employees.length && i < 6; i++) {
          _employeeNames[i].text = draft.employees[i].name;
          _employeeCompanies[i].text = draft.employees[i].company;
        }
      }
      if (activeJob != null) {
        if (_company == 'Mach Energy' || _company == 'Custom') {
          _company = _companies.contains(activeJob.company)
              ? activeJob.company
              : _company;
        }
        if (_location.text.trim().isEmpty) {
          _location.text = activeJob.padName;
        }
        if (_wellName.text.trim().isEmpty) {
          _wellName.text = activeJob.primaryWell;
        }
      }
    });
  }

  @override
  void dispose() {
    _location.dispose();
    _wellName.dispose();
    _notes.dispose();
    for (final controller in _employeeNames) {
      controller.dispose();
    }
    for (final controller in _employeeCompanies) {
      controller.dispose();
    }
    for (final controller in _signatures) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) {
      setState(() => _time = picked);
    }
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
      activeJobId: _activeJob?.id ?? '',
      company: _company,
      date: DateFormat('yyyy-MM-dd').format(_date),
      time:
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      location: _location.text.trim(),
      wellName: _wellName.text.trim(),
      task: _tasks.join(', '),
      tasks: _tasks,
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('JSA draft saved')));
  }

  Widget _activeJobBanner() {
    final activeJob = _activeJob;
    if (activeJob == null) {
      return const Card(
        margin: EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Active Job',
                style: TextStyle(color: gold, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'No active job found. Start a job first so this JSA can save under the current job.',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Active Job',
              style: TextStyle(color: gold, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              activeJob.company.trim().isEmpty
                  ? 'No company entered'
                  : activeJob.company,
              style: const TextStyle(color: gold, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _jobChip('Pad', activeJob.padName),
                _jobChip('Well', activeJob.primaryWell),
                _jobChip('Shift', activeJob.shift),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobChip(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: gold.withValues(alpha: 0.35)),
        ),
        child: Text(
          '$label: ${value.trim().isEmpty ? 'Not entered' : value.trim()}',
          style: const TextStyle(
              color: Colors.white70, fontWeight: FontWeight.w600),
        ),
      );

  Future<void> _exportPlaceholder() async {
    await _saveDraft();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content:
              Text('PDF export foundation is ready. Full PDF layout is next.')),
    );
  }

  Future<void> _clearDraft() async {
    await _storage.clearDraft();
    if (!mounted) return;
    setState(() {
      _location.clear();
      _wellName.clear();
      _notes.clear();
      for (final c in _employeeNames) {
        c.clear();
      }
      for (final c in _employeeCompanies) {
        c.clear();
      }
      for (final s in _signatures) {
        s.clear();
      }
      _company = 'Mach Energy';
      _selectedTasks
        ..clear()
        ..add('Flowback');
      _date = DateTime.now();
      _time = TimeOfDay.now();
    });
  }

  void _toggleTask(String task, bool selected) {
    setState(() {
      if (selected) {
        _selectedTasks.add(task);
      } else if (_selectedTasks.length > 1) {
        _selectedTasks.remove(task);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select at least one JSA step.')));
      }
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
          _activeJobBanner(),
          _section('Job Info'),
          DropdownButtonFormField<String>(
            initialValue: _company,
            items: _companies
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _company = v ?? _company),
            decoration: const InputDecoration(labelText: 'Company'),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Location / Pad')),
          const SizedBox(height: 12),
          TextField(
              controller: _wellName,
              decoration: const InputDecoration(labelText: 'Well Name')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: _pickDate, child: Text('Date: $dateText'))),
              const SizedBox(width: 12),
              Expanded(
                  child: OutlinedButton(
                      onPressed: _pickTime, child: Text('Time: $timeText'))),
            ],
          ),
          const SizedBox(height: 18),
          _section('JSA Steps / Tasks'),
          const Text('Select everything that applies to this job.',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _taskLibrary.keys.map((task) {
              final selected = _selectedTasks.contains(task);
              return FilterChip(
                selected: selected,
                label: Text(task),
                onSelected: (v) => _toggleTask(task, v),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          _infoCard('Selected JSA Items', _tasks),
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
          FilledButton(
              onPressed: _saveDraft, child: const Text('Save JSA Draft')),
          const SizedBox(height: 10),
          OutlinedButton(
              onPressed: _exportPlaceholder, child: const Text('Export PDF')),
          const SizedBox(height: 10),
          TextButton(onPressed: _clearDraft, child: const Text('Clear JSA')),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title,
            style: const TextStyle(
                color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
      );

  Widget _infoCard(String title, List<String> items) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: gold, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (items.isEmpty) const Text('None selected.'),
              for (final item in items)
                Padding(
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
              Text('Employee ${index + 1}',
                  style: const TextStyle(
                      color: gold, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextField(
                  controller: _employeeNames[index],
                  decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(
                  controller: _employeeCompanies[index],
                  decoration: const InputDecoration(labelText: 'Company')),
              const SizedBox(height: 12),
              Container(
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Signature(
                      controller: _signatures[index],
                      backgroundColor: const Color(0xFF111111)),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => _signatures[index].clear(),
                    child: const Text('Clear Signature')),
              ),
            ],
          ),
        ),
      );
}
