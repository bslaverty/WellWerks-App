import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import '../models/job_box_inventory.dart';
import '../models/job_setup.dart';
import '../services/active_company_service.dart';
import '../services/job_storage_service.dart';
import '../services/job_profile_defaults_service.dart';
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
  final _jobStorage = JobStorageService();
  final _activeCompanyService = ActiveCompanyService.instance;
  final _customerController = TextEditingController();
  final _dateController = TextEditingController();
  final _wellNamesController = TextEditingController();
  final _jobBoxNumberController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _hideZeroQuantityItems = false;
  String _recordId = '';
  JobSetup? _activeJob;
  DateTime _createdAt = DateTime.now();
  DateTime _updatedAt = DateTime.now();
  List<JobBoxInventoryItem> _items = [
    for (final item in JobBoxInventoryCatalog.defaultItems)
      item.copyWith(quantity: 0),
  ];

  @override
  void initState() {
    super.initState();
    _activeCompanyService.activeCompany
        .addListener(_handleActiveCompanyChanged);
    _jobStorage.activeJobListenable.addListener(_handleActiveJobChanged);
    _load();
  }

  void _handleActiveCompanyChanged() {
    if (!mounted) return;
    _load();
  }

  void _handleActiveJobChanged() {
    if (!mounted) return;
    _load();
  }

  @override
  void dispose() {
    _activeCompanyService.activeCompany
        .removeListener(_handleActiveCompanyChanged);
    _jobStorage.activeJobListenable.removeListener(_handleActiveJobChanged);
    _customerController.dispose();
    _dateController.dispose();
    _wellNamesController.dispose();
    _jobBoxNumberController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    JobBoxInventoryRecord? record;
    final initialId = widget.initialRecordId?.trim() ?? '';
    final hideZeroPreference = await _service.loadHideZeroPreference();
    final activeCompany = await _activeCompanyService.ensureLoaded();
    final activeJob = await _jobStorage.ensureActiveJobLoaded();
    if (initialId.isNotEmpty) {
      record = await _service.loadRecord(initialId);
    }
    record ??= await _service.loadWorkingDraft();
    record ??= JobBoxInventoryRecord.createDefault().copyWith(
      hideZeroQuantityItems: hideZeroPreference,
    );

    if (!mounted) return;
    final normalizedCustomer =
        _activeCompanyService.normalize(record.customer.trim());
    final selectedCompany =
        (normalizedCustomer == JobProfileDefaultsService.companyNone &&
                activeCompany.trim().isNotEmpty)
            ? activeCompany
            : normalizedCustomer;
    setState(() {
      _recordId = record!.id;
      _createdAt = record.createdAt;
      _updatedAt = record.updatedAt;
      _customerController.text =
          selectedCompany == JobProfileDefaultsService.companyNone
              ? ''
              : selectedCompany;
      _activeJob = activeJob;
      _dateController.text = record.date;
      _wellNamesController.text = initialId.isNotEmpty
          ? record.wellNames
          : _activeWellNamesLabel(activeJob, fallback: record.wellNames);
      _jobBoxNumberController.text = record.jobBoxNumber;
      _hideZeroQuantityItems = record.hideZeroQuantityItems;
      _items = record.items.isEmpty
          ? [
              for (final item in JobBoxInventoryCatalog.defaultItems)
                item.copyWith(quantity: 0),
            ]
          : _mergeWithDefaultItems(record.items);
      _loading = false;
    });
    await _persistWorkingDraft();
  }

  String get _selectedCompany {
    final normalized =
        _activeCompanyService.normalize(_customerController.text);
    return normalized;
  }

  String _activeWellNamesLabel(JobSetup? activeJob, {String fallback = ''}) {
    final fromJob = (activeJob?.resolvedWellNames ?? const <String>[])
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (fromJob.isNotEmpty) {
      return fromJob.join(', ');
    }
    return fallback.trim();
  }

  List<JobBoxInventoryItem> _mergeWithDefaultItems(
      List<JobBoxInventoryItem> savedItems) {
    final savedByKey = {
      for (final item in savedItems) item.key: item,
    };
    final defaults = [
      for (final item in JobBoxInventoryCatalog.defaultItems)
        (savedByKey[item.key] ?? item).copyWith(
          section: item.section,
          isDefault: true,
          canDelete: false,
        ),
    ];
    final defaultKeys = {
      for (final item in JobBoxInventoryCatalog.defaultItems) item.key,
    };
    final custom = savedItems
        .where((item) => !defaultKeys.contains(item.key))
        .map((item) => item.copyWith(canDelete: true))
        .toList();
    return [...defaults, ...custom];
  }

  JobBoxInventoryRecord _buildRecord({String? id}) {
    return JobBoxInventoryRecord(
      id: id ?? _recordId,
      customer: _customerController.text.trim(),
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

  String _inventoryUpdateText() {
    final customerLabel =
        _selectedCompany == JobProfileDefaultsService.companyNone
            ? '-'
            : (_customerController.text.trim().isEmpty
                ? '-'
                : _customerController.text.trim());
    final buffer = StringBuffer()
      ..writeln('Job Box Inventory')
      ..writeln()
      ..writeln('Customer: $customerLabel')
      ..writeln('Date: ${_formatGpsDate()}')
      ..writeln(
          'Well(s): ${_activeWellNamesLabel(_activeJob, fallback: _wellNamesController.text).isEmpty ? '-' : _activeWellNamesLabel(_activeJob, fallback: _wellNamesController.text)}')
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

    return buffer.toString().trimRight();
  }

  Future<void> _previewInventoryUpdate() async {
    final text = _inventoryUpdateText();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preview Text'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(text),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyInventoryUpdate() async {
    final text = _inventoryUpdateText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Inventory update copied to clipboard.')),
    );
  }

  Widget _sectionCard(String title, List<JobBoxInventoryItem> items) {
    final hideZeros = _hideZeroQuantityItems &&
        title !=
            JobBoxInventoryCatalog.sectionLabel(
                JobBoxInventoryCatalog.positiveChokesSection);
    if (items.isEmpty && hideZeros) return const SizedBox.shrink();
    final visible =
        hideZeros ? items.where((item) => item.quantity > 0).toList() : items;
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
          _quantityStepButton(
            symbol: '−',
            enabled: item.quantity > 0,
            onPressed: () => _updateItemQuantity(item.key, -1),
            accent: accent,
          ),
          const SizedBox(width: 8),
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
          const SizedBox(width: 8),
          _quantityStepButton(
            symbol: '+',
            enabled: true,
            onPressed: () => _updateItemQuantity(item.key, 1),
            accent: accent,
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

  Widget _quantityStepButton({
    required String symbol,
    required bool enabled,
    required VoidCallback onPressed,
    required Color accent,
  }) {
    return SizedBox(
      width: 56,
      height: 56,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: accent.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.black.withValues(alpha: 0.7),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          symbol,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
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
              controller: _customerController,
              readOnly: true,
              enableInteractiveSelection: false,
              decoration: const InputDecoration(labelText: 'Customer'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wellNamesController,
              readOnly: true,
              enableInteractiveSelection: false,
              decoration: const InputDecoration(
                labelText: 'Well Name(s)',
                helperText: 'Synced from Start Job / Edit Active Job',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _jobBoxNumberController,
              decoration: const InputDecoration(labelText: 'Job Box Number'),
              onChanged: (_) => _setHeaderChanged(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dateController,
              decoration: const InputDecoration(labelText: 'Date'),
              keyboardType: TextInputType.datetime,
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
          child: OutlinedButton.icon(
            onPressed: _previewInventoryUpdate,
            icon: const Icon(Icons.preview_outlined),
            label: const Text('Preview Text'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _copyInventoryUpdate,
            icon: const Icon(Icons.copy),
            label: const Text('Copy Text'),
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
          onChanged: (value) async {
            setState(() => _hideZeroQuantityItems = value);
            await _service.saveHideZeroPreference(value);
            await _persistWorkingDraft();
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
