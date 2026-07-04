import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../widgets/app_header.dart';

class EquipmentLayoutScreen extends StatefulWidget {
  const EquipmentLayoutScreen({super.key});

  @override
  State<EquipmentLayoutScreen> createState() => _EquipmentLayoutScreenState();
}

class _EquipmentLayoutScreenState extends State<EquipmentLayoutScreen> {
  final List<_LayoutItem> _items = [];
  int? _selectedId;
  final Set<int> _selectedIds = <int>{};
  bool _multiSelectMode = false;
  bool _drawIronMode = false;
  Offset? _ironStartPoint;
  final List<String> _undoStack = <String>[];
  final List<String> _redoStack = <String>[];
  static const int _maxHistory = 40;
  int _nextId = 1;
  bool _snapToGrid = true;
  final _layoutName = TextEditingController(text: 'New Layout');
  final _company = TextEditingController();
  final _padName = TextEditingController();
  final _wellName = TextEditingController();
  final _createdBy = TextEditingController();
  final _notes = TextEditingController();

  static const _gold = Color(0xFFCDA56A);
  static const _bg = Color(0xFF101113);

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  @override
  void dispose() {
    _layoutName.dispose();
    _company.dispose();
    _padName.dispose();
    _wellName.dispose();
    _createdBy.dispose();
    _notes.dispose();
    super.dispose();
  }

  double _snap(double v) => _snapToGrid ? (v / 24).round() * 24.0 : v;

  _LayoutItem? get _selectedItem {
    final id = _selectedId;
    if (id == null) return null;
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }


  String _snapshot() => jsonEncode(_payload());

  void _recordUndo() {
    _undoStack.add(_snapshot());
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _runHistoryChange(VoidCallback change) {
    _recordUndo();
    setState(change);
  }

  void _undoLayoutChange() {
    if (_undoStack.isEmpty) return;
    final current = _snapshot();
    final previous = _undoStack.removeLast();
    _redoStack.add(current);
    _applyPayload(jsonDecode(previous) as Map<String, dynamic>);
  }

  void _redoLayoutChange() {
    if (_redoStack.isEmpty) return;
    final current = _snapshot();
    final next = _redoStack.removeLast();
    _undoStack.add(current);
    _applyPayload(jsonDecode(next) as Map<String, dynamic>);
  }

  List<_LayoutItem> get _selectedItems {
    if (_selectedIds.isEmpty) return const [];
    return _items.where((item) => _selectedIds.contains(item.id)).toList();
  }

  bool get _hasMultipleSelected => _selectedIds.length > 1;

  bool get _selectedIsStraightIron {
    final item = _selectedItem;
    return item != null && (item.type == _EquipmentType.ironHorizontal || item.type == _EquipmentType.ironVertical);
  }

  bool get _selectedIsIron {
    final item = _selectedItem;
    return item != null && item.type.isIron;
  }

  double _ironLengthFeet(_LayoutItem item) {
    final pixels = item.type == _EquipmentType.ironVertical ? item.height : item.width;
    return (pixels / 6).clamp(1, 200).toDouble();
  }

  Future<void> _setSelectedIronLength() async {
    final item = _selectedItem;
    if (item == null || !(item.type == _EquipmentType.ironHorizontal || item.type == _EquipmentType.ironVertical)) return;

    final controller = TextEditingController(text: _ironLengthFeet(item).toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Iron Length'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Length',
            suffixText: 'ft',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, double.tryParse(controller.text.trim())),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result <= 0) return;

    final newPixels = (result * 6).clamp(36.0, 1200.0).toDouble();
    _runHistoryChange(() {
      if (item.type == _EquipmentType.ironHorizontal) {
        item.width = newPixels;
        item.height = 44;
      } else {
        item.height = newPixels;
        item.width = 44;
      }
    });
  }

  void _quickSetIronLength(double feet) {
    final item = _selectedItem;
    if (item == null || !(item.type == _EquipmentType.ironHorizontal || item.type == _EquipmentType.ironVertical)) return;
    final newPixels = (feet * 6).clamp(36.0, 1200.0).toDouble();
    _runHistoryChange(() {
      if (item.type == _EquipmentType.ironHorizontal) {
        item.width = newPixels;
        item.height = 44;
      } else {
        item.height = newPixels;
        item.width = 44;
      }
    });
  }

  void _setSelectedIronSize(String size) {
    final selected = _selectedItems.where((item) => item.type.isIron).toList();
    if (selected.isEmpty) return;
    _runHistoryChange(() {
      for (final item in selected) {
        item.properties['ironSize'] = size;
      }
    });
  }

  void _stretchStraightIron(_LayoutItem item, DragUpdateDetails details, bool leading, BoxConstraints constraints) {
    if (item.locked || !(item.type == _EquipmentType.ironHorizontal || item.type == _EquipmentType.ironVertical)) return;
    setState(() {
      if (item.type == _EquipmentType.ironHorizontal) {
        if (leading) {
          final newX = (item.x + details.delta.dx).clamp(0.0, item.x + item.width - 36.0);
          item.width = item.width + (item.x - newX);
          item.x = newX;
        } else {
          item.width = (item.width + details.delta.dx).clamp(36.0, constraints.maxWidth - item.x);
        }
      } else {
        if (leading) {
          final newY = (item.y + details.delta.dy).clamp(0.0, item.y + item.height - 36.0);
          item.height = item.height + (item.y - newY);
          item.y = newY;
        } else {
          item.height = (item.height + details.delta.dy).clamp(36.0, constraints.maxHeight - item.y);
        }
      }
    });
  }


  void _toggleDrawIronMode(bool value) {
    setState(() {
      _drawIronMode = value;
      _ironStartPoint = null;
      if (value) {
        _multiSelectMode = false;
        _clearSelection();
      }
    });
  }

  void _handleCanvasTap(TapDownDetails details, BoxConstraints constraints) {
    if (!_drawIronMode) return;
    final point = Offset(
      _snap(details.localPosition.dx).clamp(0.0, constraints.maxWidth),
      _snap(details.localPosition.dy).clamp(0.0, constraints.maxHeight),
    );

    final start = _ironStartPoint;
    if (start == null) {
      setState(() => _ironStartPoint = point);
      return;
    }

    final dx = point.dx - start.dx;
    final dy = point.dy - start.dy;
    if (dx.abs() < 12 && dy.abs() < 12) return;

    final horizontal = dx.abs() >= dy.abs();
    final type = horizontal ? _EquipmentType.ironHorizontal : _EquipmentType.ironVertical;
    final width = horizontal ? dx.abs().clamp(36.0, 1200.0).toDouble() : type.defaultWidth;
    final height = horizontal ? type.defaultHeight : dy.abs().clamp(36.0, 1200.0).toDouble();
    final x = horizontal ? (dx >= 0 ? start.dx : point.dx) : start.dx - width / 2;
    final y = horizontal ? start.dy - height / 2 : (dy >= 0 ? start.dy : point.dy);

    _recordUndo();
    setState(() {
      final id = _nextId++;
      _items.add(_LayoutItem(
        id: id,
        type: type,
        x: _snap(x).clamp(0.0, constraints.maxWidth - width),
        y: _snap(y).clamp(0.0, constraints.maxHeight - height),
        width: width,
        height: height,
      ));
      _selectedId = id;
      _selectedIds
        ..clear()
        ..add(id);
      _ironStartPoint = point;
    });
  }

