import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/job_setup.dart';
import '../services/job_storage_service.dart';
import '../services/recovery_state_service.dart';
import '../services/rig_up_inventory_service.dart';
import '../widgets/app_header.dart';

class RigUpInventoryScreen extends StatefulWidget {
  const RigUpInventoryScreen({super.key});

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

  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();
  final _inventoryService = RigUpInventoryService();
  final _notesController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  JobSetup? _activeJob;
  String _inventoryText = '';
  Map<String, int> _counts = <String, int>{};
  Map<String, Map<String, int>> _assignedByWell = <String, Map<String, int>>{};
  Map<String, Map<String, String>> _tankSplits =
      <String, Map<String, String>>{};

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

  @override
  void initState() {
    super.initState();
    _recoveryState.saveLastModule(RecoveryModules.rigUpInventory);
    _initializeScreen();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  List<String> get _wells {
    final activeJob = _activeJob;
    if (activeJob == null) return const <String>['Well 1'];
    final trimmed = activeJob.wells
        .map((well) => well.trim())
        .where((well) => well.isNotEmpty)
        .toList();
    if (trimmed.isNotEmpty) return trimmed;
    final primary = activeJob.primaryWell.trim();
    if (primary.isNotEmpty) return <String>[primary];
    return const <String>['Well 1'];
  }

  Future<void> _initializeScreen() async {
    final activeJob = await _jobStorage.loadActiveJob();
    final jobId = activeJob?.id ?? '';

    final counts = <String, int>{};
    for (final item in _allItems) {
      counts[item.key] = 0;
    }

    final saved = await _inventoryService.loadForJob(jobId);
    if (saved != null) {
      final rawCounts = Map<String, dynamic>.from(
        saved['counts'] as Map? ?? <String, dynamic>{},
      );
      for (final item in _allItems) {
        final value = rawCounts[item.key];
        if (value is int) {
          counts[item.key] = value;
        } else if (value is String) {
          counts[item.key] = int.tryParse(value) ?? 0;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _activeJob = activeJob;
      _counts = counts;
      _assignedByWell = _decodeAssignments(
        saved == null ? null : saved['assignedByWell'],
      );
      _tankSplits =
          _decodeTankSplits(saved == null ? null : saved['tankSplits']);
      _notesController.text =
          (saved == null ? '' : (saved['notes'] as String? ?? ''));
      _inventoryText =
          saved == null ? '' : (saved['inventoryText'] as String? ?? '');
      _loading = false;
      _reconcileToWells();
    });
  }

  Map<String, Map<String, int>> _decodeAssignments(dynamic raw) {
    final out = <String, Map<String, int>>{};
    if (raw is! Map) return out;
    for (final entry in raw.entries) {
      final itemKey = entry.key.toString();
      final next = <String, int>{};
      if (entry.value is Map) {
        for (final wellEntry in (entry.value as Map).entries) {
          final parsed = int.tryParse(wellEntry.value.toString()) ?? 0;
          if (parsed > 0) {
            next[wellEntry.key.toString()] = parsed;
          }
        }
      }
      out[itemKey] = next;
    }
    return out;
  }

  Map<String, Map<String, String>> _decodeTankSplits(dynamic raw) {
    final out = <String, Map<String, String>>{};
    if (raw is! Map) return out;
    for (final entry in raw.entries) {
      final itemKey = entry.key.toString();
      final next = <String, String>{};
      if (entry.value is Map) {
        for (final wellEntry in (entry.value as Map).entries) {
          final choice = wellEntry.value.toString();
          if (_fractionChoices.contains(choice) && choice.isNotEmpty) {
            next[wellEntry.key.toString()] = choice;
          }
        }
      }
      out[itemKey] = next;
    }
    return out;
  }

  void _reconcileToWells() {
    final wells = _wells;
    for (final item in _allItems) {
      final assigned = _assignedByWell[item.key] ?? <String, int>{};
      assigned.removeWhere((well, _) => !wells.contains(well));
      for (final well in wells) {
        assigned.putIfAbsent(well, () => 0);
      }
      _assignedByWell[item.key] = assigned;

      final splits = _tankSplits[item.key] ?? <String, String>{};
      splits.removeWhere((well, _) => !wells.contains(well));
      for (final well in wells) {
        splits.putIfAbsent(well, () => '');
      }
      _tankSplits[item.key] = splits;
    }
  }

  int _countFor(_InventoryItem item) => _counts[item.key] ?? 0;

  void _setCount(_InventoryItem item, int nextCount) {
    final clamped = nextCount < 0 ? 0 : nextCount;
    setState(() {
      _counts[item.key] = clamped;
      if (item.splittable) {
        if (clamped == 0) {
          _tankSplits[item.key] = {
            for (final well in _wells) well: '',
          };
        }
      } else {
        final assigned = _assignedByWell[item.key] ?? <String, int>{};
        final wells = _wells;
        var used = 0;
        for (final well in wells) {
          final current = assigned[well] ?? 0;
          if (used + current <= clamped) {
            used += current;
            continue;
          }
          final adjusted = (clamped - used).clamp(0, clamped);
          assigned[well] = adjusted;
          used += adjusted;
        }
        _assignedByWell[item.key] = assigned;
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
    final quantity = _countFor(item);
    if (quantity == 0) return;
    final current = _assignedByWell[item.key]?[well] ?? 0;
    if (delta > 0 && _remainingAssignable(item) <= 0) return;

    setState(() {
      final map = _assignedByWell[item.key] ?? <String, int>{};
      final next = (current + delta).clamp(0, quantity);
      map[well] = next;
      _assignedByWell[item.key] = map;
    });
  }

  void _assignOneToAllWells(_InventoryItem item) {
    final wells = _wells;
    if (wells.isEmpty) return;
    if (_countFor(item) < wells.length) return;

    setState(() {
      _assignedByWell[item.key] = {
        for (final well in wells) well: 1,
      };
    });
  }

  bool _showOneEachSuggestion(_InventoryItem item) {
    final wellCount = _wells.length;
    if (wellCount <= 1) return false;
    if (_countFor(item) != wellCount) return false;
    return _assignedTotal(item) == 0;
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

  int _allocatedUnits(_InventoryItem item) {
    final splits = _tankSplits[item.key] ?? const <String, String>{};
    var sum = 0;
    for (final value in splits.values) {
      sum += _fractionUnits(value);
    }
    return sum;
  }

  void _setWellFraction(_InventoryItem item, String well, String choice) {
    setState(() {
      final map = _tankSplits[item.key] ?? <String, String>{};
      map[well] = choice;
      _tankSplits[item.key] = map;
    });
  }

  void _applyEqualSplit(_InventoryItem item) {
    final wells = _wells;
    final count = wells.length;
    String option;
    switch (count) {
      case 2:
        option = '1/2';
        break;
      case 3:
        option = '1/3';
        break;
      case 4:
        option = '1/4';
        break;
      default:
        return;
    }

    setState(() {
      _tankSplits[item.key] = {
        for (final well in wells) well: option,
      };
    });
  }

  bool _canSuggestEqualSplit() {
    final count = _wells.length;
    return count == 2 || count == 3 || count == 4;
  }

  String _inventorySummaryText() {
    final activeJob = _activeJob;
    final nowText = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final company = activeJob?.company.trim().isNotEmpty == true
        ? activeJob!.company.trim()
        : 'Not entered';
    final pad = activeJob?.padName.trim().isNotEmpty == true
        ? activeJob!.padName.trim()
        : 'Not entered';
    final wells = _wells;

    final buffer = StringBuffer()
      ..writeln('RIG-UP INVENTORY')
      ..writeln('Company: $company')
      ..writeln('Job/Pad: $pad')
      ..writeln('Date: $nowText')
      ..writeln('Wells: ${wells.join(', ')}')
      ..writeln('')
      ..writeln('MASTER INVENTORY');

    for (final section in <String>['Equipment', 'Iron']) {
      final sectionItems = _allItems
          .where((item) => item.section == section)
          .where((item) => _countFor(item) > 0)
          .toList();
      if (sectionItems.isEmpty) continue;
      buffer.writeln('$section:');
      for (final item in sectionItems) {
        buffer.writeln('- ${item.group} / ${item.label}: ${_countFor(item)}');
      }
    }

    buffer
      ..writeln('')
      ..writeln('PER-WELL ASSIGNED INVENTORY');

    for (final well in wells) {
      buffer.writeln('$well:');
      var any = false;
      for (final item in _allItems.where((entry) => !entry.splittable)) {
        final value = _assignedByWell[item.key]?[well] ?? 0;
        if (value <= 0) continue;
        any = true;
        buffer.writeln('- ${item.label}: $value');
      }

      for (final item in _allItems.where((entry) => entry.splittable)) {
        final choice = _tankSplits[item.key]?[well] ?? '';
        if (choice.isEmpty) continue;
        any = true;
        buffer.writeln('- ${item.label}: $choice of ${_countFor(item)}');
      }

      if (!any) {
        buffer.writeln('- None assigned');
      }
    }

    final notes = _notesController.text.trim();
    if (notes.isNotEmpty) {
      buffer
        ..writeln('')
        ..writeln('NOTES')
        ..writeln(notes);
    }

    return buffer.toString().trim();
  }

  Future<void> _saveInventory() async {
    if (_saving) return;
    final activeJobId = _activeJob?.id ?? '';
    setState(() => _saving = true);

    try {
      final payload = <String, dynamic>{
        'activeJobId': activeJobId,
        'company': _activeJob?.company ?? '',
        'padName': _activeJob?.padName ?? '',
        'wells': _wells,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'counts': _counts,
        'assignedByWell': _assignedByWell,
        'tankSplits': _tankSplits,
        'notes': _notesController.text.trim(),
        'inventoryText': _inventoryText,
      };
      await _inventoryService.saveForJob(
          activeJobId: activeJobId, payload: payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rig-Up Inventory saved.')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _generateInventoryText() {
    final text = _inventorySummaryText();
    setState(() => _inventoryText = text);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Inventory text generated.')),
    );
  }

  Future<void> _copyText() async {
    if (_inventoryText.trim().isEmpty) {
      _generateInventoryText();
    }
    await Clipboard.setData(ClipboardData(text: _inventoryText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Inventory text copied.')),
    );
  }

  Future<void> _shareText() async {
    if (_inventoryText.trim().isEmpty) {
      _generateInventoryText();
    }
    await Share.share(
      _inventoryText,
      subject: 'Rig-Up Inventory',
    );
  }

  Widget _activeJobCard() {
    final activeJob = _activeJob;
    if (activeJob == null) {
      return const Card(
        margin: EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'No active job found. Inventory will save under a local draft until a job is active.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Active Job',
              style: TextStyle(color: _gold, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(activeJob.company.trim().isEmpty ? '-' : activeJob.company),
            const SizedBox(height: 4),
            Text(
                'Pad: ${activeJob.padName.trim().isEmpty ? '-' : activeJob.padName}'),
            const SizedBox(height: 4),
            Text('Wells: ${_wells.join(', ')}'),
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
              label: const Text('Assign 1 to All Wells'),
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
                    child: Text(
                      well,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<String>(
                      initialValue: _tankSplits[item.key]?[well] ?? '',
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: _fractionChoices
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value.isEmpty ? 'Select' : value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        _setWellFraction(item, well, value ?? '');
                      },
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
        children: [
          for (final item in items) _itemCard(item),
        ],
      ),
    );
  }

  Widget _inventoryTextCard() {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Generated Inventory Text',
              style: TextStyle(color: _gold, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _inventoryText.trim().isEmpty
                  ? 'Tap Generate Inventory Text to build summary.'
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
          _activeJobCard(),
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rig-Up Rules',
                    style: TextStyle(color: _gold, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Flow stays separate from wellhead to facilities. Per-well equipment must be assigned to one well or all wells. Only receiving/tank equipment can be split with fractions.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    minLines: 2,
                    maxLines: 4,
                    decoration:
                        const InputDecoration(labelText: 'Notes (optional)'),
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
            label: const Text('Save'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _generateInventoryText,
            icon: const Icon(Icons.description_outlined),
            label: const Text('Generate Inventory Text'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _copyText,
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('Copy Text'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _shareText,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share / Send'),
          ),
          _inventoryTextCard(),
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
