import 'package:flutter/material.dart';

import '../services/report_profile_service.dart';
import '../widgets/app_header.dart';
import 'production_inventory_screen.dart';

class ReportTemplateScreen extends StatefulWidget {
  const ReportTemplateScreen({
    super.key,
    this.initialSection = 'layouts',
  });

  final String initialSection;

  @override
  State<ReportTemplateScreen> createState() => _ReportTemplateScreenState();
}

class _ReportTemplateScreenState extends State<ReportTemplateScreen> {
  final _service = ReportProfileService();

  List<ReportLayoutProfile> _profiles = [];
  String _activeProfileId = 'default';
  String _selectedProfileId = 'default';
  bool _editingReport = true;
  bool _showInventory = false;
  bool _loading = true;

  ReportLayoutProfile get _selectedProfile => _profiles.firstWhere(
        (item) => item.id == _selectedProfileId,
        orElse: () => _profiles.first,
      );

  @override
  void initState() {
    super.initState();
    _showInventory = widget.initialSection.toLowerCase() == 'inventory';
    _load();
  }

  Future<void> _load() async {
    final profiles = await _service.loadProfiles();
    final activeId = await _service.loadActiveProfileId();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _activeProfileId = activeId;
      _selectedProfileId =
          profiles.any((p) => p.id == activeId) ? activeId : profiles.first.id;
      _loading = false;
    });
  }

  Future<void> _setActive() async {
    await _service.setActiveProfileId(_selectedProfile.id);
    if (!mounted) return;
    setState(() => _activeProfileId = _selectedProfile.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Active layout set to ${_selectedProfile.name}.')),
    );
  }

  Future<String?> _askLayoutName(
      {required String title, String? initial}) async {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Layout Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _createProfile() async {
    final name = await _askLayoutName(title: 'Create New Layout');
    if (name == null) return;
    final profiles =
        await _service.createProfile(name: name, source: _selectedProfile);
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _selectedProfileId = profiles.last.id;
    });
  }

  Future<void> _renameProfile() async {
    final name = await _askLayoutName(
      title: 'Rename Layout',
      initial: _selectedProfile.name,
    );
    if (name == null || name.isEmpty) return;
    final updated = _selectedProfile.copyWith(name: name);
    final profiles = await _service.upsertProfile(updated);
    if (!mounted) return;
    setState(() => _profiles = profiles);
  }

  Future<void> _duplicateProfile() async {
    final name = await _askLayoutName(
      title: 'Duplicate Layout',
      initial: '${_selectedProfile.name} Copy',
    );
    if (name == null) return;
    final profiles =
        await _service.createProfile(name: name, source: _selectedProfile);
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _selectedProfileId = profiles.last.id;
    });
  }

  Future<void> _deleteProfile() async {
    if (_profiles.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one layout must remain.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Layout?'),
            content: Text('Delete ${_selectedProfile.name}?'),
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

    final deletingId = _selectedProfile.id;
    final profiles = await _service.deleteProfile(deletingId);
    final activeId = await _service.loadActiveProfileId();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _activeProfileId = activeId;
      _selectedProfileId = profiles.first.id;
    });
  }

  Future<void> _saveCurrent(ReportLayoutProfile profile) async {
    final profiles = await _service.upsertProfile(profile);
    if (!mounted) return;
    setState(() => _profiles = profiles);
  }

  void _toggleIncluded(int index, bool value) {
    final selected = _selectedProfile;
    final fields = List<ReportField>.from(
      _editingReport ? selected.reportFields : selected.textFields,
    );
    fields[index] = fields[index].copyWith(included: value);

    final updated = _editingReport
        ? selected.copyWith(reportFields: fields)
        : selected.copyWith(textFields: fields);

    setState(() {
      _profiles = _profiles
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
    });
    _saveCurrent(updated);
  }

  void _onReorder(int oldIndex, int newIndex) {
    final selected = _selectedProfile;
    final fields = List<ReportField>.from(
      _editingReport ? selected.reportFields : selected.textFields,
    );
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = fields.removeAt(oldIndex);
    fields.insert(newIndex, moved);

    final updated = _editingReport
        ? selected.copyWith(reportFields: fields)
        : selected.copyWith(textFields: fields);

    setState(() {
      _profiles = _profiles
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
    });
    _saveCurrent(updated);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Report/Text Layouts', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final selected = _selectedProfile;
    final fields = _editingReport ? selected.reportFields : selected.textFields;

    return Scaffold(
      appBar: const AppHeader(title: 'Report/Text Layouts', showBack: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Production Inventory'),
                  icon: Icon(Icons.inventory),
                ),
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Layout Profiles'),
                  icon: Icon(Icons.edit_note),
                ),
              ],
              selected: {_showInventory},
              onSelectionChanged: (selected) {
                setState(() => _showInventory = selected.first);
              },
            ),
          ),
          if (_showInventory)
            const Expanded(
              child: ProductionInventoryScreen(
                embedded: true,
                showManageLayoutsButton: false,
              ),
            ),
          if (!_showInventory) ...[
            Padding(
              padding: const EdgeInsets.all(18),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Layout Profiles',
                        style: TextStyle(
                          color: Color(0xFFCDA56A),
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selected.id,
                        decoration:
                            const InputDecoration(labelText: 'Layout Profile'),
                        items: [
                          for (final profile in _profiles)
                            DropdownMenuItem(
                              value: profile.id,
                              child: Text(
                                profile.id == _activeProfileId
                                    ? '${profile.name} (Active)'
                                    : profile.name,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _selectedProfileId = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _createProfile,
                            icon: const Icon(Icons.add),
                            label: const Text('Create New Layout'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _renameProfile,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit Layout Name'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _duplicateProfile,
                            icon: const Icon(Icons.copy),
                            label: const Text('Duplicate Layout'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _deleteProfile,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete Layout'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _setActive,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Set Active Layout'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Production Report Fields'),
                    icon: Icon(Icons.table_chart),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Text Update Fields'),
                    icon: Icon(Icons.sms),
                  ),
                ],
                selected: {_editingReport},
                onSelectionChanged: (selected) {
                  setState(() => _editingReport = selected.first);
                },
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                itemCount: fields.length,
                onReorderItem: _onReorder,
                itemBuilder: (context, index) {
                  final field = fields[index];
                  return Card(
                    key: ValueKey(
                        '${selected.id}_${field.key}_${_editingReport ? 'r' : 't'}'),
                    child: ListTile(
                      leading: const Icon(Icons.drag_handle),
                      title: Text(field.label),
                      trailing: Switch(
                        value: field.included,
                        onChanged: (value) => _toggleIncluded(index, value),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
