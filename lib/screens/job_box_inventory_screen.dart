import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import '../models/job_box_inventory.dart';
import '../services/job_box_inventory_service.dart';
import '../widgets/app_header.dart';

class JobBoxInventoryScreen extends StatefulWidget {
  const JobBoxInventoryScreen({super.key, this.initialRecordId});

  final String? initialRecordId;

  @override
  State<JobBoxInventoryScreen> createState() => _JobBoxInventoryScreenState();
}

class _JobBoxInventoryScreenState extends State<JobBoxInventoryScreen> {
  final _service = JobBoxInventoryService();
  final _dateController = TextEditingController();
  final _wellNamesController = TextEditingController();
  final _jobBoxNumberController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _hideZeroQuantityItems = true;
  String _recordId = '';
  DateTime _createdAt = DateTime.now();
  DateTime _updatedAt = DateTime.now();
  List<JobBoxInventoryItem> _items = [
    for (final item in JobBoxInventoryCatalog.defaultItems)
      item.copyWith(quantity: 0),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dateController.dispose();
    _wellNamesController.dispose();
    _jobBoxNumberController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    JobBoxInventoryRecord? record;
    final initialId = widget.initialRecordId?.trim() ?? '';
    if (initialId.isNotEmpty) {
      record = await _service.loadRecord(initialId);
    }
    record ??= await _service.loadWorkingDraft();
    record ??= JobBoxInventoryRecord.createDefault();

    if (!mounted) return;
    setState(() {
      _recordId = record!.id;
      _createdAt = record.createdAt;
      _updatedAt = record.updatedAt;
      _dateController.text = record.date;
      _wellNamesController.text = record.wellNames;
      _jobBoxNumberController.text = record.jobBoxNumber;
      _hideZeroQuantityItems = record.hideZeroQuantityItems;
      _items = record.items.isEmpty
          ? [
              for (final item in JobBoxInventoryCatalog.defaultItems)
                item.copyWith(quantity: 0),
            ]
          : record.items;
      _loading = false;
    });
    await _persistWorkingDraft();
  }

  JobBoxInventoryRecord _buildRecord({String? id}) {
    return JobBoxInventoryRecord(
      id: id ?? _recordId,
      date: _dateController.text.trim(),
      wellNames: _wellNamesController.text.trim(),
      jobBoxNumber: _jobBoxNumberController.text.trim(),
      hideZeroQuantityItems: _hideZeroQuantityItems,
      items: _items,
      createdAt: _createdAt,
      updatedAt: _updatedAt,
    );
  }

  Future<void> _persistWorkingDraft() async {
    _updatedAt = DateTime.now();
    await _service.saveWorkingDraft(_buildRecord());
  }

  void _updateItemQuantity(String key, int delta) {
    setState(() {
      _items = [
        for (final item in _items)
          if (item.key == key)
            item.copyWith(quantity: (item.quantity + delta).clamp(0, 9999))
          else
            item,
      ];
    });
    _persistWorkingDraft();
  }

  void _setHeaderChanged() {
    _persistWorkingDraft();
  }

  void _resetCounts() {
    setState(() {
      _items = [for (final item in _items) item.copyWith(quantity: 0)];
    });
    _persistWorkingDraft();
  }

