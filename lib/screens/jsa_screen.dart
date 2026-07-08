import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:signature/signature.dart';

import '../models/job_setup.dart';
import '../models/jsa_draft.dart';
import '../services/jsa_export_service.dart';
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
  final _exportService = const JsaExportService();
  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();
  final _exportImageKey = GlobalKey();
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
  JsaDraft? _exportPreviewDraft;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  final Set<String> _selectedTasks = {'Flowback'};
  bool _exporting = false;

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
    final draft = activeJob != null
        ? await _storage.loadTodayForJob(activeJob.id)
        : await _storage.loadDraft();
    if (!mounted) return;
    setState(() {
      _activeJob = activeJob;
      _clearFormValues(resetDateTime: false);
      if (draft != null) {
        _applyDraft(draft);
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

  String get _draftDateKey => DateFormat('yyyy-MM-dd').format(_date);

  void _clearFormValues({required bool resetDateTime}) {
    _location.clear();
    _wellName.clear();
    _notes.clear();
    for (final controller in _employeeNames) {
      controller.clear();
    }
    for (final controller in _employeeCompanies) {
      controller.clear();
    }
    for (final signature in _signatures) {
      signature.clear();
    }
    _company = 'Mach Energy';
    _selectedTasks
      ..clear()
      ..add('Flowback');
    if (resetDateTime) {
      _date = DateTime.now();
      _time = TimeOfDay.now();
    }
  }

  void _applyDraft(JsaDraft draft) {
    _company = _companies.contains(draft.company) ? draft.company : 'Custom';
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
    _date = DateTime.tryParse(draft.date) ?? _date;
    final parts = draft.time.split(':');
    if (parts.length >= 2) {
      _time = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? _time.hour,
        minute: int.tryParse(parts[1]) ?? _time.minute,
      );
    }
    for (var i = 0; i < draft.employees.length && i < 6; i++) {
      final employee = draft.employees[i];
      _employeeNames[i].text = employee.name;
      _employeeCompanies[i].text = employee.company;
      if (employee.signaturePoints.isNotEmpty) {
        _signatures[i].points = employee.signaturePoints
            .map(
              (point) => Point(
                Offset(point.x, point.y),
                point.type == 'move' ? PointType.move : PointType.tap,
                point.pressure,
              ),
            )
            .toList();
        _signatures[i].pushCurrentStateToUndoStack();
      }
    }
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
        signaturePoints: _signatures[i]
            .points
            .map(
              (point) => JsaSignaturePoint(
                x: point.offset.dx,
                y: point.offset.dy,
                type: point.type == PointType.move ? 'move' : 'tap',
                pressure: point.pressure,
              ),
            )
            .toList(),
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

  Future<JsaDraft> _saveDraft({bool showFeedback = true}) async {
    final draft = await _buildDraft();
    await _storage.saveDraft(draft);
    _exportPreviewDraft = draft;
    if (!mounted) return draft;
    if (showFeedback) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('JSA draft saved')));
    }
    return draft;
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

  Future<Uint8List?> _captureExportImageBytes(JsaDraft draft) async {
    setState(() => _exportPreviewDraft = draft);
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    final boundary = _exportImageKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      return null;
    }
    final image = await boundary.toImage(pixelRatio: 2.5);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _saveAsPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final draft = await _saveDraft(showFeedback: false);
      final exported = await _exportService.exportPdf(
        draft: draft,
        activeJob: _activeJob,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved PDF: ${exported.fileName}')),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _saveAsImage() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final draft = await _saveDraft(showFeedback: false);
      final imageBytes = await _captureExportImageBytes(draft);
      if (imageBytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to capture JSA image.')),
        );
        return;
      }
      final exported = await _exportService.exportImage(
        draft: draft,
        pngBytes: imageBytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved Image: ${exported.fileName}')),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _shareJsa() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final draft = await _saveDraft(showFeedback: false);
      final exported = await _exportService.exportPdf(
        draft: draft,
        activeJob: _activeJob,
      );
      await Share.shareXFiles(
        [XFile(exported.filePath)],
        subject: 'WellWerks JSA',
        text: 'JSA exported from WellWerks.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('JSA shared.')),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _clearDraft() async {
    await _storage.deleteDraft(
      activeJobId: _activeJob?.id ?? '',
      date: _draftDateKey,
    );
    await _storage.clearDraft();
    if (!mounted) return;
    setState(() {
      _clearFormValues(resetDateTime: true);
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
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          ListView(
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
                  decoration:
                      const InputDecoration(labelText: 'Location / Pad')),
              const SizedBox(height: 12),
              TextField(
                  controller: _wellName,
                  decoration: const InputDecoration(labelText: 'Well Name')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: OutlinedButton(
                          onPressed: _pickDate,
                          child: Text('Date: $dateText'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: OutlinedButton(
                          onPressed: _pickTime,
                          child: Text('Time: $timeText'))),
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
                decoration:
                    const InputDecoration(labelText: 'Additional notes'),
              ),
              const SizedBox(height: 18),
              _section('Employees & Signatures'),
              for (var i = 0; i < 6; i++) _employeeCard(i),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _exporting ? null : () => _saveDraft(),
                child: const Text('Save JSA Draft'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _exporting ? null : _saveAsPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Save as PDF'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _exporting ? null : _saveAsImage,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Save as Image'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _exporting ? null : _shareJsa,
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share / Send'),
              ),
              const SizedBox(height: 10),
              TextButton(
                  onPressed: _clearDraft, child: const Text('Clear JSA')),
            ],
          ),
          Positioned(
            left: -5000,
            top: 0,
            child: IgnorePointer(
              child: RepaintBoundary(
                key: _exportImageKey,
                child: SizedBox(
                  width: 900,
                  child: _exportPreviewCard(_exportPreviewDraft),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exportPreviewCard(JsaDraft? draft) {
    final exportDraft = draft ??
        JsaDraft(
          activeJobId: _activeJob?.id ?? '',
          company: _company,
          date: _draftDateKey,
          time:
              '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
          location: _location.text.trim(),
          wellName: _wellName.text.trim(),
          task: _tasks.join(', '),
          tasks: _tasks,
          steps: _steps,
          hazards: _hazards,
          recommendations: _recommendations,
          employees: const [],
          notes: _notes.text.trim(),
        );

    return Material(
      color: const Color(0xFF111111),
      child: Container(
        padding: const EdgeInsets.all(24),
        color: const Color(0xFF111111),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WellWerks JSA',
              style: TextStyle(
                color: gold,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              exportDraft.company.trim().isEmpty
                  ? '-'
                  : exportDraft.company.trim(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            _exportPreviewSection('Job Information', [
              _previewLine('Date', exportDraft.date),
              _previewLine('Time', exportDraft.time),
              _previewLine('Location', exportDraft.location),
              _previewLine('Pad', _activeJob?.padName ?? ''),
              _previewLine(
                'Well',
                exportDraft.wellName.trim().isEmpty
                    ? (_activeJob?.primaryWell ?? '')
                    : exportDraft.wellName,
              ),
              _previewLine('Customer', _activeJob?.customer ?? ''),
              _previewLine('Lease', _activeJob?.leaseName ?? ''),
            ]),
            _exportPreviewSection(
                'Selected Steps', _previewBullets(exportDraft.tasks)),
            _exportPreviewSection(
                'Basic Steps', _previewBullets(exportDraft.steps)),
            _exportPreviewSection(
                'Hazards', _previewBullets(exportDraft.hazards)),
            _exportPreviewSection(
              'Recommendations',
              _previewBullets(exportDraft.recommendations),
            ),
            _exportPreviewSection('Employees & Signatures', [
              if (exportDraft.employees
                  .where((employee) =>
                      employee.name.trim().isNotEmpty ||
                      employee.company.trim().isNotEmpty ||
                      (employee.signaturePngBase64 ?? '').trim().isNotEmpty)
                  .isEmpty)
                const Text(
                  'No employees entered.',
                  style: TextStyle(color: Colors.white70),
                ),
              for (final employee in exportDraft.employees)
                if (employee.name.trim().isNotEmpty ||
                    employee.company.trim().isNotEmpty ||
                    (employee.signaturePngBase64 ?? '').trim().isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.name.trim().isEmpty
                              ? 'Unnamed employee'
                              : employee.name.trim(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          employee.company.trim().isEmpty
                              ? 'Company not entered'
                              : employee.company.trim(),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        if ((employee.signaturePngBase64 ?? '')
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            height: 90,
                            width: 220,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: _signatureImage(employee.signaturePngBase64),
                          ),
                        ],
                      ],
                    ),
                  ),
            ]),
            _exportPreviewSection('Notes / Comments', [
              Text(
                exportDraft.notes.trim().isEmpty
                    ? '-'
                    : exportDraft.notes.trim(),
                style: const TextStyle(color: Colors.white70),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _exportPreviewSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF17130E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: gold,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  List<Widget> _previewBullets(List<String> items) {
    final visibleItems = items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (visibleItems.isEmpty) {
      return const [
        Text('None entered.', style: TextStyle(color: Colors.white70)),
      ];
    }
    return visibleItems
        .map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child:
                Text('• $item', style: const TextStyle(color: Colors.white70)),
          ),
        )
        .toList();
  }

  Widget _previewLine(String label, String value) {
    final trimmed = value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: gold,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: trimmed.isEmpty ? '-' : trimmed,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signatureImage(String? base64Value) {
    try {
      final bytes = base64Decode(base64Value ?? '');
      return Image.memory(bytes, fit: BoxFit.contain);
    } catch (_) {
      return const SizedBox.shrink();
    }
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