  void _addItem(_EquipmentType type) {
    final offset = 36.0 + (_items.length % 8) * 20.0;
    _runHistoryChange(() {
      final id = _nextId++;
      _items.add(_LayoutItem(
        id: id,
        type: type,
        x: _snap(offset),
        y: _snap(offset),
        width: type.defaultWidth,
        height: type.defaultHeight,
      ));
      _selectedId = id;
      _selectedIds
        ..clear()
        ..add(id);
    });
  }

  void _selectOnly(int id) {
    setState(() {
      _selectedId = id;
      _selectedIds
        ..clear()
        ..add(id);
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      _selectedId = _selectedIds.isEmpty ? null : id;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedId = null;
      _selectedIds.clear();
    });
  }

  void _deleteSelected() {
    final ids = Set<int>.from(_selectedIds);
    if (ids.isEmpty && _selectedId != null) ids.add(_selectedId!);
    if (ids.isEmpty) return;
    _runHistoryChange(() {
      _items.removeWhere((item) => ids.contains(item.id));
      _selectedId = null;
      _selectedIds.clear();
    });
  }

  void _toggleSelectedLock() {
    final selected = _selectedItems;
    if (selected.isEmpty) return;
    final shouldLock = selected.any((item) => !item.locked);
    _runHistoryChange(() {
      for (final item in selected) {
        item.locked = shouldLock;
      }
    });
  }

  void _duplicateSelected() {
    final originals = _selectedItems;
    if (originals.isEmpty) return;
    _runHistoryChange(() {
      _selectedIds.clear();
      for (final original in originals) {
        final newId = _nextId++;
        _items.add(_LayoutItem(
          id: newId,
          type: original.type,
          x: _snap(original.x + 24),
          y: _snap(original.y + 24),
          width: original.width,
          height: original.height,
          properties: Map<String, String>.from(original.properties),
          rotationTurns: original.rotationTurns,
          locked: false,
        ));
        _selectedIds.add(newId);
        _selectedId = newId;
      }
    });
  }

  void _clearLayout() {
    _runHistoryChange(() {
      _items.clear();
      _selectedId = null;
      _selectedIds.clear();
      _nextId = 1;
    });
  }

  Map<String, dynamic> _payload() => {
        'name': _layoutName.text.trim().isEmpty ? 'New Layout' : _layoutName.text.trim(),
        'company': _company.text.trim(),
        'padName': _padName.text.trim(),
        'wellName': _wellName.text.trim(),
        'createdBy': _createdBy.text.trim(),
        'notes': _notes.text.trim(),
        'nextId': _nextId,
        'snapToGrid': _snapToGrid,
        'items': _items.map((item) => item.toJson()).toList(),
      };

  void _applyPayload(Map<String, dynamic> data) {
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((item) => _LayoutItem.fromJson(item as Map<String, dynamic>))
        .toList();
    setState(() {
      _items
        ..clear()
        ..addAll(items);
      _nextId = data['nextId'] as int? ?? ((_items.length) + 1);
      _snapToGrid = data['snapToGrid'] as bool? ?? true;
      _layoutName.text = data['name'] as String? ?? 'Saved Layout';
      _company.text = data['company'] as String? ?? '';
      _padName.text = data['padName'] as String? ?? '';
      _wellName.text = data['wellName'] as String? ?? '';
      _createdBy.text = data['createdBy'] as String? ?? '';
      _notes.text = data['notes'] as String? ?? '';
      _selectedId = null;
      _selectedIds.clear();
    });
  }