  Future<void> _addCustomItem() async {
    final nameController = TextEditingController();
    final quantityController = TextEditingController(text: '0');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Custom Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Item name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Starting quantity'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != true) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;
    final quantity = int.tryParse(quantityController.text.trim()) ?? 0;
    final now = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _items = [
        ..._items,
        JobBoxInventoryItem(
          key: 'custom_$now',
          name: name,
          quantity: quantity < 0 ? 0 : quantity,
          section: JobBoxInventoryCatalog.customSection,
          isDefault: false,
          canDelete: true,
        ),
      ];
    });
    await _persistWorkingDraft();
  }

  Future<void> _deleteCustomItem(JobBoxInventoryItem item) async {
    if (!item.canDelete) return;
    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Custom Item?'),
            content: Text('Remove ${item.name}?'),
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
    if (!confirm) return;
    setState(() {
      _items = _items.where((entry) => entry.key != item.key).toList();
    });
    await _persistWorkingDraft();
  }

  Future<void> _saveToHistory() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final savedId = await _service.saveRecord(_buildRecord());
      if (!mounted) return;
      setState(() {
        _recordId = savedId;
      });
      await _service.saveWorkingDraft(_buildRecord(id: savedId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inventory saved to History.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatGpsDate() {
    return _dateController.text.trim().isEmpty
        ? DateFormat('MM/dd/yyyy').format(DateTime.now())
        : _dateController.text.trim();
  }

  Future<void> _copyInventoryUpdate() async {
    final buffer = StringBuffer()
      ..writeln('Job Box Inventory')
      ..writeln()
      ..writeln('Date: ${_formatGpsDate()}')
      ..writeln(
          'Well(s): ${_wellNamesController.text.trim().isEmpty ? '-' : _wellNamesController.text.trim()}')
      ..writeln(
          'Job Box: ${_jobBoxNumberController.text.trim().isEmpty ? '-' : _jobBoxNumberController.text.trim()}')
      ..writeln();

    void writeSection(String section) {
      final visible = _items
          .where((item) => item.section == section && item.quantity > 0)
          .toList();
      if (visible.isEmpty) return;
      if (section == JobBoxInventoryCatalog.positiveChokesSection) {
        buffer.writeln('Positive Chokes');
      }
      for (final item in visible) {
        buffer.writeln('${item.name}: ${item.quantity}');
      }
      buffer.writeln();
    }

    writeSection(JobBoxInventoryCatalog.mainSection);
    writeSection(JobBoxInventoryCatalog.positiveChokesSection);
    final customVisible = _items
        .where((item) =>
            item.section == JobBoxInventoryCatalog.customSection &&
            item.quantity > 0)
        .toList();
    for (final item in customVisible) {
      buffer.writeln('${item.name}: ${item.quantity}');
    }

    final text = buffer.toString().trimRight();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Inventory update copied to clipboard.')),
    );
  }

  Widget _sectionCard(String title, List<JobBoxInventoryItem> items) {
    if (items.isEmpty && _hideZeroQuantityItems) return const SizedBox.shrink();
    final visible = _hideZeroQuantityItems
        ? items.where((item) => item.quantity > 0).toList()
        : items;
    if (visible.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in visible) ...[
              _itemRow(item),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemRow(JobBoxInventoryItem item) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 54,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Text(
              '${item.quantity}',
              style: TextStyle(
                color: accent,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _stepButton(
            icon: Icons.remove,
            onPressed: item.quantity <= 0
                ? null
                : () => _updateItemQuantity(item.key, -1),
          ),
          const SizedBox(width: 8),
          _stepButton(
            icon: Icons.add,
            onPressed: () => _updateItemQuantity(item.key, 1),
          ),
          if (item.canDelete) ...[
            const SizedBox(width: 8),
            _stepButton(
              icon: Icons.delete_outline,
              onPressed: () => _deleteCustomItem(item),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepButton(
      {required IconData icon, required VoidCallback? onPressed}) {
    return SizedBox(
      width: 50,
      height: 50,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }

  Widget _buildHeaderFields() {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: _dateController,
              decoration: const InputDecoration(labelText: 'Date'),
              keyboardType: TextInputType.datetime,
              onChanged: (_) => _setHeaderChanged(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wellNamesController,
              decoration: const InputDecoration(labelText: 'Well Name(s)'),
              onChanged: (_) => _setHeaderChanged(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _jobBoxNumberController,
              decoration: const InputDecoration(labelText: 'Job Box Number'),
              onChanged: (_) => _setHeaderChanged(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBar() {
    final saveLabel = _recordId.isEmpty ? 'Save to History' : 'Save Changes';
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _copyInventoryUpdate,
            icon: const Icon(Icons.copy),
            label: const Text('Copy Inventory Update'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _saveToHistory,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : saveLabel),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _resetCounts,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset Counts'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _addCustomItem,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Add Custom Item'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Hide Zero Quantity Items'),
          value: _hideZeroQuantityItems,
          onChanged: (value) {
            setState(() => _hideZeroQuantityItems = value);
            _persistWorkingDraft();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Job Box Inventory', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Job Box Inventory', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Track job box inventory quickly with field-friendly counts and one-tap updates.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          _buildHeaderFields(),
          _actionBar(),
          const SizedBox(height: 14),
          _sectionCard(
            JobBoxInventoryCatalog.sectionLabel(
              JobBoxInventoryCatalog.mainSection,
            ),
            _items
                .where((item) =>
                    item.section == JobBoxInventoryCatalog.mainSection)
                .toList(),
          ),
          _sectionCard(
            JobBoxInventoryCatalog.sectionLabel(
              JobBoxInventoryCatalog.positiveChokesSection,
            ),
            _items
                .where((item) =>
                    item.section ==
                    JobBoxInventoryCatalog.positiveChokesSection)
                .toList(),
          ),
          _sectionCard(
            JobBoxInventoryCatalog.sectionLabel(
                JobBoxInventoryCatalog.customSection),
            _items
                .where((item) =>
                    item.section == JobBoxInventoryCatalog.customSection)
                .toList(),
          ),
        ],
      ),
    );
  }
}
