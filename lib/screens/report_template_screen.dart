import 'package:flutter/material.dart';

import '../services/report_profile_service.dart';
import '../widgets/app_header.dart';

class ReportTemplateScreen extends StatefulWidget {
  const ReportTemplateScreen({super.key});

  @override
  State<ReportTemplateScreen> createState() => _ReportTemplateScreenState();
}

class _ReportTemplateScreenState extends State<ReportTemplateScreen> {
  final _service = ReportProfileService();
  late ReportProfile _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await _service.loadCustomProfile();
    if (!mounted) return;
    setState(() {
      _profile = loaded.fields.isEmpty ? _service.builtIn('Custom') : loaded;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _service.saveCustomProfile(_profile);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Custom report profile saved')));
  }

  void _toggleIncluded(int index, bool value) {
    final fields = List<ReportField>.from(_profile.fields);
    fields[index] = fields[index].copyWith(included: value);
    setState(() => _profile = ReportProfile(name: _profile.name, fields: fields));
  }

  void _toggleRequired(int index, bool value) {
    final fields = List<ReportField>.from(_profile.fields);
    fields[index] = fields[index].copyWith(required: value, included: value ? true : fields[index].included);
    setState(() => _profile = ReportProfile(name: _profile.name, fields: fields));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Report Builder', showBack: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                        Text('Custom Company Profile', style: TextStyle(color: Color(0xFFCDA56A), fontWeight: FontWeight.bold, fontSize: 18)),
                        SizedBox(height: 6),
                        Text('Pick what goes on the shift report. Required fields must be filled before copying.'),
                      ]),
                    ),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    itemCount: _profile.fields.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        final fields = List<ReportField>.from(_profile.fields);
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = fields.removeAt(oldIndex);
                        fields.insert(newIndex, item);
                        _profile = ReportProfile(name: _profile.name, fields: fields);
                      });
                    },
                    itemBuilder: (context, index) {
                      final field = _profile.fields[index];
                      return Card(
                        key: ValueKey(field.key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.drag_handle),
                              Expanded(child: Text(field.label, style: const TextStyle(fontWeight: FontWeight.bold))),
                              Column(children: [
                                const Text('Include', style: TextStyle(fontSize: 11)),
                                Switch(value: field.included, onChanged: (v) => _toggleIncluded(index, v)),
                              ]),
                              Column(children: [
                                const Text('Required', style: TextStyle(fontSize: 11)),
                                Switch(value: field.required, onChanged: (v) => _toggleRequired(index, v)),
                              ]),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Save Custom Profile')),
                ),
              ],
            ),
    );
  }
}