  Future<Map<String, dynamic>> _savedLayouts(SharedPreferences prefs) async {
    final raw = prefs.getString('wellwerks_saved_layouts_v1');
    if (raw == null || raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final name = _layoutName.text.trim().isEmpty ? 'New Layout' : _layoutName.text.trim();
    final layouts = await _savedLayouts(prefs);
    final payload = _payload();
    layouts[name] = payload;
    await prefs.setString('wellwerks_saved_layouts_v1', jsonEncode(layouts));
    await prefs.setString('wellwerks_layout_designer_v2', jsonEncode(payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Layout saved: $name')));
  }

  Future<void> _loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('wellwerks_layout_designer_v2') ?? prefs.getString('wellwerks_layout_designer_v1');
    if (raw == null || raw.isEmpty) return;
    try {
      _applyPayload(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<void> _showLoadLayouts() async {
    final prefs = await SharedPreferences.getInstance();
    final layouts = await _savedLayouts(prefs);
    if (!mounted) return;
    if (layouts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No saved layouts yet')));
      return;
    }
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Saved Layouts', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          for (final name in layouts.keys)
            Card(
              child: ListTile(
                leading: const Icon(Icons.folder_open),
                title: Text(name),
                subtitle: Text('${((layouts[name] as Map)['items'] as List?)?.length ?? 0} items'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    layouts.remove(name);
                    await prefs.setString('wellwerks_saved_layouts_v1', jsonEncode(layouts));
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
                onTap: () {
                  _applyPayload(Map<String, dynamic>.from(layouts[name] as Map));
                  Navigator.pop(context);
                },
              ),
            ),
        ],
      ),
    );
  }

  List<_EquipmentType> get _equipmentTypes => const [
        _EquipmentType.wellhead,
        _EquipmentType.esdValve,
        _EquipmentType.lineHeater,
        _EquipmentType.plugCatcher,
        _EquipmentType.cyclonicSandSep,
        _EquipmentType.sphericalSandSep,
        _EquipmentType.chokeManifold,
        _EquipmentType.flowbackTank,
        _EquipmentType.productionTank,
        _EquipmentType.testSeparator,
        _EquipmentType.flare,
        _EquipmentType.compressor,
        _EquipmentType.facilities,
      ];

  List<_EquipmentType> get _ironTypes => const [
        _EquipmentType.ironHorizontal,
        _EquipmentType.ironVertical,
        _EquipmentType.elbowUpRight,
        _EquipmentType.elbowRightDown,
        _EquipmentType.elbowDownLeft,
        _EquipmentType.elbowLeftUp,
        _EquipmentType.teeUp,
        _EquipmentType.teeRight,
        _EquipmentType.teeDown,
        _EquipmentType.teeLeft,
        _EquipmentType.bypass,
      ];

  Map<String, int> _equipmentSummary() {
    final summary = <String, int>{};
    for (final item in _items) {
      summary[item.type.label] = (summary[item.type.label] ?? 0) + 1;
    }
    return summary;
  }

  Future<void> _showLayoutInfo() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Layout Information'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _company, decoration: const InputDecoration(labelText: 'Company')),
                const SizedBox(height: 8),
                TextField(controller: _padName, decoration: const InputDecoration(labelText: 'Pad Name')),
                const SizedBox(height: 8),
                TextField(controller: _wellName, decoration: const InputDecoration(labelText: 'Well / Location')),
                const SizedBox(height: 8),
                TextField(controller: _createdBy, decoration: const InputDecoration(labelText: 'Created By')),
                const SizedBox(height: 8),
                TextField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  minLines: 3,
                  maxLines: 5,
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
    setState(() {});
  }

  Future<void> _exportPdf() async {
    final summary = _equipmentSummary();
    final layoutName = _layoutName.text.trim().isEmpty ? 'New Layout' : _layoutName.text.trim();
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text('WellWerks Layout', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text(layoutName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 14),
          if (_company.text.trim().isNotEmpty) pw.Text('Company: ${_company.text.trim()}'),
          if (_padName.text.trim().isNotEmpty) pw.Text('Pad: ${_padName.text.trim()}'),
          if (_wellName.text.trim().isNotEmpty) pw.Text('Well / Location: ${_wellName.text.trim()}'),
          if (_createdBy.text.trim().isNotEmpty) pw.Text('Created By: ${_createdBy.text.trim()}'),
          pw.Text('Created: ${DateTime.now().toLocal()}'),
          pw.SizedBox(height: 18),
          pw.Text('Equipment Summary', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          if (summary.isEmpty)
            pw.Text('No equipment added.')
          else
            pw.Table(
              border: pw.TableBorder.all(width: .5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Count', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                for (final entry in summary.entries)
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(entry.key)),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(entry.value.toString())),
                    ],
                  ),
              ],
            ),
          if (_notes.text.trim().isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text('Notes', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Text(_notes.text.trim()),
          ],
          pw.SizedBox(height: 18),
          pw.Text('Layout Items', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          for (final item in _items)
            pw.Text('${item.displayLabel}${item.primaryPropertyLabel.isNotEmpty ? ' (${item.primaryPropertyLabel})' : ''}  -  X: ${item.x.toStringAsFixed(0)}, Y: ${item.y.toStringAsFixed(0)}'),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }



  Future<void> _showRigUpAssistant() async {
    String template = 'Standard Flowback';
    final wells = TextEditingController(text: '1');
    final flowbackTanks = TextEditingController(text: '2');
    final productionTanks = TextEditingController(text: '0');
    final sandSeparators = TextEditingController(text: '1');
    bool lineHeater = true;
    bool compressor = false;
    bool testSeparator = false;
    bool flare = true;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rig-Up Assistant'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: template,
                    decoration: const InputDecoration(labelText: 'Template'),
                    items: const [
                      DropdownMenuItem(value: 'Standard Flowback', child: Text('Standard Flowback')),
                      DropdownMenuItem(value: 'Dual Sand Separator', child: Text('Dual Sand Separator')),
                      DropdownMenuItem(value: 'Production Test', child: Text('Production Test')),
                      DropdownMenuItem(value: 'Frac Assist', child: Text('Frac Assist')),
                      DropdownMenuItem(value: 'Cleanout', child: Text('Cleanout')),
                      DropdownMenuItem(value: 'Blank', child: Text('Blank')),
                    ],
                    onChanged: (v) {
                      setDialogState(() {
                        template = v ?? 'Standard Flowback';
                        if (template == 'Dual Sand Separator') sandSeparators.text = '2';
                        if (template == 'Production Test') {
                          testSeparator = true;
                          productionTanks.text = '2';
                          flowbackTanks.text = '1';
                        }
                        if (template == 'Frac Assist') {
                          sandSeparators.text = '2';
                          flowbackTanks.text = '3';
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextField(controller: wells, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Wells'))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: sandSeparators, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sand Seps'))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: flowbackTanks, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Flowback Tanks'))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: productionTanks, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Production Tanks'))),
                  ]),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: lineHeater,
                    title: const Text('Line Heater'),
                    dense: true,
                    onChanged: (v) => setDialogState(() => lineHeater = v ?? false),
                  ),
                  CheckboxListTile(
                    value: testSeparator,
                    title: const Text('Test Separator'),
                    dense: true,
                    onChanged: (v) => setDialogState(() => testSeparator = v ?? false),
                  ),
                  CheckboxListTile(
                    value: compressor,
                    title: const Text('Compressor'),
                    dense: true,
                    onChanged: (v) => setDialogState(() => compressor = v ?? false),
                  ),
                  CheckboxListTile(
                    value: flare,
                    title: const Text('Flare'),
                    dense: true,
                    onChanged: (v) => setDialogState(() => flare = v ?? false),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                _applyRigUpTemplate(
                  template: template,
                  wells: int.tryParse(wells.text.trim()) ?? 1,
                  sandSeparators: int.tryParse(sandSeparators.text.trim()) ?? 1,
                  flowbackTanks: int.tryParse(flowbackTanks.text.trim()) ?? 2,
                  productionTanks: int.tryParse(productionTanks.text.trim()) ?? 0,
                  lineHeater: lineHeater,
                  compressor: compressor,
                  testSeparator: testSeparator,
                  flare: flare,
                );
                Navigator.pop(context);
              },
              child: const Text('Build Layout'),
            ),
          ],
        ),
      ),
    );

    wells.dispose();
    flowbackTanks.dispose();
    productionTanks.dispose();
    sandSeparators.dispose();
  }

  void _autoItem(_EquipmentType type, double x, double y, {double? width, double? height}) {
    _items.add(_LayoutItem(
      id: _nextId++,
      type: type,
      x: _snap(x),
      y: _snap(y),
      width: width ?? type.defaultWidth,
      height: height ?? type.defaultHeight,
    ));
  }

  void _applyRigUpTemplate({
    required String template,
    required int wells,
    required int sandSeparators,
    required int flowbackTanks,
    required int productionTanks,
    required bool lineHeater,
    required bool compressor,
    required bool testSeparator,
    required bool flare,
  }) {
    _runHistoryChange(() {
      _items.clear();
      _selectedId = null;
      _selectedIds.clear();
      _nextId = 1;
      if (template == 'Blank') return;

      final safeWells = wells.clamp(1, 8);
      final safeSand = sandSeparators.clamp(1, 4);
      final safeFlowTanks = flowbackTanks.clamp(0, 8);
      final safeProdTanks = productionTanks.clamp(0, 8);

      for (int i = 0; i < safeWells; i++) {
        _autoItem(_EquipmentType.wellhead, 24, 56 + (i * 96));
        _autoItem(_EquipmentType.ironHorizontal, 144, 70 + (i * 96), width: 90, height: 44);
      }

      _autoItem(_EquipmentType.esdValve, 252, 56);
      _autoItem(_EquipmentType.ironHorizontal, 350, 70, width: 80, height: 44);
      _autoItem(_EquipmentType.plugCatcher, 444, 48);
      _autoItem(_EquipmentType.ironHorizontal, 564, 70, width: 90, height: 44);

      double x = 670;
      if (lineHeater) {
        _autoItem(_EquipmentType.lineHeater, x, 48);
        _autoItem(_EquipmentType.ironHorizontal, x + 122, 70, width: 70, height: 44);
        x += 210;
      }

      for (int i = 0; i < safeSand; i++) {
        _autoItem(i.isEven ? _EquipmentType.cyclonicSandSep : _EquipmentType.sphericalSandSep, x, 48 + (i * 96));
        if (i == 0) _autoItem(_EquipmentType.ironHorizontal, x + 122, 70, width: 80, height: 44);
      }
      x += 220;

      _autoItem(_EquipmentType.chokeManifold, x, 48);
      _autoItem(_EquipmentType.teeDown, x + 124, 48);

      for (int i = 0; i < safeFlowTanks; i++) {
        _autoItem(_EquipmentType.flowbackTank, x + 230, 24 + (i * 86));
        _autoItem(_EquipmentType.ironHorizontal, x + 160, 50 + (i * 86), width: 65, height: 44);
      }

      for (int i = 0; i < safeProdTanks; i++) {
        _autoItem(_EquipmentType.productionTank, x + 380, 24 + (i * 86));
      }

      if (testSeparator) _autoItem(_EquipmentType.testSeparator, x + 150, 330);
      if (flare) _autoItem(_EquipmentType.flare, x + 370, 330);
      if (compressor) _autoItem(_EquipmentType.compressor, x + 150, 430);

      _autoItem(_EquipmentType.facilities, x + 540, 300, width: 190, height: 100);
      _layoutName.text = template;
    });
  }


  List<_PropertyField> _propertyFields(_EquipmentType type) {
    switch (type) {
      case _EquipmentType.wellhead:
        return const [
          _PropertyField('wellName', 'Well Name'),
          _PropertyField('apiNumber', 'API Number'),
          _PropertyField('status', 'Status'),
          _PropertyField('notes', 'Notes', maxLines: 3),
        ];
      case _EquipmentType.chokeManifold:
        return const [
          _PropertyField('chokeSize', 'Choke Size'),
          _PropertyField('chokeType', 'POS / ADJ'),
          _PropertyField('upstreamPressure', 'Upstream Pressure'),
          _PropertyField('downstreamPressure', 'Downstream Pressure'),
          _PropertyField('notes', 'Notes', maxLines: 3),
        ];
      case _EquipmentType.flowbackTank:
      case _EquipmentType.productionTank:
        return const [
          _PropertyField('tankName', 'Tank Name / Number'),
          _PropertyField('capacity', 'Capacity'),
          _PropertyField('currentLevel', 'Current Level'),
          _PropertyField('assignedWell', 'Assigned Well'),
          _PropertyField('notes', 'Notes', maxLines: 3),
        ];
      case _EquipmentType.compressor:
        return const [
          _PropertyField('company', 'Company'),
          _PropertyField('suctionPressure', 'Suction Pressure'),
          _PropertyField('dischargePressure', 'Discharge Pressure'),
          _PropertyField('injectionRate', 'Injection Rate (MCF)'),
          _PropertyField('running', 'Running / Status'),
          _PropertyField('notes', 'Notes', maxLines: 3),
        ];
      case _EquipmentType.lineHeater:
        return const [
          _PropertyField('fuelGasPressure', 'Fuel Gas Pressure'),
          _PropertyField('temperature', 'Temperature'),
          _PropertyField('status', 'Status'),
          _PropertyField('notes', 'Notes', maxLines: 3),
        ];
      case _EquipmentType.esdValve:
        return const [
          _PropertyField('status', 'Open / Closed'),
          _PropertyField('lastTested', 'Last Tested'),
          _PropertyField('notes', 'Notes', maxLines: 3),
        ];
      case _EquipmentType.cyclonicSandSep:
      case _EquipmentType.sphericalSandSep:
        return const [
          _PropertyField('separatorType', 'Separator Type'),
          _PropertyField('sandRate', 'Sand Rate (GAL/hr)'),
          _PropertyField('assignedWell', 'Assigned Well'),
          _PropertyField('notes', 'Notes', maxLines: 3),
        ];
      default:
        return const [
          _PropertyField('name', 'Name / Label'),
          _PropertyField('status', 'Status'),
          _PropertyField('notes', 'Notes', maxLines: 3),
        ];
    }
  }

  bool get _selectedCanHaveProperties {
    final item = _selectedItem;
    return item != null && _selectedIds.length == 1 && !item.type.isIron;
  }

  bool get _hasSelectedItem => _selectedIds.isNotEmpty;

  void _rotateSelected() {
    final selected = _selectedItems.where((item) => !item.locked).toList();
    if (selected.isEmpty) return;
    _runHistoryChange(() {
      for (final item in selected) {
        item.rotationTurns = (item.rotationTurns + 1) % 4;
        if (!item.type.isIron || item.type.name.startsWith('elbow') || item.type.name.startsWith('tee')) {
          final oldWidth = item.width;
          item.width = item.height;
          item.height = oldWidth;
        }
      }
    });
  }

  Future<void> _renameSelected() async {
    final item = _selectedItem;
    if (item == null) return;
    final controller = TextEditingController(text: item.displayLabel);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Label shown on layout'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      _runHistoryChange(() {
        final value = controller.text.trim();
        if (value.isEmpty || value == item.type.label) {
          item.properties.remove('displayLabel');
        } else {
          item.properties['displayLabel'] = value;
        }
      });
    }
    controller.dispose();
  }

  void _nudgeSelected(double dx, double dy) {
    final selected = _selectedItems.where((item) => !item.locked).toList();
    if (selected.isEmpty) return;
    _runHistoryChange(() {
      for (final item in selected) {
        item.x = _snap(item.x + dx).clamp(0.0, 5000.0);
        item.y = _snap(item.y + dy).clamp(0.0, 5000.0);
      }
    });
  }

  void _alignSelected(_LayoutAlign align) {
    final selected = _selectedItems.where((item) => !item.locked).toList();
    if (selected.length < 2) return;
    _runHistoryChange(() {
      switch (align) {
        case _LayoutAlign.left:
          final x = selected.map((item) => item.x).reduce((a, b) => a < b ? a : b);
          for (final item in selected) item.x = _snap(x);
          break;
        case _LayoutAlign.right:
          final right = selected.map((item) => item.x + item.width).reduce((a, b) => a > b ? a : b);
          for (final item in selected) item.x = _snap(right - item.width);
          break;
        case _LayoutAlign.top:
          final y = selected.map((item) => item.y).reduce((a, b) => a < b ? a : b);
          for (final item in selected) item.y = _snap(y);
          break;
        case _LayoutAlign.bottom:
          final bottom = selected.map((item) => item.y + item.height).reduce((a, b) => a > b ? a : b);
          for (final item in selected) item.y = _snap(bottom - item.height);
          break;
        case _LayoutAlign.horizontalCenter:
          final center = selected.map((item) => item.x + item.width / 2).reduce((a, b) => a + b) / selected.length;
          for (final item in selected) item.x = _snap(center - item.width / 2);
          break;
        case _LayoutAlign.verticalCenter:
          final center = selected.map((item) => item.y + item.height / 2).reduce((a, b) => a + b) / selected.length;
          for (final item in selected) item.y = _snap(center - item.height / 2);
          break;
      }
    });
  }

  void _distributeSelected(_LayoutDistribution distribution) {
    final selected = _selectedItems.where((item) => !item.locked).toList();
    if (selected.length < 3) return;

    _runHistoryChange(() {
      switch (distribution) {
        case _LayoutDistribution.horizontal:
          selected.sort((a, b) => (a.x + a.width / 2).compareTo(b.x + b.width / 2));
          final firstCenter = selected.first.x + selected.first.width / 2;
          final lastCenter = selected.last.x + selected.last.width / 2;
          final step = (lastCenter - firstCenter) / (selected.length - 1);
          for (var i = 1; i < selected.length - 1; i++) {
            selected[i].x = _snap(firstCenter + step * i - selected[i].width / 2);
          }
          break;
        case _LayoutDistribution.vertical:
          selected.sort((a, b) => (a.y + a.height / 2).compareTo(b.y + b.height / 2));
          final firstCenter = selected.first.y + selected.first.height / 2;
          final lastCenter = selected.last.y + selected.last.height / 2;
          final step = (lastCenter - firstCenter) / (selected.length - 1);
          for (var i = 1; i < selected.length - 1; i++) {
            selected[i].y = _snap(firstCenter + step * i - selected[i].height / 2);
          }
          break;
      }
    });
  }


  void _showInventory() {
    final counts = <String, int>{};
    var totalIronFeet = 0.0;

    for (final item in _items) {
      String key;
      if (item.type == _EquipmentType.ironHorizontal || item.type == _EquipmentType.ironVertical) {
        final feet = _ironLengthFeet(item).round();
        totalIronFeet += feet;
        key = '${item.ironSize}" Straight Iron - $feet ft';
      } else if (item.type.isIron) {
        key = '${item.ironSize}" ${item.type.label}';
      } else {
        key = item.type.label;
      }
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final lines = counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rig-Up Inventory'),
        content: SizedBox(
          width: 420,
          child: lines.isEmpty
              ? const Text('No equipment or iron added yet.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...lines.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('${e.value} × ${e.key}'),
                        )),
                    const Divider(height: 22),
                    Text('Total straight iron: ${totalIronFeet.toStringAsFixed(0)} ft', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _showSelectedProperties() async {
    final item = _selectedItem;
    if (item == null || item.type.isIron) return;
    final fields = _propertyFields(item.type);
    final controllers = <String, TextEditingController>{
      for (final field in fields) field.key: TextEditingController(text: item.properties[field.key] ?? ''),
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.type.label} Properties'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in fields) ...[
                  TextField(
                    controller: controllers[field.key],
                    decoration: InputDecoration(labelText: field.label),
                    minLines: field.maxLines > 1 ? field.maxLines : 1,
                    maxLines: field.maxLines,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved == true) {
      _runHistoryChange(() {
        item.properties
          ..clear()
          ..addEntries(controllers.entries.where((e) => e.value.text.trim().isNotEmpty).map((e) => MapEntry(e.key, e.value.text.trim())));
      });
    }
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Layout Designer', showBack: true),
      body: Column(
        children: [
          _library(),
          _toolbar(),
          Expanded(child: _canvas()),
        ],
      ),
    );
  }

  Widget _library() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0F),
        border: Border(bottom: BorderSide(color: Color(0xFF333333))),
      ),
      child: SizedBox(
        height: 112,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            ..._libraryButtons('Equipment', _equipmentTypes),
            const SizedBox(width: 16),
            ..._libraryButtons('Iron', _ironTypes),
          ],
        ),
      ),
    );
  }

  List<Widget> _libraryButtons(String group, List<_EquipmentType> types) {
    return [
      SizedBox(
        width: 84,
        child: Center(
          child: Text(group.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: _gold, fontWeight: FontWeight.bold)),
        ),
      ),
      for (final type in types)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: SizedBox(
            width: type.isIron ? 104 : 118,
            child: OutlinedButton(
              onPressed: () => _addItem(type),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF3A3A3A)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.all(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(type.icon, color: _gold, size: 24),
                  const SizedBox(height: 4),
                  Text(type.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  Widget _toolbar() {
    final selected = _selectedIds.isNotEmpty;
    final multiSelected = _selectedIds.length > 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _layoutName,
              decoration: const InputDecoration(labelText: 'Layout Name', prefixIcon: Icon(Icons.drive_file_rename_outline)),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _undoStack.isNotEmpty ? _undoLayoutChange : null,
            icon: const Icon(Icons.undo),
            label: const Text('Undo'),
          ),
          OutlinedButton.icon(
            onPressed: _redoStack.isNotEmpty ? _redoLayoutChange : null,
            icon: const Icon(Icons.redo),
            label: const Text('Redo'),
          ),
          FilterChip(
            selected: _snapToGrid,
            label: const Text('Snap to Grid'),
            avatar: const Icon(Icons.grid_4x4),
            onSelected: (value) => setState(() => _snapToGrid = value),
          ),
          FilterChip(
            selected: _multiSelectMode,
            label: Text(_multiSelectMode ? 'Multi-Select On' : 'Multi-Select'),
            avatar: const Icon(Icons.select_all),
            onSelected: (value) => setState(() => _multiSelectMode = value),
          ),
          FilterChip(
            selected: _drawIronMode,
            label: Text(_drawIronMode ? 'Draw Iron On' : 'Draw Iron'),
            avatar: const Icon(Icons.edit_road),
            onSelected: _toggleDrawIronMode,
          ),
          if (_drawIronMode && _ironStartPoint != null)
            OutlinedButton.icon(
              onPressed: () => setState(() => _ironStartPoint = null),
              icon: const Icon(Icons.close),
              label: const Text('Clear Iron Start'),
            ),
          if (selected) OutlinedButton.icon(onPressed: _clearSelection, icon: const Icon(Icons.deselect), label: Text('Clear Selection (${_selectedIds.length})')),
          OutlinedButton.icon(onPressed: selected ? _duplicateSelected : null, icon: const Icon(Icons.copy), label: const Text('Duplicate')),
          OutlinedButton.icon(onPressed: selected ? _deleteSelected : null, icon: const Icon(Icons.delete), label: const Text('Delete')),
          OutlinedButton.icon(onPressed: _hasSelectedItem ? _renameSelected : null, icon: const Icon(Icons.drive_file_rename_outline), label: const Text('Rename')),
          OutlinedButton.icon(onPressed: _hasSelectedItem ? _rotateSelected : null, icon: const Icon(Icons.rotate_right), label: const Text('Rotate')),
          OutlinedButton.icon(
            onPressed: _hasSelectedItem ? _toggleSelectedLock : null,
            icon: Icon((_selectedItem?.locked ?? false) ? Icons.lock_open : Icons.lock),
            label: Text((_selectedItem?.locked ?? false) ? 'Unlock' : 'Lock'),
          ),
          OutlinedButton.icon(onPressed: _selectedCanHaveProperties ? _showSelectedProperties : null, icon: const Icon(Icons.edit_note), label: const Text('Properties')),
          if (multiSelected) ...[
            OutlinedButton(onPressed: () => _alignSelected(_LayoutAlign.left), child: const Text('Align L')),
            OutlinedButton(onPressed: () => _alignSelected(_LayoutAlign.right), child: const Text('Align R')),
            OutlinedButton(onPressed: () => _alignSelected(_LayoutAlign.top), child: const Text('Align T')),
            OutlinedButton(onPressed: () => _alignSelected(_LayoutAlign.bottom), child: const Text('Align B')),
            OutlinedButton(onPressed: () => _alignSelected(_LayoutAlign.horizontalCenter), child: const Text('Center X')),
            OutlinedButton(onPressed: () => _alignSelected(_LayoutAlign.verticalCenter), child: const Text('Center Y')),
            OutlinedButton.icon(onPressed: _selectedIds.length > 2 ? () => _distributeSelected(_LayoutDistribution.horizontal) : null, icon: const Icon(Icons.align_horizontal_center), label: const Text('Space H')),
            OutlinedButton.icon(onPressed: _selectedIds.length > 2 ? () => _distributeSelected(_LayoutDistribution.vertical) : null, icon: const Icon(Icons.align_vertical_center), label: const Text('Space V')),
          ],
          if (_hasSelectedItem) ...[
            OutlinedButton(onPressed: () => _nudgeSelected(-24, 0), child: const Text('←')),
            OutlinedButton(onPressed: () => _nudgeSelected(24, 0), child: const Text('→')),
            OutlinedButton(onPressed: () => _nudgeSelected(0, -24), child: const Text('↑')),
            OutlinedButton(onPressed: () => _nudgeSelected(0, 24), child: const Text('↓')),
          ],
          if (_selectedIsIron) ...[
            OutlinedButton(onPressed: () => _setSelectedIronSize('2'), child: const Text('2"')),
            OutlinedButton(onPressed: () => _setSelectedIronSize('3'), child: const Text('3"')),
            OutlinedButton(onPressed: () => _setSelectedIronSize('4'), child: const Text('4"')),
          ],
          if (_selectedIsStraightIron) ...[
            OutlinedButton(onPressed: () => _quickSetIronLength(5), child: const Text('5 ft')),
            OutlinedButton(onPressed: () => _quickSetIronLength(10), child: const Text('10 ft')),
            OutlinedButton(onPressed: () => _quickSetIronLength(20), child: const Text('20 ft')),
            OutlinedButton(onPressed: () => _quickSetIronLength((_selectedItem == null ? 5 : _ironLengthFeet(_selectedItem!) - 5).clamp(5, 200).toDouble()), child: const Text('Shorten')),
            OutlinedButton(onPressed: () => _quickSetIronLength((_selectedItem == null ? 10 : _ironLengthFeet(_selectedItem!) + 5).clamp(5, 200).toDouble()), child: const Text('Lengthen')),
            FilledButton.icon(onPressed: _setSelectedIronLength, icon: const Icon(Icons.straighten), label: const Text('Custom Length')),
          ],
          FilledButton.icon(onPressed: _showRigUpAssistant, icon: const Icon(Icons.auto_awesome), label: const Text('Rig-Up Assistant')),
          OutlinedButton.icon(onPressed: _showLayoutInfo, icon: const Icon(Icons.info_outline), label: const Text('Info')),
                OutlinedButton.icon(onPressed: _showInventory, icon: const Icon(Icons.inventory_2_outlined), label: const Text('Inventory')),
          OutlinedButton.icon(onPressed: _saveLayout, icon: const Icon(Icons.save), label: const Text('Save')),
          OutlinedButton.icon(onPressed: _showLoadLayouts, icon: const Icon(Icons.folder_open), label: const Text('Load')),
          OutlinedButton.icon(onPressed: _exportPdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('Export PDF')),
          OutlinedButton.icon(onPressed: _clearLayout, icon: const Icon(Icons.clear_all), label: const Text('Clear')),
        ],
      ),
    );
  }

  Widget _canvas() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(color: _bg, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(18)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _handleCanvasTap(details, constraints),
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: _GridPainter())),
                  if (_drawIronMode && _ironStartPoint != null)
                    Positioned(
                      left: _ironStartPoint!.dx - 7,
                      top: _ironStartPoint!.dy - 7,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _gold,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                      ),
                    ),
                if (_items.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Add equipment or turn on Draw Iron. In Draw Iron mode, tap a start point, then tap the next point to create horizontal or vertical iron. Keep tapping to continue the run.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 16)),
                    ),
                  ),
                for (final item in _items)
                  Positioned(
                    left: item.x,
                    top: item.y,
                    width: item.width,
                    height: item.height,
                    child: GestureDetector(
                      onTap: () => _multiSelectMode ? _toggleSelection(item.id) : _selectOnly(item.id),
                      onPanStart: (_) {
                        final moving = _selectedIds.contains(item.id) ? _selectedItems : [item];
                        if (moving.every((it) => it.locked)) return;
                        _recordUndo();
                      },
                      onPanUpdate: (details) {
                        final moving = _selectedIds.contains(item.id) ? _selectedItems : [item];
                        if (moving.every((it) => it.locked)) return;
                        setState(() {
                          for (final it in moving) {
                            if (it.locked) continue;
                            it.x = (it.x + details.delta.dx).clamp(0.0, constraints.maxWidth - it.width);
                            it.y = (it.y + details.delta.dy).clamp(0.0, constraints.maxHeight - it.height);
                          }
                        });
                      },
                      onPanEnd: (_) {
                        final moving = _selectedIds.contains(item.id) ? _selectedItems : [item];
                        if (moving.every((it) => it.locked)) return;
                        if (!_snapToGrid) return;
                        setState(() {
                          for (final it in moving) {
                            if (it.locked) continue;
                            it.x = _snap(it.x).clamp(0.0, constraints.maxWidth - it.width);
                            it.y = _snap(it.y).clamp(0.0, constraints.maxHeight - it.height);
                          }
                        });
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(child: _LayoutTile(item: item, selected: _selectedIds.contains(item.id))),
                          if (_selectedIds.contains(item.id) && (item.type == _EquipmentType.ironHorizontal || item.type == _EquipmentType.ironVertical)) ...[
                            _IronStretchHandle(
                              item: item,
                              leading: true,
                              onPanStart: () => _recordUndo(),
                              onPanUpdate: (details) => _stretchStraightIron(item, details, true, constraints),
                              onPanEnd: () {
                                if (!_snapToGrid) return;
                                setState(() {
                                  item.x = _snap(item.x).clamp(0.0, constraints.maxWidth - item.width);
                                  item.y = _snap(item.y).clamp(0.0, constraints.maxHeight - item.height);
                                });
                              },
                            ),
                            _IronStretchHandle(
                              item: item,
                              leading: false,
                              onPanStart: () => _recordUndo(),
                              onPanUpdate: (details) => _stretchStraightIron(item, details, false, constraints),
                              onPanEnd: () {
                                if (!_snapToGrid) return;
                                setState(() {
                                  item.x = _snap(item.x).clamp(0.0, constraints.maxWidth - item.width);
                                  item.y = _snap(item.y).clamp(0.0, constraints.maxHeight - item.height);
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _LayoutAlign { left, right, top, bottom, horizontalCenter, verticalCenter }

enum _LayoutDistribution { horizontal, vertical }

enum _EquipmentType {
  wellhead,
  esdValve,
  lineHeater,
  plugCatcher,
  cyclonicSandSep,
  sphericalSandSep,
  chokeManifold,
  flowbackTank,
  productionTank,
  testSeparator,
  flare,
  compressor,
  facilities,
  ironHorizontal,
  ironVertical,
  elbowUpRight,
  elbowRightDown,
  elbowDownLeft,
  elbowLeftUp,
  teeUp,
  teeRight,
  teeDown,
  teeLeft,
  bypass,
}

extension _EquipmentTypeInfo on _EquipmentType {
  bool get isIron => name.startsWith('iron') || name.startsWith('elbow') || name.startsWith('tee') || this == _EquipmentType.bypass;

  String get label {
    switch (this) {
      case _EquipmentType.wellhead:
        return 'Wellhead';
      case _EquipmentType.esdValve:
        return 'ESD Valve';
      case _EquipmentType.lineHeater:
        return 'Line Heater';
      case _EquipmentType.plugCatcher:
        return 'Plug Catcher';
      case _EquipmentType.cyclonicSandSep:
        return 'Cyclonic Sand Sep';
      case _EquipmentType.sphericalSandSep:
        return 'Spherical Sand Sep';
      case _EquipmentType.chokeManifold:
        return 'Choke Manifold';
      case _EquipmentType.flowbackTank:
        return 'Flowback Tank';
      case _EquipmentType.productionTank:
        return 'Production Tank';
      case _EquipmentType.testSeparator:
        return 'Test Separator';
      case _EquipmentType.flare:
        return 'Flare';
      case _EquipmentType.compressor:
        return 'Compressor';
      case _EquipmentType.facilities:
        return 'Facilities';
      case _EquipmentType.ironHorizontal:
        return 'Iron Horizontal';
      case _EquipmentType.ironVertical:
        return 'Iron Vertical';
      case _EquipmentType.elbowUpRight:
        return '90° Up/Right';
      case _EquipmentType.elbowRightDown:
        return '90° Right/Down';
      case _EquipmentType.elbowDownLeft:
        return '90° Down/Left';
      case _EquipmentType.elbowLeftUp:
        return '90° Left/Up';
      case _EquipmentType.teeUp:
        return 'Tee Up';
      case _EquipmentType.teeRight:
        return 'Tee Right';
      case _EquipmentType.teeDown:
        return 'Tee Down';
      case _EquipmentType.teeLeft:
        return 'Tee Left';
      case _EquipmentType.bypass:
        return 'Bypass';
    }
  }

  IconData get icon {
    switch (this) {
      case _EquipmentType.wellhead:
        return Icons.account_tree;
      case _EquipmentType.esdValve:
        return Icons.emergency;
      case _EquipmentType.lineHeater:
        return Icons.whatshot;
      case _EquipmentType.plugCatcher:
        return Icons.filter_alt;
      case _EquipmentType.cyclonicSandSep:
        return Icons.cyclone;
      case _EquipmentType.sphericalSandSep:
        return Icons.circle;
      case _EquipmentType.chokeManifold:
        return Icons.tune;
      case _EquipmentType.flowbackTank:
      case _EquipmentType.productionTank:
        return Icons.oil_barrel;
      case _EquipmentType.testSeparator:
        return Icons.precision_manufacturing;
      case _EquipmentType.flare:
        return Icons.local_fire_department;
      case _EquipmentType.compressor:
        return Icons.compress;
      case _EquipmentType.facilities:
        return Icons.crop_square;
      case _EquipmentType.ironHorizontal:
        return Icons.horizontal_rule;
      case _EquipmentType.ironVertical:
        return Icons.more_vert;
      case _EquipmentType.elbowUpRight:
      case _EquipmentType.elbowRightDown:
      case _EquipmentType.elbowDownLeft:
      case _EquipmentType.elbowLeftUp:
        return Icons.turn_right;
      case _EquipmentType.teeUp:
      case _EquipmentType.teeRight:
      case _EquipmentType.teeDown:
      case _EquipmentType.teeLeft:
        return Icons.call_split;
      case _EquipmentType.bypass:
        return Icons.alt_route;
    }
  }

  double get defaultWidth {
    if (this == _EquipmentType.facilities) return 160;
    if (this == _EquipmentType.ironHorizontal) return 160;
    if (this == _EquipmentType.ironVertical) return 36;
    if (this == _EquipmentType.bypass) return 220;
    if (isIron) return 76;
    if (this == _EquipmentType.esdValve) return 92;
    return 116;
  }

  double get defaultHeight {
    if (this == _EquipmentType.facilities) return 78;
    if (this == _EquipmentType.ironHorizontal) return 36;
    if (this == _EquipmentType.ironVertical) return 160;
    if (this == _EquipmentType.bypass) return 96;
    if (isIron) return 76;
    if (this == _EquipmentType.esdValve) return 64;
    return 72;
  }
}

class _LayoutItem {
  final int id;
  final _EquipmentType type;
  double x;
  double y;
  double width;
  double height;
  final Map<String, String> properties;
  int rotationTurns;
  bool locked;

  _LayoutItem({required this.id, required this.type, required this.x, required this.y, required this.width, required this.height, Map<String, String>? properties, this.rotationTurns = 0, this.locked = false}) : properties = properties ?? <String, String>{};

  Map<String, dynamic> toJson() => {'id': id, 'type': type.name, 'x': x, 'y': y, 'width': width, 'height': height, 'properties': properties, 'rotationTurns': rotationTurns, 'locked': locked};

  factory _LayoutItem.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? _EquipmentType.plugCatcher.name;
    final type = _EquipmentType.values.firstWhere((item) => item.name == typeName, orElse: () => _EquipmentType.plugCatcher);
    return _LayoutItem(
      id: json['id'] as int? ?? 0,
      type: type,
      x: (json['x'] as num? ?? 20).toDouble(),
      y: (json['y'] as num? ?? 20).toDouble(),
      width: (json['width'] as num? ?? type.defaultWidth).toDouble(),
      height: (json['height'] as num? ?? type.defaultHeight).toDouble(),
      properties: Map<String, String>.from(json['properties'] as Map? ?? {}),
      rotationTurns: json['rotationTurns'] as int? ?? 0,
      locked: json['locked'] as bool? ?? false,
    );
  }
}


class _PropertyField {
  final String key;
  final String label;
  final int maxLines;
  const _PropertyField(this.key, this.label, {this.maxLines = 1});
}

extension _LayoutItemProperties on _LayoutItem {
  String get displayLabel {
    final custom = properties['displayLabel'];
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    return type.label;
  }

  String get ironSize {
    final value = properties['ironSize'];
    if (value == '2' || value == '3' || value == '4') return value!;
    return '3';
  }

  String get primaryPropertyLabel {
    for (final key in ['wellName', 'tankName', 'company', 'chokeSize', 'status', 'name', 'assignedWell']) {
      final value = properties[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }
}

class _LayoutTile extends StatelessWidget {
  final _LayoutItem item;
  final bool selected;

  const _LayoutTile({required this.item, required this.selected});

  @override
  Widget build(BuildContext context) {
    final isIron = item.type.isIron;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: isIron ? Colors.transparent : (item.type == _EquipmentType.facilities ? const Color(0xFF202327) : const Color(0xFF191B1F)),
        border: Border.all(color: selected ? const Color(0xFFCDA56A) : (isIron ? Colors.transparent : const Color(0xFF4A4A4A)), width: selected ? 2.5 : 1.2),
        borderRadius: BorderRadius.circular(item.type == _EquipmentType.sphericalSandSep ? 999 : 14),
        boxShadow: selected ? [BoxShadow(color: const Color(0xFFCDA56A).withOpacity(.25), blurRadius: 12)] : null,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ShapePainter(item.type, turns: item.rotationTurns, ironSize: item.ironSize),
              child: isIron
                  ? Stack(
                      children: [
                        const SizedBox.expand(),
                        if (item.type == _EquipmentType.ironHorizontal || item.type == _EquipmentType.ironVertical)
                          Positioned.fill(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(.65),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFCDA56A).withOpacity(.45)),
                                ),
                                child: Text(
                                  '${((item.type == _EquipmentType.ironVertical ? item.height : item.width) / 6).toStringAsFixed(0)} ft • ${item.ironSize}"',
                                  style: const TextStyle(color: Color(0xFFCDA56A), fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        if (item.type.isIron && item.type != _EquipmentType.ironHorizontal && item.type != _EquipmentType.ironVertical)
                          Positioned.fill(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(.65),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFCDA56A).withOpacity(.45)),
                                ),
                                child: Text('${item.ironSize}"', style: const TextStyle(color: Color(0xFFCDA56A), fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.all(7),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(item.type.icon, color: const Color(0xFFCDA56A), size: 22),
                        const SizedBox(height: 2),
                        Text(item.displayLabel, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                        if (item.primaryPropertyLabel.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(item.primaryPropertyLabel, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFCDA56A), fontSize: 9, fontWeight: FontWeight.w700)),
                        ],
                      ]),
                    ),
            ),
          ),
          if (item.locked)
            const Positioned(
              right: 4,
              top: 4,
              child: Icon(Icons.lock, size: 14, color: Color(0xFFCDA56A)),
            ),
        ],
      ),
    );
  }
}


class _IronStretchHandle extends StatelessWidget {
  final _LayoutItem item;
  final bool leading;
  final VoidCallback onPanStart;
  final ValueChanged<DragUpdateDetails> onPanUpdate;
  final VoidCallback onPanEnd;

  const _IronStretchHandle({
    required this.item,
    required this.leading,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    final isHorizontal = item.type == _EquipmentType.ironHorizontal;
    final left = isHorizontal ? (leading ? -9.0 : item.width - 9.0) : (item.width / 2) - 9.0;
    final top = isHorizontal ? (item.height / 2) - 9.0 : (leading ? -9.0 : item.height - 9.0);

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => onPanStart(),
        onPanUpdate: onPanUpdate,
        onPanEnd: (_) => onPanEnd(),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFFFFC857),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.35), blurRadius: 5)],
          ),
          child: Icon(isHorizontal ? Icons.drag_handle : Icons.unfold_more, size: 12, color: Colors.black),
        ),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  final _EquipmentType type;
  final int turns;
  final String ironSize;

  _ShapePainter(this.type, {this.turns = 0, this.ironSize = '3'});

  @override
  void paint(Canvas canvas, Size size) {
    final accent = Paint()
      ..color = const Color(0xFFCDA56A).withOpacity(.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final strokeWidth = ironSize == '2' ? 5.5 : (ironSize == '4' ? 9.0 : 7.0);
    final iron = Paint()
      ..color = const Color(0xFFD7D7D7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    final shadow = Paint()
      ..color = Colors.black.withOpacity(.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 4
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;

    if (turns % 4 != 0) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate((turns % 4) * 1.57079632679);
      canvas.translate(-size.width / 2, -size.height / 2);
    }

    void drawIron(Path p) {
      canvas.drawPath(p, shadow);
      canvas.drawPath(p, iron);
    }

    if (type == _EquipmentType.ironHorizontal) {
      final p = Path()..moveTo(size.width * .08, size.height * .5)..lineTo(size.width * .92, size.height * .5);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.ironVertical) {
      final p = Path()..moveTo(size.width * .5, size.height * .08)..lineTo(size.width * .5, size.height * .92);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.elbowUpRight) {
      final p = Path()..moveTo(size.width * .5, size.height * .92)..lineTo(size.width * .5, size.height * .5)..lineTo(size.width * .92, size.height * .5);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.elbowRightDown) {
      final p = Path()..moveTo(size.width * .08, size.height * .5)..lineTo(size.width * .5, size.height * .5)..lineTo(size.width * .5, size.height * .92);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.elbowDownLeft) {
      final p = Path()..moveTo(size.width * .5, size.height * .08)..lineTo(size.width * .5, size.height * .5)..lineTo(size.width * .08, size.height * .5);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.elbowLeftUp) {
      final p = Path()..moveTo(size.width * .92, size.height * .5)..lineTo(size.width * .5, size.height * .5)..lineTo(size.width * .5, size.height * .08);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.teeUp) {
      final p = Path()..moveTo(size.width * .08, size.height * .5)..lineTo(size.width * .92, size.height * .5)..moveTo(size.width * .5, size.height * .5)..lineTo(size.width * .5, size.height * .08);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.teeRight) {
      final p = Path()..moveTo(size.width * .5, size.height * .08)..lineTo(size.width * .5, size.height * .92)..moveTo(size.width * .5, size.height * .5)..lineTo(size.width * .92, size.height * .5);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.teeDown) {
      final p = Path()..moveTo(size.width * .08, size.height * .5)..lineTo(size.width * .92, size.height * .5)..moveTo(size.width * .5, size.height * .5)..lineTo(size.width * .5, size.height * .92);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.teeLeft) {
      final p = Path()..moveTo(size.width * .5, size.height * .08)..lineTo(size.width * .5, size.height * .92)..moveTo(size.width * .5, size.height * .5)..lineTo(size.width * .08, size.height * .5);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.bypass) {
      // Simple field-style bypass: two tees off the main iron,
      // straight branch legs to equipment inlet/outlet, no loop.
      final y1 = size.height * .36;
      final y2 = size.height * .64;
      final mainX = size.width * .14;
      final eqX = size.width * .88;
      final p = Path()
        ..moveTo(mainX, y1)..lineTo(eqX, y1)
        ..moveTo(mainX, y2)..lineTo(eqX, y2)
        // main iron/header side shown through both tees
        ..moveTo(mainX, size.height * .18)..lineTo(mainX, size.height * .82)
        // equipment side shows the two ends that land on equipment inlet/outlet
        ..moveTo(eqX, y1 - 10)..lineTo(eqX, y1 + 10)
        ..moveTo(eqX, y2 - 10)..lineTo(eqX, y2 + 10);
      drawIron(p);

      final fitting = Paint()
        ..color = const Color(0xFFCDA56A)
        ..style = PaintingStyle.fill;
      final border = Paint()
        ..color = Colors.black.withOpacity(.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      void block(double x, double y) {
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y), width: 14, height: 14), const Radius.circular(3));
        canvas.drawRRect(r, fitting);
        canvas.drawRRect(r, border);
      }
      block(mainX, y1);
      block(mainX, y2);
      block(eqX, y1);
      block(eqX, y2);
      return;
    }

    if (type == _EquipmentType.wellhead) {
      canvas.drawCircle(Offset(size.width * .5, size.height * .5), size.shortestSide * .22, accent);
      canvas.drawLine(Offset(size.width * .5, size.height * .18), Offset(size.width * .5, size.height * .82), accent);
      canvas.drawLine(Offset(size.width * .2, size.height * .5), Offset(size.width * .8, size.height * .5), accent);
    } else if (type == _EquipmentType.esdValve) {
      canvas.drawLine(Offset(size.width * .16, size.height * .5), Offset(size.width * .84, size.height * .5), accent);
      canvas.drawCircle(Offset(size.width * .5, size.height * .5), size.shortestSide * .18, accent);
      canvas.drawLine(Offset(size.width * .4, size.height * .38), Offset(size.width * .6, size.height * .62), accent);
      canvas.drawLine(Offset(size.width * .6, size.height * .38), Offset(size.width * .4, size.height * .62), accent);
    } else if (type == _EquipmentType.lineHeater) {
      final rect = Rect.fromLTWH(size.width * .16, size.height * .25, size.width * .68, size.height * .5);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)), accent);
      final flame = Path()
        ..moveTo(size.width * .5, size.height * .68)
        ..cubicTo(size.width * .35, size.height * .55, size.width * .48, size.height * .44, size.width * .45, size.height * .32)
        ..cubicTo(size.width * .62, size.height * .43, size.width * .68, size.height * .54, size.width * .5, size.height * .68);
      canvas.drawPath(flame, accent);
    } else if (type == _EquipmentType.flowbackTank || type == _EquipmentType.productionTank) {
      final rect = Rect.fromLTWH(size.width * .18, size.height * .16, size.width * .64, size.height * .68);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)), accent);
      canvas.drawLine(Offset(size.width * .25, size.height * .28), Offset(size.width * .75, size.height * .28), accent);
      canvas.drawLine(Offset(size.width * .25, size.height * .72), Offset(size.width * .75, size.height * .72), accent);
    } else if (type == _EquipmentType.chokeManifold) {
      canvas.drawLine(Offset(size.width * .18, size.height * .5), Offset(size.width * .82, size.height * .5), accent);
      canvas.drawCircle(Offset(size.width * .38, size.height * .5), 7, accent);
      canvas.drawCircle(Offset(size.width * .62, size.height * .5), 7, accent);
    } else if (type == _EquipmentType.plugCatcher) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * .15, size.height * .28, size.width * .7, size.height * .44), const Radius.circular(8)), accent);
      canvas.drawLine(Offset(size.width * .25, size.height * .35), Offset(size.width * .75, size.height * .65), accent);
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePainter oldDelegate) => oldDelegate.type != type || oldDelegate.turns != turns || oldDelegate.ironSize != ironSize;
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(.045)
      ..strokeWidth = 1;
    const spacing = 24.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
