// ignore_for_file: unused_element, curly_braces_in_flow_control_structures, prefer_const_constructors, deprecated_member_use, unnecessary_brace_in_string_interps

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/job_setup.dart';
import '../services/job_storage_service.dart';
import '../services/recovery_state_service.dart';
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
  String _drawIronSize = '3';
  Offset? _ironStartPoint;
  final List<String> _undoStack = <String>[];
  final List<String> _redoStack = <String>[];
  final List<String> _historyLog = <String>[];
  static const int _maxHistory = 40;
  int _nextId = 1;
  bool _snapToGrid = true;
  bool _measureMode = false;
  bool _showEquipment = true;
  bool _showIron = true;
  bool _showLabels = true;
  bool _showGrid = true;
  Offset? _measurementStart;
  Offset? _measurementEnd;
  static const double _dragStartThreshold = 2.0;
  static const double _virtualCanvasMultiplier = 5.0;
  final TransformationController _canvasTransform = TransformationController();
  final GlobalKey _canvasViewportKey = GlobalKey();
  Size _viewportSize = Size.zero;
  _DrawerLibrarySection _mobileDrawerSection = _DrawerLibrarySection.equipment;
  Offset? _dragSceneStart;
  bool _dragActive = false;
  int? _snapCandidateIronId;
  Offset? _snapIndicatorScene;
  final Map<int, Offset> _dragItemStart = <int, Offset>{};
  final _layoutName = TextEditingController(text: 'New Layout');
  final _company = TextEditingController();
  final _jobLocation = TextEditingController();
  final GlobalKey _exportImageKey = GlobalKey();
  final _date = TextEditingController(
    text: DateTime.now().toLocal().toString().split(' ')[0],
  );
  final _preparedBy = TextEditingController();
  final _notes = TextEditingController();
  bool _showSideLibrary = false;
  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();
  JobSetup? _activeJob;

  static const _gold = Color(0xFFCDA56A);
  static const _bg = Color(0xFF101113);

  @override
  void initState() {
    super.initState();
    _recoveryState.saveLastModule(RecoveryModules.layoutDesigner);
    _loadLayout();
  }

  @override
  void dispose() {
    _canvasTransform.dispose();
    _layoutName.dispose();
    _company.dispose();
    _jobLocation.dispose();
    _date.dispose();
    _preparedBy.dispose();
    _notes.dispose();
    super.dispose();
  }

  double _snap(double v) => _snapToGrid ? (v / 24).round() * 24.0 : v;

  Size get _virtualCanvasSize {
    final viewportWidth = _viewportSize.width > 0 ? _viewportSize.width : 400.0;
    final viewportHeight =
        _viewportSize.height > 0 ? _viewportSize.height : 760.0;
    return Size(
      math.max(2200.0, viewportWidth * _virtualCanvasMultiplier),
      math.max(3200.0, viewportHeight * _virtualCanvasMultiplier),
    );
  }

  Offset _scenePointFromViewport(Offset viewportPoint) {
    return _canvasTransform.toScene(viewportPoint);
  }

  Offset _scenePointFromGlobal(Offset globalPoint) {
    final context = _canvasViewportKey.currentContext;
    if (context == null) return globalPoint;
    final box = context.findRenderObject();
    if (box is! RenderBox) return globalPoint;
    final viewportPoint = box.globalToLocal(globalPoint);
    return _scenePointFromViewport(viewportPoint);
  }

  Offset _clampToCanvas(Offset point) {
    final canvasSize = _virtualCanvasSize;
    return Offset(
      point.dx.clamp(0.0, canvasSize.width),
      point.dy.clamp(0.0, canvasSize.height),
    );
  }

  Offset _viewportCenterOnCanvas() {
    if (_viewportSize.width <= 0 || _viewportSize.height <= 0) {
      return const Offset(180, 180);
    }
    final viewportCenter =
        Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    return _clampToCanvas(_scenePointFromViewport(viewportCenter));
  }

  void _setViewportSize(Size size) {
    final widthDelta = (_viewportSize.width - size.width).abs();
    final heightDelta = (_viewportSize.height - size.height).abs();
    if (widthDelta < 1 && heightDelta < 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _viewportSize = size);
    });
  }

  void _openEquipmentDrawer(
      {_DrawerLibrarySection section = _DrawerLibrarySection.equipment}) {
    setState(() {
      _showSideLibrary = true;
      _mobileDrawerSection = section;
    });
  }

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

  void _appendHistoryEntry(String entry) {
    if (_historyLog.isEmpty || _historyLog.last != entry) {
      _historyLog.add(entry);
      if (_historyLog.length > 12) {
        _historyLog.removeAt(0);
      }
    }
  }

  bool _itemIsVisible(_LayoutItem item) {
    if (item.type.isIron) return _showIron;
    return _showEquipment;
  }

  bool _isStraightIronType(_EquipmentType type) {
    return type == _EquipmentType.ironHorizontal ||
        type == _EquipmentType.ironVertical;
  }

  bool _isFittingType(_EquipmentType type) {
    return type == _EquipmentType.bypass ||
        type == _EquipmentType.esdValve ||
        type.name.startsWith('elbow') ||
        type.name.startsWith('tee');
  }

  _LayoutItem? _findItemById(int id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  _SnapCandidate? _nearestSnapCandidate(
      _LayoutItem fitting, Offset desiredTopLeft) {
    final center = Offset(desiredTopLeft.dx + fitting.width / 2,
        desiredTopLeft.dy + fitting.height / 2);
    const snapThreshold = 34.0;
    _SnapCandidate? best;

    for (final iron in _items) {
      if (iron.id == fitting.id || !_isStraightIronType(iron.type)) continue;
      final isHorizontal = iron.type == _EquipmentType.ironHorizontal;
      final lineCenter = isHorizontal
          ? Offset(center.dx.clamp(iron.x, iron.x + iron.width),
              iron.y + iron.height / 2)
          : Offset(iron.x + iron.width / 2,
              center.dy.clamp(iron.y, iron.y + iron.height));

      final orthogonalDistance = isHorizontal
          ? (center.dy - lineCenter.dy).abs()
          : (center.dx - lineCenter.dx).abs();
      final alongOverflow = isHorizontal
          ? (center.dx < iron.x
              ? iron.x - center.dx
              : (center.dx > iron.x + iron.width
                  ? center.dx - (iron.x + iron.width)
                  : 0.0))
          : (center.dy < iron.y
              ? iron.y - center.dy
              : (center.dy > iron.y + iron.height
                  ? center.dy - (iron.y + iron.height)
                  : 0.0));

      if (orthogonalDistance > snapThreshold || alongOverflow > 72.0) continue;

      final score = orthogonalDistance + (alongOverflow * 0.35);

      if (best == null || score < best.score) {
        best = _SnapCandidate(
          ironId: iron.id,
          horizontal: isHorizontal,
          indicator: lineCenter,
          score: score,
        );
      }
    }

    return best;
  }

  Offset _applySnapToSpecificIron(_LayoutItem fitting, _LayoutItem iron,
      {required Offset desiredTopLeft}) {
    final canvasSize = _virtualCanvasSize;
    final center = Offset(desiredTopLeft.dx + fitting.width / 2,
        desiredTopLeft.dy + fitting.height / 2);

    if (iron.type == _EquipmentType.ironHorizontal) {
      final centerX = center.dx.clamp(iron.x, iron.x + iron.width);
      final x = (centerX - fitting.width / 2)
          .clamp(0.0, canvasSize.width - fitting.width)
          .toDouble();
      final y = (iron.y + (iron.height / 2) - (fitting.height / 2))
          .clamp(0.0, canvasSize.height - fitting.height)
          .toDouble();
      return Offset(x, y);
    }

    final centerY = center.dy.clamp(iron.y, iron.y + iron.height);
    final x = (iron.x + (iron.width / 2) - (fitting.width / 2))
        .clamp(0.0, canvasSize.width - fitting.width)
        .toDouble();
    final y = (centerY - fitting.height / 2)
        .clamp(0.0, canvasSize.height - fitting.height)
        .toDouble();
    return Offset(x, y);
  }

  Offset _resolveFittingPlacement(_LayoutItem fitting, Offset desiredTopLeft,
      {required bool allowNewSnap}) {
    final canvasSize = _virtualCanvasSize;

    final attachedIronId = int.tryParse(fitting.properties['snapIronId'] ?? '');
    final attachedIron =
        attachedIronId == null ? null : _findItemById(attachedIronId);
    if (attachedIron != null && _isStraightIronType(attachedIron.type)) {
      final aligned = _applySnapToSpecificIron(fitting, attachedIron,
          desiredTopLeft: desiredTopLeft);
      _snapCandidateIronId = attachedIron.id;
      _snapIndicatorScene = Offset(
        attachedIron.type == _EquipmentType.ironHorizontal
            ? (aligned.dx + fitting.width / 2)
            : (attachedIron.x + attachedIron.width / 2),
        attachedIron.type == _EquipmentType.ironHorizontal
            ? (attachedIron.y + attachedIron.height / 2)
            : (aligned.dy + fitting.height / 2),
      );
      return aligned;
    }

    if (!allowNewSnap) {
      _snapCandidateIronId = null;
      _snapIndicatorScene = null;
      return Offset(
        desiredTopLeft.dx.clamp(0.0, canvasSize.width - fitting.width),
        desiredTopLeft.dy.clamp(0.0, canvasSize.height - fitting.height),
      );
    }

    final candidate = _nearestSnapCandidate(fitting, desiredTopLeft);
    if (candidate == null) {
      fitting.properties.remove('snapIronId');
      fitting.properties.remove('snapAxis');
      _snapCandidateIronId = null;
      _snapIndicatorScene = null;
      return Offset(
        desiredTopLeft.dx.clamp(0.0, canvasSize.width - fitting.width),
        desiredTopLeft.dy.clamp(0.0, canvasSize.height - fitting.height),
      );
    }

    fitting.properties['snapIronId'] = candidate.ironId.toString();
    fitting.properties['snapAxis'] =
        candidate.horizontal ? 'horizontal' : 'vertical';
    _snapCandidateIronId = candidate.ironId;
    _snapIndicatorScene = candidate.indicator;

    final iron = _findItemById(candidate.ironId);
    if (iron == null) {
      return Offset(
        desiredTopLeft.dx.clamp(0.0, canvasSize.width - fitting.width),
        desiredTopLeft.dy.clamp(0.0, canvasSize.height - fitting.height),
      );
    }
    return _applySnapToSpecificIron(fitting, iron,
        desiredTopLeft: desiredTopLeft);
  }

  void _reflowSnappedFittings() {
    for (final item in _items) {
      if (!_isFittingType(item.type)) continue;
      final ironId = int.tryParse(item.properties['snapIronId'] ?? '');
      if (ironId == null) continue;
      final iron = _findItemById(ironId);
      if (iron == null || !_isStraightIronType(iron.type)) {
        item.properties.remove('snapIronId');
        item.properties.remove('snapAxis');
        continue;
      }

      final aligned = _applySnapToSpecificIron(item, iron,
          desiredTopLeft: Offset(item.x, item.y));
      item.x = aligned.dx;
      item.y = aligned.dy;
    }
  }

  List<_LayoutItem> get _visibleItems => _items.where(_itemIsVisible).toList();

  void _toggleMeasurementMode() {
    setState(() {
      _measureMode = !_measureMode;
      if (!_measureMode) {
        _measurementStart = null;
        _measurementEnd = null;
      }
    });
  }

  void _clearMeasurement() {
    setState(() {
      _measurementStart = null;
      _measurementEnd = null;
    });
  }

  void _beginItemDrag(_LayoutItem anchor, DragStartDetails details) {
    final moving = _selectedIds.contains(anchor.id) ? _selectedItems : [anchor];
    if (moving.every((it) => it.locked)) return;
    _dragSceneStart = _scenePointFromGlobal(details.globalPosition);
    _dragActive = false;
    _dragItemStart
      ..clear()
      ..addEntries(moving.map((it) => MapEntry(it.id, Offset(it.x, it.y))));
  }

  void _updateItemDrag(_LayoutItem anchor, DragUpdateDetails details) {
    final moving = _selectedIds.contains(anchor.id) ? _selectedItems : [anchor];
    if (moving.every((it) => it.locked)) return;

    final start = _dragSceneStart;
    if (start == null) return;
    final scenePoint = _scenePointFromGlobal(details.globalPosition);
    final delta = scenePoint - start;

    if (!_dragActive && delta.distance < _dragStartThreshold) {
      return;
    }

    if (!_dragActive) {
      _recordUndo();
      _dragActive = true;
    }

    setState(() {
      final canvasSize = _virtualCanvasSize;
      _snapCandidateIronId = null;
      _snapIndicatorScene = null;
      for (final it in moving) {
        if (it.locked) continue;
        final origin = _dragItemStart[it.id] ?? Offset(it.x, it.y);
        final desired = Offset(origin.dx + delta.dx, origin.dy + delta.dy);
        if (_isFittingType(it.type)) {
          final placed =
              _resolveFittingPlacement(it, desired, allowNewSnap: true);
          it.x = placed.dx;
          it.y = placed.dy;
        } else {
          it.x = desired.dx.clamp(0.0, canvasSize.width - it.width);
          it.y = desired.dy.clamp(0.0, canvasSize.height - it.height);
        }
      }
      _reflowSnappedFittings();
    });
  }

  void _endItemDrag(_LayoutItem anchor) {
    final moving = _selectedIds.contains(anchor.id) ? _selectedItems : [anchor];
    if (moving.every((it) => it.locked)) {
      _dragSceneStart = null;
      _dragItemStart.clear();
      _dragActive = false;
      return;
    }

    if (_dragActive && _snapToGrid) {
      setState(() {
        final canvasSize = _virtualCanvasSize;
        for (final it in moving) {
          if (it.locked) continue;
          if (_isFittingType(it.type) && it.properties['snapIronId'] != null) {
            continue;
          }
          it.x = _snap(it.x).clamp(0.0, canvasSize.width - it.width);
          it.y = _snap(it.y).clamp(0.0, canvasSize.height - it.height);
        }
        _reflowSnappedFittings();
      });
    }

    _dragSceneStart = null;
    _dragItemStart.clear();
    _dragActive = false;
    if (_snapCandidateIronId != null || _snapIndicatorScene != null) {
      setState(() {
        _snapCandidateIronId = null;
        _snapIndicatorScene = null;
      });
    }
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
    return item != null &&
        (item.type == _EquipmentType.ironHorizontal ||
            item.type == _EquipmentType.ironVertical);
  }

  bool get _selectedIsIron {
    final item = _selectedItem;
    return item != null && item.type.isIron;
  }

  double _ironLengthFeet(_LayoutItem item) {
    final pixels =
        item.type == _EquipmentType.ironVertical ? item.height : item.width;
    return (pixels / 6).clamp(1, 200).toDouble();
  }

  Future<void> _setSelectedIronLength() async {
    final item = _selectedItem;
    if (item == null ||
        !(item.type == _EquipmentType.ironHorizontal ||
            item.type == _EquipmentType.ironVertical)) return;

    final controller =
        TextEditingController(text: _ironLengthFeet(item).toStringAsFixed(0));
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
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text.trim())),
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
    if (item == null ||
        !(item.type == _EquipmentType.ironHorizontal ||
            item.type == _EquipmentType.ironVertical)) return;
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

  void _stretchStraightIron(
      _LayoutItem item, DragUpdateDetails details, bool leading) {
    if (item.locked ||
        !(item.type == _EquipmentType.ironHorizontal ||
            item.type == _EquipmentType.ironVertical)) return;
    final canvasSize = _virtualCanvasSize;
    setState(() {
      if (item.type == _EquipmentType.ironHorizontal) {
        if (leading) {
          final newX = (item.x + details.delta.dx)
              .clamp(0.0, item.x + item.width - 36.0);
          item.width = item.width + (item.x - newX);
          item.x = newX;
        } else {
          item.width = (item.width + details.delta.dx)
              .clamp(36.0, canvasSize.width - item.x);
        }
      } else {
        if (leading) {
          final newY = (item.y + details.delta.dy)
              .clamp(0.0, item.y + item.height - 36.0);
          item.height = item.height + (item.y - newY);
          item.y = newY;
        } else {
          item.height = (item.height + details.delta.dy)
              .clamp(36.0, canvasSize.height - item.y);
        }
      }
      _reflowSnappedFittings();
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

  void _finishIronDrawing() {
    if (!_drawIronMode) return;
    setState(() {
      _drawIronMode = false;
      _ironStartPoint = null;
    });
  }

  void _cancelIronDrawing() {
    if (!_drawIronMode) return;
    setState(() {
      _drawIronMode = false;
      _ironStartPoint = null;
    });
  }

  void _handleCanvasTap(Offset point) {
    final clampedPoint = _clampToCanvas(point);

    if (_measureMode) {
      setState(() {
        if (_measurementStart == null || _measurementEnd != null) {
          _measurementStart = clampedPoint;
          _measurementEnd = null;
        } else {
          _measurementEnd = clampedPoint;
        }
      });
      return;
    }

    if (!_drawIronMode) return;
    final canvasSize = _virtualCanvasSize;
    final snappedPoint = Offset(
      _snap(clampedPoint.dx).clamp(0.0, canvasSize.width),
      _snap(clampedPoint.dy).clamp(0.0, canvasSize.height),
    );

    final start = _ironStartPoint;
    if (start == null) {
      setState(() => _ironStartPoint = snappedPoint);
      return;
    }

    final dx = snappedPoint.dx - start.dx;
    final dy = snappedPoint.dy - start.dy;
    if (dx.abs() < 12 && dy.abs() < 12) return;

    final horizontal = dx.abs() >= dy.abs();
    final type = horizontal
        ? _EquipmentType.ironHorizontal
        : _EquipmentType.ironVertical;
    final width = horizontal
        ? dx.abs().clamp(36.0, 1200.0).toDouble()
        : type.defaultWidth;
    final height = horizontal
        ? type.defaultHeight
        : dy.abs().clamp(36.0, 1200.0).toDouble();
    final x = horizontal
        ? (dx >= 0 ? start.dx : snappedPoint.dx)
        : start.dx - width / 2;
    final y = horizontal
        ? start.dy - height / 2
        : (dy >= 0 ? start.dy : snappedPoint.dy);

    _recordUndo();
    setState(() {
      final id = _nextId++;
      _items.add(_LayoutItem(
        id: id,
        type: type,
        x: _snap(x).clamp(0.0, canvasSize.width - width),
        y: _snap(y).clamp(0.0, canvasSize.height - height),
        width: width,
        height: height,
        properties: <String, String>{'ironSize': _drawIronSize},
      ));
      _selectedId = id;
      _selectedIds
        ..clear()
        ..add(id);
      _ironStartPoint = snappedPoint;
    });
    _appendHistoryEntry(type.isIron ? 'Added iron' : 'Added equipment');
  }

  void _addItem(_EquipmentType type) {
    final center = _viewportCenterOnCanvas();
    final spread = (_items.length % 6) * 18.0;
    _runHistoryChange(() {
      final id = _nextId++;
      final rawX = center.dx - type.defaultWidth / 2 + spread;
      final rawY = center.dy - type.defaultHeight / 2 + spread;
      final canvasSize = _virtualCanvasSize;
      _items.add(_LayoutItem(
        id: id,
        type: type,
        x: _snap(rawX).clamp(0.0, canvasSize.width - type.defaultWidth),
        y: _snap(rawY).clamp(0.0, canvasSize.height - type.defaultHeight),
        width: type.defaultWidth,
        height: type.defaultHeight,
      ));
      _selectedId = id;
      _selectedIds
        ..clear()
        ..add(id);
    });
    _appendHistoryEntry(type.isIron ? 'Added iron' : 'Added equipment');
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
      _reflowSnappedFittings();
      _selectedId = null;
      _selectedIds.clear();
    });
    _appendHistoryEntry(
      _items.any((item) => item.type.isIron)
          ? 'Removed iron'
          : 'Deleted equipment',
    );
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
          x: _snap(original.x + 42),
          y: _snap(original.y + 42),
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
    _appendHistoryEntry('Duplicated equipment');
  }

  void _duplicateSingleForQuickDrag(_LayoutItem item) {
    _runHistoryChange(() {
      final newId = _nextId++;
      _items.add(_LayoutItem(
        id: newId,
        type: item.type,
        x: _snap(item.x + 42),
        y: _snap(item.y + 42),
        width: item.width,
        height: item.height,
        properties: Map<String, String>.from(item.properties),
        rotationTurns: item.rotationTurns,
        locked: false,
      ));
      _selectedIds
        ..clear()
        ..add(newId);
      _selectedId = newId;
    });
    _appendHistoryEntry('Duplicated equipment');
  }

  Future<void> _confirmClearLayout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Layout?'),
        content: const Text(
            'This will remove all equipment, iron, and manual layout items from the current rig-up.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true) return;

    _runHistoryChange(() {
      _items.clear();
      _selectedId = null;
      _selectedIds.clear();
      _nextId = 1;
    });
  }

  Map<String, dynamic> _inventorySnapshot() {
    final counts = <String, int>{};
    var totalIronFeet = 0.0;

    for (final item in _items) {
      String key;
      if (item.type == _EquipmentType.ironHorizontal ||
          item.type == _EquipmentType.ironVertical) {
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

    return {
      'counts': counts,
      'totalStraightIronFeet': totalIronFeet,
    };
  }

  Map<String, dynamic> _payload() => {
        'name': _layoutName.text.trim().isEmpty
            ? 'New Layout'
            : _layoutName.text.trim(),
        'activeJobId': _activeJob?.id ?? '',
        'company': _company.text.trim(),
        'padName': _jobLocation.text.trim(),
        'wellName': _jobLocation.text.trim(),
        'date': _date.text.trim(),
        'createdBy': _preparedBy.text.trim(),
        'preparedBy': _preparedBy.text.trim(),
        'notes': _notes.text.trim(),
        'nextId': _nextId,
        'snapToGrid': _snapToGrid,
        'items': _items.map((item) => item.toJson()).toList(),
        'metadata': {
          'version': 1,
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'inventory': _inventorySnapshot(),
        },
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
      _jobLocation.text = ((data['jobLocation'] as String?) ??
              (data['wellName'] as String?) ??
              (data['padName'] as String?) ??
              '')
          .toString();
      _date.text = data['date'] as String? ?? '';
      _preparedBy.text = ((data['preparedBy'] as String?) ??
              (data['createdBy'] as String?) ??
              '')
          .toString();
      _notes.text = data['notes'] as String? ?? '';
      _selectedId = null;
      _selectedIds.clear();
      _reflowSnappedFittings();
    });
  }

  Widget _activeJobBanner() {
    final activeJob = _activeJob;
    if (activeJob == null) {
      return const Card(
        margin: EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Active Job',
                style: TextStyle(
                  color: Color(0xFFCDA56A),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'No active job found. Start a job first so saved layout drawings can attach to the current job.',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Active Job',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              activeJob.company.trim().isEmpty
                  ? 'No company entered'
                  : activeJob.company,
              style: const TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.bold,
              ),
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

  Widget _jobChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFCDA56A).withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        '$label: ${value.trim().isEmpty ? 'Not entered' : value.trim()}',
        style:
            const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
      ),
    );
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

  Future<Map<String, dynamic>> _savedRigUps(SharedPreferences prefs) async {
    final raw = prefs.getString('wellwerks_rigups_v1');
    if (raw == null || raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveLayout() async => _saveLayoutInternal();

  Future<void> _saveLayoutInternal() async {
    final prefs = await SharedPreferences.getInstance();
    final name = _layoutName.text.trim().isEmpty
        ? 'New Layout'
        : _layoutName.text.trim();
    final layouts = await _savedLayouts(prefs);
    final payload = _payload();
    layouts[name] = payload;
    await prefs.setString('wellwerks_saved_layouts_v1', jsonEncode(layouts));
    await prefs.setString('wellwerks_layout_designer_v2', jsonEncode(payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Layout saved: $name')));
  }

  Future<Map<String, dynamic>> _savedFavorites(SharedPreferences prefs) async {
    final raw = prefs.getString('wellwerks_favorites_v1');
    if (raw == null || raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveFavoriteAssembly() async {
    final selected = _selectedItems;
    if (selected.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Select equipment first to save a favorite.')),
      );
      return;
    }

    final controller = TextEditingController(
        text: 'Favorite ${DateTime.now().month}/${DateTime.now().day}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Favorite Assembly'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Favorite Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    final favoriteName = controller.text.trim();
    controller.dispose();
    if (saved != true) return;

    final prefs = await SharedPreferences.getInstance();
    final favorites = await _savedFavorites(prefs);
    final name = favoriteName.isEmpty
        ? 'Favorite ${DateTime.now().millisecondsSinceEpoch}'
        : favoriteName;
    favorites[name] = {
      'items': selected.map((item) => item.toJson()).toList(),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    await prefs.setString('wellwerks_favorites_v1', jsonEncode(favorites));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved favorite: $name')),
    );
  }

  Future<void> _showFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = await _savedFavorites(prefs);
    if (!mounted) return;
    if (favorites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No favorites saved yet.')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Favorites'),
        content: SizedBox(
          width: _dialogWidth(context, max: 420),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: favorites.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final name = favorites.keys.elementAt(index);
              final payload = favorites[name];
              final items =
                  (payload as Map<String, dynamic>?)?['items'] as List? ??
                      const [];
              return ListTile(
                leading: const Icon(Icons.star, color: Color(0xFFCDA56A)),
                title: Text(name),
                subtitle: Text('${items.length} items'),
                onTap: () {
                  Navigator.pop(context);
                  _insertFavoriteFromPayload(
                      name, payload as Map<String, dynamic>);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  void _insertFavoriteFromPayload(String name, Map<String, dynamic> payload) {
    final favoriteItems = (payload['items'] as List<dynamic>? ?? [])
        .map((item) => item as Map<String, dynamic>)
        .toList();
    if (favoriteItems.isEmpty) return;
    _runHistoryChange(() {
      final baseX = 36.0 + (_items.length % 6) * 24.0;
      final baseY = 36.0 + (_items.length % 5) * 24.0;
      final createdIds = <int>[];
      for (final raw in favoriteItems) {
        final item = _LayoutItem.fromJson(raw);
        final id = _nextId++;
        createdIds.add(id);
        _items.add(_LayoutItem(
          id: id,
          type: item.type,
          x: _snap(item.x + baseX),
          y: _snap(item.y + baseY),
          width: item.width,
          height: item.height,
          properties: Map<String, String>.from(item.properties),
          rotationTurns: item.rotationTurns,
          locked: false,
        ));
      }
      _selectedId = createdIds.isNotEmpty ? createdIds.last : null;
      _selectedIds
        ..clear()
        ..addAll(createdIds);
    });
    _appendHistoryEntry(
        favoriteItems.any((item) => (_LayoutItem.fromJson(item).type.isIron))
            ? 'Added iron'
            : 'Added equipment');
  }

  Future<void> _loadLayout() async {
    final activeJob = await _jobStorage.loadActiveJob();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('wellwerks_layout_designer_v2') ??
        prefs.getString('wellwerks_layout_designer_v1');
    _activeJob = activeJob;
    if (raw == null || raw.isEmpty) {
      if (!mounted || activeJob == null) return;
      setState(() {
        if (_company.text.trim().isEmpty) {
          _company.text = activeJob.company;
        }
        if (_jobLocation.text.trim().isEmpty) {
          _jobLocation.text = activeJob.padName.isNotEmpty
              ? activeJob.padName
              : activeJob.primaryWell;
        }
      });
      return;
    }
    try {
      _applyPayload(jsonDecode(raw) as Map<String, dynamic>);
      if (!mounted || activeJob == null) return;
      setState(() {
        if (_company.text.trim().isEmpty) {
          _company.text = activeJob.company;
        }
        if (_jobLocation.text.trim().isEmpty) {
          _jobLocation.text = activeJob.padName.isNotEmpty
              ? activeJob.padName
              : activeJob.primaryWell;
        }
      });
    } catch (_) {}
  }

  Future<void> _saveRigUp() async {
    final prefs = await SharedPreferences.getInstance();
    final name = _layoutName.text.trim().isEmpty
        ? 'New Rig-Up'
        : _layoutName.text.trim();
    final rigUps = await _savedRigUps(prefs);
    final payload = _payload();
    rigUps[name] = payload;
    await prefs.setString('wellwerks_rigups_v1', jsonEncode(rigUps));
    await prefs.setString('wellwerks_layout_designer_v2', jsonEncode(payload));
    _appendHistoryEntry('Saved rig-up');
    await prefs.setString(
        'wellwerks_saved_layouts_v1',
        jsonEncode({
          ...await _savedLayouts(prefs),
          name: payload,
        }));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Rig-Up saved: $name')));
  }

  Future<void> _showLoadRigUps() async {
    final prefs = await SharedPreferences.getInstance();
    final rigUps = await _savedRigUps(prefs);
    if (!mounted) return;
    if (rigUps.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No saved rig-ups yet')));
      return;
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Saved Rig-Ups',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          for (final name in rigUps.keys)
            Card(
              child: ListTile(
                leading: const Icon(Icons.tune),
                title: Text(name),
                subtitle: Text(
                    '${((rigUps[name] as Map)['items'] as List?)?.length ?? 0} items'),
                onTap: () {
                  _applyPayload(Map<String, dynamic>.from(rigUps[name] as Map));
                  _appendHistoryEntry('Loaded rig-up');
                  Navigator.pop(context);
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showLoadLayouts() async {
    final prefs = await SharedPreferences.getInstance();
    final layouts = await _savedLayouts(prefs);
    if (!mounted) return;
    if (layouts.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No saved layouts yet')));
      return;
    }
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Saved Layouts',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          for (final name in layouts.keys)
            Card(
              child: ListTile(
                leading: const Icon(Icons.folder_open),
                title: Text(name),
                subtitle: Text(
                    '${((layouts[name] as Map)['items'] as List?)?.length ?? 0} items'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    layouts.remove(name);
                    await prefs.setString(
                        'wellwerks_saved_layouts_v1', jsonEncode(layouts));
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
                onTap: () {
                  _applyPayload(
                      Map<String, dynamic>.from(layouts[name] as Map));
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

  double _dialogWidth(BuildContext context, {double max = 460}) {
    final available = MediaQuery.of(context).size.width - 48;
    return math.min(max, available.clamp(260.0, max));
  }

  Widget _toolbarSection(
    String title,
    List<Widget> actions, {
    required double width,
    int minRows = 1,
  }) {
    final sectionHeight = 74.0 + (minRows - 1) * 56.0;
    return Container(
      width: width,
      constraints: BoxConstraints(minHeight: sectionHeight),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF121417),
        border: Border.all(color: const Color(0xFF3A3A3A)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFCDA56A),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }

  ButtonStyle _compactFilledStyle({bool highlighted = false}) {
    return FilledButton.styleFrom(
      backgroundColor: highlighted ? _gold : const Color(0xFF1A1D21),
      foregroundColor: highlighted ? Colors.black : Colors.white,
      minimumSize: const Size(148, 46),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  ButtonStyle _compactOutlineStyle({bool highlighted = false}) {
    return OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(
        color: highlighted ? _gold : const Color(0xFF4A4A4A),
        width: highlighted ? 1.4 : 1,
      ),
      minimumSize: const Size(148, 46),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Map<String, int> _equipmentSummary() {
    final summary = <String, int>{};
    for (final item in _items) {
      summary[item.type.label] = (summary[item.type.label] ?? 0) + 1;
    }
    return summary;
  }

  _BillOfMaterialsData _billOfMaterialsSummary() =>
      _billOfMaterialsSummaryForItems(_items);

  Future<void> _showBillOfMaterials() async {
    final summary = _billOfMaterialsSummary();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121417),
        titleTextStyle: const TextStyle(
          color: Color(0xFFCDA56A),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        title: const Text('Bill of Materials'),
        content: SizedBox(
          width: _dialogWidth(context, max: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Material counts for the current rig-up layout.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (_company.text.trim().isNotEmpty ||
                    _jobLocation.text.trim().isNotEmpty ||
                    _date.text.trim().isNotEmpty ||
                    _preparedBy.text.trim().isNotEmpty ||
                    _notes.text.trim().isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1D21),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF3A3A3A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Job Info',
                          style: TextStyle(
                            color: Color(0xFFCDA56A),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (_company.text.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'Company: ${_company.text.trim()}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                          ),
                        if (_jobLocation.text.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'Well / Pad Name: ${_jobLocation.text.trim()}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                          ),
                        if (_date.text.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'Date: ${_date.text.trim()}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                          ),
                        if (_preparedBy.text.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'Prepared By: ${_preparedBy.text.trim()}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                          ),
                        if (_notes.text.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'Notes: ${_notes.text.trim()}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _buildMaterialSection('Equipment', summary.categories),
                const SizedBox(height: 12),
                _buildMaterialSection('Iron by Size', summary.ironSizes),
                if (summary.customLabels.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Custom Labels',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...summary.customLabels.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          entry,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(backgroundColor: _gold),
            child: const Text('Close', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialSection(String title, Map<String, int> values) {
    final entries = values.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFCDA56A),
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1D21),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF3A3A3A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ),
                      Text(
                        entry.value.toString(),
                        style: const TextStyle(
                          color: Color(0xFFCDA56A),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showLayoutInfo() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Job Information'),
        content: SizedBox(
          width: _dialogWidth(context, max: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _company,
                  decoration: const InputDecoration(labelText: 'Company'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _jobLocation,
                  decoration:
                      const InputDecoration(labelText: 'Well / Pad Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _date,
                  decoration: const InputDecoration(labelText: 'Date'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _preparedBy,
                  decoration: const InputDecoration(labelText: 'Prepared By'),
                ),
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
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done')),
        ],
      ),
    );
    setState(() {});
  }

  Future<File?> _captureLayoutImageFile() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final boundary = _exportImageKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        if (!mounted) return null;
        messenger?.showSnackBar(
          const SnackBar(content: Text('Unable to capture the layout image.')),
        );
        return null;
      }

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (!mounted) return null;
        messenger?.showSnackBar(
          const SnackBar(content: Text('No image data was generated.')),
        );
        return null;
      }

      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/wellwerks_layout_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      return file;
    } catch (_) {
      if (!mounted) return null;
      messenger?.showSnackBar(
        const SnackBar(content: Text('Unable to share the layout image.')),
      );
      return null;
    }
  }

  Future<void> _saveLayoutImage() async {
    final file = await _captureLayoutImageFile();
    if (file == null || !mounted) return;
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'WellWerks Layout Image',
      text: 'Rig-Up layout exported from WellWerks.',
    );
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Layout image shared.')),
    );
  }

  Future<void> _shareRigUpPackage() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final layoutName = _layoutName.text.trim().isEmpty
          ? 'New Layout'
          : _layoutName.text.trim();
      final exportTime = DateTime.now().toLocal();
      final doc = pw.Document();
      final visibleItems = _visibleItems;
      final summary = <String, int>{};
      for (final item in visibleItems) {
        summary[item.type.label] = (summary[item.type.label] ?? 0) + 1;
      }
      final bom = _billOfMaterialsSummaryForItems(visibleItems);
      final plotBounds = _pdfPlotBounds(visibleItems);
      final drawScale =
          _pdfDrawScale(plotBounds, maxWidth: 420.0, maxHeight: 280.0);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(28),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: double.infinity,
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFF101113),
                  border: pw.Border.all(
                    color: const PdfColor.fromInt(0xFFCDA56A),
                    width: 1.2,
                  ),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(12)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'WellWerks',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFFCDA56A),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      layoutName,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Exported: ${exportTime.toString()}',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey300),
                    ),
                    if (_company.text.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Company: ${_company.text.trim()}',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey300),
                      ),
                    ],
                    if (_jobLocation.text.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Well / Pad Name: ${_jobLocation.text.trim()}',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey300),
                      ),
                    ],
                    if (_date.text.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Date: ${_date.text.trim()}',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey300),
                      ),
                    ],
                    if (_preparedBy.text.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Prepared By: ${_preparedBy.text.trim()}',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey300),
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 14),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Job Info',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFFCDA56A),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    if (_company.text.trim().isNotEmpty)
                      pw.Text(
                        'Company: ${_company.text.trim()}',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.black),
                      ),
                    if (_jobLocation.text.trim().isNotEmpty)
                      pw.Text(
                        'Well / Pad Name: ${_jobLocation.text.trim()}',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.black),
                      ),
                    if (_date.text.trim().isNotEmpty)
                      pw.Text(
                        'Date: ${_date.text.trim()}',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.black),
                      ),
                    if (_preparedBy.text.trim().isNotEmpty)
                      pw.Text(
                        'Prepared By: ${_preparedBy.text.trim()}',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.black),
                      ),
                    if (_notes.text.trim().isNotEmpty)
                      pw.Text(
                        'Notes: ${_notes.text.trim()}',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.black),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),
              pw.Text(
                'Layout Drawing',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFFCDA56A),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                width: double.infinity,
                height: 320,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFF121417),
                  border: pw.Border.all(color: PdfColors.grey700, width: 1),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Stack(
                  children: [
                    pw.Positioned.fill(
                      child: pw.Container(
                        decoration: pw.BoxDecoration(
                          color: const PdfColor.fromInt(0xFF121417),
                          borderRadius:
                              const pw.BorderRadius.all(pw.Radius.circular(8)),
                        ),
                      ),
                    ),
                    pw.Stack(
                      children: [
                        ..._pdfLayoutWidgets(
                          items: visibleItems,
                          scale: drawScale,
                          offsetX: 24,
                          offsetY: 24,
                          canvasWidth: 420,
                          canvasHeight: 280,
                        ),
                      ],
                    ),
                    if (visibleItems.isEmpty)
                      pw.Center(
                        child: pw.Text(
                          'No equipment added yet.',
                          style: const pw.TextStyle(
                              color: PdfColors.grey400, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),
              pw.Text(
                'Bill of Materials',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFFCDA56A),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    ...bom.categories.entries.map((entry) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 3),
                          child: pw.Text(
                            '${entry.key}: ${entry.value}',
                            style: const pw.TextStyle(
                                color: PdfColors.black, fontSize: 9),
                          ),
                        )),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Iron by Size',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFFCDA56A),
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    ...bom.ironSizes.entries.map((entry) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 3),
                          child: pw.Text(
                            '${entry.key}: ${entry.value}',
                            style: const pw.TextStyle(
                                color: PdfColors.black, fontSize: 9),
                          ),
                        )),
                    if (bom.customLabels.isNotEmpty) ...[
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Custom Labels',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFFCDA56A),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      ...bom.customLabels.map((entry) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 3),
                            child: pw.Text(
                              entry,
                              style: const pw.TextStyle(
                                  color: PdfColors.black, fontSize: 9),
                            ),
                          )),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 14),
              pw.Text(
                'Equipment Labels',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFFCDA56A),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (summary.isEmpty)
                      pw.Text('No equipment added.',
                          style: const pw.TextStyle(color: PdfColors.grey700))
                    else
                      ...summary.entries.map((entry) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 3),
                            child: pw.Text(
                              '${entry.key}: ${entry.value}',
                              style: const pw.TextStyle(
                                  color: PdfColors.black, fontSize: 10),
                            ),
                          )),
                    if (_notes.text.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Notes',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFFCDA56A),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        _notes.text.trim(),
                        style: const pw.TextStyle(
                            color: PdfColors.black, fontSize: 10),
                      ),
                    ],
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Item Details',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFFCDA56A),
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    ...visibleItems.map((item) {
                      final label = item.displayLabel;
                      final detail = item.primaryPropertyLabel.isNotEmpty
                          ? ' • ${item.primaryPropertyLabel}'
                          : '';
                      final sizeText =
                          item.type.isIron ? ' • ${item.ironSize}"' : '';
                      return pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3),
                        child: pw.Text(
                          '$label$detail$sizeText',
                          style: const pw.TextStyle(
                              color: PdfColors.black, fontSize: 9),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      final pdfDirectory = await getTemporaryDirectory();
      final pdfFile = File(
        '${pdfDirectory.path}/wellwerks_rigup_package_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await pdfFile.writeAsBytes(await doc.save());

      final imageFile = await _captureLayoutImageFile();
      final files = <XFile>[XFile(pdfFile.path)];
      if (imageFile != null) {
        files.add(XFile(imageFile.path));
      }

      await Share.shareXFiles(
        files,
        subject: 'WellWerks Rig-Up Package',
        text:
            'Rig-Up package exported from WellWerks with PDF and image attachments.',
      );
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(content: Text('Rig-Up package shared.')),
      );
    } catch (_) {
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(content: Text('Unable to share the rig-up package.')),
      );
    }
  }

  Future<void> _exportPdf() async {
    final layoutName = _layoutName.text.trim().isEmpty
        ? 'New Layout'
        : _layoutName.text.trim();
    final exportTime = DateTime.now().toLocal();
    final doc = pw.Document();

    final visibleItems = _visibleItems;
    final summary = <String, int>{};
    for (final item in visibleItems) {
      summary[item.type.label] = (summary[item.type.label] ?? 0) + 1;
    }
    final bom = _billOfMaterialsSummaryForItems(visibleItems);
    final plotBounds = _pdfPlotBounds(visibleItems);
    final drawScale =
        _pdfDrawScale(plotBounds, maxWidth: 420.0, maxHeight: 280.0);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFF101113),
                border: pw.Border.all(
                  color: const PdfColor.fromInt(0xFFCDA56A),
                  width: 1.2,
                ),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'WellWerks',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFFCDA56A),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    layoutName,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Exported: ${exportTime.toString()}',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey300),
                  ),
                  if (_company.text.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Company: ${_company.text.trim()}',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey300),
                    ),
                  ],
                  if (_jobLocation.text.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Well / Pad Name: ${_jobLocation.text.trim()}',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey300),
                    ),
                  ],
                  if (_date.text.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Date: ${_date.text.trim()}',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey300),
                    ),
                  ],
                  if (_preparedBy.text.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Prepared By: ${_preparedBy.text.trim()}',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey300),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Job Info',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFFCDA56A),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  if (_company.text.trim().isNotEmpty)
                    pw.Text(
                      'Company: ${_company.text.trim()}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.black),
                    ),
                  if (_jobLocation.text.trim().isNotEmpty)
                    pw.Text(
                      'Well / Pad Name: ${_jobLocation.text.trim()}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.black),
                    ),
                  if (_date.text.trim().isNotEmpty)
                    pw.Text(
                      'Date: ${_date.text.trim()}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.black),
                    ),
                  if (_preparedBy.text.trim().isNotEmpty)
                    pw.Text(
                      'Prepared By: ${_preparedBy.text.trim()}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.black),
                    ),
                  if (_notes.text.trim().isNotEmpty)
                    pw.Text(
                      'Notes: ${_notes.text.trim()}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.black),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              'Layout Drawing',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFFCDA56A),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              width: double.infinity,
              height: 320,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFF121417),
                border: pw.Border.all(color: PdfColors.grey700, width: 1),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              ),
              child: pw.Stack(
                children: [
                  pw.Positioned.fill(
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        color: const PdfColor.fromInt(0xFF121417),
                        borderRadius:
                            const pw.BorderRadius.all(pw.Radius.circular(8)),
                      ),
                    ),
                  ),
                  pw.Stack(
                    children: [
                      ..._pdfLayoutWidgets(
                        items: visibleItems,
                        scale: drawScale,
                        offsetX: 24,
                        offsetY: 24,
                        canvasWidth: 420,
                        canvasHeight: 280,
                      ),
                    ],
                  ),
                  if (visibleItems.isEmpty)
                    pw.Center(
                      child: pw.Text(
                        'No equipment added yet.',
                        style: const pw.TextStyle(
                            color: PdfColors.grey400, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              'Bill of Materials',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFFCDA56A),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  ...bom.categories.entries.map((entry) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3),
                        child: pw.Text(
                          '${entry.key}: ${entry.value}',
                          style: const pw.TextStyle(
                              color: PdfColors.black, fontSize: 9),
                        ),
                      )),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Iron by Size',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFFCDA56A),
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  ...bom.ironSizes.entries.map((entry) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3),
                        child: pw.Text(
                          '${entry.key}: ${entry.value}',
                          style: const pw.TextStyle(
                              color: PdfColors.black, fontSize: 9),
                        ),
                      )),
                  if (bom.customLabels.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Custom Labels',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFFCDA56A),
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    ...bom.customLabels.map((entry) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 3),
                          child: pw.Text(
                            entry,
                            style: const pw.TextStyle(
                                color: PdfColors.black, fontSize: 9),
                          ),
                        )),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              'Equipment Labels',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFFCDA56A),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (summary.isEmpty)
                    pw.Text('No equipment added.',
                        style: const pw.TextStyle(color: PdfColors.grey700))
                  else
                    ...summary.entries.map((entry) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 3),
                          child: pw.Text(
                            '${entry.key}: ${entry.value}',
                            style: const pw.TextStyle(
                                color: PdfColors.black, fontSize: 10),
                          ),
                        )),
                  if (_notes.text.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Notes',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFFCDA56A),
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      _notes.text.trim(),
                      style: const pw.TextStyle(
                          color: PdfColors.black, fontSize: 10),
                    ),
                  ],
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Item Details',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFFCDA56A),
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  ..._items.map((item) {
                    final label = item.displayLabel;
                    final detail = item.primaryPropertyLabel.isNotEmpty
                        ? ' • ${item.primaryPropertyLabel}'
                        : '';
                    final sizeText =
                        item.type.isIron ? ' • ${item.ironSize}"' : '';
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 3),
                      child: pw.Text(
                        '$label$detail$sizeText',
                        style: const pw.TextStyle(
                            color: PdfColors.black, fontSize: 9),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  _BillOfMaterialsData _billOfMaterialsSummaryForItems(
      List<_LayoutItem> items) {
    final categories = <String, int>{
      'Wellhead': 0,
      'Plug Catcher': 0,
      'Line Heater': 0,
      'Facilities': 0,
      'Spherical Sand Separator': 0,
      'Cyclonic Sand Separator': 0,
      'Equipment Bypass': 0,
      'Tees': 0,
      '90° Fittings': 0,
    };
    final ironSizes = <String, int>{'2"': 0, '3"': 0, '4"': 0};
    final customLabels = <String>[];

    for (final item in items) {
      if (item.displayLabel != item.type.label) {
        customLabels.add('${item.displayLabel} (${item.type.label})');
      }

      switch (item.type) {
        case _EquipmentType.wellhead:
          categories['Wellhead'] = (categories['Wellhead'] ?? 0) + 1;
          break;
        case _EquipmentType.plugCatcher:
          categories['Plug Catcher'] = (categories['Plug Catcher'] ?? 0) + 1;
          break;
        case _EquipmentType.lineHeater:
          categories['Line Heater'] = (categories['Line Heater'] ?? 0) + 1;
          break;
        case _EquipmentType.facilities:
          categories['Facilities'] = (categories['Facilities'] ?? 0) + 1;
          break;
        case _EquipmentType.sphericalSandSep:
          categories['Spherical Sand Separator'] =
              (categories['Spherical Sand Separator'] ?? 0) + 1;
          break;
        case _EquipmentType.cyclonicSandSep:
          categories['Cyclonic Sand Separator'] =
              (categories['Cyclonic Sand Separator'] ?? 0) + 1;
          break;
        case _EquipmentType.bypass:
          categories['Equipment Bypass'] =
              (categories['Equipment Bypass'] ?? 0) + 1;
          break;
        case _EquipmentType.teeUp:
        case _EquipmentType.teeRight:
        case _EquipmentType.teeDown:
        case _EquipmentType.teeLeft:
          categories['Tees'] = (categories['Tees'] ?? 0) + 1;
          break;
        case _EquipmentType.elbowUpRight:
        case _EquipmentType.elbowRightDown:
        case _EquipmentType.elbowDownLeft:
        case _EquipmentType.elbowLeftUp:
          categories['90° Fittings'] = (categories['90° Fittings'] ?? 0) + 1;
          break;
        default:
          break;
      }

      if (item.type.isIron) {
        final size = item.ironSize;
        if (size == '2' || size == '3' || size == '4') {
          ironSizes['${size}"'] = (ironSizes['${size}"'] ?? 0) + 1;
        }
      }
    }

    customLabels.sort();
    return _BillOfMaterialsData(
      categories: categories,
      ironSizes: ironSizes,
      customLabels: customLabels,
    );
  }

  Rect _pdfPlotBounds(List<_LayoutItem> items) {
    if (items.isEmpty) return const Rect.fromLTWH(0, 0, 1, 1);
    var minX = items.first.x;
    var minY = items.first.y;
    var maxX = items.first.x + items.first.width;
    var maxY = items.first.y + items.first.height;
    for (final item in items.skip(1)) {
      minX = minX < item.x ? minX : item.x;
      minY = minY < item.y ? minY : item.y;
      final itemMaxX = item.x + item.width;
      final itemMaxY = item.y + item.height;
      maxX = maxX > itemMaxX ? maxX : itemMaxX;
      maxY = maxY > itemMaxY ? maxY : itemMaxY;
    }
    return Rect.fromLTRB(minX - 24, minY - 24, maxX + 24, maxY + 24);
  }

  double _pdfDrawScale(Rect bounds,
      {required double maxWidth, required double maxHeight}) {
    if (bounds.width <= 0 || bounds.height <= 0) return 1.0;
    final widthScale = maxWidth / bounds.width;
    final heightScale = maxHeight / bounds.height;
    return widthScale < heightScale ? widthScale : heightScale;
  }

  Future<void> _showRigUpAssistant() async {
    final templates = <String>[
      'Standard Flowback',
      'Sand Separation',
      'Dual Sand Separator',
      'Production Testing',
      'Frac Assist',
      'Cleanup Flowback',
      'Blank Layout',
    ];

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rig-Up Templates'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: 420,
            maxWidth: _dialogWidth(context, max: 460),
          ),
          child: SizedBox(
            width: _dialogWidth(context, max: 460),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: templates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final template = templates[index];
                return ListTile(
                  leading: const Icon(Icons.tune, color: Color(0xFFCDA56A)),
                  title: Text(template),
                  subtitle: Text(_templateDescription(template)),
                  onTap: () {
                    _applyRigUpTemplate(template: template);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  String _templateDescription(String template) {
    switch (template) {
      case 'Standard Flowback':
        return 'Wellhead, separator, flowback tanks, and a compact iron run.';
      case 'Sand Separation':
        return 'Focused separator layout with a clean flowback train.';
      case 'Dual Sand Separator':
        return 'Two separators with wider spacing and additional iron.';
      case 'Production Testing':
        return 'Production tank and test separator setup for testing runs.';
      case 'Frac Assist':
        return 'High-capacity tank and separator arrangement for frac support.';
      case 'Cleanup Flowback':
        return 'Simplified cleanup layout with a bypass and recovery equipment.';
      case 'Blank Layout':
      default:
        return 'Start with a clean canvas for a custom rig-up.';
    }
  }

  void _autoItem(_EquipmentType type, double x, double y,
      {double? width, double? height}) {
    _items.add(_LayoutItem(
      id: _nextId++,
      type: type,
      x: _snap(x),
      y: _snap(y),
      width: width ?? type.defaultWidth,
      height: height ?? type.defaultHeight,
    ));
  }

  void _applyRigUpTemplate({required String template}) {
    _runHistoryChange(() {
      _items.clear();
      _selectedId = null;
      _selectedIds.clear();
      _nextId = 1;
      if (template == 'Blank Layout') {
        _layoutName.text = template;
        return;
      }

      switch (template) {
        case 'Standard Flowback':
          _autoItem(_EquipmentType.wellhead, 24, 56);
          _autoItem(_EquipmentType.ironHorizontal, 138, 70,
              width: 90, height: 44);
          _autoItem(_EquipmentType.esdValve, 248, 56);
          _autoItem(_EquipmentType.ironHorizontal, 348, 70,
              width: 78, height: 44);
          _autoItem(_EquipmentType.bypass, 426, 54, width: 70, height: 46);
          _autoItem(_EquipmentType.ironHorizontal, 512, 70,
              width: 86, height: 44);
          _autoItem(_EquipmentType.plugCatcher, 614, 48);
          _autoItem(_EquipmentType.ironHorizontal, 742, 70,
              width: 92, height: 44);
          _autoItem(_EquipmentType.lineHeater, 860, 48);
          _autoItem(_EquipmentType.ironHorizontal, 982, 70,
              width: 78, height: 44);
          _autoItem(_EquipmentType.cyclonicSandSep, 1090, 48);
          _autoItem(_EquipmentType.ironHorizontal, 1220, 70,
              width: 82, height: 44);
          _autoItem(_EquipmentType.chokeManifold, 1330, 48);
          _autoItem(_EquipmentType.teeDown, 1458, 48);
          _autoItem(_EquipmentType.ironHorizontal, 1560, 70,
              width: 70, height: 44);
          _autoItem(_EquipmentType.flowbackTank, 1650, 24);
          _autoItem(_EquipmentType.ironHorizontal, 1560, 150,
              width: 70, height: 44);
          _autoItem(_EquipmentType.flowbackTank, 1650, 122);
          _autoItem(_EquipmentType.ironVertical, 1730, 140,
              width: 44, height: 100);
          _autoItem(_EquipmentType.productionTank, 1820, 24);
          _autoItem(_EquipmentType.ironHorizontal, 1740, 300,
              width: 90, height: 44);
          _autoItem(_EquipmentType.facilities, 1860, 260,
              width: 190, height: 100);
          break;
        case 'Sand Separation':
          _autoItem(_EquipmentType.wellhead, 24, 56);
          _autoItem(_EquipmentType.ironHorizontal, 138, 70,
              width: 92, height: 44);
          _autoItem(_EquipmentType.esdValve, 248, 56);
          _autoItem(_EquipmentType.ironHorizontal, 348, 70,
              width: 86, height: 44);
          _autoItem(_EquipmentType.plugCatcher, 450, 48);
          _autoItem(_EquipmentType.ironHorizontal, 572, 70,
              width: 94, height: 44);
          _autoItem(_EquipmentType.sphericalSandSep, 690, 48);
          _autoItem(_EquipmentType.ironHorizontal, 820, 70,
              width: 82, height: 44);
          _autoItem(_EquipmentType.chokeManifold, 930, 48);
          _autoItem(_EquipmentType.teeDown, 1060, 48);
          _autoItem(_EquipmentType.ironHorizontal, 1160, 70,
              width: 70, height: 44);
          _autoItem(_EquipmentType.flowbackTank, 1260, 24);
          _autoItem(_EquipmentType.ironHorizontal, 1160, 150,
              width: 70, height: 44);
          _autoItem(_EquipmentType.flowbackTank, 1260, 122);
          _autoItem(_EquipmentType.ironVertical, 1360, 140,
              width: 44, height: 100);
          _autoItem(_EquipmentType.productionTank, 1460, 24);
          _autoItem(_EquipmentType.facilities, 1580, 260,
              width: 190, height: 100);
          break;
        case 'Dual Sand Separator':
          _autoItem(_EquipmentType.wellhead, 24, 56);
          _autoItem(_EquipmentType.ironHorizontal, 138, 70,
              width: 92, height: 44);
          _autoItem(_EquipmentType.esdValve, 248, 56);
          _autoItem(_EquipmentType.ironHorizontal, 348, 70,
              width: 84, height: 44);
          _autoItem(_EquipmentType.bypass, 438, 54, width: 70, height: 46);
          _autoItem(_EquipmentType.plugCatcher, 530, 48);
          _autoItem(_EquipmentType.ironHorizontal, 658, 70,
              width: 94, height: 44);
          _autoItem(_EquipmentType.cyclonicSandSep, 780, 48);
          _autoItem(_EquipmentType.ironHorizontal, 910, 70,
              width: 80, height: 44);
          _autoItem(_EquipmentType.sphericalSandSep, 1020, 48);
          _autoItem(_EquipmentType.ironHorizontal, 1150, 70,
              width: 82, height: 44);
          _autoItem(_EquipmentType.chokeManifold, 1260, 48);
          _autoItem(_EquipmentType.teeDown, 1388, 48);
          _autoItem(_EquipmentType.ironHorizontal, 1490, 70,
              width: 70, height: 44);
          _autoItem(_EquipmentType.flowbackTank, 1590, 24);
          _autoItem(_EquipmentType.ironHorizontal, 1490, 150,
              width: 70, height: 44);
          _autoItem(_EquipmentType.flowbackTank, 1590, 122);
          _autoItem(_EquipmentType.productionTank, 1710, 24);
          _autoItem(_EquipmentType.facilities, 1830, 260,
              width: 190, height: 100);
          break;
        case 'Production Testing':
          _autoItem(_EquipmentType.wellhead, 24, 56);
          _autoItem(_EquipmentType.ironHorizontal, 138, 70,
              width: 92, height: 44);
          _autoItem(_EquipmentType.esdValve, 248, 56);
          _autoItem(_EquipmentType.ironHorizontal, 348, 70,
              width: 84, height: 44);
          _autoItem(_EquipmentType.plugCatcher, 450, 48);
          _autoItem(_EquipmentType.ironHorizontal, 572, 70,
              width: 94, height: 44);
          _autoItem(_EquipmentType.testSeparator, 690, 48);
          _autoItem(_EquipmentType.ironHorizontal, 820, 70,
              width: 82, height: 44);
          _autoItem(_EquipmentType.productionTank, 930, 24);
          _autoItem(_EquipmentType.ironHorizontal, 1060, 70,
              width: 80, height: 44);
          _autoItem(_EquipmentType.productionTank, 1160, 24);
          _autoItem(_EquipmentType.ironHorizontal, 1290, 70,
              width: 82, height: 44);
          _autoItem(_EquipmentType.facilities, 1420, 260,
              width: 190, height: 100);
          break;
        case 'Frac Assist':
          _autoItem(_EquipmentType.wellhead, 24, 56);
          _autoItem(_EquipmentType.ironHorizontal, 138, 70,
              width: 92, height: 44);
          _autoItem(_EquipmentType.esdValve, 248, 56);
          _autoItem(_EquipmentType.ironHorizontal, 348, 70,
              width: 84, height: 44);
          _autoItem(_EquipmentType.plugCatcher, 450, 48);
          _autoItem(_EquipmentType.ironHorizontal, 572, 70,
              width: 94, height: 44);
          _autoItem(_EquipmentType.cyclonicSandSep, 690, 48);
          _autoItem(_EquipmentType.ironHorizontal, 820, 70,
              width: 80, height: 44);
          _autoItem(_EquipmentType.sphericalSandSep, 930, 48);
          _autoItem(_EquipmentType.ironHorizontal, 1060, 70,
              width: 82, height: 44);
          _autoItem(_EquipmentType.flowbackTank, 1170, 24);
          _autoItem(_EquipmentType.ironHorizontal, 1290, 70,
              width: 70, height: 44);
          _autoItem(_EquipmentType.flowbackTank, 1390, 24);
          _autoItem(_EquipmentType.ironHorizontal, 1510, 70,
              width: 70, height: 44);
          _autoItem(_EquipmentType.flowbackTank, 1610, 24);
          _autoItem(_EquipmentType.compressor, 1740, 24);
          _autoItem(_EquipmentType.facilities, 1860, 260,
              width: 190, height: 100);
          break;
        case 'Cleanup Flowback':
          _autoItem(_EquipmentType.wellhead, 24, 56);
          _autoItem(_EquipmentType.ironHorizontal, 138, 70,
              width: 92, height: 44);
          _autoItem(_EquipmentType.esdValve, 248, 56);
          _autoItem(_EquipmentType.ironHorizontal, 348, 70,
              width: 88, height: 44);
          _autoItem(_EquipmentType.bypass, 438, 54, width: 70, height: 46);
          _autoItem(_EquipmentType.ironHorizontal, 520, 70,
              width: 84, height: 44);
          _autoItem(_EquipmentType.plugCatcher, 620, 48);
          _autoItem(_EquipmentType.ironHorizontal, 744, 70,
              width: 90, height: 44);
          _autoItem(_EquipmentType.cyclonicSandSep, 860, 48);
          _autoItem(_EquipmentType.ironHorizontal, 990, 70,
              width: 76, height: 44);
          _autoItem(_EquipmentType.flowbackTank, 1090, 24);
          _autoItem(_EquipmentType.ironHorizontal, 1210, 70,
              width: 72, height: 44);
          _autoItem(_EquipmentType.flowbackTank, 1310, 24);
          _autoItem(_EquipmentType.facilities, 1430, 260,
              width: 190, height: 100);
          break;
        default:
          break;
      }

      _layoutName.text = template;
    });
  }

  List<_PropertyField> _propertyFields(_EquipmentType type) {
    final baseFields = <_PropertyField>[
      const _PropertyField('assetNumber', 'Asset Number'),
      const _PropertyField('size', 'Size'),
      const _PropertyField('pressureRating', 'Pressure Rating'),
      const _PropertyField('serialNumber', 'Serial Number'),
      const _PropertyField('notes', 'Notes', maxLines: 3),
    ];

    switch (type) {
      case _EquipmentType.wellhead:
        return [
          ...baseFields,
          const _PropertyField('wellName', 'Well Name'),
          const _PropertyField('apiNumber', 'API Number'),
          const _PropertyField('status', 'Status'),
        ];
      case _EquipmentType.chokeManifold:
        return [
          ...baseFields,
          const _PropertyField('chokeSize', 'Choke Size'),
          const _PropertyField('chokeType', 'POS / ADJ'),
          const _PropertyField('upstreamPressure', 'Upstream Pressure'),
          const _PropertyField('downstreamPressure', 'Downstream Pressure'),
        ];
      case _EquipmentType.flowbackTank:
      case _EquipmentType.productionTank:
        return [
          ...baseFields,
          const _PropertyField('tankName', 'Tank Name / Number'),
          const _PropertyField('capacity', 'Capacity'),
          const _PropertyField('currentLevel', 'Current Level'),
          const _PropertyField('assignedWell', 'Assigned Well'),
        ];
      case _EquipmentType.compressor:
        return [
          ...baseFields,
          const _PropertyField('company', 'Company'),
          const _PropertyField('suctionPressure', 'Suction Pressure'),
          const _PropertyField('dischargePressure', 'Discharge Pressure'),
          const _PropertyField('injectionRate', 'Injection Rate (MCF)'),
          const _PropertyField('running', 'Running / Status'),
        ];
      case _EquipmentType.lineHeater:
        return [
          ...baseFields,
          const _PropertyField('fuelGasPressure', 'Fuel Gas Pressure'),
          const _PropertyField('temperature', 'Temperature'),
          const _PropertyField('status', 'Status'),
        ];
      case _EquipmentType.esdValve:
        return [
          ...baseFields,
          const _PropertyField('status', 'Open / Closed'),
          const _PropertyField('lastTested', 'Last Tested'),
        ];
      case _EquipmentType.cyclonicSandSep:
      case _EquipmentType.sphericalSandSep:
        return [
          ...baseFields,
          const _PropertyField('separatorType', 'Separator Type'),
          const _PropertyField('sandRate', 'Sand Rate (GAL/hr)'),
          const _PropertyField('assignedWell', 'Assigned Well'),
        ];
      default:
        return [
          ...baseFields,
          const _PropertyField('name', 'Name / Label'),
          const _PropertyField('status', 'Status'),
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
        if (!item.type.isIron ||
            item.type.name.startsWith('elbow') ||
            item.type.name.startsWith('tee')) {
          final oldWidth = item.width;
          item.width = item.height;
          item.height = oldWidth;
        }
      }
    });
    _appendHistoryEntry('Rotated equipment');
  }

  Future<void> _renameSelected() async {
    final item = _selectedItem;
    if (item == null) return;
    final controller = TextEditingController(text: item.displayLabel);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Label shown on layout',
                hintText: 'e.g. Sand Sep 1',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Examples: Wellhead, Plug Catcher, Line Heater, Facilities, Sand Sep 1, Sand Sep 2',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
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
    _appendHistoryEntry('Moved equipment');
  }

  void _alignSelected(_LayoutAlign align) {
    final selected = _selectedItems.where((item) => !item.locked).toList();
    if (selected.length < 2) return;
    _runHistoryChange(() {
      switch (align) {
        case _LayoutAlign.left:
          final x =
              selected.map((item) => item.x).reduce((a, b) => a < b ? a : b);
          for (final item in selected) item.x = _snap(x);
          break;
        case _LayoutAlign.right:
          final right = selected
              .map((item) => item.x + item.width)
              .reduce((a, b) => a > b ? a : b);
          for (final item in selected) item.x = _snap(right - item.width);
          break;
        case _LayoutAlign.top:
          final y =
              selected.map((item) => item.y).reduce((a, b) => a < b ? a : b);
          for (final item in selected) item.y = _snap(y);
          break;
        case _LayoutAlign.bottom:
          final bottom = selected
              .map((item) => item.y + item.height)
              .reduce((a, b) => a > b ? a : b);
          for (final item in selected) item.y = _snap(bottom - item.height);
          break;
        case _LayoutAlign.horizontalCenter:
          final center = selected
                  .map((item) => item.x + item.width / 2)
                  .reduce((a, b) => a + b) /
              selected.length;
          for (final item in selected) item.x = _snap(center - item.width / 2);
          break;
        case _LayoutAlign.verticalCenter:
          final center = selected
                  .map((item) => item.y + item.height / 2)
                  .reduce((a, b) => a + b) /
              selected.length;
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
          selected
              .sort((a, b) => (a.x + a.width / 2).compareTo(b.x + b.width / 2));
          final firstCenter = selected.first.x + selected.first.width / 2;
          final lastCenter = selected.last.x + selected.last.width / 2;
          final step = (lastCenter - firstCenter) / (selected.length - 1);
          for (var i = 1; i < selected.length - 1; i++) {
            selected[i].x =
                _snap(firstCenter + step * i - selected[i].width / 2);
          }
          break;
        case _LayoutDistribution.vertical:
          selected.sort(
              (a, b) => (a.y + a.height / 2).compareTo(b.y + b.height / 2));
          final firstCenter = selected.first.y + selected.first.height / 2;
          final lastCenter = selected.last.y + selected.last.height / 2;
          final step = (lastCenter - firstCenter) / (selected.length - 1);
          for (var i = 1; i < selected.length - 1; i++) {
            selected[i].y =
                _snap(firstCenter + step * i - selected[i].height / 2);
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
      if (item.type == _EquipmentType.ironHorizontal ||
          item.type == _EquipmentType.ironVertical) {
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
          width: _dialogWidth(context, max: 420),
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
                    Text(
                        'Total straight iron: ${totalIronFeet.toStringAsFixed(0)} ft',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _showSelectedProperties() async {
    final item = _selectedItem;
    if (item == null || item.type.isIron) return;
    final fields = _propertyFields(item.type);
    final controllers = <String, TextEditingController>{
      for (final field in fields)
        field.key:
            TextEditingController(text: item.properties[field.key] ?? ''),
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.type.label} Properties'),
        content: SizedBox(
          width: _dialogWidth(context, max: 460),
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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );

    if (saved == true) {
      _runHistoryChange(() {
        item.properties
          ..clear()
          ..addEntries(controllers.entries
              .where((e) => e.value.text.trim().isNotEmpty)
              .map((e) => MapEntry(e.key, e.value.text.trim())));
      });
    }
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  void _showHistoryDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recent History'),
        content: SizedBox(
          width: _dialogWidth(context, max: 360),
          child: _historyLog.isEmpty
              ? const Text('No actions recorded yet.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _historyLog.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => ListTile(
                    leading:
                        const Icon(Icons.history, color: Color(0xFFCDA56A)),
                    title: Text(_historyLog[_historyLog.length - 1 - index]),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddEquipmentDrawer() async {
    final isWide = MediaQuery.of(context).size.width >= 780;
    if (isWide) {
      setState(() => _showSideLibrary = true);
      return;
    }
    _openEquipmentDrawer(section: _DrawerLibrarySection.equipment);
  }

  Future<void> _showToolsDrawer() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101113),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: StatefulBuilder(
          builder: (context, setSheetState) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.88,
            minChildSize: 0.5,
            maxChildSize: 0.96,
            builder: (context, scrollController) => LayoutBuilder(
              builder: (context, constraints) {
                final actionWidth = ((constraints.maxWidth - 44) / 2)
                    .clamp(140.0, 260.0)
                    .toDouble();
                Widget action(Widget child) =>
                    SizedBox(width: actionWidth, child: child);

                final selected = _selectedIds.isNotEmpty;
                final multiSelected = _selectedIds.length > 1;

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A3A3A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Layout Tools',
                      style: TextStyle(
                        color: Color(0xFFCDA56A),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        action(FilledButton.icon(
                          onPressed: () {
                            final width = MediaQuery.of(context).size.width;
                            if (width >= 780) {
                              setState(() => _showSideLibrary = true);
                              Navigator.pop(context);
                              return;
                            }
                            Navigator.pop(context);
                            _showAddEquipmentDrawer();
                          },
                          icon: const Icon(Icons.add_box_outlined),
                          label: Text(MediaQuery.of(context).size.width >= 780
                              ? 'Show Equipment Library'
                              : 'Add Equipment'),
                          style: _compactFilledStyle(highlighted: true),
                        )),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _layoutName,
                      decoration: const InputDecoration(
                        labelText: 'Layout Name',
                        prefixIcon: Icon(Icons.drive_file_rename_outline),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ExpansionTile(
                      collapsedIconColor: _gold,
                      iconColor: _gold,
                      title: const Text('Save / Load / Clear',
                          style: TextStyle(color: Color(0xFFCDA56A))),
                      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            action(FilledButton.icon(
                              onPressed: _saveRigUp,
                              icon: const Icon(Icons.save_alt),
                              label: const Text('Save Rig-Up'),
                              style: _compactFilledStyle(highlighted: true),
                            )),
                            action(OutlinedButton.icon(
                              onPressed: _showLoadRigUps,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Load Rig-Up'),
                              style: _compactOutlineStyle(highlighted: true),
                            )),
                            action(OutlinedButton.icon(
                              onPressed: _confirmClearLayout,
                              icon: const Icon(Icons.clear_all),
                              label: const Text('Clear Layout'),
                              style: _compactOutlineStyle(highlighted: true),
                            )),
                          ],
                        ),
                      ],
                    ),
                    ExpansionTile(
                      collapsedIconColor: _gold,
                      iconColor: _gold,
                      title: const Text('Export / Share',
                          style: TextStyle(color: Color(0xFFCDA56A))),
                      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            action(FilledButton.icon(
                              onPressed: _exportPdf,
                              icon: const Icon(Icons.picture_as_pdf),
                              label: const Text('Export PDF'),
                              style: _compactFilledStyle(highlighted: true),
                            )),
                            action(FilledButton.icon(
                              onPressed: _saveLayoutImage,
                              icon: const Icon(Icons.image_outlined),
                              label: const Text('Save Image'),
                              style: _compactFilledStyle(highlighted: true),
                            )),
                            action(FilledButton.icon(
                              onPressed: _shareRigUpPackage,
                              icon: const Icon(Icons.share_outlined),
                              label: const Text('Share Package'),
                              style: _compactFilledStyle(highlighted: true),
                            )),
                            action(FilledButton.icon(
                              onPressed: _showBillOfMaterials,
                              icon: const Icon(Icons.format_list_bulleted),
                              label: const Text('Bill of Materials'),
                              style: _compactFilledStyle(highlighted: true),
                            )),
                            action(OutlinedButton.icon(
                              onPressed: _showInventory,
                              icon: const Icon(Icons.inventory_2_outlined),
                              label: const Text('Inventory'),
                              style: _compactOutlineStyle(),
                            )),
                          ],
                        ),
                      ],
                    ),
                    ExpansionTile(
                      collapsedIconColor: _gold,
                      iconColor: _gold,
                      title: const Text('Templates / Favorites / Job',
                          style: TextStyle(color: Color(0xFFCDA56A))),
                      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            action(FilledButton.icon(
                              onPressed: _showRigUpAssistant,
                              icon: const Icon(Icons.auto_awesome),
                              label: const Text('Templates'),
                              style: _compactFilledStyle(highlighted: true),
                            )),
                            action(FilledButton.icon(
                              onPressed: _saveFavoriteAssembly,
                              icon: const Icon(Icons.favorite_border),
                              label: const Text('Save Favorite'),
                              style: _compactFilledStyle(),
                            )),
                            action(OutlinedButton.icon(
                              onPressed: _showFavorites,
                              icon: const Icon(Icons.star_outline),
                              label: const Text('Favorites'),
                              style: _compactOutlineStyle(),
                            )),
                            action(OutlinedButton.icon(
                              onPressed: _showLayoutInfo,
                              icon: const Icon(Icons.info_outline),
                              label: const Text('Job Info'),
                              style: _compactOutlineStyle(),
                            )),
                          ],
                        ),
                      ],
                    ),
                    ExpansionTile(
                      collapsedIconColor: _gold,
                      iconColor: _gold,
                      initiallyExpanded: true,
                      title: const Text('Tools',
                          style: TextStyle(color: Color(0xFFCDA56A))),
                      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            action(FilledButton.icon(
                              onPressed: () {
                                setState(() => _snapToGrid = !_snapToGrid);
                                setSheetState(() {});
                              },
                              icon: const Icon(Icons.grid_4x4),
                              label: Text(_snapToGrid
                                  ? 'Grid Snap ON'
                                  : 'Grid Snap OFF'),
                              style:
                                  _compactFilledStyle(highlighted: _snapToGrid),
                            )),
                            action(FilledButton.icon(
                              onPressed: () {
                                _toggleMeasurementMode();
                                setSheetState(() {});
                              },
                              icon: const Icon(Icons.straighten),
                              label:
                                  Text(_measureMode ? 'Measuring' : 'Measure'),
                              style: _compactFilledStyle(
                                  highlighted: _measureMode),
                            )),
                            if (_measurementStart != null ||
                                _measurementEnd != null)
                              action(OutlinedButton.icon(
                                onPressed: () {
                                  _clearMeasurement();
                                  setSheetState(() {});
                                },
                                icon: const Icon(Icons.close),
                                label: const Text('Clear Measure'),
                                style: _compactOutlineStyle(),
                              )),
                            action(OutlinedButton.icon(
                              onPressed: _showHistoryDialog,
                              icon: const Icon(Icons.history),
                              label: const Text('History'),
                              style: _compactOutlineStyle(),
                            )),
                            action(FilledButton.icon(
                              onPressed: () {
                                _toggleDrawIronMode(!_drawIronMode);
                                setSheetState(() {});
                              },
                              icon: const Icon(Icons.edit_road),
                              label: Text(_drawIronMode
                                  ? 'Draw Iron On'
                                  : 'Draw Iron Off'),
                              style: _compactFilledStyle(
                                  highlighted: _drawIronMode),
                            )),
                          ],
                        ),
                      ],
                    ),
                    ExpansionTile(
                      collapsedIconColor: _gold,
                      iconColor: _gold,
                      title: const Text('Layers',
                          style: TextStyle(color: Color(0xFFCDA56A))),
                      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            action(OutlinedButton.icon(
                              onPressed: () {
                                setState(
                                    () => _showEquipment = !_showEquipment);
                                setSheetState(() {});
                              },
                              icon: const Icon(Icons.precision_manufacturing),
                              label: Text(_showEquipment
                                  ? 'Equipment On'
                                  : 'Equipment Off'),
                              style: _compactOutlineStyle(),
                            )),
                            action(OutlinedButton.icon(
                              onPressed: () {
                                setState(() => _showIron = !_showIron);
                                setSheetState(() {});
                              },
                              icon: const Icon(Icons.tune),
                              label: Text(_showIron ? 'Iron On' : 'Iron Off'),
                              style: _compactOutlineStyle(),
                            )),
                            action(OutlinedButton.icon(
                              onPressed: () {
                                setState(() => _showLabels = !_showLabels);
                                setSheetState(() {});
                              },
                              icon: const Icon(Icons.label_outline),
                              label: Text(
                                  _showLabels ? 'Labels On' : 'Labels Off'),
                              style: _compactOutlineStyle(),
                            )),
                            action(OutlinedButton.icon(
                              onPressed: () {
                                setState(() => _showGrid = !_showGrid);
                                setSheetState(() {});
                              },
                              icon: const Icon(Icons.grid_on),
                              label: Text(_showGrid ? 'Grid On' : 'Grid Off'),
                              style: _compactOutlineStyle(),
                            )),
                          ],
                        ),
                      ],
                    ),
                    ExpansionTile(
                      collapsedIconColor: _gold,
                      iconColor: _gold,
                      title: const Text('Selection',
                          style: TextStyle(color: Color(0xFFCDA56A))),
                      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (selected)
                              action(OutlinedButton.icon(
                                onPressed: () {
                                  _clearSelection();
                                  setSheetState(() {});
                                },
                                icon: const Icon(Icons.deselect),
                                label: Text(
                                    'Clear Selection (${_selectedIds.length})'),
                                style: _compactOutlineStyle(),
                              )),
                            action(OutlinedButton.icon(
                              onPressed: selected ? _duplicateSelected : null,
                              icon: const Icon(Icons.copy),
                              label: const Text('Duplicate'),
                              style: _compactOutlineStyle(),
                            )),
                            action(OutlinedButton.icon(
                              onPressed: selected ? _deleteSelected : null,
                              icon: const Icon(Icons.delete),
                              label: const Text('Delete'),
                              style: _compactOutlineStyle(),
                            )),
                            action(OutlinedButton.icon(
                              onPressed:
                                  _hasSelectedItem ? _renameSelected : null,
                              icon: const Icon(Icons.drive_file_rename_outline),
                              label: const Text('Rename'),
                              style: _compactOutlineStyle(),
                            )),
                            action(OutlinedButton.icon(
                              onPressed:
                                  _hasSelectedItem ? _rotateSelected : null,
                              icon: const Icon(Icons.rotate_right),
                              label: const Text('Rotate'),
                              style: _compactOutlineStyle(),
                            )),
                            action(OutlinedButton.icon(
                              onPressed:
                                  _hasSelectedItem ? _toggleSelectedLock : null,
                              icon: Icon((_selectedItem?.locked ?? false)
                                  ? Icons.lock_open
                                  : Icons.lock),
                              label: Text((_selectedItem?.locked ?? false)
                                  ? 'Unlock'
                                  : 'Lock'),
                              style: _compactOutlineStyle(),
                            )),
                            action(OutlinedButton.icon(
                              onPressed: _selectedCanHaveProperties
                                  ? _showSelectedProperties
                                  : null,
                              icon: const Icon(Icons.edit_note),
                              label: const Text('Properties'),
                              style: _compactOutlineStyle(),
                            )),
                            if (multiSelected) ...[
                              OutlinedButton(
                                  onPressed: () =>
                                      _alignSelected(_LayoutAlign.left),
                                  child: const Text('Align L')),
                              OutlinedButton(
                                  onPressed: () =>
                                      _alignSelected(_LayoutAlign.right),
                                  child: const Text('Align R')),
                              OutlinedButton(
                                  onPressed: () =>
                                      _alignSelected(_LayoutAlign.top),
                                  child: const Text('Align T')),
                              OutlinedButton(
                                  onPressed: () =>
                                      _alignSelected(_LayoutAlign.bottom),
                                  child: const Text('Align B')),
                              OutlinedButton(
                                  onPressed: () => _alignSelected(
                                      _LayoutAlign.horizontalCenter),
                                  child: const Text('Center X')),
                              OutlinedButton(
                                  onPressed: () => _alignSelected(
                                      _LayoutAlign.verticalCenter),
                                  child: const Text('Center Y')),
                              OutlinedButton.icon(
                                  onPressed: _selectedIds.length > 2
                                      ? () => _distributeSelected(
                                          _LayoutDistribution.horizontal)
                                      : null,
                                  icon:
                                      const Icon(Icons.align_horizontal_center),
                                  label: const Text('Space H')),
                              OutlinedButton.icon(
                                  onPressed: _selectedIds.length > 2
                                      ? () => _distributeSelected(
                                          _LayoutDistribution.vertical)
                                      : null,
                                  icon: const Icon(Icons.align_vertical_center),
                                  label: const Text('Space V')),
                            ],
                            if (_hasSelectedItem) ...[
                              OutlinedButton(
                                  onPressed: () => _nudgeSelected(-24, 0),
                                  child: const Text('←')),
                              OutlinedButton(
                                  onPressed: () => _nudgeSelected(24, 0),
                                  child: const Text('→')),
                              OutlinedButton(
                                  onPressed: () => _nudgeSelected(0, -24),
                                  child: const Text('↑')),
                              OutlinedButton(
                                  onPressed: () => _nudgeSelected(0, 24),
                                  child: const Text('↓')),
                            ],
                            if (_selectedIsIron) ...[
                              OutlinedButton(
                                  onPressed: () => _setSelectedIronSize('2'),
                                  child: const Text('2"')),
                              OutlinedButton(
                                  onPressed: () => _setSelectedIronSize('3'),
                                  child: const Text('3"')),
                              OutlinedButton(
                                  onPressed: () => _setSelectedIronSize('4'),
                                  child: const Text('4"')),
                            ],
                            if (_selectedIsStraightIron) ...[
                              OutlinedButton(
                                  onPressed: () => _quickSetIronLength(5),
                                  child: const Text('5 ft')),
                              OutlinedButton(
                                  onPressed: () => _quickSetIronLength(10),
                                  child: const Text('10 ft')),
                              OutlinedButton(
                                  onPressed: () => _quickSetIronLength(20),
                                  child: const Text('20 ft')),
                              OutlinedButton(
                                  onPressed: () => _quickSetIronLength(
                                      (_selectedItem == null
                                              ? 5
                                              : _ironLengthFeet(
                                                      _selectedItem!) -
                                                  5)
                                          .clamp(5, 200)
                                          .toDouble()),
                                  child: const Text('Shorten')),
                              OutlinedButton(
                                  onPressed: () => _quickSetIronLength(
                                      (_selectedItem == null
                                              ? 10
                                              : _ironLengthFeet(
                                                      _selectedItem!) +
                                                  5)
                                          .clamp(5, 200)
                                          .toDouble()),
                                  child: const Text('Lengthen')),
                              FilledButton.icon(
                                onPressed: _setSelectedIronLength,
                                icon: const Icon(Icons.straighten),
                                label: const Text('Custom Length'),
                                style: _compactFilledStyle(),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 780;
    final dockWidth =
        screenWidth >= 1200 ? 340.0 : (screenWidth >= 900 ? 300.0 : 220.0);
    return Scaffold(
      appBar: const AppHeader(title: 'Layout Designer', showBack: true),
      body: Column(
        children: [
          _toolbar(isWide: isWide),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _canvas()),
                if (isWide && _showSideLibrary)
                  Positioned(
                    left: 12,
                    top: 12,
                    bottom: 12,
                    width: dockWidth,
                    child: _sideLibraryPanel(),
                  ),
                if (!isWide)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 12,
                    child: _mobileEquipmentDrawer(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<MapEntry<String, _EquipmentType>> get _quickEquipmentEntries =>
      const <MapEntry<String, _EquipmentType>>[
        MapEntry<String, _EquipmentType>('Wellhead', _EquipmentType.wellhead),
        MapEntry<String, _EquipmentType>('ESD Valve', _EquipmentType.esdValve),
        MapEntry<String, _EquipmentType>(
            'Choke Manifold', _EquipmentType.chokeManifold),
        MapEntry<String, _EquipmentType>(
            'Plug Catcher', _EquipmentType.plugCatcher),
        MapEntry<String, _EquipmentType>(
            'Line Heater', _EquipmentType.lineHeater),
        MapEntry<String, _EquipmentType>(
            'Facilities', _EquipmentType.facilities),
        MapEntry<String, _EquipmentType>(
            'Spherical Sand Separator', _EquipmentType.sphericalSandSep),
        MapEntry<String, _EquipmentType>(
            'Cyclonic Sand Separator', _EquipmentType.cyclonicSandSep),
        MapEntry<String, _EquipmentType>(
            'Flowback Tank', _EquipmentType.flowbackTank),
        MapEntry<String, _EquipmentType>(
            'Production Tank', _EquipmentType.productionTank),
        MapEntry<String, _EquipmentType>(
            'Test Separator', _EquipmentType.testSeparator),
        MapEntry<String, _EquipmentType>('Flare', _EquipmentType.flare),
        MapEntry<String, _EquipmentType>(
            'Compressor', _EquipmentType.compressor),
        MapEntry<String, _EquipmentType>(
            'Equipment Bypass', _EquipmentType.bypass),
        MapEntry<String, _EquipmentType>('Tee', _EquipmentType.teeRight),
        MapEntry<String, _EquipmentType>(
            '90° Fitting', _EquipmentType.elbowUpRight),
      ];

  List<_EquipmentType> get _straightIronTypes => const [
        _EquipmentType.ironHorizontal,
        _EquipmentType.ironVertical,
      ];

  List<_EquipmentType> get _teeOnlyTypes => const [
        _EquipmentType.teeUp,
        _EquipmentType.teeRight,
        _EquipmentType.teeDown,
        _EquipmentType.teeLeft,
      ];

  List<_EquipmentType> get _elbowOnlyTypes => const [
        _EquipmentType.elbowUpRight,
        _EquipmentType.elbowRightDown,
        _EquipmentType.elbowDownLeft,
        _EquipmentType.elbowLeftUp,
      ];

  Widget _libraryCategoryTabs({required bool isMobile}) {
    const tabs = <MapEntry<String, _DrawerLibrarySection>>[
      MapEntry<String, _DrawerLibrarySection>(
          'Equipment', _DrawerLibrarySection.equipment),
      MapEntry<String, _DrawerLibrarySection>(
          'Iron', _DrawerLibrarySection.iron),
      MapEntry<String, _DrawerLibrarySection>(
          'Tees', _DrawerLibrarySection.tees),
      MapEntry<String, _DrawerLibrarySection>(
          '90s', _DrawerLibrarySection.nineties),
      MapEntry<String, _DrawerLibrarySection>(
          'Bypass', _DrawerLibrarySection.bypass),
      MapEntry<String, _DrawerLibrarySection>(
          'Labels', _DrawerLibrarySection.labels),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in tabs) ...[
            ChoiceChip(
              selectedColor: const Color(0xFFCDA56A),
              labelStyle: TextStyle(
                color: _mobileDrawerSection == tab.value
                    ? Colors.black
                    : Colors.white,
                fontWeight: FontWeight.w700,
              ),
              side: BorderSide(
                color: _mobileDrawerSection == tab.value
                    ? const Color(0xFFCDA56A)
                    : const Color(0xFF4A4A4A),
              ),
              backgroundColor: const Color(0xFF1A1D21),
              selected: _mobileDrawerSection == tab.value,
              label: Text(tab.key),
              onSelected: (_) => setState(() {
                _mobileDrawerSection = tab.value;
                if (tab.value == _DrawerLibrarySection.iron) {
                  _drawIronMode = true;
                }
              }),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _equipmentButtonForLibrary(_EquipmentType type,
      {required bool outlined, required bool isMobile}) {
    return SizedBox(
      width: isMobile ? 162 : 138,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: () => _addItem(type),
              icon: Icon(type.icon),
              label: Text(type.label, maxLines: 2),
              style: _compactOutlineStyle(highlighted: true),
            )
          : FilledButton.icon(
              onPressed: () => _addItem(type),
              icon: Icon(type.icon),
              label: Text(type.label, maxLines: 2),
              style: _compactFilledStyle(highlighted: true),
            ),
    );
  }

  Widget _libraryCategoryBody({required bool isMobile}) {
    List<_EquipmentType> types;
    var outlined = false;
    String title;

    switch (_mobileDrawerSection) {
      case _DrawerLibrarySection.equipment:
        types = _equipmentTypes;
        title = 'Equipment';
        break;
      case _DrawerLibrarySection.iron:
        types = _straightIronTypes;
        outlined = true;
        title = 'Straight Iron';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Straight Iron',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: FilledButton.icon(
                    onPressed: () => setState(() {
                      _drawIronMode = true;
                    }),
                    icon: const Icon(Icons.edit_road),
                    label: Text(_drawIronMode ? 'Draw Iron ON' : 'Draw Iron'),
                    style: _compactFilledStyle(highlighted: _drawIronMode),
                  ),
                ),
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _drawIronMode = false;
                      _ironStartPoint = null;
                    }),
                    icon: const Icon(Icons.pan_tool_alt_outlined),
                    label: const Text('Select / Move'),
                    style: _compactOutlineStyle(),
                  ),
                ),
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: FilledButton(
                    onPressed: () => setState(() => _drawIronSize = '2'),
                    style:
                        _compactFilledStyle(highlighted: _drawIronSize == '2'),
                    child: const Text('2" Iron'),
                  ),
                ),
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: FilledButton(
                    onPressed: () => setState(() => _drawIronSize = '3'),
                    style:
                        _compactFilledStyle(highlighted: _drawIronSize == '3'),
                    child: const Text('3" Iron'),
                  ),
                ),
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: FilledButton(
                    onPressed: () => setState(() => _drawIronSize = '4'),
                    style:
                        _compactFilledStyle(highlighted: _drawIronSize == '4'),
                    child: const Text('4" Iron'),
                  ),
                ),
                for (final type in types)
                  _equipmentButtonForLibrary(type,
                      outlined: outlined, isMobile: isMobile),
              ],
            ),
          ],
        );
      case _DrawerLibrarySection.tees:
        types = _teeOnlyTypes;
        outlined = true;
        title = 'Tees';
        break;
      case _DrawerLibrarySection.nineties:
        types = _elbowOnlyTypes;
        outlined = true;
        title = '90s';
        break;
      case _DrawerLibrarySection.bypass:
        types = const [_EquipmentType.bypass];
        outlined = true;
        title = 'Bypass';
        break;
      case _DrawerLibrarySection.labels:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Labels',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: OutlinedButton.icon(
                    onPressed: _hasSelectedItem ? _renameSelected : null,
                    icon: const Icon(Icons.drive_file_rename_outline),
                    label: const Text('Rename Label'),
                    style: _compactOutlineStyle(highlighted: true),
                  ),
                ),
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: OutlinedButton.icon(
                    onPressed: _selectedCanHaveProperties
                        ? _showSelectedProperties
                        : null,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Properties'),
                    style: _compactOutlineStyle(),
                  ),
                ),
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: FilledButton.icon(
                    onPressed: () => setState(() => _showLabels = !_showLabels),
                    icon: const Icon(Icons.label_outline),
                    label: Text(_showLabels ? 'Labels On' : 'Labels Off'),
                    style: _compactFilledStyle(highlighted: _showLabels),
                  ),
                ),
              ],
            ),
          ],
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFCDA56A),
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in types)
              _equipmentButtonForLibrary(type,
                  outlined: outlined, isMobile: isMobile),
          ],
        ),
      ],
    );
  }

  Widget _sideLibraryPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 8, 12),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Rig-Up Library',
                  style: TextStyle(
                    color: Color(0xFFCDA56A),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _showSideLibrary = false),
                icon: const Icon(Icons.close, color: Colors.white70),
                tooltip: 'Close library',
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap to place multiple pieces quickly. Panel stays open while you build.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _libraryCategoryTabs(isMobile: false),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: _libraryCategoryBody(isMobile: false),
            ),
          ),
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
          child: Text(group.toUpperCase(),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: _gold, fontWeight: FontWeight.bold)),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.all(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(type.icon, color: _gold, size: 24),
                  const SizedBox(height: 4),
                  Text(type.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  Widget _jobInfoSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF121417),
          border: Border.all(color: const Color(0xFF3A3A3A)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Job Info',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _company,
                    decoration: const InputDecoration(labelText: 'Company'),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _jobLocation,
                    decoration: const InputDecoration(
                      labelText: 'Well / Pad Name',
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _date,
                    decoration: const InputDecoration(labelText: 'Date'),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _preparedBy,
                    decoration: const InputDecoration(labelText: 'Prepared By'),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _notes,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    minLines: 1,
                    maxLines: 3,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar({required bool isWide}) {
    final hasSelected = _hasSelectedItem;
    final locked = _selectedItem?.locked ?? false;
    final drawIronLabel = _drawIronMode ? 'Stop Draw Iron' : 'Start Draw Iron';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0F),
        border: Border(bottom: BorderSide(color: Color(0xFF2E2E2E))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilledButton.icon(
              onPressed: () =>
                  setState(() => _showSideLibrary = !_showSideLibrary),
              icon: const Icon(Icons.view_sidebar_outlined),
              label: Text(_showSideLibrary ? 'Close Library' : 'Open Library'),
              style: _compactFilledStyle(highlighted: true),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _undoStack.isNotEmpty ? _undoLayoutChange : null,
              icon: const Icon(Icons.undo),
              label: const Text('Undo'),
              style: _compactOutlineStyle(),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _redoStack.isNotEmpty ? _redoLayoutChange : null,
              icon: const Icon(Icons.redo),
              label: const Text('Redo'),
              style: _compactOutlineStyle(),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _saveRigUp,
              icon: const Icon(Icons.save_alt),
              label: const Text('Save'),
              style: _compactFilledStyle(highlighted: true),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'More actions',
              onSelected: (value) {
                switch (value) {
                  case 'clear':
                    _confirmClearLayout();
                    break;
                  case 'duplicate':
                    _duplicateSelected();
                    break;
                  case 'lock':
                    _toggleSelectedLock();
                    break;
                  case 'delete':
                    _deleteSelected();
                    break;
                  case 'tools':
                    _showToolsDrawer();
                    break;
                  case 'drawIron':
                    setState(() {
                      _drawIronMode = !_drawIronMode;
                      _mobileDrawerSection = _DrawerLibrarySection.iron;
                      if (!isWide && _drawIronMode) {
                        _showSideLibrary = true;
                      }
                    });
                    break;
                  case 'loadRigUp':
                    _showLoadRigUps();
                    break;
                  case 'loadLayout':
                    _showLoadLayouts();
                    break;
                  case 'exportPdf':
                    _exportPdf();
                    break;
                  case 'sharePackage':
                    _shareRigUpPackage();
                    break;
                  case 'bom':
                    _showBillOfMaterials();
                    break;
                  case 'templates':
                    _showRigUpAssistant();
                    break;
                  case 'favorites':
                    _showFavorites();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'drawIron',
                  child: Text(drawIronLabel),
                ),
                const PopupMenuItem<String>(
                  value: 'loadRigUp',
                  child: Text('Load Rig-Up'),
                ),
                const PopupMenuItem<String>(
                  value: 'loadLayout',
                  child: Text('Load Layout'),
                ),
                const PopupMenuItem<String>(
                  value: 'exportPdf',
                  child: Text('Export PDF'),
                ),
                const PopupMenuItem<String>(
                  value: 'sharePackage',
                  child: Text('Share Package'),
                ),
                const PopupMenuItem<String>(
                  value: 'bom',
                  child: Text('Bill of Materials'),
                ),
                const PopupMenuItem<String>(
                  value: 'templates',
                  child: Text('Templates'),
                ),
                const PopupMenuItem<String>(
                  value: 'favorites',
                  child: Text('Favorites'),
                ),
                const PopupMenuItem<String>(
                  value: 'clear',
                  child: Text('Clear Layout'),
                ),
                PopupMenuItem<String>(
                  value: 'duplicate',
                  enabled: hasSelected,
                  child: const Text('Duplicate Selected'),
                ),
                PopupMenuItem<String>(
                  value: 'lock',
                  enabled: hasSelected,
                  child: Text(locked ? 'Unlock Selected' : 'Lock Selected'),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  enabled: hasSelected,
                  child: const Text('Delete Selected'),
                ),
                const PopupMenuItem<String>(
                  value: 'tools',
                  child: Text('More Tools'),
                ),
              ],
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1D21),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF4A4A4A)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.more_horiz, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'More',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _primaryActionBar({required bool isWide}) {
    final hasSelected = _hasSelectedItem;
    final locked = _selectedItem?.locked ?? false;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF111315),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _showSideLibrary = true;
                  _drawIronMode = false;
                });
              },
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Add Equipment'),
              style: _compactFilledStyle(highlighted: true),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _showSideLibrary = true;
                  _drawIronMode = true;
                  _ironStartPoint = null;
                });
              },
              icon: const Icon(Icons.edit_road),
              label: const Text('Add Iron'),
              style: _compactFilledStyle(highlighted: _drawIronMode),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                if (!_drawIronMode) return;
                setState(() {
                  _drawIronMode = false;
                  _ironStartPoint = null;
                });
              },
              icon: const Icon(Icons.pan_tool_alt_outlined),
              label: const Text('Select / Move'),
              style: _compactOutlineStyle(highlighted: !_drawIronMode),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: hasSelected ? _deleteSelected : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
              style: _compactOutlineStyle(highlighted: hasSelected),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: hasSelected ? _duplicateSelected : null,
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Duplicate'),
              style: _compactOutlineStyle(),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: hasSelected ? _toggleSelectedLock : null,
              icon: Icon(locked ? Icons.lock_open : Icons.lock_outline),
              label: Text(locked ? 'Unlock' : 'Lock'),
              style: _compactOutlineStyle(),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _confirmClearLayout,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear Layout'),
              style: _compactOutlineStyle(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileEquipmentDrawer() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: _showSideLibrary ? 360 : 56,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A3A)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _showSideLibrary = !_showSideLibrary),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.view_carousel_outlined, color: _gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _showSideLibrary ? 'Close Library' : 'Open Library',
                      style: const TextStyle(
                        color: Color(0xFFCDA56A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_showSideLibrary)
                    TextButton(
                      onPressed: () => setState(() => _showSideLibrary = false),
                      child: const Text('Done'),
                    ),
                  IconButton(
                    onPressed: () => setState(() => _showSideLibrary = false),
                    icon: Icon(
                      _showSideLibrary ? Icons.close : Icons.keyboard_arrow_up,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showSideLibrary)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _libraryCategoryTabs(isMobile: true),
                    const SizedBox(height: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        child: _libraryCategoryBody(isMobile: true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ironDrawControls() {
    final hasStart = _ironStartPoint != null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF14171B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_road, color: _gold),
              const SizedBox(width: 8),
              const Text(
                'DRAW IRON ACTIVE',
                style: TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Selected Size: ${_drawIronSize}"',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasStart
                ? 'Start point set. Tap next point to add straight iron, then keep tapping to extend.'
                : 'Tap once to set a start point, then tap next point to create horizontal or vertical iron.',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => setState(() => _drawIronSize = '2'),
                style: _compactFilledStyle(highlighted: _drawIronSize == '2'),
                child: const Text('2"'),
              ),
              FilledButton(
                onPressed: () => setState(() => _drawIronSize = '3'),
                style: _compactFilledStyle(highlighted: _drawIronSize == '3'),
                child: const Text('3"'),
              ),
              FilledButton(
                onPressed: () => setState(() => _drawIronSize = '4'),
                style: _compactFilledStyle(highlighted: _drawIronSize == '4'),
                child: const Text('4"'),
              ),
              FilledButton.icon(
                onPressed: _finishIronDrawing,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Finish / Done'),
                style: _compactFilledStyle(highlighted: true),
              ),
              OutlinedButton.icon(
                onPressed: _cancelIronDrawing,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel'),
                style: _compactOutlineStyle(highlighted: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _selectionQuickActionsBar() {
    final selected = _hasSelectedItem;
    final locked = _selectedItem?.locked ?? false;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF131519),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: _clearSelection,
              icon: const Icon(Icons.deselect),
              label: const Text('Clear Selection / Unselect'),
              style: _compactOutlineStyle(highlighted: true),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: selected ? _rotateSelected : null,
              icon: const Icon(Icons.rotate_right),
              label: const Text('Rotate'),
              style: _compactOutlineStyle(),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: selected ? _duplicateSelected : null,
              icon: const Icon(Icons.copy),
              label: const Text('Duplicate'),
              style: _compactOutlineStyle(),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: selected ? _toggleSelectedLock : null,
              icon: Icon(locked ? Icons.lock_open : Icons.lock),
              label: Text(locked ? 'Unlock' : 'Lock'),
              style: _compactOutlineStyle(),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: selected ? _renameSelected : null,
              icon: const Icon(Icons.drive_file_rename_outline),
              label: const Text('Rename'),
              style: _compactOutlineStyle(),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed:
                  _selectedCanHaveProperties ? _showSelectedProperties : null,
              icon: const Icon(Icons.edit_note),
              label: const Text('Properties'),
              style: _compactOutlineStyle(),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: selected ? _deleteSelected : null,
              icon: const Icon(Icons.delete),
              label: const Text('Delete'),
              style: _compactOutlineStyle(highlighted: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _floatingSelectionToolbar(
      _LayoutItem item, Size canvasSize, bool isLocked) {
    const width = 248.0;
    const height = 46.0;
    final top = (item.y - 58).clamp(8.0, canvasSize.height - height - 8);
    final left = (item.x + item.width + 12)
        .clamp(8.0, canvasSize.width - width - 8)
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1114),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: const Color(0xFFCDA56A).withValues(alpha: 0.8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: IconButton(
                onPressed: () => _duplicateSingleForQuickDrag(item),
                icon: const Icon(Icons.copy_outlined, color: Colors.white),
                tooltip: 'Duplicate',
              ),
            ),
            Expanded(
              child: IconButton(
                onPressed: _rotateSelected,
                icon: const Icon(Icons.rotate_right, color: Colors.white),
                tooltip: 'Rotate 90°',
              ),
            ),
            Expanded(
              child: IconButton(
                onPressed: _toggleSelectedLock,
                icon: Icon(
                  isLocked ? Icons.lock_open : Icons.lock_outline,
                  color: Colors.white,
                ),
                tooltip: isLocked ? 'Unlock' : 'Lock',
              ),
            ),
            Expanded(
              child: IconButton(
                onPressed: _deleteSelected,
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                tooltip: 'Delete',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exportImagePreview() {
    final layoutName = _layoutName.text.trim().isEmpty
        ? 'New Layout'
        : _layoutName.text.trim();
    final exportBounds = _pdfPlotBounds(_items);
    final exportScale =
        _pdfDrawScale(exportBounds, maxWidth: 620.0, maxHeight: 300.0);

    return Material(
      color: const Color(0xFF111315),
      child: Container(
        width: 900,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 46,
                  height: 46,
                  child: Image.asset(
                    'assets/images/app-icon.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.oil_barrel,
                      color: Color(0xFFCDA56A),
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'WellWerks',
                        style: TextStyle(
                          color: Color(0xFFCDA56A),
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        layoutName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D21),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3A3A3A)),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  if (_company.text.trim().isNotEmpty)
                    Text(
                      'Company: ${_company.text.trim()}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  if (_jobLocation.text.trim().isNotEmpty)
                    Text(
                      'Well / Pad: ${_jobLocation.text.trim()}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  if (_date.text.trim().isNotEmpty)
                    Text(
                      'Date: ${_date.text.trim()}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  if (_preparedBy.text.trim().isNotEmpty)
                    Text(
                      'Prepared By: ${_preparedBy.text.trim()}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  if (_notes.text.trim().isNotEmpty)
                    Text(
                      'Notes: ${_notes.text.trim()}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF121417),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF3A3A3A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Layout Drawing',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 760,
                    height: 360,
                    child: Stack(
                      children: [
                        if (_showGrid)
                          Positioned.fill(
                            child: CustomPaint(painter: _GridPainter()),
                          ),
                        if (_measureMode &&
                            _measurementStart != null &&
                            _measurementEnd != null) ...[
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _MeasurementPainter(
                                _measurementStart!,
                                _measurementEnd!,
                              ),
                            ),
                          ),
                          Positioned(
                            left:
                                ((_measurementStart!.dx + _measurementEnd!.dx) /
                                        2)
                                    .clamp(16, 760 - 180),
                            top:
                                ((_measurementStart!.dy + _measurementEnd!.dy) /
                                        2)
                                    .clamp(16, 360 - 40),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF121417),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: const Color(0xFFCDA56A)),
                              ),
                              child: Text(
                                'Distance: ${((_measurementEnd! - _measurementStart!).distance).toStringAsFixed(0)} px',
                                style: const TextStyle(
                                  color: Color(0xFFCDA56A),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                        for (final item in _visibleItems)
                          Positioned(
                            left:
                                (item.x - exportBounds.left) * exportScale + 24,
                            top: (item.y - exportBounds.top) * exportScale + 24,
                            width: item.width * exportScale,
                            height: item.height * exportScale,
                            child: _LayoutTile(
                              item: item,
                              selected: false,
                              showLabel: _showLabels,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1D2025),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3A3A3A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Equipment Labels',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      for (final item in _items)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121417),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF3A3A3A)),
                          ),
                          child: Text(
                            item.type.isIron
                                ? '${item.displayLabel} • ${item.ironSize}"'
                                : item.displayLabel,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _canvas() {
    return Column(
      children: [
        Offstage(
          offstage: true,
          child: RepaintBoundary(
            key: _exportImageKey,
            child: _exportImagePreview(),
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: _bg,
              border: Border.all(color: const Color(0xFF333333)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewportSize =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  _setViewportSize(viewportSize);
                  final canvasSize = _virtualCanvasSize;

                  return GestureDetector(
                    key: _canvasViewportKey,
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) {
                      final scenePoint =
                          _scenePointFromViewport(details.localPosition);
                      _handleCanvasTap(scenePoint);
                    },
                    child: InteractiveViewer(
                      transformationController: _canvasTransform,
                      minScale: 0.45,
                      maxScale: 3.5,
                      boundaryMargin: const EdgeInsets.all(420),
                      constrained: false,
                      panEnabled: true,
                      scaleEnabled: true,
                      child: SizedBox(
                        width: canvasSize.width,
                        height: canvasSize.height,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(painter: _GridPainter()),
                            ),
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
                                    border: Border.all(
                                        color: Colors.black, width: 2),
                                  ),
                                ),
                              ),
                            if (_snapIndicatorScene != null)
                              Positioned(
                                left: _snapIndicatorScene!.dx - 11,
                                top: _snapIndicatorScene!.dy - 11,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFFCDA56A)
                                          .withValues(alpha: 0.16),
                                      border: Border.all(
                                        color: const Color(0xFFCDA56A),
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (_items.isEmpty)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'Add equipment or turn on Draw Iron. Pinch to zoom and drag to pan this larger rig-up workspace.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 16),
                                  ),
                                ),
                              ),
                            for (final item in _items)
                              Positioned(
                                left: item.x - 8,
                                top: item.y - 8,
                                width: item.width + 16,
                                height: item.height + 16,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () => _multiSelectMode
                                      ? _toggleSelection(item.id)
                                      : _selectOnly(item.id),
                                  onDoubleTap: () {
                                    _selectOnly(item.id);
                                    if (!item.locked) {
                                      _rotateSelected();
                                    }
                                  },
                                  onLongPress: () {
                                    _selectOnly(item.id);
                                    if (!item.locked) {
                                      _duplicateSingleForQuickDrag(item);
                                    }
                                  },
                                  onPanStart: (details) =>
                                      _beginItemDrag(item, details),
                                  onPanUpdate: (details) =>
                                      _updateItemDrag(item, details),
                                  onPanEnd: (_) => _endItemDrag(item),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Positioned(
                                        left: 8,
                                        top: 8,
                                        width: item.width,
                                        height: item.height,
                                        child: _LayoutTile(
                                          item: item,
                                          selected:
                                              _selectedIds.contains(item.id),
                                          showLabel: _showLabels,
                                          snapHighlight:
                                              _snapCandidateIronId == item.id,
                                        ),
                                      ),
                                      if (_selectedIds.contains(item.id) &&
                                          (item.type ==
                                                  _EquipmentType
                                                      .ironHorizontal ||
                                              item.type ==
                                                  _EquipmentType
                                                      .ironVertical)) ...[
                                        _IronStretchHandle(
                                          item: item,
                                          leading: true,
                                          onPanStart: () => _recordUndo(),
                                          onPanUpdate: (details) =>
                                              _stretchStraightIron(
                                            item,
                                            details,
                                            true,
                                          ),
                                          onPanEnd: () {
                                            if (!_snapToGrid) return;
                                            setState(() {
                                              item.x = _snap(item.x).clamp(
                                                0.0,
                                                canvasSize.width - item.width,
                                              );
                                              item.y = _snap(item.y).clamp(
                                                0.0,
                                                canvasSize.height - item.height,
                                              );
                                            });
                                          },
                                        ),
                                        _IronStretchHandle(
                                          item: item,
                                          leading: false,
                                          onPanStart: () => _recordUndo(),
                                          onPanUpdate: (details) =>
                                              _stretchStraightIron(
                                            item,
                                            details,
                                            false,
                                          ),
                                          onPanEnd: () {
                                            if (!_snapToGrid) return;
                                            setState(() {
                                              item.x = _snap(item.x).clamp(
                                                0.0,
                                                canvasSize.width - item.width,
                                              );
                                              item.y = _snap(item.y).clamp(
                                                0.0,
                                                canvasSize.height - item.height,
                                              );
                                            });
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            if (_selectedItems.length == 1 &&
                                _selectedItem != null)
                              _floatingSelectionToolbar(
                                _selectedItem!,
                                canvasSize,
                                _selectedItem!.locked,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _LayoutAlign { left, right, top, bottom, horizontalCenter, verticalCenter }

enum _LayoutDistribution { horizontal, vertical }

enum _DrawerLibrarySection { equipment, iron, tees, nineties, bypass, labels }

class _SnapCandidate {
  final int ironId;
  final bool horizontal;
  final Offset indicator;
  final double score;

  const _SnapCandidate({
    required this.ironId,
    required this.horizontal,
    required this.indicator,
    required this.score,
  });
}

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
  bool get isIron =>
      name.startsWith('iron') ||
      name.startsWith('elbow') ||
      name.startsWith('tee') ||
      this == _EquipmentType.bypass;

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
    if (this == _EquipmentType.wellhead) return 98;
    if (this == _EquipmentType.plugCatcher) return 170;
    if (this == _EquipmentType.lineHeater) return 178;
    if (this == _EquipmentType.facilities) return 220;
    if (this == _EquipmentType.sphericalSandSep) return 134;
    if (this == _EquipmentType.cyclonicSandSep) return 116;
    if (this == _EquipmentType.esdValve) return 64;
    if (this == _EquipmentType.ironHorizontal) return 150;
    if (this == _EquipmentType.ironVertical) return 28;
    if (this == _EquipmentType.bypass) return 66;
    if (name.startsWith('tee')) return 42;
    if (name.startsWith('elbow')) return 42;
    if (isIron) return 76;
    return 116;
  }

  double get defaultHeight {
    if (this == _EquipmentType.wellhead) return 64;
    if (this == _EquipmentType.plugCatcher) return 94;
    if (this == _EquipmentType.lineHeater) return 98;
    if (this == _EquipmentType.facilities) return 112;
    if (this == _EquipmentType.sphericalSandSep) return 124;
    if (this == _EquipmentType.cyclonicSandSep) return 110;
    if (this == _EquipmentType.esdValve) return 44;
    if (this == _EquipmentType.ironHorizontal) return 24;
    if (this == _EquipmentType.ironVertical) return 150;
    if (this == _EquipmentType.bypass) return 34;
    if (name.startsWith('tee')) return 42;
    if (name.startsWith('elbow')) return 42;
    if (isIron) return 76;
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

  _LayoutItem(
      {required this.id,
      required this.type,
      required this.x,
      required this.y,
      required this.width,
      required this.height,
      Map<String, String>? properties,
      this.rotationTurns = 0,
      this.locked = false})
      : properties = properties ?? <String, String>{};

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'properties': properties,
        'rotationTurns': rotationTurns,
        'locked': locked
      };

  factory _LayoutItem.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? _EquipmentType.plugCatcher.name;
    final type = _EquipmentType.values.firstWhere(
        (item) => item.name == typeName,
        orElse: () => _EquipmentType.plugCatcher);
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

class _BillOfMaterialsData {
  final Map<String, int> categories;
  final Map<String, int> ironSizes;
  final List<String> customLabels;

  const _BillOfMaterialsData({
    required this.categories,
    required this.ironSizes,
    required this.customLabels,
  });
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
    for (final key in [
      'wellName',
      'tankName',
      'company',
      'chokeSize',
      'status',
      'name',
      'assignedWell'
    ]) {
      final value = properties[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  String get canvasEquipmentLabel {
    if (type == _EquipmentType.cyclonicSandSep) return 'Cyclonic Sep';
    if (type == _EquipmentType.sphericalSandSep) return 'Spherical Sep';
    return displayLabel;
  }
}

class _LayoutTile extends StatelessWidget {
  final _LayoutItem item;
  final bool selected;
  final bool showLabel;
  final bool snapHighlight;

  const _LayoutTile(
      {required this.item,
      required this.selected,
      this.showLabel = true,
      this.snapHighlight = false});

  double get _labelBottomOffset {
    return -15;
  }

  Widget _labelChip({
    required String text,
    required bool compact,
    required Color textColor,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 6, vertical: compact ? 1.5 : 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.76),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCDA56A).withOpacity(.55)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: textColor,
          fontSize: compact ? 9.5 : 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIron = item.type.isIron;
    final showSnapHighlight = snapHighlight &&
        (item.type == _EquipmentType.ironHorizontal ||
            item.type == _EquipmentType.ironVertical);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(
            color: selected || showSnapHighlight
                ? const Color(0xFFCDA56A)
                : Colors.transparent,
            width: selected ? 2.5 : (showSnapHighlight ? 2.0 : 1.2)),
        borderRadius: BorderRadius.circular(
            item.type == _EquipmentType.sphericalSandSep ? 999 : 14),
        boxShadow: selected || showSnapHighlight
            ? [
                BoxShadow(
                    color: const Color(0xFFCDA56A)
                        .withOpacity(showSnapHighlight ? .4 : .25),
                    blurRadius: showSnapHighlight ? 16 : 12)
              ]
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ShapePainter(item.type,
                  turns: item.rotationTurns, ironSize: item.ironSize),
              child: isIron
                  ? const SizedBox.expand()
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final shortest = math.min(
                            constraints.maxWidth, constraints.maxHeight);
                        final compact = constraints.maxHeight < 78 ||
                            constraints.maxWidth < 120;
                        final inset = (shortest * 0.12).clamp(4.0, 12.0);
                        final iconSize = (shortest * 0.36)
                            .clamp(16.0, compact ? 24.0 : 30.0);

                        return Padding(
                          padding: EdgeInsets.all(inset),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: item.type == _EquipmentType.facilities
                                  ? const Color(0xFF202327)
                                  : const Color(0xFF191B1F),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFFCDA56A)
                                    : const Color(0xFF4A4A4A),
                                width: selected ? 1.8 : 1.0,
                              ),
                              borderRadius: BorderRadius.circular(
                                  item.type == _EquipmentType.sphericalSandSep
                                      ? 999
                                      : 12),
                            ),
                            child: Center(
                              child: Icon(
                                item.type.icon,
                                color: const Color(0xFFF3C77D),
                                size: iconSize,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          if (showLabel && !isIron)
            Positioned(
              left: 0,
              right: 0,
              bottom: _labelBottomOffset,
              child: Center(
                child: _labelChip(
                  text: item.canvasEquipmentLabel,
                  compact: item.width < 120 || item.height < 78,
                  textColor: Colors.white,
                ),
              ),
            ),
          if (showLabel &&
              !isIron &&
              item.primaryPropertyLabel.isNotEmpty &&
              item.height >= 78)
            Positioned(
              left: 4,
              right: 4,
              bottom: _labelBottomOffset - 14,
              child: Text(
                item.primaryPropertyLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFCDA56A),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
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
    final left = isHorizontal
        ? (leading ? -9.0 : item.width - 9.0)
        : (item.width / 2) - 9.0;
    final top = isHorizontal
        ? (item.height / 2) - 9.0
        : (leading ? -9.0 : item.height - 9.0);

    return Positioned(
      left: left + 8,
      top: top + 8,
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
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(.35), blurRadius: 5)
            ],
          ),
          child: Icon(isHorizontal ? Icons.drag_handle : Icons.unfold_more,
              size: 12, color: Colors.black),
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
    final strokeWidth = ironSize == '2' ? 1.4 : (ironSize == '4' ? 2.0 : 1.7);
    final iron = Paint()
      ..color = const Color(0xFFD7D7D7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    final shadow = Paint()
      ..color = Colors.black.withOpacity(.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 1.0
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
      final p = Path()
        ..moveTo(size.width * .08, size.height * .5)
        ..lineTo(size.width * .92, size.height * .5);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.ironVertical) {
      final p = Path()
        ..moveTo(size.width * .5, size.height * .08)
        ..lineTo(size.width * .5, size.height * .92);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.elbowUpRight) {
      final p = Path()
        ..moveTo(size.width * .5, size.height * .92)
        ..lineTo(size.width * .5, size.height * .5)
        ..lineTo(size.width * .92, size.height * .5);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.elbowRightDown) {
      final p = Path()
        ..moveTo(size.width * .08, size.height * .5)
        ..lineTo(size.width * .5, size.height * .5)
        ..lineTo(size.width * .5, size.height * .92);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.elbowDownLeft) {
      final p = Path()
        ..moveTo(size.width * .5, size.height * .08)
        ..lineTo(size.width * .5, size.height * .5)
        ..lineTo(size.width * .08, size.height * .5);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.elbowLeftUp) {
      final p = Path()
        ..moveTo(size.width * .92, size.height * .5)
        ..lineTo(size.width * .5, size.height * .5)
        ..lineTo(size.width * .5, size.height * .08);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.teeUp) {
      final p = Path()
        ..moveTo(size.width * .08, size.height * .5)
        ..lineTo(size.width * .92, size.height * .5)
        ..moveTo(size.width * .5, size.height * .5)
        ..lineTo(size.width * .5, size.height * .08);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.teeRight) {
      final p = Path()
        ..moveTo(size.width * .5, size.height * .08)
        ..lineTo(size.width * .5, size.height * .92)
        ..moveTo(size.width * .5, size.height * .5)
        ..lineTo(size.width * .92, size.height * .5);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.teeDown) {
      final p = Path()
        ..moveTo(size.width * .08, size.height * .5)
        ..lineTo(size.width * .92, size.height * .5)
        ..moveTo(size.width * .5, size.height * .5)
        ..lineTo(size.width * .5, size.height * .92);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.teeLeft) {
      final p = Path()
        ..moveTo(size.width * .5, size.height * .08)
        ..lineTo(size.width * .5, size.height * .92)
        ..moveTo(size.width * .5, size.height * .5)
        ..lineTo(size.width * .08, size.height * .5);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.bypass) {
      final leftX = size.width * .24;
      final rightX = size.width * .76;
      final centerY = size.height * .5;
      final branchLength = size.height * .18;
      final stemLength = size.width * .12;
      final valveRadius = ironSize == '4' ? 3.0 : (ironSize == '2' ? 2.2 : 2.6);
      final branchDirection = size.height * .12;

      void drawValveAt(double x, double y, {bool horizontal = true}) {
        final valveFill = Paint()
          ..color = const Color(0xFFD7D7D7)
          ..style = PaintingStyle.fill;
        final valveBorder = Paint()
          ..color = Colors.black.withOpacity(.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;
        final center = Offset(x, y);
        canvas.drawCircle(center, valveRadius, valveFill);
        canvas.drawCircle(center, valveRadius, valveBorder);
        if (horizontal) {
          canvas.drawLine(Offset(x - valveRadius * .8, y),
              Offset(x + valveRadius * .8, y), valveBorder);
        } else {
          canvas.drawLine(Offset(x, y - valveRadius * .8),
              Offset(x, y + valveRadius * .8), valveBorder);
        }
      }

      void drawTeeAt(double x) {
        final body = Path()
          ..moveTo(x - stemLength, centerY)
          ..lineTo(x + stemLength, centerY)
          ..moveTo(x, centerY)
          ..lineTo(x, centerY - branchDirection);
        drawIron(body);

        final branch = Path()
          ..moveTo(x, centerY - branchDirection)
          ..lineTo(x, centerY - branchLength);
        drawIron(branch);
        drawValveAt(x, centerY - branchLength, horizontal: false);
      }

      final mainLine = Path()
        ..moveTo(leftX + stemLength, centerY)
        ..lineTo(rightX - stemLength, centerY);
      drawIron(mainLine);
      drawTeeAt(leftX);
      drawTeeAt(rightX);
      drawValveAt(size.width * .5, centerY, horizontal: true);
      return;
    }

    if (type == _EquipmentType.wellhead) {
      canvas.drawCircle(Offset(size.width * .5, size.height * .5),
          size.shortestSide * .22, accent);
      canvas.drawLine(Offset(size.width * .5, size.height * .18),
          Offset(size.width * .5, size.height * .82), accent);
      canvas.drawLine(Offset(size.width * .2, size.height * .5),
          Offset(size.width * .8, size.height * .5), accent);
    } else if (type == _EquipmentType.esdValve) {
      canvas.drawLine(Offset(size.width * .16, size.height * .5),
          Offset(size.width * .84, size.height * .5), accent);
      canvas.drawCircle(Offset(size.width * .5, size.height * .5),
          size.shortestSide * .18, accent);
      canvas.drawLine(Offset(size.width * .4, size.height * .38),
          Offset(size.width * .6, size.height * .62), accent);
      canvas.drawLine(Offset(size.width * .6, size.height * .38),
          Offset(size.width * .4, size.height * .62), accent);
    } else if (type == _EquipmentType.lineHeater) {
      final rect = Rect.fromLTWH(size.width * .16, size.height * .25,
          size.width * .68, size.height * .5);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(12)), accent);
      final flame = Path()
        ..moveTo(size.width * .5, size.height * .68)
        ..cubicTo(size.width * .35, size.height * .55, size.width * .48,
            size.height * .44, size.width * .45, size.height * .32)
        ..cubicTo(size.width * .62, size.height * .43, size.width * .68,
            size.height * .54, size.width * .5, size.height * .68);
      canvas.drawPath(flame, accent);
    } else if (type == _EquipmentType.flowbackTank ||
        type == _EquipmentType.productionTank) {
      final rect = Rect.fromLTWH(size.width * .18, size.height * .16,
          size.width * .64, size.height * .68);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(18)), accent);
      canvas.drawLine(Offset(size.width * .25, size.height * .28),
          Offset(size.width * .75, size.height * .28), accent);
      canvas.drawLine(Offset(size.width * .25, size.height * .72),
          Offset(size.width * .75, size.height * .72), accent);
    } else if (type == _EquipmentType.chokeManifold) {
      canvas.drawLine(Offset(size.width * .18, size.height * .5),
          Offset(size.width * .82, size.height * .5), accent);
      canvas.drawCircle(Offset(size.width * .38, size.height * .5), 7, accent);
      canvas.drawCircle(Offset(size.width * .62, size.height * .5), 7, accent);
    } else if (type == _EquipmentType.plugCatcher) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(size.width * .15, size.height * .28,
                  size.width * .7, size.height * .44),
              const Radius.circular(8)),
          accent);
      canvas.drawLine(Offset(size.width * .25, size.height * .35),
          Offset(size.width * .75, size.height * .65), accent);
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePainter oldDelegate) =>
      oldDelegate.type != type ||
      oldDelegate.turns != turns ||
      oldDelegate.ironSize != ironSize;
}

List<pw.Widget> _pdfLayoutWidgets({
  required List<_LayoutItem> items,
  required double scale,
  required double offsetX,
  required double offsetY,
  required double canvasWidth,
  required double canvasHeight,
}) {
  final widgets = <pw.Widget>[];
  for (final item in items) {
    final left = offsetX + item.x * scale;
    final top = offsetY + item.y * scale;
    final width = item.width * scale;
    final height = item.height * scale;

    if (item.type == _EquipmentType.ironHorizontal ||
        item.type == _EquipmentType.ironVertical) {
      widgets.add(
        pw.Positioned(
          left: left,
          top: top + height / 2 - 1,
          child: pw.Container(
            width: width,
            height: 2,
            color: const PdfColor.fromInt(0xFFD7D7D7),
          ),
        ),
      );
    } else if (item.type == _EquipmentType.bypass) {
      widgets.add(
        pw.Positioned(
          left: left,
          top: top,
          child: pw.Container(
            width: width,
            height: height,
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFF1E2328),
              border: pw.Border.all(
                color: const PdfColor.fromInt(0xFFCDA56A),
                width: 0.6,
              ),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
          ),
        ),
      );
    } else {
      widgets.add(
        pw.Positioned(
          left: left,
          top: top,
          child: pw.Container(
            width: width,
            height: height,
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFF1E2328),
              border: pw.Border.all(
                color: const PdfColor.fromInt(0xFFCDA56A),
                width: 0.6,
              ),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Center(
              child: pw.Text(
                item.displayLabel,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
              ),
            ),
          ),
        ),
      );
    }
  }

  return widgets;
}

class _MeasurementPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  const _MeasurementPainter(this.start, this.end);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCDA56A)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, paint);
    canvas.drawCircle(start, 5, paint..style = PaintingStyle.fill);
    canvas.drawCircle(end, 5, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _MeasurementPainter oldDelegate) =>
      oldDelegate.start != start || oldDelegate.end != end;
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
