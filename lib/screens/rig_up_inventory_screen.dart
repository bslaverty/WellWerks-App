import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../services/recovery_state_service.dart';
import '../services/rig_up_inventory_service.dart';
import '../widgets/app_header.dart';

class RigUpInventoryScreen extends StatefulWidget {
  const RigUpInventoryScreen({
    super.key,
    this.initialRecordId,
  });

  final String? initialRecordId;

  @override
  State<RigUpInventoryScreen> createState() => _RigUpInventoryScreenState();
}

class _RigUpInventoryScreenState extends State<RigUpInventoryScreen> {
  static const Color _gold = Color(0xFFCDA56A);

  static const List<String> _fractionChoices = <String>[
    '',
    '1/4',
    '1/3',
    '1/2',
    '2/3',
    '3/4',
    'Full',
  ];

  static const List<_InventoryItem> _equipmentItems = <_InventoryItem>[
    _InventoryItem('esd2', 'ESD 2"',
        section: 'Equipment', group: 'Pressure Control'),
    _InventoryItem('esd3', 'ESD 3"',
        section: 'Equipment', group: 'Pressure Control'),
    _InventoryItem('chokeManifold2', 'Choke Manifold 2"',
        section: 'Equipment', group: 'Pressure Control'),
    _InventoryItem('chokeManifold3', 'Choke Manifold 3"',
        section: 'Equipment', group: 'Pressure Control'),
    _InventoryItem('singleBarrelPlugCatcher', 'Single Barrel Plug Catcher',
        section: 'Equipment', group: 'Pressure Control'),
    _InventoryItem('doubleBarrelPlugCatcher', 'Double Barrel Plug Catcher',
        section: 'Equipment', group: 'Pressure Control'),
    _InventoryItem('restraints', 'Restraints',
        section: 'Equipment', group: 'Pressure Control'),
    _InventoryItem('sphericalSeparator', 'Spherical Sand Separator',
        section: 'Equipment', group: 'Sand Separation'),
    _InventoryItem('cyclonicSeparator', 'Cyclonic Sand Separator',
        section: 'Equipment', group: 'Sand Separation'),
    _InventoryItem(
        'standardImpingementSeparator', 'Standard Impingement Sand Separator',
        section: 'Equipment', group: 'Sand Separation'),
    _InventoryItem('lineHeater', 'Line Heater',
        section: 'Equipment', group: 'Production'),
    _InventoryItem('testProductionUnit', 'Test Production Unit',
        section: 'Equipment', group: 'Production'),
    _InventoryItem('gasBusterFlowbackTank', 'Gas Buster Flowback Tank',
        section: 'Equipment', group: 'Production', splittable: true),
    _InventoryItem('flowbackTank', 'Flowback Tank',
        section: 'Equipment', group: 'Production', splittable: true),
    _InventoryItem('halfFlowbackTank', '1/2 Flowback Tank',
        section: 'Equipment', group: 'Production', splittable: true),
    _InventoryItem('quarterFlowbackTank', '1/4 Flowback Tank',
        section: 'Equipment', group: 'Production', splittable: true),
    _InventoryItem('sandX', 'SandX',
        section: 'Equipment', group: 'Production', splittable: true),
    _InventoryItem('superLoop', 'Super Loop',
        section: 'Equipment', group: 'Production', splittable: true),
    _InventoryItem('fs3Tank', 'FS3 Tank',
        section: 'Equipment', group: 'Production', splittable: true),
  ];

