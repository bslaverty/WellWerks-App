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
  final _jobStorage = JobStorageService();

  final _customerController = TextEditingController();
  final _padController = TextEditingController();
  final _notesController = TextEditingController();
  final _newWellController = TextEditingController();
  final _newWellFocusNode = FocusNode();

  bool _loading = true;
  bool _saving = false;
  DateTime _date = DateTime.now();
  String _recordId = '';
  String _inventoryText = '';
  JobSetup? _activeJob;

  final List<String> _wells = <String>[];
  Map<String, int> _counts = <String, int>{};
  Map<String, Map<String, int>> _assignedByWell = <String, Map<String, int>>{};
  Map<String, Map<String, String>> _tankSplits =
      <String, Map<String, String>>{};
  Map<String, Map<String, List<String>>> _assetNumbersByWell =
      <String, Map<String, List<String>>>{};
  Map<String, bool> _assignByWellEnabled = <String, bool>{};
  Map<String, bool> _splitByWellEnabled = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _recoveryState.saveLastModule(RecoveryModules.rigUpInventory);
    _jobStorage.activeJobListenable.addListener(_handleActiveJobChanged);
    _initialize();
  }

  void _handleActiveJobChanged() {
    if (!mounted) return;
    _initialize();
  }

  @override
  void dispose() {
    _jobStorage.activeJobListenable.removeListener(_handleActiveJobChanged);
    _customerController.dispose();
    _padController.dispose();
    _notesController.dispose();
    _newWellController.dispose();
    _newWellFocusNode.dispose();
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
    final activeJob = await _jobStorage.ensureActiveJobLoaded();

    if (!mounted) return;

    setState(() {
      _counts = counts;
      _recordId = initialId;
      _activeJob = activeJob;
      _assignByWellEnabled = {
        for (final item in _allItems.where((item) => !item.splittable))
          item.key: false,
      };
      _splitByWellEnabled = {
        for (final item in _allItems.where((item) => item.splittable))
          item.key: false,
      };

      if (record != null) {
        _customerController.text = record['customer']?.toString() ?? '';
        _padController.text =
            (record['pad']?.toString() ?? record['jobPad']?.toString() ?? '');
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
        _assetNumbersByWell = _decodeAssetNumbers(record['assetNumbersByWell']);
        _assignByWellEnabled = _decodeToggleMap(
          record['assignByWellEnabled'],
          keys: _allItems
              .where((item) => !item.splittable)
              .map((item) => item.key),
        );
        _splitByWellEnabled = _decodeToggleMap(
          record['splitByWellEnabled'],
          keys: _allItems
              .where((item) => item.splittable)
              .map((item) => item.key),
        );
      } else {
        final contextWells = (activeJob?.resolvedWellNames ?? const <String>[])
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        if (contextWells.isNotEmpty) {
          _wells
            ..clear()
            ..addAll(contextWells);
        }
        if (activeJob != null) {
          if (_padController.text.trim().isEmpty) {
            _padController.text = activeJob.padName.trim();
          }
          if (_customerController.text.trim().isEmpty) {
            _customerController.text = activeJob.company.trim();
          }
        }
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

  Map<String, bool> _decodeToggleMap(
    dynamic raw, {
    required Iterable<String> keys,
  }) {
    final out = <String, bool>{for (final key in keys) key: false};
    if (raw is! Map) return out;

    for (final entry in raw.entries) {
      final key = entry.key.toString();
      if (!out.containsKey(key)) continue;
      final value = entry.value;
      if (value is bool) {
        out[key] = value;
      } else if (value is num) {
        out[key] = value != 0;
      } else if (value is String) {
        final normalized = value.trim().toLowerCase();
        out[key] = normalized == 'true' || normalized == '1';
      }
    }
    return out;
  }

  Map<String, Map<String, List<String>>> _decodeAssetNumbers(dynamic raw) {
    final out = <String, Map<String, List<String>>>{};
    if (raw is! Map) return out;

    for (final itemEntry in raw.entries) {
      final itemKey = itemEntry.key.toString();
      final wellMap = <String, List<String>>{};
      if (itemEntry.value is Map) {
        for (final wellEntry in (itemEntry.value as Map).entries) {
          final well = wellEntry.key.toString();
          final value = wellEntry.value;
          if (value is List) {
            wellMap[well] = value
                .map((it) => it.toString())
                .map((it) => it.trim())
                .toList();
          }
        }
      }
      out[itemKey] = wellMap;
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

      final assetMap =
          _assetNumbersByWell[item.key] ?? <String, List<String>>{};
      assetMap.removeWhere((well, _) => !_wells.contains(well));
      for (final well in _wells) {
        assetMap.putIfAbsent(well, () => <String>[]);
      }
      _assetNumbersByWell[item.key] = assetMap;

      if (item.splittable) {
        _splitByWellEnabled.putIfAbsent(item.key, () => false);
      } else {
        _assignByWellEnabled.putIfAbsent(item.key, () => false);
      }

      for (final well in _wells) {
        _syncAssetCapacityForWell(item, well);
      }
    }
  }

  int _targetAssetCapacity(_InventoryItem item, String well) {
    if (item.splittable) {
      final splitByWell = _splitByWellEnabled[item.key] ?? false;
      if (!splitByWell) return 0;
      final split = _tankSplits[item.key]?[well] ?? '';
      return split.isEmpty ? 0 : 1;
    }
    final assignByWell = _assignByWellEnabled[item.key] ?? false;
    if (assignByWell) {
      return _assignedByWell[item.key]?[well] ?? 0;
    }
    return _countFor(item);
  }

  void _syncAssetCapacityForWell(_InventoryItem item, String well) {
    final perItem = _assetNumbersByWell[item.key] ?? <String, List<String>>{};
    final existing = List<String>.from(perItem[well] ?? const <String>[]);
    final target = _targetAssetCapacity(item, well);
    if (existing.length < target) {
      existing.addAll(List<String>.filled(target - existing.length, ''));
    } else if (existing.length > target) {
      existing.removeRange(target, existing.length);
    }
    perItem[well] = existing;
    _assetNumbersByWell[item.key] = perItem;
  }

  bool _hasAssetDataPast(_InventoryItem item, int nextCount) {
    if (nextCount >= _countFor(item)) return false;
    if (item.splittable) {
      return false;
    }
    final assignByWell = _assignByWellEnabled[item.key] ?? false;
    if (assignByWell) return false;
    final perItem =
        _assetNumbersByWell[item.key] ?? const <String, List<String>>{};
    for (final well in _wells) {
      final values = perItem[well] ?? const <String>[];
      for (int i = nextCount; i < values.length; i++) {
        if (values[i].trim().isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  int _countFor(_InventoryItem item) => _counts[item.key] ?? 0;

  void _setCount(_InventoryItem item, int next) {
    final clamped = next < 0 ? 0 : next;
    setState(() {
      _counts[item.key] = clamped;
      if (item.splittable && clamped == 0) {
        _splitByWellEnabled[item.key] = false;
        _tankSplits[item.key] = {for (final well in _wells) well: ''};
      }
      for (final well in _wells) {
        _syncAssetCapacityForWell(item, well);
      }
    });
  }

  Future<void> _changeCount(_InventoryItem item, int next) async {
    final current = _countFor(item);
    final clamped = next < 0 ? 0 : next;
    if (clamped >= current) {
      _setCount(item, clamped);
      return;
    }

    final willTrimAssets = _hasAssetDataPast(item, clamped);
    if (willTrimAssets) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Reduce Quantity?'),
              content: const Text(
                'Reducing quantity will remove saved Asset Numbers for trimmed units. Continue?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Reduce'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }

    _setCount(item, clamped);
  }

  void _setAssignedForWell(_InventoryItem item, String well, int value) {
    setState(() {
      final map = _assignedByWell[item.key] ?? <String, int>{};
      map[well] = value < 0 ? 0 : value;
      _assignedByWell[item.key] = map;
      _syncAssetCapacityForWell(item, well);
    });
  }

  void _toggleAssignByWell(_InventoryItem item, bool enabled) {
    setState(() {
      _assignByWellEnabled[item.key] = enabled;
      if (enabled) {
        final defaultQty = _countFor(item);
        _assignedByWell[item.key] = {
          for (final well in _wells)
            well: (_assignedByWell[item.key]?[well] ?? defaultQty),
        };
      }
      for (final well in _wells) {
        _syncAssetCapacityForWell(item, well);
      }
    });
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
      _syncAssetCapacityForWell(item, well);
    });
  }

  void _toggleSplitByWell(_InventoryItem item, bool enabled) {
    setState(() {
      _splitByWellEnabled[item.key] = enabled;
      if (!enabled) {
        _tankSplits[item.key] = {for (final well in _wells) well: ''};
      }
      for (final well in _wells) {
        _syncAssetCapacityForWell(item, well);
      }
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
      for (final well in _wells) {
        _syncAssetCapacityForWell(item, well);
      }
    });
  }

  List<String> _assetListFor(_InventoryItem item, String well) {
    final perItem =
        _assetNumbersByWell[item.key] ?? const <String, List<String>>{};
    return List<String>.from(perItem[well] ?? const <String>[]);
  }

  void _setAssetNumberAt(
    _InventoryItem item,
    String well,
    int index,
    String value,
  ) {
    setState(() {
      final perItem = _assetNumbersByWell[item.key] ?? <String, List<String>>{};
      final entries = List<String>.from(perItem[well] ?? const <String>[]);
      if (index < 0 || index >= entries.length) return;
      entries[index] = value.trim();
      perItem[well] = entries;
      _assetNumbersByWell[item.key] = perItem;
    });
  }

  String _assetNumbersText(_InventoryItem item, String well) {
    final values = _assetListFor(item, well)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return values.join(', ');
  }

  List<Widget> _assetFieldsForWell(_InventoryItem item, String well) {
    final assetValues = _assetListFor(item, well).asMap().entries.toList();
    if (assetValues.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 6),
      const Text(
        'Asset Numbers',
        style: TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 6),
      for (final asset in assetValues)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: TextFormField(
            initialValue: asset.value,
            key: ValueKey(
              'asset-${item.key}-$well-${asset.key}-${asset.value}',
            ),
            decoration: InputDecoration(
              labelText: 'Asset ${asset.key + 1}',
            ),
            onChanged: (value) {
              _setAssetNumberAt(item, well, asset.key, value);
            },
          ),
        ),
    ];
  }

  List<Widget> _splitAssetFieldForWell(_InventoryItem item, String well) {
    final assetValues = _assetListFor(item, well);
    if (assetValues.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 6),
      TextFormField(
        initialValue: assetValues.first,
        key: ValueKey(
          'split-asset-${item.key}-$well-${assetValues.first}',
        ),
        decoration: const InputDecoration(
          labelText: 'Asset Number',
        ),
        onChanged: (value) => _setAssetNumberAt(item, well, 0, value),
      ),
    ];
  }

  Future<void> _copyInventory() async {
    if (!_validateHeader()) return;
    final text = _buildInventoryText();
    setState(() => _inventoryText = text);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rig-Up Inventory copied.')),
    );
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
    if ((_activeJob?.resolvedWellNames ?? const <String>[]).isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wells are synced from Active Job.'),
        ),
      );
      return;
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _newWellFocusNode.requestFocus();
    });
  }

  void _removeWell(String name) {
    if ((_activeJob?.resolvedWellNames ?? const <String>[]).isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Manage wells from Active Job.'),
        ),
      );
      return;
    }
    setState(() {
      _wells.remove(name);
      _reconcileToWells();
    });
  }

  bool _validateHeader() {
    if (_padController.text.trim().isEmpty ||
        _wells.where((well) => well.trim().isNotEmpty).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter Pad and at least one Well.'),
        ),
      );
      return false;
    }
    return true;
  }

  String _buildInventoryText() {
    final customer = _customerController.text.trim();
    final pad = _padController.text.trim();
    final dateText = DateFormat('yyyy-MM-dd').format(_date);

    final perWellLines = <String>[];
    final padTotals = <String, String>{};

    for (final well in _wells) {
      final entries = <String>[];

      for (final item in _allItems.where((x) => !x.splittable)) {
        final usePerWellAssignments = _assignByWellEnabled[item.key] ?? false;
        final value = usePerWellAssignments
            ? (_assignedByWell[item.key]?[well] ?? 0)
            : _countFor(item);
        if (value <= 0) continue;
        entries.add('- ${item.label}: $value');
        final assetText = _assetNumbersText(item, well);
        if (assetText.isNotEmpty) {
          entries.add('  Asset #: $assetText');
        }
        final current = int.tryParse(padTotals[item.label] ?? '0') ?? 0;
        padTotals[item.label] = '${current + value}';
      }

      for (final item in _allItems.where((x) => x.splittable)) {
        final totalPadQty = _countFor(item);
        if (totalPadQty > 0) {
          padTotals[item.label] = '$totalPadQty';
        }

        final splitByWell = _splitByWellEnabled[item.key] ?? false;
        if (!splitByWell) continue;

        final split = _tankSplits[item.key]?[well] ?? '';
        if (split.isEmpty) continue;
        entries.add('- ${item.label}: $split of $totalPadQty');
        final assetText = _assetNumbersText(item, well);
        if (assetText.isNotEmpty) {
          entries.add('  Asset #: $assetText');
        }
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
      ..writeln('RIG-UP PACKAGE INVENTORY')
      ..writeln('')
      ..writeln('Customer: ${customer.isEmpty ? '-' : customer}')
      ..writeln('Pad: ${pad.isEmpty ? '-' : pad}')
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
        'customer': _customerController.text.trim(),
        'pad': _padController.text.trim(),
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'wells': _wells,
        'counts': _counts,
        'assignedByWell': _assignedByWell,
        'assignByWellEnabled': _assignByWellEnabled,
        'tankSplits': _tankSplits,
        'splitByWellEnabled': _splitByWellEnabled,
        'assetNumbersByWell': _assetNumbersByWell,
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

  ButtonStyle get _primaryActionStyle => FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      );

  ButtonStyle get _secondaryActionStyle => OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      );

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
              'Rig-Up Package Inventory',
              style: TextStyle(color: _gold, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _customerController,
              decoration: const InputDecoration(labelText: 'Customer'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: _secondaryActionStyle,
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('Date: $dateText'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _padController,
              decoration: const InputDecoration(labelText: 'Pad'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Wells',
              style: TextStyle(color: _gold, fontWeight: FontWeight.w700),
            ),
            if ((_activeJob?.resolvedWellNames ?? const <String>[]).isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Synced from Active Job',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final well in _wells)
                  InputChip(
                    label: Text(well),
                    onDeleted:
                        (_activeJob?.resolvedWellNames ?? const <String>[])
                                .isNotEmpty
                            ? null
                            : () => _removeWell(well),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if ((_activeJob?.resolvedWellNames ?? const <String>[]).isEmpty)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newWellController,
                      focusNode: _newWellFocusNode,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(labelText: 'Well Name'),
                      onSubmitted: (_) => _addWell(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _addWell,
                    child: const Text('Add'),
                  ),
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
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton.filledTonal(
          style: IconButton.styleFrom(
            backgroundColor: scheme.surfaceContainerHighest,
            foregroundColor: scheme.onSurface,
          ),
          onPressed: () => _changeCount(item, value - 1),
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
          style: IconButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
          ),
          onPressed: () => _changeCount(item, value + 1),
          icon: const Icon(Icons.add),
          tooltip: 'Increase ${item.label}',
        ),
      ],
    );
  }

  String _quantityLabel(_InventoryItem item) {
    if (item.splittable) return 'Pad Qty';
    if (item.label == 'Footage') return 'Footage Per Well';
    return 'Qty Per Well';
  }

  Widget _dedicatedAssignmentEditor(_InventoryItem item) {
    final quantity = _countFor(item);
    if (quantity <= 0) return const SizedBox.shrink();
    final assignByWell = _assignByWellEnabled[item.key] ?? false;

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
            assignByWell
                ? 'Assign by Well is on for this item.'
                : '${_quantityLabel(item)} applies to every well by default.',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          if (!assignByWell)
            OutlinedButton.icon(
              onPressed: _wells.length > 1
                  ? () => _toggleAssignByWell(item, true)
                  : null,
              icon: const Icon(Icons.tune),
              label: const Text('Assign by Well'),
            )
          else ...[
            OutlinedButton.icon(
              onPressed: () => _toggleAssignByWell(item, false),
              icon: const Icon(Icons.restart_alt),
              label: Text('Use ${_quantityLabel(item)} for all wells'),
            ),
            const SizedBox(height: 8),
            for (final well in _wells)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            well,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: () => _setAssignedForWell(
                            item,
                            well,
                            (_assignedByWell[item.key]?[well] ?? quantity) - 1,
                          ),
                          icon: const Icon(Icons.remove),
                        ),
                        Container(
                          width: 42,
                          alignment: Alignment.center,
                          child: Text(
                            '${_assignedByWell[item.key]?[well] ?? quantity}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton.filled(
                          onPressed: () => _setAssignedForWell(
                            item,
                            well,
                            (_assignedByWell[item.key]?[well] ?? quantity) + 1,
                          ),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    ..._assetFieldsForWell(item, well),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _splitAssignmentEditor(_InventoryItem item) {
    final quantity = _countFor(item);
    if (quantity <= 0) return const SizedBox.shrink();
    final splitByWell = _splitByWellEnabled[item.key] ?? false;

    if (!splitByWell) {
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
            const Text(
              'Pad Inventory only by default. Split is optional.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _wells.length > 1
                  ? () => _toggleSplitByWell(item, true)
                  : null,
              icon: const Icon(Icons.call_split),
              label: const Text('Split by Well'),
            ),
          ],
        ),
      );
    }

    final allocated = _allocatedUnits(item);
    final remaining = 12 - allocated;

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
          const Text(
            'Split by Well is on. Use fractions for wells receiving this equipment.',
            style: TextStyle(
              color: Colors.white70,
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
          OutlinedButton.icon(
            onPressed: () => _toggleSplitByWell(item, false),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Use Pad Inventory Only'),
          ),
          const SizedBox(height: 8),
          for (final well in _wells)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(well,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
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
                              .map((value) => DropdownMenuItem<String>(
                                    value: value,
                                    child:
                                        Text(value.isEmpty ? 'Select' : value),
                                  ))
                              .toList(),
                          onChanged: (value) =>
                              _setWellSplit(item, well, value ?? ''),
                        ),
                      ),
                    ],
                  ),
                  ..._splitAssetFieldForWell(item, well),
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
            Text(
              _quantityLabel(item),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 6),
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
            style: _primaryActionStyle,
            onPressed: _saving ? null : _saveInventory,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save Inventory'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: _secondaryActionStyle,
            onPressed: _previewInventory,
            icon: const Icon(Icons.description_outlined),
            label: const Text('Preview Inventory'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: _secondaryActionStyle,
            onPressed: _copyInventory,
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy Inventory'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: _primaryActionStyle,
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
