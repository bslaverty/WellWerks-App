import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/job_setup.dart';
import '../models/round_reading.dart';
import '../services/job_storage_service.dart';
import '../services/report_profile_service.dart';
import '../services/round_storage_service.dart';
import '../services/report_field_formatter.dart';
import '../widgets/app_header.dart';
import 'report_template_screen.dart';

class ShiftReportScreen extends StatefulWidget {
  const ShiftReportScreen({super.key});

  @override
  State<ShiftReportScreen> createState() => _ShiftReportScreenState();
}

class _ShiftReportScreenState extends State<ShiftReportScreen> {
  final _storage = RoundStorageService();
  final _jobStorage = JobStorageService();
  final _profiles = ReportProfileService();
  final _wellName = TextEditingController();
  final _choke = TextEditingController();
  String _chokeStyle = 'adj';
  String _company = 'Mach Energy';
  RoundReading? _latest;
  JobSetup? _job;
  ReportProfile? _customProfile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final readings = await _storage.loadReadings();
    final job = await _jobStorage.loadActiveJob();
    final custom = await _profiles.loadCustomProfile();
    if (!mounted) return;
    setState(() {
      _latest = readings.isEmpty ? null : readings.first;
      _job = job;
      _customProfile = custom;
      _loading = false;
      _company = job?.company ?? 'Mach Energy';
      if (_wellName.text.trim().isEmpty && (job?.wells.isNotEmpty ?? false)) {
        _wellName.text = job!.wells.first;
      }
      if ((_choke.text.trim().isEmpty) && (_latest?.choke.trim().isNotEmpty ?? false)) {
        _choke.text = _latest!.choke.trim();
      }
      _chokeStyle = _latest?.chokeStyle ?? 'adj';
    });
  }

  ReportProfile get _activeProfile {
    if (_company == 'Custom') return _customProfile ?? _profiles.builtIn('Custom');
    return _profiles.builtIn(_company);
  }

  String get _timeLabel {
    final raw = _latest?.roundLabel.trim() ?? '';
    if (raw.isNotEmpty) return raw.toUpperCase().contains('UPDATE') ? raw : '$raw UPDATE';
    return '${DateFormat('h:mm a').format(DateTime.now())} UPDATE';
  }

  String _v(String? value, {String fallback = 'N/A'}) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String get _currentChoke {
    final typed = _choke.text.trim();
    final size = typed.isNotEmpty
        ? typed
        : (_latest?.choke.trim().isNotEmpty == true ? _latest!.choke.trim() : 'N/A');
    if (size == 'N/A') return size;
    return '$size $_chokeStyle';
  }

  String _fieldValue(String key) {
    final r = _latest;
    if (r == null) return '';
    switch (key) {
      case 'tbg':
        return _v(r.tubingPressure);
      case 'csg':
        return _v(r.casingPressure);
      case 'icp':
        return _v(r.icp);
      case 'scp':
        return _v(r.scp);
      case 'choke':
        return _currentChoke;
      case 'waterRate':
        return _v(r.waterRate);
      case 'oilRate':
        return _v(r.oilRate);
      case 'gasRate':
        return _v(r.gasRate);
      case 'diff':
        return _v(r.differentialPressure);
      case 'sp':
        return _v(r.separatorPressure);
      case 'gasTemp':
        return _v(r.gasTemp);
      case 'whTemp':
        return _v(r.wellheadTemp);
      case 'waterTemp':
        return _v(r.waterTemp);
      case 'prop':
        return _v(r.propRate);
      case 'biocide':
        return _v(r.biocideRate);
      case 'ecdTemp':
        return _v(r.ecdTemp);
      case 'notes':
        return r.notes.trim();
    }
    return '';
  }

  String _formattedLine(ReportField field, {bool email = false}) {
    final value = _fieldValue(field.key);
    return ReportFieldFormatter.line(
      field: field,
      value: value,
      company: _company,
      email: email,
    );
  }

  List<String> get _missing {
    final r = _latest;
    if (r == null) return ['No round saved yet'];
    final missing = <String>[];
    if (_wellName.text.trim().isEmpty) missing.add('Well name');
    for (final field in _activeProfile.fields.where((f) => f.required)) {
      final value = _fieldValue(field.key).trim();
      if (value.isEmpty || value == 'N/A') missing.add(field.label);
    }
    return missing;
  }

  List<ReportField> get _includedFields =>
      _activeProfile.fields.where((f) => f.included).toList();

  String _buildReport({bool email = false}) {
    final r = _latest;
    final well = _wellName.text.trim().isEmpty ? 'Well Name' : _wellName.text.trim();
    if (r == null) return 'No round saved yet. Enter a Quick Round first.';

    final lines = <String>[
      email ? 'Well: $well' : well,
      email ? 'Update: $_timeLabel' : _timeLabel,
      '',
    ];
    for (final field in _includedFields) {
      final line = _formattedLine(field, email: email);
      if (line.trim().isNotEmpty) lines.add(line);
    }
    return lines.join('\n');
  }

  Future<void> _copy({bool email = false}) async {
    await Clipboard.setData(ClipboardData(text: _buildReport(email: email)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(email ? 'Email report copied' : 'iMessage report copied')),
    );
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
                if (_job != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text('${_job!.padName.isEmpty ? 'Active Job' : _job!.padName}\n${_job!.company}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
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
                if (_company == 'Custom')
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportTemplateScreen()));
                        await _load();
                      },
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Edit Custom Fields'),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(controller: _wellName, decoration: const InputDecoration(labelText: 'Well Name'), onChanged: (_) => setState(() {})),
                const SizedBox(height: 12),
                TextField(controller: _choke, keyboardType: TextInputType.text, decoration: const InputDecoration(labelText: 'Choke Size Override'), onChanged: (_) => setState(() {})),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _chokeStyle,
                  decoration: const InputDecoration(labelText: 'Choke Style'),
                  items: const [
                    DropdownMenuItem(value: 'adj', child: Text('adj - Adjustable')),
                    DropdownMenuItem(value: 'pos', child: Text('pos - Positive')),
                  ],
                  onChanged: (value) => setState(() => _chokeStyle = value ?? 'adj'),
                ),
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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Smart units are applied automatically. Empty optional fields are hidden from the copied report.',
                      style: TextStyle(color: Colors.grey.shade300),
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
                FilledButton.icon(onPressed: () => _copy(), icon: const Icon(Icons.sms), label: const Text('Copy for iMessage')),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: () => _copy(email: true), icon: const Icon(Icons.email), label: const Text('Copy for Email')),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _buildReport()));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF export foundation ready - report text copied for now')));
                }, icon: const Icon(Icons.picture_as_pdf), label: const Text('Export PDF (coming soon)')),
              ],
            ),
    );
  }
}