  static const List<_InventoryItem> _ironItems = <_InventoryItem>[
    _InventoryItem('iron2Footage', 'Footage',
        section: 'Iron', group: '2" Iron'),
    _InventoryItem('iron290', '90°', section: 'Iron', group: '2" Iron'),
    _InventoryItem('iron2Tee', 'Tee', section: 'Iron', group: '2" Iron'),
    _InventoryItem('iron2PlugValve', 'Plug Valve',
        section: 'Iron', group: '2" Iron'),
    _InventoryItem('iron2ChokeAssembly', 'Choke Assembly',
        section: 'Iron', group: '2" Iron'),
    _InventoryItem('iron2ChokeBonnet', 'Choke Bonnet',
        section: 'Iron', group: '2" Iron'),
    _InventoryItem('iron2ChokeTee', 'Choke Tee',
        section: 'Iron', group: '2" Iron'),
    _InventoryItem('iron3Footage', 'Footage',
        section: 'Iron', group: '3" Iron'),
    _InventoryItem('iron390', '90°', section: 'Iron', group: '3" Iron'),
    _InventoryItem('iron3Tee', 'Tee', section: 'Iron', group: '3" Iron'),
    _InventoryItem('iron3PlugValve', 'Plug Valve',
        section: 'Iron', group: '3" Iron'),
    _InventoryItem('iron3ChokeAssembly', 'Choke Assembly',
        section: 'Iron', group: '3" Iron'),
    _InventoryItem('iron3ChokeBonnet', 'Choke Bonnet',
        section: 'Iron', group: '3" Iron'),
    _InventoryItem('iron3ChokeTee', 'Choke Tee',
        section: 'Iron', group: '3" Iron'),
    _InventoryItem('iron4Footage', 'Footage',
        section: 'Iron', group: '4" Iron'),
    _InventoryItem('iron490', '90°', section: 'Iron', group: '4" Iron'),
    _InventoryItem('iron4Tee', 'Tee', section: 'Iron', group: '4" Iron'),
  ];

  static final List<_InventoryItem> _allItems = <_InventoryItem>[
    ..._equipmentItems,
    ..._ironItems
  ];

  final _recoveryState = RecoveryStateService();
  final _inventoryService = RigUpInventoryService();

  final _companyController = TextEditingController();
  final _customerController = TextEditingController();
  final _jobPadController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  final _newWellController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  DateTime _date = DateTime.now();
  String _recordId = '';
  String _inventoryText = '';

  final List<String> _wells = <String>['Well 1'];
  Map<String, int> _counts = <String, int>{};
  Map<String, Map<String, int>> _assignedByWell = <String, Map<String, int>>{};
  Map<String, Map<String, String>> _tankSplits =
      <String, Map<String, String>>{};

  @override
  void initState() {
    super.initState();
    _recoveryState.saveLastModule(RecoveryModules.rigUpInventory);
    _initialize();
  }

  @override
  void dispose() {
    _companyController.dispose();
    _customerController.dispose();
    _jobPadController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _newWellController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final counts = <String, int>{};
    for (final item in _allItems) {
      counts[item.key] = 0;
    }

    final initialId = widget.initialRecordId?.trim() ?? '';
    final record = initialId.isEmpty
        ? null
        : await _inventoryService.loadRecord(initialId);

    if (!mounted) return;

    setState(() {
      _counts = counts;
      _recordId = initialId;

      if (record != null) {
        _companyController.text = record['company']?.toString() ?? '';
        _customerController.text = record['customer']?.toString() ?? '';
        _jobPadController.text = record['jobPad']?.toString() ?? '';
        _locationController.text = record['location']?.toString() ?? '';
        _notesController.text = record['notes']?.toString() ?? '';
        _inventoryText = record['inventoryText']?.toString() ?? '';

        final rawDate = record['date']?.toString() ?? '';
        _date = DateTime.tryParse(rawDate) ?? DateTime.now();

        final rawWells =
            List<String>.from(record['wells'] as List? ?? const []);
        _wells
          ..clear()
          ..addAll(rawWells
              .map((well) => well.trim())
              .where((well) => well.isNotEmpty));
        if (_wells.isEmpty) _wells.add('Well 1');

        final rawCounts = Map<String, dynamic>.from(
            record['counts'] as Map? ?? <String, dynamic>{});
        for (final item in _allItems) {
          final value = rawCounts[item.key];
          if (value is int) {
            _counts[item.key] = value;
          } else if (value is String) {
            _counts[item.key] = int.tryParse(value) ?? 0;
          }
        }

        _assignedByWell = _decodeAssignments(record['assignedByWell']);
        _tankSplits = _decodeTankSplits(record['tankSplits']);
      }

      _reconcileToWells();
      _loading = false;
    });
  }

  Map<String, Map<String, int>> _decodeAssignments(dynamic raw) {
    final out = <String, Map<String, int>>{};
    if (raw is! Map) return out;

    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final itemMap = <String, int>{};
      if (entry.value is Map) {
        for (final wellEntry in (entry.value as Map).entries) {
          itemMap[wellEntry.key.toString()] =
              int.tryParse(wellEntry.value.toString()) ?? 0;
        }
      }
      out[key] = itemMap;
    }
    return out;
  }

  Map<String, Map<String, String>> _decodeTankSplits(dynamic raw) {
    final out = <String, Map<String, String>>{};
    if (raw is! Map) return out;

    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final itemMap = <String, String>{};
      if (entry.value is Map) {
        for (final wellEntry in (entry.value as Map).entries) {
          final value = wellEntry.value.toString();
          if (_fractionChoices.contains(value)) {
            itemMap[wellEntry.key.toString()] = value;
          }
        }
      }
      out[key] = itemMap;
    }
    return out;
  }

  void _reconcileToWells() {
    for (final item in _allItems) {
      final assigned = _assignedByWell[item.key] ?? <String, int>{};
      assigned.removeWhere((well, _) => !_wells.contains(well));
      for (final well in _wells) {
        assigned.putIfAbsent(well, () => 0);
      }
      _assignedByWell[item.key] = assigned;

      final splits = _tankSplits[item.key] ?? <String, String>{};
      splits.removeWhere((well, _) => !_wells.contains(well));
      for (final well in _wells) {
        splits.putIfAbsent(well, () => '');
      }
      _tankSplits[item.key] = splits;
    }
  }

  int _countFor(_InventoryItem item) => _counts[item.key] ?? 0;

  void _setCount(_InventoryItem item, int next) {
    final clamped = next < 0 ? 0 : next;
    setState(() {
      _counts[item.key] = clamped;
      if (item.splittable && clamped == 0) {
        _tankSplits[item.key] = {for (final well in _wells) well: ''};
      }
    });
  }

  int _assignedTotal(_InventoryItem item) {
    final map = _assignedByWell[item.key] ?? const <String, int>{};
    var total = 0;
    for (final value in map.values) {
      total += value;
    }
    return total;
  }

  int _remainingAssignable(_InventoryItem item) {
    return (_countFor(item) - _assignedTotal(item)).clamp(0, 999999);
  }

  void _assignToWell(_InventoryItem item, String well, int delta) {
    if (_countFor(item) == 0) return;
    if (delta > 0 && _remainingAssignable(item) <= 0) return;

    setState(() {
      final map = _assignedByWell[item.key] ?? <String, int>{};
      final current = map[well] ?? 0;
      map[well] = (current + delta).clamp(0, _countFor(item));
      _assignedByWell[item.key] = map;
    });
  }

  void _assignOneToAllWells(_InventoryItem item) {
    if (_wells.isEmpty) return;
    if (_countFor(item) < _wells.length) return;

    setState(() {
      _assignedByWell[item.key] = {for (final well in _wells) well: 1};
    });
  }

  bool _showOneEachSuggestion(_InventoryItem item) {
    return _wells.length > 1 &&
        _countFor(item) == _wells.length &&
        _assignedTotal(item) == 0;
  }

  int _fractionUnits(String value) {
    switch (value) {
      case '1/4':
        return 3;
      case '1/3':
        return 4;
      case '1/2':
        return 6;
      case '2/3':
        return 8;
      case '3/4':
        return 9;
      case 'Full':
        return 12;
      default:
        return 0;
    }
  }

  String _unitsToFractionLabel(int units) {
    if (units == 0) return '0';
    if (units == 12) return 'Full';

    int gcd(int a, int b) {
      var x = a.abs();
      var y = b.abs();
      while (y != 0) {
        final t = x % y;
        x = y;
        y = t;
      }
      return x == 0 ? 1 : x;
    }

    final d = gcd(units, 12);
    return '${units ~/ d}/${12 ~/ d}';
  }

  String _twelfthsToDisplay(int units) {
    if (units <= 0) return '0';
    final whole = units ~/ 12;
    final remainder = units % 12;
    if (remainder == 0) return '$whole';
    final fraction = _unitsToFractionLabel(remainder);
    return whole == 0 ? fraction : '$whole $fraction';
  }

  int _parseDisplayToTwelfths(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '0') return 0;

    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return (int.tryParse(trimmed) ?? 0) * 12;
    }

    if (RegExp(r'^\d+\s+\d+/\d+$').hasMatch(trimmed)) {
      final parts = trimmed.split(RegExp(r'\s+'));
      final whole = int.tryParse(parts[0]) ?? 0;
      final fracParts = parts[1].split('/');
      final n = int.tryParse(fracParts.first) ?? 0;
      final d = fracParts.length > 1 ? (int.tryParse(fracParts[1]) ?? 1) : 1;
      return (whole * 12) + ((n * 12) ~/ d);
    }

    if (RegExp(r'^\d+/\d+$').hasMatch(trimmed)) {
      final parts = trimmed.split('/');
      final n = int.tryParse(parts.first) ?? 0;
      final d = parts.length > 1 ? (int.tryParse(parts[1]) ?? 1) : 1;
      return (n * 12) ~/ d;
    }

    return 0;
  }

  int _allocatedUnits(_InventoryItem item) {
    final map = _tankSplits[item.key] ?? const <String, String>{};
    var units = 0;
    for (final split in map.values) {
      units += _fractionUnits(split);
    }
    return units;
  }

  void _setWellSplit(_InventoryItem item, String well, String value) {
    setState(() {
      final map = _tankSplits[item.key] ?? <String, String>{};
      map[well] = value;
      _tankSplits[item.key] = map;
    });
  }

  void _applyEqualSplit(_InventoryItem item) {
    String split;
    switch (_wells.length) {
      case 2:
        split = '1/2';
        break;
      case 3:
        split = '1/3';
        break;
      case 4:
        split = '1/4';
        break;
      default:
        return;
    }

    setState(() {
      _tankSplits[item.key] = {for (final well in _wells) well: split};
    });
  }

  bool _canSuggestEqualSplit() {
    return _wells.length == 2 || _wells.length == 3 || _wells.length == 4;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  void _addWell() {
    final name = _newWellController.text.trim();
    if (name.isEmpty) return;
    if (_wells.contains(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That well is already listed.')),
      );
      return;
    }

    setState(() {
      _wells.add(name);
      _newWellController.clear();
      _reconcileToWells();
    });
  }

  void _removeWell(String name) {
    if (_wells.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one well is required.')),
      );
      return;
    }

    setState(() {
      _wells.remove(name);
      _reconcileToWells();
    });
  }

  bool _validateHeader() {
    if (_companyController.text.trim().isEmpty ||
        _jobPadController.text.trim().isEmpty ||
        _wells.where((well) => well.trim().isNotEmpty).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter Company, Job/Pad, and at least one Well.'),
        ),
      );
      return false;
    }
    return true;
  }

  String _buildInventoryText() {
    final company = _companyController.text.trim();
    final jobPad = _jobPadController.text.trim();
    final dateText = DateFormat('yyyy-MM-dd').format(_date);

    final perWellLines = <String>[];
    final padTotals = <String, String>{};

    for (final well in _wells) {
      final entries = <String>[];

      for (final item in _allItems.where((x) => !x.splittable)) {
        final value = _assignedByWell[item.key]?[well] ?? 0;
        if (value <= 0) continue;
        entries.add('- ${item.label}: $value');
        final current = int.tryParse(padTotals[item.label] ?? '0') ?? 0;
        padTotals[item.label] = '${current + value}';
      }

      for (final item in _allItems.where((x) => x.splittable)) {
        final split = _tankSplits[item.key]?[well] ?? '';
        if (split.isEmpty) continue;
        entries.add('- ${item.label}: $split of ${_countFor(item)}');
        final units = _fractionUnits(split) * _countFor(item);
        final currentUnits =
            _parseDisplayToTwelfths(padTotals[item.label] ?? '0');
        padTotals[item.label] = _twelfthsToDisplay(currentUnits + units);
      }

      perWellLines.add(well);
      if (entries.isEmpty) {
        perWellLines.add('- None assigned');
      } else {
        perWellLines.addAll(entries);
      }
      perWellLines.add('');
    }

    final padLines = padTotals.entries
        .where((entry) => entry.value != '0')
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final buffer = StringBuffer()
      ..writeln('RIG-UP INVENTORY')
      ..writeln('')
      ..writeln('Company: ${company.isEmpty ? '-' : company}')
      ..writeln('Job/Pad: ${jobPad.isEmpty ? '-' : jobPad}')
      ..writeln('Date: $dateText')
      ..writeln('')
      ..writeln('PER-WELL INVENTORY')
      ..writeln('');

    for (final line in perWellLines) {
      buffer.writeln(line);
    }

    buffer.writeln('PAD INVENTORY');
    if (padLines.isEmpty) {
      buffer.writeln('- None assigned');
    } else {
      for (final line in padLines) {
        buffer.writeln('- ${line.key}: ${line.value}');
      }
    }

    final notes = _notesController.text.trim();
    if (notes.isNotEmpty) {
      buffer
        ..writeln('')
        ..writeln('Notes: $notes');
    }

    return buffer.toString().trim();
  }

  Future<void> _saveInventory() async {
    if (_saving || !_validateHeader()) return;
    setState(() => _saving = true);

    try {
      final text = _buildInventoryText();
      final payload = <String, dynamic>{
        'company': _companyController.text.trim(),
        'customer': _customerController.text.trim(),
        'jobPad': _jobPadController.text.trim(),
        'location': _locationController.text.trim(),
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'wells': _wells,
        'counts': _counts,
        'assignedByWell': _assignedByWell,
        'tankSplits': _tankSplits,
        'notes': _notesController.text.trim(),
        'inventoryText': text,
      };

      final id = await _inventoryService.saveRecord(
        recordId: _recordId.isEmpty ? null : _recordId,
        payload: payload,
      );

      if (!mounted) return;
      setState(() {
        _recordId = id;
        _inventoryText = text;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rig-Up Inventory saved.')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _previewInventory() {
    if (!_validateHeader()) return;
    setState(() {
      _inventoryText = _buildInventoryText();
    });
  }

  Future<void> _shareSend() async {
    if (!_validateHeader()) return;
    final text = _buildInventoryText();
    setState(() => _inventoryText = text);
    await Share.share(text, subject: 'Rig-Up Inventory');
  }

  Widget _recordHeaderCard() {
    final dateText = DateFormat('MM/dd/yyyy').format(_date);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rig-Up Record',
              style: TextStyle(color: _gold, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _companyController,
              decoration: const InputDecoration(labelText: 'Company'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _customerController,
              decoration: const InputDecoration(labelText: 'Customer'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _jobPadController,
              decoration: const InputDecoration(labelText: 'Job / Pad'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('Date: $dateText'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Wells',
              style: TextStyle(color: _gold, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final well in _wells)
                  InputChip(
                    label: Text(well),
                    onDeleted: () => _removeWell(well),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newWellController,
                    decoration:
                        const InputDecoration(labelText: 'Add Well Name'),
                    onSubmitted: (_) => _addWell(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _addWell, child: const Text('Add')),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quantityStepper(_InventoryItem item) {
    final value = _countFor(item);
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: () => _setCount(item, value - 1),
          icon: const Icon(Icons.remove),
          tooltip: 'Decrease ${item.label}',
        ),
        const SizedBox(width: 10),
        Container(
          constraints: const BoxConstraints(minWidth: 64),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF4A4A4A)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filled(
          onPressed: () => _setCount(item, value + 1),
          icon: const Icon(Icons.add),
          tooltip: 'Increase ${item.label}',
        ),
      ],
    );
  }

  Widget _dedicatedAssignmentEditor(_InventoryItem item) {
    final quantity = _countFor(item);
    if (quantity <= 0) return const SizedBox.shrink();
    final remaining = _remainingAssignable(item);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF333333)),
        color: const Color(0xFF13161A),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assigned: ${_assignedTotal(item)}  |  Remaining: $remaining',
            style: const TextStyle(color: Colors.white70),
          ),
          if (_showOneEachSuggestion(item)) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF17130E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _gold.withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assign one to every well?',
                    style: TextStyle(color: _gold, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () => _assignOneToAllWells(item),
                        child: const Text('Yes'),
                      ),
                      OutlinedButton(
                        onPressed: () {},
                        child: const Text('Assign Manually'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (_wells.length > 1) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: quantity >= _wells.length
                  ? () => _assignOneToAllWells(item)
                  : null,
              icon: const Icon(Icons.done_all),
              label: const Text('Assign to All Wells'),
            ),
          ],
          const SizedBox(height: 8),
          for (final well in _wells)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      well,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _assignToWell(item, well, -1),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Container(
                    width: 42,
                    alignment: Alignment.center,
                    child: Text(
                      '${_assignedByWell[item.key]?[well] ?? 0}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _assignToWell(item, well, 1),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _splitAssignmentEditor(_InventoryItem item) {
    final quantity = _countFor(item);
    if (quantity <= 0) return const SizedBox.shrink();

    final allocated = _allocatedUnits(item);
    final remaining = 12 - allocated;
    final complete = allocated == 12;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF333333)),
        color: const Color(0xFF13161A),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Allocated: ${_unitsToFractionLabel(allocated.clamp(0, 12))}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              Expanded(
                child: Text(
                  'Remaining: ${_unitsToFractionLabel(remaining.abs())}${remaining < 0 ? ' over' : ''}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: remaining < 0 ? Colors.redAccent : Colors.white70,
                    fontWeight:
                        remaining < 0 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            complete
                ? 'Split complete.'
                : 'Fractions must total Full before complete.',
            style: TextStyle(
              color: complete ? _gold : Colors.orangeAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_canSuggestEqualSplit()) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _applyEqualSplit(item),
              icon: const Icon(Icons.auto_fix_high),
              label: Text('Use Equal Split (${_wells.length} wells)'),
            ),
          ],
          const SizedBox(height: 8),
          for (final well in _wells)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(well,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<String>(
                      initialValue: _tankSplits[item.key]?[well] ?? '',
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: _fractionChoices
                          .map((value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value.isEmpty ? 'Select' : value),
                              ))
                          .toList(),
                      onChanged: (value) =>
                          _setWellSplit(item, well, value ?? ''),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemCard(_InventoryItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.label,
              style: const TextStyle(
                color: _gold,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            _quantityStepper(item),
            item.splittable
                ? _splitAssignmentEditor(item)
                : _dedicatedAssignmentEditor(item),
          ],
        ),
      ),
    );
  }

  Widget _groupSection(String title, List<_InventoryItem> items) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          title,
          style: const TextStyle(color: _gold, fontWeight: FontWeight.w800),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [for (final item in items) _itemCard(item)],
      ),
    );
  }

  Widget _previewCard() {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Preview Inventory',
              style: TextStyle(color: _gold, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _inventoryText.trim().isEmpty
                  ? 'Tap Preview Inventory to generate the latest text.'
                  : _inventoryText,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Rig-Up Inventory', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final equipmentGroups = <String, List<_InventoryItem>>{
      'Pressure Control': _equipmentItems
          .where((item) => item.group == 'Pressure Control')
          .toList(),
      'Sand Separation': _equipmentItems
          .where((item) => item.group == 'Sand Separation')
          .toList(),
      'Production':
          _equipmentItems.where((item) => item.group == 'Production').toList(),
    };

    final ironGroups = <String, List<_InventoryItem>>{
      '2" Iron': _ironItems.where((item) => item.group == '2" Iron').toList(),
      '3" Iron': _ironItems.where((item) => item.group == '3" Iron').toList(),
      '4" Iron': _ironItems.where((item) => item.group == '4" Iron').toList(),
    };

    return Scaffold(
      appBar: const AppHeader(title: 'Rig-Up Inventory', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _recordHeaderCard(),
          const Card(
            margin: EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rig-Up Rules',
                    style: TextStyle(color: _gold, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Flow stays separate from wellhead to facilities. Dedicated equipment is assigned by well and never split. Only tank/receiving equipment can be split using fractions.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: const Text(
                'Equipment',
                style: TextStyle(color: _gold, fontWeight: FontWeight.w800),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                for (final group in equipmentGroups.entries)
                  _groupSection(group.key, group.value),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: const Text(
                'Iron',
                style: TextStyle(color: _gold, fontWeight: FontWeight.w800),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                for (final group in ironGroups.entries)
                  _groupSection(group.key, group.value),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _saveInventory,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save Inventory'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _previewInventory,
            icon: const Icon(Icons.description_outlined),
            label: const Text('Preview Inventory'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _shareSend,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share / Send'),
          ),
          _previewCard(),
        ],
      ),
    );
  }
}

class _InventoryItem {
  const _InventoryItem(
    this.key,
    this.label, {
    required this.section,
    required this.group,
    this.splittable = false,
  });

  final String key;
  final String label;
  final String section;
  final String group;
  final bool splittable;
}
