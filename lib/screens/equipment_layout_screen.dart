// ignore_for_file: unused_element, curly_braces_in_flow_control_structures, prefer_const_constructors, deprecated_member_use, unnecessary_brace_in_string_interps

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
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

class _EquipmentLayoutScreenState extends State<EquipmentLayoutScreen>
    with WidgetsBindingObserver {
  final List<_LayoutItem> _items = [];
  int? _selectedId;
  final Set<int> _selectedIds = <int>{};
  final bool _multiSelectMode = false;
  bool _drawIronMode = false;
  String _drawIronSize = '3';
  final List<String> _undoStack = <String>[];
  final List<String> _redoStack = <String>[];
  final List<String> _historyLog = <String>[];
  static const int _maxHistory = 40;
  int _nextId = 1;
  bool _snapToGrid = false;
  bool _measureMode = false;
  bool _showEquipment = true;
  bool _showIron = true;
  bool _showLabels = false;
  bool _showConnectionPoints = false;
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
  bool? _selectedEndpointLeading;
  String? _selectedBypassHandle;
  _ActiveEndpointDrag? _activeEndpointDrag;
  _InteractionMode _interactionMode = _InteractionMode.idle;
  bool _duplicateInProgress = false;
  bool _arrowHoldTriggered = false;
  Timer? _arrowRepeatTimer;
  Timer? _arrowRepeatDelayTimer;
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
  bool _libraryKeepOpen = true;
  bool _moveControlsActive = false;
  double _mobileLibraryHeight = 0;
  int? _dragPreviewItemId;
  Offset? _dragPreviewScenePosition;
  Offset? _libraryDragScenePoint;
  _ConnectionTarget? _drawIronStartTarget;
  _ConnectionTarget? _drawIronHoverTarget;
  Offset? _drawIronPointerScene;
  _ConnectionTarget? _pendingContinueIronTarget;
  String? _pendingContinueIronSize;
  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();
  JobSetup? _activeJob;

  Color get _gold => Theme.of(context).colorScheme.primary;
  Color get _bg => Theme.of(context).colorScheme.surface;
  static const double _endpointHandleVisibleSize = 22.0;
  static const double _endpointHandleTouchSize = 44.0;
  static const double _toolbarViewportPadding = 8.0;
  static const double _toolbarSelectionGap = 16.0;
  static const double _toolbarBottomClearance = 84.0;
  static const double _equipmentAnchorSnapRadius = 24.0;
  static const double _selectionStripHeight = 118.0;
  static const double _mobileLibraryMinHeight = 56.0;
  static const double _mobileLibraryDefaultFraction = 0.38;
  static const double _mobileLibraryMaxFraction = 0.82;
  static const double _dragLiftScreenOffsetY = 64.0;
  static const double _connectionSnapRadius = 24.0;
  static const String _labelsPrefKey = 'wellwerks_layout_show_labels_v1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recoveryState.saveLastModule(RecoveryModules.layoutDesigner);
    _canvasTransform.addListener(_handleCanvasTransformChanged);
    _loadLayout();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopArrowRepeat();
    _canvasTransform.removeListener(_handleCanvasTransformChanged);
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

  Offset _viewportPointFromScene(Offset scenePoint) {
    return MatrixUtils.transformPoint(_canvasTransform.value, scenePoint);
  }

  void _handleCanvasTransformChanged() {
    if (!mounted || _selectedItem == null) return;
    setState(() {});
  }

  Offset _scenePointFromGlobal(Offset globalPoint) {
    final context = _canvasViewportKey.currentContext;
    if (context == null) return globalPoint;
    final box = context.findRenderObject();
    if (box is! RenderBox) return globalPoint;
    final viewportPoint = box.globalToLocal(globalPoint);
    return _scenePointFromViewport(viewportPoint);
  }

  Offset _sceneDeltaFromScreen(Offset screenDelta) {
    final originScene = _scenePointFromViewport(Offset.zero);
    final translatedScene = _scenePointFromViewport(screenDelta);
    return translatedScene - originScene;
  }

  double _sceneRadiusFromScreen(double screenPixels) {
    return _sceneDeltaFromScreen(Offset(screenPixels, 0)).distance;
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

  double _effectiveMobileLibraryHeight() {
    if (_viewportSize.height <= 0) return _mobileLibraryMinHeight;
    final desired = _mobileLibraryHeight > 0
        ? _mobileLibraryHeight
        : (_viewportSize.height * _mobileLibraryDefaultFraction);
    final maxHeight = (_viewportSize.height * _mobileLibraryMaxFraction)
        .clamp(_mobileLibraryMinHeight, _viewportSize.height - 24);
    return desired.clamp(_mobileLibraryMinHeight, maxHeight).toDouble();
  }

  Offset _visibleCanvasPlacementCenter({required bool isWide}) {
    if (isWide || !_showSideLibrary) {
      return _viewportCenterOnCanvas();
    }
    final libraryHeight = _effectiveMobileLibraryHeight();
    const topInset = 14.0;
    final bottomInset = libraryHeight + 24.0;
    final usableHeight = (_viewportSize.height - topInset - bottomInset).clamp(
      80.0,
      _viewportSize.height,
    );
    final centerViewport = Offset(
      (_viewportSize.width <= 0 ? 240.0 : _viewportSize.width / 2),
      topInset + (usableHeight / 2),
    );
    return _clampToCanvas(_scenePointFromViewport(centerViewport));
  }

  void _clearDragPreview() {
    _dragPreviewItemId = null;
    _dragPreviewScenePosition = null;
  }

  Future<void> _persistShowLabelsPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_labelsPrefKey, _showLabels);
  }

  void _toggleShowEquipmentLabels() {
    setState(() => _showLabels = !_showLabels);
    _persistShowLabelsPreference();
  }

  void _startConnectIronMode(
    String size, {
    bool minimizeLibrary = true,
    _ConnectionTarget? initialTarget,
  }) {
    _stopArrowRepeat();
    setState(() {
      _drawIronSize = size;
      _drawIronMode = true;
      _interactionMode = _InteractionMode.placeIron;
      _drawIronStartTarget = initialTarget;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = initialTarget?.point;
      _pendingContinueIronTarget = null;
      _pendingContinueIronSize = null;
      if (minimizeLibrary) {
        _showSideLibrary = false;
      }
    });
  }

  void _enterDrawIronMode({
    bool minimizeLibrary = true,
    _ConnectionTarget? initialTarget,
  }) {
    _startConnectIronMode(
      _drawIronSize,
      minimizeLibrary: minimizeLibrary,
      initialTarget: initialTarget,
    );
  }

  void _clearDrawIronSelection({bool exitMode = false}) {
    setState(() {
      _drawIronStartTarget = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      if (exitMode) {
        _drawIronMode = false;
        _interactionMode = _InteractionMode.idle;
        _pendingContinueIronTarget = null;
        _pendingContinueIronSize = null;
      }
    });
  }

  String get _drawIronStatusText {
    if (!_drawIronMode) return '';
    if (_drawIronStartTarget == null) return 'Select starting point';
    return 'Select destination';
  }

  void _openEquipmentDrawer(
      {_DrawerLibrarySection section = _DrawerLibrarySection.equipment}) {
    _stopArrowRepeat();
    setState(() {
      _dragSceneStart = null;
      _dragItemStart.clear();
      _dragActive = false;
      _activeEndpointDrag = null;
      _snapCandidateIronId = null;
      _snapIndicatorScene = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      _interactionMode =
          _drawIronMode ? _InteractionMode.placeIron : _InteractionMode.idle;
      if (!_drawIronMode) {
        _selectedId = null;
        _selectedEndpointLeading = null;
        _selectedBypassHandle = null;
        _selectedIds.clear();
      }
      _showSideLibrary = true;
      if (_mobileLibraryHeight <= _mobileLibraryMinHeight) {
        _mobileLibraryHeight =
            (_viewportSize.height * _mobileLibraryDefaultFraction)
                .clamp(_mobileLibraryMinHeight, _viewportSize.height * 0.8)
                .toDouble();
      }
      _mobileDrawerSection = section;
    });
  }

  void _toggleSideLibrary() {
    _stopArrowRepeat();
    setState(() {
      final opening = !_showSideLibrary;
      _dragSceneStart = null;
      _dragItemStart.clear();
      _dragActive = false;
      _activeEndpointDrag = null;
      _snapCandidateIronId = null;
      _snapIndicatorScene = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      _interactionMode =
          _drawIronMode ? _InteractionMode.placeIron : _InteractionMode.idle;
      if (opening && !_drawIronMode) {
        _selectedId = null;
        _selectedEndpointLeading = null;
        _selectedBypassHandle = null;
        _selectedIds.clear();
      }
      _showSideLibrary = opening;
      if (opening && _mobileLibraryHeight <= _mobileLibraryMinHeight) {
        _mobileLibraryHeight =
            (_viewportSize.height * _mobileLibraryDefaultFraction)
                .clamp(_mobileLibraryMinHeight, _viewportSize.height * 0.8)
                .toDouble();
      }
    });
  }

  double _interactionPaddingForItem(_LayoutItem item) {
    if (_isStraightIronType(item.type)) return 24.0;
    if (item.type == _EquipmentType.bypass) return 20.0;
    return 12.0;
  }

  bool get _showAnchorsForConnection {
    return _showConnectionPoints || _activeEndpointDrag != null;
  }

  _LayoutItem? get _selectedStraightIron {
    final selected = _selectedItem;
    if (selected == null || !_isStraightIronType(selected.type)) {
      return null;
    }
    return selected;
  }

  bool _shouldShowAnchorCandidate(_EquipmentAnchorCandidate anchor) {
    if (_showConnectionPoints) return true;
    final active = _activeEndpointDrag;
    if (active == null) return false;
    final radius = _sceneRadiusFromScreen(_connectionSnapRadius * 1.4);
    return (anchor.point - active.worldPosition).distance <= radius;
  }

  void _toggleMoveControls() {
    if (!_hasSelectedItem) return;
    setState(() => _moveControlsActive = !_moveControlsActive);
  }

  void _toggleShowConnectionPoints() {
    setState(() => _showConnectionPoints = !_showConnectionPoints);
  }

  _LayoutItem? _itemAtScenePoint(Offset scenePoint) {
    for (final item in _items.reversed) {
      if (!_itemIsVisible(item)) continue;
      final pad = _interactionPaddingForItem(item);
      final hitRect = Rect.fromLTWH(
        item.x - pad,
        item.y - pad,
        item.width + (pad * 2),
        item.height + (pad * 2),
      );
      if (hitRect.contains(scenePoint)) {
        return item;
      }
    }
    return null;
  }

  bool get _hideFloatingToolbar =>
      _interactionMode == _InteractionMode.itemDrag ||
      _interactionMode == _InteractionMode.stretchEndpoint ||
      _interactionMode == _InteractionMode.attachBypass;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      setState(() {
        _interactionMode =
            _drawIronMode ? _InteractionMode.placeIron : _InteractionMode.idle;
      });
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _resetTransientInteractionState();
    }
  }

  void _resetTransientInteractionState() {
    _stopArrowRepeat();
    if (!mounted) {
      _dragSceneStart = null;
      _dragItemStart.clear();
      _dragActive = false;
      _activeEndpointDrag = null;
      _snapCandidateIronId = null;
      _snapIndicatorScene = null;
      _clearDragPreview();
      _libraryDragScenePoint = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      _selectedEndpointLeading = null;
      _selectedBypassHandle = null;
      _interactionMode =
          _drawIronMode ? _InteractionMode.placeIron : _InteractionMode.idle;
      return;
    }
    setState(() {
      _dragSceneStart = null;
      _dragItemStart.clear();
      _dragActive = false;
      _activeEndpointDrag = null;
      _snapCandidateIronId = null;
      _snapIndicatorScene = null;
      _clearDragPreview();
      _libraryDragScenePoint = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      _selectedEndpointLeading = null;
      _selectedBypassHandle = null;
      _interactionMode =
          _drawIronMode ? _InteractionMode.placeIron : _InteractionMode.idle;
    });
  }

  void _toggleSnapToGrid() {
    _stopArrowRepeat();
    setState(() {
      _snapToGrid = !_snapToGrid;
      _activeEndpointDrag = null;
      _snapCandidateIronId = null;
      _snapIndicatorScene = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      _selectedEndpointLeading = null;
      _selectedBypassHandle = null;
      _interactionMode =
          _drawIronMode ? _InteractionMode.placeIron : _InteractionMode.idle;
    });
  }

  void _stopArrowRepeat() {
    _arrowRepeatDelayTimer?.cancel();
    _arrowRepeatDelayTimer = null;
    _arrowRepeatTimer?.cancel();
    _arrowRepeatTimer = null;
    _arrowHoldTriggered = false;
  }

  void _moveSelectedBy(Offset delta, {bool recordHistory = true}) {
    final moving = _selectedItems;
    if (moving.isEmpty) return;
    if (moving.every(_segmentMoveBlocked)) return;

    void applyMove() {
      final canvasSize = _virtualCanvasSize;
      for (final item in moving) {
        if (_segmentMoveBlocked(item)) continue;
        final origin = Offset(item.x, item.y);
        final desired = Offset(origin.dx + delta.dx, origin.dy + delta.dy);
        if (item.type == _EquipmentType.bypass &&
            (_bypassAttachmentIron(item, 'Primary') != null ||
                _bypassAttachmentIron(item, 'Secondary') != null)) {
          _slideBypassOnRail(item, desired);
          continue;
        }
        if (_isFittingType(item.type)) {
          final placed =
              _resolveFittingPlacement(item, desired, allowNewSnap: true);
          item.x = placed.dx;
          item.y = placed.dy;
          continue;
        }
        item.x = desired.dx.clamp(0.0, canvasSize.width - item.width);
        item.y = desired.dy.clamp(0.0, canvasSize.height - item.height);
      }
      _reflowSnappedFittings();
    }

    if (recordHistory) {
      _runHistoryChange(applyMove);
    } else {
      setState(applyMove);
    }
  }

  Offset _nudgeDelta(Offset directionUnit) {
    final step = _snapToGrid ? 2.0 : 1.0;
    return Offset(directionUnit.dx * step, directionUnit.dy * step);
  }

  void _nudgeSelectionBy(Offset directionUnit) {
    _moveSelectedBy(_nudgeDelta(directionUnit));
  }

  void _startArrowRepeat(Offset directionUnit) {
    _stopArrowRepeat();
    if (_selectedItems.every(_segmentMoveBlocked)) return;
    _arrowRepeatDelayTimer = Timer(const Duration(milliseconds: 380), () {
      if (!mounted ||
          _selectedItems.isEmpty ||
          _selectedItems.every(_segmentMoveBlocked)) {
        return;
      }
      _arrowHoldTriggered = true;
      _recordUndo();
      _moveSelectedBy(_nudgeDelta(directionUnit), recordHistory: false);
      _arrowRepeatTimer =
          Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted ||
            _selectedItems.isEmpty ||
            _selectedItems.every(_segmentMoveBlocked)) {
          _stopArrowRepeat();
          return;
        }
        _moveSelectedBy(_nudgeDelta(directionUnit), recordHistory: false);
      });
    });
  }

  Widget _selectionNudgeButton({
    required IconData icon,
    required String tooltip,
    required Offset directionUnit,
    bool disabled = false,
    bool isCenter = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: disabled ? 0.45 : 1.0,
        child: Material(
          color: const Color(0xFF15181D),
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: disabled || isCenter
                ? null
                : (_) => _startArrowRepeat(directionUnit),
            onTapUp: disabled || isCenter
                ? null
                : (_) {
                    _arrowRepeatDelayTimer?.cancel();
                    _arrowRepeatDelayTimer = null;
                    _arrowRepeatTimer?.cancel();
                    _arrowRepeatTimer = null;
                  },
            onTapCancel: disabled || isCenter ? null : _stopArrowRepeat,
            onTap: disabled
                ? null
                : () {
                    if (isCenter) {
                      _stopArrowRepeat();
                      _clearSelection();
                      return;
                    }
                    if (!_arrowHoldTriggered) {
                      _nudgeSelectionBy(directionUnit);
                    }
                    _arrowHoldTriggered = false;
                  },
            child: SizedBox(
              width: 20,
              height: 20,
              child: Icon(icon, color: _gold, size: isCenter ? 13 : 17),
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionDPad({required bool disabled}) {
    const buttonSpan = 28.0;
    const gridSpan = 96.0;
    return Container(
      key: const ValueKey<String>('selection-dpad'),
      width: 108,
      height: 108,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1014),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: SizedBox(
        width: gridSpan,
        height: gridSpan,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: (gridSpan - buttonSpan) / 2,
              child: _selectionNudgeButton(
                icon: Icons.keyboard_arrow_up,
                tooltip: 'Move Up',
                directionUnit: const Offset(0, -1),
                disabled: disabled,
              ),
            ),
            Positioned(
              top: (gridSpan - buttonSpan) / 2,
              left: 0,
              child: _selectionNudgeButton(
                icon: Icons.keyboard_arrow_left,
                tooltip: 'Move Left',
                directionUnit: const Offset(-1, 0),
                disabled: disabled,
              ),
            ),
            Positioned(
              top: (gridSpan - buttonSpan) / 2,
              left: (gridSpan - buttonSpan) / 2,
              child: _selectionNudgeButton(
                icon: Icons.close,
                tooltip: 'Deselect',
                directionUnit: Offset.zero,
                isCenter: true,
              ),
            ),
            Positioned(
              top: (gridSpan - buttonSpan) / 2,
              left: gridSpan - buttonSpan,
              child: _selectionNudgeButton(
                icon: Icons.keyboard_arrow_right,
                tooltip: 'Move Right',
                directionUnit: const Offset(1, 0),
                disabled: disabled,
              ),
            ),
            Positioned(
              top: gridSpan - buttonSpan,
              left: (gridSpan - buttonSpan) / 2,
              child: _selectionNudgeButton(
                icon: Icons.keyboard_arrow_down,
                tooltip: 'Move Down',
                directionUnit: const Offset(0, 1),
                disabled: disabled,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _selectedConnectionDots(_LayoutItem item) {
    if (item.type.isIron || item.type == _EquipmentType.bypass) {
      return const <Widget>[];
    }

    final points = <Offset>[
      Offset(item.width / 2, 0),
      Offset(item.width, item.height / 2),
      Offset(item.width / 2, item.height),
      Offset(0, item.height / 2),
    ];

    return [
      for (final point in points)
        Positioned(
          left: point.dx - 5,
          top: point.dy - 5,
          child: IgnorePointer(
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFCDA56A),
                border: Border.all(color: Colors.black, width: 1.0),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
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

  Future<void> _persistWorkingLayoutSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'wellwerks_layout_designer_v2', jsonEncode(_payload()));
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

  Map<String, String> _clonePropertiesWithoutConnections(
      Map<String, String> source) {
    final copy = Map<String, String>.from(source);
    for (final key in <String>[
      'jointStart',
      'jointEnd',
      'anchorStartItemId',
      'anchorEndItemId',
      'anchorStartSide',
      'anchorEndSide',
      'snapIronId',
      'snapAxis',
      'bypassPrimaryIronId',
      'bypassPrimaryT',
      'bypassSecondaryIronId',
      'bypassSecondaryT',
    ]) {
      copy.remove(key);
    }
    return copy;
  }

  String _endpointJointKey(bool leading) => leading ? 'jointStart' : 'jointEnd';

  String _endpointAnchorItemKey(bool leading) =>
      leading ? 'anchorStartItemId' : 'anchorEndItemId';

  String _endpointAnchorSideKey(bool leading) =>
      leading ? 'anchorStartSide' : 'anchorEndSide';

  String _bypassIronKey(String slot) => 'bypass${slot}IronId';

  String _bypassTKey(String slot) => 'bypass${slot}T';

  Offset _ironEndpoint(_LayoutItem item, bool leading) {
    final horizontal = item.type == _EquipmentType.ironHorizontal;
    if (horizontal) {
      return Offset(
        leading ? item.x : item.x + item.width,
        item.y + item.height / 2,
      );
    }
    return Offset(
      item.x + item.width / 2,
      leading ? item.y : item.y + item.height,
    );
  }

  Offset _equipmentAnchorPoint(_LayoutItem item, String side) {
    for (final anchor in _equipmentAnchorCandidates(item)) {
      if (anchor.side == side) {
        return anchor.point;
      }
    }
    return Offset(item.x + item.width / 2, item.y + item.height / 2);
  }

  List<_AnchorDefinition> _anchorDefinitionsForType(_EquipmentType type) {
    switch (type) {
      case _EquipmentType.bypass:
        return const <_AnchorDefinition>[
          _AnchorDefinition('bypassPrimary', 0.0, 0.5),
          _AnchorDefinition('bypassSecondary', 1.0, 0.5),
        ];
      case _EquipmentType.wellhead:
        return const <_AnchorDefinition>[
          _AnchorDefinition('left', 0.0, 0.5),
          _AnchorDefinition('right', 1.0, 0.5),
          _AnchorDefinition('bottom', 0.5, 1.0),
        ];
      case _EquipmentType.chokeManifold:
        return const <_AnchorDefinition>[
          _AnchorDefinition('top', 0.5, 0.0),
          _AnchorDefinition('left', 0.0, 0.5),
          _AnchorDefinition('right', 1.0, 0.5),
          _AnchorDefinition('bottom', 0.5, 1.0),
        ];
      case _EquipmentType.esdValve:
      case _EquipmentType.lineHeater:
      case _EquipmentType.plugCatcher:
      case _EquipmentType.flowbackTank:
      case _EquipmentType.productionTank:
        return const <_AnchorDefinition>[
          _AnchorDefinition('left', 0.0, 0.5),
          _AnchorDefinition('right', 1.0, 0.5),
        ];
      default:
        return const <_AnchorDefinition>[
          _AnchorDefinition('top', 0.5, 0.0),
          _AnchorDefinition('left', 0.0, 0.5),
          _AnchorDefinition('right', 1.0, 0.5),
          _AnchorDefinition('bottom', 0.5, 1.0),
        ];
    }
  }

  Offset _rotatedLocalAnchorPoint(_LayoutItem item, _AnchorDefinition anchor) {
    final local = Offset(item.width * anchor.u, item.height * anchor.v);
    final center = Offset(item.width / 2, item.height / 2);
    final turns = ((item.rotationTurns % 4) + 4) % 4;
    final delta = local - center;
    Offset rotated;
    switch (turns) {
      case 1:
        rotated = Offset(-delta.dy, delta.dx);
        break;
      case 2:
        rotated = Offset(-delta.dx, -delta.dy);
        break;
      case 3:
        rotated = Offset(delta.dy, -delta.dx);
        break;
      default:
        rotated = delta;
    }
    return center + rotated;
  }

  List<_EquipmentAnchorCandidate> _equipmentAnchorCandidates(_LayoutItem item) {
    if (_isStraightIronType(item.type))
      return const <_EquipmentAnchorCandidate>[];
    return _anchorDefinitionsForType(item.type).map((anchor) {
      final local = _rotatedLocalAnchorPoint(item, anchor);
      return _EquipmentAnchorCandidate(
        itemId: item.id,
        side: anchor.id,
        point: Offset(item.x + local.dx, item.y + local.dy),
        score: 0,
      );
    }).toList(growable: false);
  }

  String? _jointId(_LayoutItem item, bool leading) =>
      item.properties[_endpointJointKey(leading)];

  void _setJointId(_LayoutItem item, bool leading, String? value) {
    final key = _endpointJointKey(leading);
    if (value == null || value.isEmpty) {
      item.properties.remove(key);
    } else {
      item.properties[key] = value;
    }
  }

  void _setEndpointAnchor(
    _LayoutItem item,
    bool leading, {
    required int? anchorItemId,
    required String? side,
  }) {
    final itemKey = _endpointAnchorItemKey(leading);
    final sideKey = _endpointAnchorSideKey(leading);
    if (anchorItemId == null || side == null || side.isEmpty) {
      item.properties.remove(itemKey);
      item.properties.remove(sideKey);
      return;
    }
    item.properties[itemKey] = anchorItemId.toString();
    item.properties[sideKey] = side;
  }

  void _clearEndpointAttachment(_LayoutItem item, bool leading) {
    _setJointId(item, leading, null);
    _setEndpointAnchor(item, leading, anchorItemId: null, side: null);
  }

  bool _endpointHasLockedPeer(_LayoutItem item, bool leading) {
    final jointId = _jointId(item, leading);
    if (jointId == null || jointId.isEmpty) return false;
    for (final other in _items) {
      if (other.id == item.id ||
          !other.locked ||
          !_isStraightIronType(other.type)) {
        continue;
      }
      if (_jointId(other, true) == jointId ||
          _jointId(other, false) == jointId) {
        return true;
      }
    }
    final anchorItemId = int.tryParse(
      item.properties[_endpointAnchorItemKey(leading)] ?? '',
    );
    final anchorItem =
        anchorItemId == null ? null : _findItemById(anchorItemId);
    return anchorItem?.locked ?? false;
  }

  bool _segmentMoveBlocked(_LayoutItem item) {
    if (item.locked) return true;
    if (!_isStraightIronType(item.type)) return false;
    return _endpointHasLockedPeer(item, true) ||
        _endpointHasLockedPeer(item, false);
  }

  void _setIronEndpointPosition(_LayoutItem item, bool leading, Offset point) {
    if (item.type == _EquipmentType.ironHorizontal) {
      final opposite = _ironEndpoint(item, !leading);
      final newX = leading
          ? point.dx.clamp(0.0, opposite.dx - 36.0)
          : point.dx.clamp(item.x + 36.0, _virtualCanvasSize.width);
      if (leading) {
        item.width = opposite.dx - newX;
        item.x = newX;
      } else {
        item.width = newX - item.x;
      }
      item.y =
          _snap(item.y).clamp(0.0, _virtualCanvasSize.height - item.height);
      return;
    }

    final opposite = _ironEndpoint(item, !leading);
    final newY = leading
        ? point.dy.clamp(0.0, opposite.dy - 36.0)
        : point.dy.clamp(item.y + 36.0, _virtualCanvasSize.height);
    if (leading) {
      item.height = opposite.dy - newY;
      item.y = newY;
    } else {
      item.height = newY - item.y;
    }
    item.x = _snap(item.x).clamp(0.0, _virtualCanvasSize.width - item.width);
  }

  String _newJointId() =>
      'joint_${DateTime.now().microsecondsSinceEpoch}_${_nextId}';

  Offset _pointAlongIron(_LayoutItem iron, double t) {
    final clampedT = t.clamp(0.0, 1.0);
    if (iron.type == _EquipmentType.ironHorizontal) {
      return Offset(iron.x + iron.width * clampedT, iron.y + iron.height / 2);
    }
    return Offset(iron.x + iron.width / 2, iron.y + iron.height * clampedT);
  }

  double _normalizedPositionAlongIron(_LayoutItem iron, Offset point) {
    if (iron.type == _EquipmentType.ironHorizontal) {
      if (iron.width <= 0) return 0.0;
      return ((point.dx - iron.x) / iron.width).clamp(0.0, 1.0);
    }
    if (iron.height <= 0) return 0.0;
    return ((point.dy - iron.y) / iron.height).clamp(0.0, 1.0);
  }

  _EndpointCandidate? _nearestEndpointCandidate(
    _LayoutItem item,
    bool leading,
    Offset target,
  ) {
    final endpointRadius = _sceneRadiusFromScreen(36);
    _EndpointCandidate? best;
    for (final other in _items) {
      if (other.id == item.id || !_isStraightIronType(other.type)) continue;
      for (final otherLeading in const <bool>[true, false]) {
        final point = _ironEndpoint(other, otherLeading);
        final distance = (point - target).distance;
        if (distance > endpointRadius) {
          continue;
        }
        final score = distance;
        if (best == null || score < best.score) {
          best = _EndpointCandidate(
            itemId: other.id,
            leading: otherLeading,
            point: point,
            score: score,
          );
        }
      }
    }
    return best;
  }

  _ConnectionTarget _connectionTargetFromAnchor(_EquipmentAnchorCandidate c,
      {required double distance, required bool exact}) {
    return _ConnectionTarget(
      kind: _ConnectionTargetKind.equipmentAnchor,
      point: c.point,
      distance: distance,
      isExactHit: exact,
      equipmentItemId: c.itemId,
      anchorId: c.side,
    );
  }

  _ConnectionTarget _connectionTargetFromEndpoint(_EndpointCandidate c,
      {required double distance, required bool exact}) {
    return _ConnectionTarget(
      kind: _ConnectionTargetKind.ironEndpoint,
      point: c.point,
      distance: distance,
      isExactHit: exact,
      ironItemId: c.itemId,
      ironLeading: c.leading,
    );
  }

  _ConnectionTarget? _nearestAnchorTarget(
    Offset target, {
    required double radius,
    required bool exact,
  }) {
    _ConnectionTarget? best;
    var bestDistance = double.infinity;
    for (final item in _items) {
      if (_isStraightIronType(item.type)) continue;
      for (final anchor in _equipmentAnchorCandidates(item)) {
        final distance = (anchor.point - target).distance;
        if (distance > radius) continue;
        if (distance < bestDistance) {
          bestDistance = distance;
          best = _connectionTargetFromAnchor(anchor,
              distance: distance, exact: exact);
        }
      }
    }
    return best;
  }

  _ConnectionTarget? _nearestIronEndpointTarget(
    Offset target, {
    required double radius,
    required bool exact,
    int? movingIronId,
    bool? movingIronLeading,
  }) {
    _ConnectionTarget? best;
    var bestDistance = double.infinity;
    for (final other in _items) {
      if (!_isStraightIronType(other.type)) continue;
      if (movingIronId != null && other.id == movingIronId) continue;
      for (final leading in const <bool>[true, false]) {
        if (movingIronId != null &&
            movingIronLeading != null &&
            other.id == movingIronId &&
            leading == movingIronLeading) {
          continue;
        }
        final point = _ironEndpoint(other, leading);
        final distance = (point - target).distance;
        if (distance > radius) continue;
        if (distance < bestDistance) {
          bestDistance = distance;
          best = _connectionTargetFromEndpoint(
            _EndpointCandidate(
              itemId: other.id,
              leading: leading,
              point: point,
              score: distance,
            ),
            distance: distance,
            exact: exact,
          );
        }
      }
    }
    return best;
  }

  _ConnectionTarget? _findBestConnectionTarget(
    Offset target, {
    int? movingIronId,
    bool? movingIronLeading,
  }) {
    final snapRadius = _sceneRadiusFromScreen(_connectionSnapRadius);
    final nearestAnchor = _nearestAnchorTarget(
      target,
      radius: snapRadius,
      exact: false,
    );
    final nearestEndpoint = _nearestIronEndpointTarget(
      target,
      radius: snapRadius,
      exact: false,
      movingIronId: movingIronId,
      movingIronLeading: movingIronLeading,
    );

    if (nearestAnchor == null) return nearestEndpoint;
    if (nearestEndpoint == null) return nearestAnchor;
    return nearestAnchor.distance <= nearestEndpoint.distance
        ? nearestAnchor
        : nearestEndpoint;
  }

  _EndpointSnapTarget _snapTargetFromConnection(_ConnectionTarget target) {
    if (target.kind == _ConnectionTargetKind.ironEndpoint) {
      return _EndpointSnapTarget(
        point: target.point,
        endpoint: _EndpointCandidate(
          itemId: target.ironItemId!,
          leading: target.ironLeading!,
          point: target.point,
          score: target.distance,
        ),
      );
    }
    if (target.anchorId == 'bypassPrimary' ||
        target.anchorId == 'bypassSecondary') {
      return _EndpointSnapTarget(
        point: target.point,
        bypass: _BypassHandleCandidate(
          itemId: target.equipmentItemId!,
          side: target.anchorId!,
          point: target.point,
          score: target.distance,
        ),
      );
    }
    return _EndpointSnapTarget(
      point: target.point,
      equipment: _EquipmentAnchorCandidate(
        itemId: target.equipmentItemId!,
        side: target.anchorId!,
        point: target.point,
        score: target.distance,
      ),
    );
  }

  _EquipmentAnchorCandidate? _nearestEquipmentAnchorCandidate(
    _LayoutItem iron,
    Offset target,
  ) {
    final best = _nearestAnchorTarget(target,
        radius: _sceneRadiusFromScreen(40), exact: false);
    if (best == null || best.kind != _ConnectionTargetKind.equipmentAnchor) {
      return null;
    }
    return _EquipmentAnchorCandidate(
      itemId: best.equipmentItemId!,
      side: best.anchorId!,
      point: best.point,
      score: best.distance,
    );
  }

  _BypassHandleCandidate? _nearestBypassHandleCandidate(Offset target) {
    final handleRadius = _sceneRadiusFromScreen(34);
    _BypassHandleCandidate? best;
    for (final item in _items) {
      if (item.type != _EquipmentType.bypass) continue;
      for (final side in const <String>['bypassPrimary', 'bypassSecondary']) {
        final point = _equipmentAnchorPoint(item, side);
        final distance = (point - target).distance;
        if (distance > handleRadius) continue;
        if (best == null || distance < best.score) {
          best = _BypassHandleCandidate(
            itemId: item.id,
            side: side,
            point: point,
            score: distance,
          );
        }
      }
    }
    return best;
  }

  _EndpointSnapTarget? _nearestEndpointSnapTarget(
    _LayoutItem item,
    bool leading,
    Offset target,
  ) {
    final resolved = _findBestConnectionTarget(
      target,
      movingIronId: item.id,
      movingIronLeading: leading,
    );
    if (resolved == null) return null;
    return _snapTargetFromConnection(resolved);
  }

  _EndpointSnapTarget? _stabilizeEndpointSnapTarget({
    required Offset sourcePoint,
    required _EndpointSnapTarget? previous,
    required _EndpointSnapTarget? candidate,
  }) {
    if (candidate == null) return null;
    if (previous == null ||
        previous.endpoint == null ||
        candidate.endpoint == null) {
      return candidate;
    }
    final sameEndpoint =
        previous.endpoint!.itemId == candidate.endpoint!.itemId &&
            previous.endpoint!.leading == candidate.endpoint!.leading;
    if (sameEndpoint) {
      return candidate;
    }
    final switchBias = _sceneRadiusFromScreen(4.0);
    final previousDistance = (previous.point - sourcePoint).distance;
    final candidateDistance = (candidate.point - sourcePoint).distance;
    if (candidateDistance + switchBias < previousDistance) {
      return candidate;
    }
    return previous;
  }

  void _connectIronEndpoints(
    _LayoutItem item,
    bool leading,
    _EndpointCandidate candidate,
  ) {
    final other = _findItemById(candidate.itemId);
    if (other == null) return;
    final jointId = _jointId(other, candidate.leading) ?? _newJointId();
    _clearEndpointAttachment(item, leading);
    _clearEndpointAttachment(other, candidate.leading);
    _setJointId(item, leading, jointId);
    _setJointId(other, candidate.leading, jointId);
    _setIronEndpointPosition(item, leading, candidate.point);
    _setIronEndpointPosition(other, candidate.leading, candidate.point);
    _snapIndicatorScene = candidate.point;
  }

  void _attachIronEndpointToEquipment(
    _LayoutItem item,
    bool leading,
    _EquipmentAnchorCandidate candidate,
  ) {
    _clearEndpointAttachment(item, leading);
    _setEndpointAnchor(
      item,
      leading,
      anchorItemId: candidate.itemId,
      side: candidate.side,
    );
    _setIronEndpointPosition(item, leading, candidate.point);
    _snapIndicatorScene = candidate.point;
  }

  void _attachIronEndpointToBypass(
    _LayoutItem item,
    bool leading,
    _BypassHandleCandidate candidate,
  ) {
    _clearEndpointAttachment(item, leading);
    _setEndpointAnchor(
      item,
      leading,
      anchorItemId: candidate.itemId,
      side: candidate.side,
    );
    _setIronEndpointPosition(item, leading, candidate.point);
    _snapIndicatorScene = candidate.point;
  }

  double? _bypassAttachmentT(_LayoutItem item, String slot) {
    return double.tryParse(item.properties[_bypassTKey(slot)] ?? '');
  }

  _LayoutItem? _bypassAttachmentIron(_LayoutItem item, String slot) {
    final ironId = int.tryParse(item.properties[_bypassIronKey(slot)] ?? '');
    return ironId == null ? null : _findItemById(ironId);
  }

  void _setBypassAttachment(
      _LayoutItem item, String slot, _LayoutItem? iron, double? t) {
    if (iron == null || t == null) {
      item.properties.remove(_bypassIronKey(slot));
      item.properties.remove(_bypassTKey(slot));
      return;
    }
    item.properties[_bypassIronKey(slot)] = iron.id.toString();
    item.properties[_bypassTKey(slot)] = t.clamp(0.0, 1.0).toStringAsFixed(4);
  }

  _SnapCandidate? _nearestBypassRail(
    _LayoutItem item,
    Offset desiredTopLeft, {
    int? excludedIronId,
    double maxDistance = _equipmentAnchorSnapRadius,
  }) {
    final center = Offset(
      desiredTopLeft.dx + item.width / 2,
      desiredTopLeft.dy + item.height / 2,
    );
    _SnapCandidate? best;
    for (final iron in _items) {
      if (!_isStraightIronType(iron.type)) continue;
      if (excludedIronId != null && iron.id == excludedIronId) continue;
      final horizontal = iron.type == _EquipmentType.ironHorizontal;
      final projected = horizontal
          ? Offset(center.dx.clamp(iron.x, iron.x + iron.width),
              iron.y + iron.height / 2)
          : Offset(iron.x + iron.width / 2,
              center.dy.clamp(iron.y, iron.y + iron.height));
      final distance = (projected - center).distance;
      if (distance > maxDistance) continue;
      if (best == null || distance < best.score) {
        best = _SnapCandidate(
          ironId: iron.id,
          horizontal: horizontal,
          indicator: projected,
          score: distance,
        );
      }
    }
    return best;
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
    final jointIds = <String>{};
    for (final item in _items) {
      if (_isStraightIronType(item.type)) {
        for (final leading in const <bool>[true, false]) {
          final jointId = _jointId(item, leading);
          if (jointId != null && jointId.isNotEmpty) {
            jointIds.add(jointId);
          }
          final anchorItemId = int.tryParse(
            item.properties[_endpointAnchorItemKey(leading)] ?? '',
          );
          final anchorSide = item.properties[_endpointAnchorSideKey(leading)];
          final anchorItem =
              anchorItemId == null ? null : _findItemById(anchorItemId);
          if (anchorItem != null &&
              anchorSide != null &&
              anchorSide.isNotEmpty) {
            _setIronEndpointPosition(
              item,
              leading,
              _equipmentAnchorPoint(anchorItem, anchorSide),
            );
          } else if (anchorItemId != null) {
            _setEndpointAnchor(item, leading, anchorItemId: null, side: null);
          }
        }
      }

      if (!_isFittingType(item.type)) continue;

      if (item.type == _EquipmentType.bypass) {
        final primaryIron = _bypassAttachmentIron(item, 'Primary');
        final secondaryIron = _bypassAttachmentIron(item, 'Secondary');
        final primaryT = _bypassAttachmentT(item, 'Primary');
        final secondaryT = _bypassAttachmentT(item, 'Secondary');
        Offset? primaryPoint;
        Offset? secondaryPoint;
        if (primaryIron != null && primaryT != null) {
          primaryPoint = _pointAlongIron(primaryIron, primaryT);
        } else if (item.properties[_bypassIronKey('Primary')] != null) {
          _setBypassAttachment(item, 'Primary', null, null);
        }
        if (secondaryIron != null && secondaryT != null) {
          secondaryPoint = _pointAlongIron(secondaryIron, secondaryT);
        } else if (item.properties[_bypassIronKey('Secondary')] != null) {
          _setBypassAttachment(item, 'Secondary', null, null);
        }
        final anchorPoint = primaryPoint ?? secondaryPoint;
        if (anchorPoint != null) {
          final center = (primaryPoint != null && secondaryPoint != null)
              ? Offset(
                  (primaryPoint.dx + secondaryPoint.dx) / 2,
                  (primaryPoint.dy + secondaryPoint.dy) / 2,
                )
              : anchorPoint;
          item.x = center.dx - item.width / 2;
          item.y = center.dy - item.height / 2;
          continue;
        }
      }

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

    for (final jointId in jointIds) {
      final members = <(_LayoutItem, bool)>[];
      for (final item in _items) {
        if (!_isStraightIronType(item.type)) continue;
        for (final leading in const <bool>[true, false]) {
          if (_jointId(item, leading) == jointId) {
            members.add((item, leading));
          }
        }
      }
      if (members.isEmpty) continue;
      final target = _ironEndpoint(members.first.$1, members.first.$2);
      for (final member in members.skip(1)) {
        _setIronEndpointPosition(member.$1, member.$2, target);
      }
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
    if (moving.every((it) => it.locked)) {
      _interactionMode =
          _drawIronMode ? _InteractionMode.placeIron : _InteractionMode.idle;
      return;
    }
    _interactionMode = _InteractionMode.itemDrag;
    _activeEndpointDrag = null;
    _snapIndicatorScene = null;
    _dragSceneStart = _scenePointFromGlobal(details.globalPosition);
    if (anchor.id == _selectedId && anchor.type == _EquipmentType.bypass) {
      final startPoint = _dragSceneStart!;
      final handleHitRadius = _sceneRadiusFromScreen(20.0);
      final primaryPoint = Offset(anchor.x, anchor.y + anchor.height / 2);
      final secondaryPoint =
          Offset(anchor.x + anchor.width, anchor.y + anchor.height / 2);
      final primaryDistance = (startPoint - primaryPoint).distance;
      final secondaryDistance = (startPoint - secondaryPoint).distance;
      if (primaryDistance <= handleHitRadius) {
        _selectedBypassHandle = 'Primary';
        _selectedEndpointLeading = null;
        _interactionMode = _InteractionMode.attachBypass;
      } else if (secondaryDistance <= handleHitRadius) {
        _selectedBypassHandle = 'Secondary';
        _selectedEndpointLeading = null;
        _interactionMode = _InteractionMode.attachBypass;
      } else {
        _selectedBypassHandle = null;
      }
    } else {
      _selectedEndpointLeading = null;
    }
    _dragActive = false;
    _clearDragPreview();
    _dragItemStart
      ..clear()
      ..addEntries(moving.map((it) => MapEntry(it.id, Offset(it.x, it.y))));
    if (mounted) {
      setState(() {});
    }
  }

  void _updateItemDrag(_LayoutItem anchor, DragUpdateDetails details) {
    if (_interactionMode == _InteractionMode.stretchEndpoint &&
        anchor.id == _selectedId &&
        _isStraightIronType(anchor.type) &&
        _selectedEndpointLeading != null) {
      if (!_dragActive) {
        _recordUndo();
        _dragActive = true;
      }
      _stretchStraightIron(anchor, details, _selectedEndpointLeading!);
      return;
    }

    if (_interactionMode == _InteractionMode.attachBypass &&
        anchor.id == _selectedId &&
        anchor.type == _EquipmentType.bypass &&
        _selectedBypassHandle != null) {
      if (!_dragActive) {
        _recordUndo();
        _dragActive = true;
      }
      _attachBypassHandleToNearestRail(anchor, _selectedBypassHandle!, details);
      return;
    }

    final moving = _selectedIds.contains(anchor.id) ? _selectedItems : [anchor];
    if (moving.every((it) => _segmentMoveBlocked(it))) return;

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
      _clearDragPreview();
      for (final it in moving) {
        if (_segmentMoveBlocked(it)) continue;
        final origin = _dragItemStart[it.id] ?? Offset(it.x, it.y);
        final desired = Offset(origin.dx + delta.dx, origin.dy + delta.dy);
        if (it.type == _EquipmentType.bypass &&
            (_bypassAttachmentIron(it, 'Primary') != null ||
                _bypassAttachmentIron(it, 'Secondary') != null)) {
          _slideBypassOnRail(it, desired);
        } else if (_isFittingType(it.type)) {
          final placed =
              _resolveFittingPlacement(it, desired, allowNewSnap: true);
          it.x = placed.dx;
          it.y = placed.dy;
        } else {
          it.x = desired.dx.clamp(0.0, canvasSize.width - it.width);
          it.y = desired.dy.clamp(0.0, canvasSize.height - it.height);
        }
        if (it.id == _selectedId && !it.type.isIron) {
          _dragPreviewItemId = it.id;
          _dragPreviewScenePosition =
              Offset(it.x + it.width / 2, it.y + it.height / 2);
        }
      }
      _reflowSnappedFittings();
    });
  }

  void _endItemDrag(_LayoutItem anchor) {
    final moving = _selectedIds.contains(anchor.id) ? _selectedItems : [anchor];
    if (moving.every((it) => _segmentMoveBlocked(it))) {
      _dragSceneStart = null;
      _dragItemStart.clear();
      _dragActive = false;
      return;
    }

    if (_interactionMode == _InteractionMode.stretchEndpoint &&
        anchor.id == _selectedId &&
        _isStraightIronType(anchor.type) &&
        _selectedEndpointLeading != null) {
      setState(() {
        final leading = _selectedEndpointLeading!;
        final active = _activeEndpointDrag;
        final activeTarget = (active != null &&
                active.ironId == anchor.id &&
                active.leading == leading)
            ? active.target
            : null;
        _commitIronEndpointConnection(anchor, leading, target: activeTarget);
        _activeEndpointDrag = null;
        _reflowSnappedFittings();
      });
    }

    if (_interactionMode == _InteractionMode.attachBypass &&
        anchor.id == _selectedId &&
        anchor.type == _EquipmentType.bypass &&
        _selectedBypassHandle != null) {
      setState(() {
        final candidate =
            _nearestBypassRail(anchor, Offset(anchor.x, anchor.y));
        if (candidate != null) {
          final iron = _findItemById(candidate.ironId);
          if (iron != null) {
            final center = Offset(
                anchor.x + anchor.width / 2, anchor.y + anchor.height / 2);
            _setBypassAttachment(
              anchor,
              _selectedBypassHandle!,
              iron,
              _normalizedPositionAlongIron(iron, center),
            );
            _reflowSnappedFittings();
          }
        }
      });
    }

    if (_dragActive && _snapToGrid) {
      setState(() {
        final canvasSize = _virtualCanvasSize;
        for (final it in moving) {
          if (_segmentMoveBlocked(it)) continue;
          if (_isFittingType(it.type) && it.properties['snapIronId'] != null) {
            continue;
          }
          it.x = _snap(it.x).clamp(0.0, canvasSize.width - it.width);
          it.y = _snap(it.y).clamp(0.0, canvasSize.height - it.height);
        }
        _reflowSnappedFittings();
      });
    }

    setState(() {
      _dragSceneStart = null;
      _dragItemStart.clear();
      _dragActive = false;
      _activeEndpointDrag = null;
      _clearDragPreview();
      _interactionMode =
          _drawIronMode ? _InteractionMode.placeIron : _InteractionMode.idle;
    });
    if (_snapCandidateIronId != null || _snapIndicatorScene != null) {
      setState(() {
        _snapCandidateIronId = null;
        _snapIndicatorScene = null;
      });
    }
  }

  void _slideBypassOnRail(_LayoutItem item, Offset desiredTopLeft) {
    final rail = _bypassAttachmentIron(item, 'Primary') ??
        _bypassAttachmentIron(item, 'Secondary');
    if (rail == null || !_isStraightIronType(rail.type)) {
      item.x = desiredTopLeft.dx;
      item.y = desiredTopLeft.dy;
      return;
    }

    final desiredCenter = Offset(
      desiredTopLeft.dx + item.width / 2,
      desiredTopLeft.dy + item.height / 2,
    );
    final t = _normalizedPositionAlongIron(rail, desiredCenter);
    if (_bypassAttachmentIron(item, 'Primary') != null) {
      _setBypassAttachment(item, 'Primary', rail, t);
    }
    if (_bypassAttachmentIron(item, 'Secondary') != null) {
      _setBypassAttachment(
          item,
          'Secondary',
          _bypassAttachmentIron(item, 'Secondary'),
          _normalizedPositionAlongIron(
              _bypassAttachmentIron(item, 'Secondary')!, desiredCenter));
    }
  }

  void _commitIronEndpointConnection(
    _LayoutItem item,
    bool leading, {
    _EndpointSnapTarget? target,
  }) {
    final effectiveTarget = target ??
        _nearestEndpointSnapTarget(item, leading, _ironEndpoint(item, leading));
    if (effectiveTarget == null) {
      _reflowSnappedFittings();
      return;
    }
    if (effectiveTarget.endpoint != null) {
      _connectIronEndpoints(item, leading, effectiveTarget.endpoint!);
    } else if (effectiveTarget.equipment != null) {
      _attachIronEndpointToEquipment(item, leading, effectiveTarget.equipment!);
    } else if (effectiveTarget.bypass != null) {
      _attachIronEndpointToBypass(item, leading, effectiveTarget.bypass!);
    }
    _reflowSnappedFittings();
  }

  void _commitBypassHandleAttachment(_LayoutItem item, String slot) {
    final otherSlot = slot == 'Primary' ? 'Secondary' : 'Primary';
    final otherIron = _bypassAttachmentIron(item, otherSlot);
    final candidate = _nearestBypassRail(
          item,
          Offset(item.x, item.y),
          excludedIronId: otherIron?.id,
          maxDistance: otherIron == null
              ? _equipmentAnchorSnapRadius
              : _equipmentAnchorSnapRadius * 4,
        ) ??
        _nearestBypassRail(item, Offset(item.x, item.y));
    if (candidate == null) {
      _reflowSnappedFittings();
      return;
    }
    final iron = _findItemById(candidate.ironId);
    if (iron == null) {
      _reflowSnappedFittings();
      return;
    }
    final center = Offset(item.x + item.width / 2, item.y + item.height / 2);
    _setBypassAttachment(
      item,
      slot,
      iron,
      _normalizedPositionAlongIron(iron, center),
    );
    _reflowSnappedFittings();
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
    _stretchStraightIronByScreenDelta(item, details.delta, leading);
  }

  void _stretchStraightIronByScreenDelta(
    _LayoutItem item,
    Offset screenDelta,
    bool leading,
  ) {
    if (item.locked ||
        !(item.type == _EquipmentType.ironHorizontal ||
            item.type == _EquipmentType.ironVertical)) return;
    setState(() {
      _selectedEndpointLeading = leading;
      _selectedBypassHandle = null;
      _interactionMode = _InteractionMode.stretchEndpoint;
      final current = _ironEndpoint(item, leading);
      final sceneDelta = _sceneDeltaFromScreen(screenDelta);
      final desired = item.type == _EquipmentType.ironHorizontal
          ? Offset(current.dx + sceneDelta.dx, current.dy)
          : Offset(current.dx, current.dy + sceneDelta.dy);
      _clearEndpointAttachment(item, leading);
      _setIronEndpointPosition(item, leading, desired);

      final snappedPoint = _ironEndpoint(item, leading);
      final candidate = _nearestEndpointSnapTarget(item, leading, snappedPoint);
      final prior = (_activeEndpointDrag != null &&
              _activeEndpointDrag!.ironId == item.id &&
              _activeEndpointDrag!.leading == leading)
          ? _activeEndpointDrag!.target
          : null;
      final target = _stabilizeEndpointSnapTarget(
        sourcePoint: snappedPoint,
        previous: prior,
        candidate: candidate,
      );
      _activeEndpointDrag = _ActiveEndpointDrag(
        ironId: item.id,
        leading: leading,
        worldPosition: snappedPoint,
        target: target,
      );
      _snapIndicatorScene = target?.point;
      _reflowSnappedFittings();
    });
  }

  void _startEndpointHandleDrag(_LayoutItem item, bool leading) {
    if (item.locked || !_isStraightIronType(item.type)) return;
    _recordUndo();
    setState(() {
      _selectedEndpointLeading = leading;
      _selectedBypassHandle = null;
      _interactionMode = _InteractionMode.stretchEndpoint;
      _activeEndpointDrag = _ActiveEndpointDrag(
        ironId: item.id,
        leading: leading,
        worldPosition: _ironEndpoint(item, leading),
        target: null,
      );
    });
  }

  void _updateEndpointHandleDrag(_LayoutItem item, bool leading, Offset delta) {
    _stretchStraightIronByScreenDelta(item, delta, leading);
  }

  void _endEndpointHandleDrag(_LayoutItem item, bool leading) {
    setState(() {
      final active = _activeEndpointDrag;
      final activeTarget = (active != null &&
              active.ironId == item.id &&
              active.leading == leading)
          ? active.target
          : null;
      _commitIronEndpointConnection(item, leading, target: activeTarget);
      _activeEndpointDrag = null;
      _interactionMode = _InteractionMode.idle;
      _reflowSnappedFittings();
      _snapIndicatorScene = null;
    });
    _persistWorkingLayoutSnapshot();
  }

  void _disconnectSelectedConnection() {
    final item = _selectedItem;
    final leading = _selectedEndpointLeading;
    if (item == null || leading == null) return;
    _runHistoryChange(() {
      _clearEndpointAttachment(item, leading);
      _selectedEndpointLeading = null;
      _snapIndicatorScene = null;
    });
    _appendHistoryEntry('Disconnected iron joint');
  }

  void _attachBypassHandleToNearestRail(
    _LayoutItem item,
    String slot,
    DragUpdateDetails details,
  ) {
    if (item.locked) return;
    setState(() {
      _selectedBypassHandle = slot;
      _selectedEndpointLeading = null;
      final sceneDelta = _sceneDeltaFromScreen(details.delta);
      final desired = Offset(item.x + sceneDelta.dx, item.y + sceneDelta.dy);
      final candidate = _nearestBypassRail(item, desired);
      if (candidate == null) {
        _snapIndicatorScene = null;
        return;
      }
      final iron = _findItemById(candidate.ironId);
      if (iron == null) return;
      final center =
          Offset(desired.dx + item.width / 2, desired.dy + item.height / 2);
      _setBypassAttachment(
          item, slot, iron, _normalizedPositionAlongIron(iron, center));
      _snapIndicatorScene = candidate.indicator;
      _reflowSnappedFittings();
    });
  }

  void _toggleDrawIronMode(bool value) {
    setState(() {
      _drawIronMode = false;
      _interactionMode = _InteractionMode.idle;
      _drawIronStartTarget = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      _pendingContinueIronTarget = null;
      _pendingContinueIronSize = null;
    });
  }

  void _finishIronDrawing() {
    if (!_drawIronMode) return;
    setState(() {
      _drawIronMode = false;
      _interactionMode = _InteractionMode.idle;
      _pendingContinueIronTarget = null;
      _pendingContinueIronSize = null;
    });
  }

  void _cancelIronDrawing() {
    if (!_drawIronMode) return;
    setState(() {
      _drawIronMode = false;
      _interactionMode = _InteractionMode.idle;
      _pendingContinueIronTarget = null;
      _pendingContinueIronSize = null;
    });
  }

  void _continueIronRun() {
    final target = _pendingContinueIronTarget;
    if (target == null) return;
    _startConnectIronMode(
      _pendingContinueIronSize ?? _drawIronSize,
      minimizeLibrary: false,
      initialTarget: target,
    );
  }

  void _finishContinueIronPrompt() {
    setState(() {
      _pendingContinueIronTarget = null;
      _pendingContinueIronSize = null;
      _drawIronMode = false;
      _interactionMode = _InteractionMode.idle;
      _drawIronStartTarget = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
    });
  }

  void _commitPendingSelectionConnections() {
    final selected = _selectedItem;
    if (selected == null) return;

    if (_isStraightIronType(selected.type) &&
        _selectedEndpointLeading != null) {
      _recordUndo();
      _commitIronEndpointConnection(selected, _selectedEndpointLeading!);
      return;
    }

    if (selected.type == _EquipmentType.bypass &&
        _selectedBypassHandle != null) {
      _recordUndo();
      _commitBypassHandleAttachment(selected, _selectedBypassHandle!);
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

    if (!_drawIronMode) {
      final hitItem = _itemAtScenePoint(clampedPoint);
      if (hitItem == null && _selectedIds.isNotEmpty) {
        _clearSelection();
      }
      return;
    }
    if (_drawIronStartTarget == null) {
      final startTarget = _findBestConnectionTarget(clampedPoint);
      if (startTarget == null) return;
      setState(() {
        _drawIronStartTarget = startTarget;
        _drawIronPointerScene = startTarget.point;
        _drawIronHoverTarget = null;
      });
      return;
    }

    _finalizeDrawIron(clampedPoint);
  }

  void _updateDrawIronPreview(Offset scenePoint) {
    if (!_drawIronMode || _drawIronStartTarget == null) return;
    final clamped = _clampToCanvas(scenePoint);
    final hover = _findBestConnectionTarget(clamped);
    setState(() {
      _drawIronPointerScene = clamped;
      _drawIronHoverTarget = hover;
      _snapIndicatorScene = hover?.point;
    });
  }

  void _handleDrawIronPanStart(DragStartDetails details) {
    if (!_drawIronMode) return;
    final scenePoint = _scenePointFromGlobal(details.globalPosition);
    if (_drawIronStartTarget == null) {
      final start = _findBestConnectionTarget(scenePoint);
      if (start == null) return;
      setState(() {
        _drawIronStartTarget = start;
        _drawIronPointerScene = start.point;
        _drawIronHoverTarget = null;
      });
      return;
    }
    _updateDrawIronPreview(scenePoint);
  }

  void _handleDrawIronPanUpdate(DragUpdateDetails details) {
    if (!_drawIronMode || _drawIronStartTarget == null) return;
    _updateDrawIronPreview(_scenePointFromGlobal(details.globalPosition));
  }

  void _handleDrawIronPanEnd(DragEndDetails details) {
    if (!_drawIronMode || _drawIronStartTarget == null) return;
    final endPoint = _drawIronHoverTarget?.point ?? _drawIronPointerScene;
    if (endPoint == null) return;
    _finalizeDrawIron(endPoint);
  }

  void _finalizeDrawIron(Offset scenePoint) {
    final start = _drawIronStartTarget;
    if (start == null) return;
    final clamped = _clampToCanvas(scenePoint);
    final endTarget = _findBestConnectionTarget(clamped);
    final startPoint = start.point;
    final endPoint = endTarget?.point ?? clamped;
    final dx = endPoint.dx - startPoint.dx;
    final dy = endPoint.dy - startPoint.dy;
    if (dx.abs() < 12 && dy.abs() < 12) {
      return;
    }

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
        ? (dx >= 0 ? startPoint.dx : endPoint.dx)
        : startPoint.dx - width / 2;
    final y = horizontal
        ? startPoint.dy - height / 2
        : (dy >= 0 ? startPoint.dy : endPoint.dy);
    final canvasSize = _virtualCanvasSize;

    _runHistoryChange(() {
      final id = _nextId++;
      final newIron = _LayoutItem(
        id: id,
        type: type,
        x: _snap(x).clamp(0.0, canvasSize.width - width),
        y: _snap(y).clamp(0.0, canvasSize.height - height),
        width: width,
        height: height,
        properties: <String, String>{'ironSize': _drawIronSize},
      );
      _items.add(newIron);
      final startDistanceToLeading =
          (_ironEndpoint(newIron, true) - start.point).distance;
      final startIsLeading = startDistanceToLeading <=
          (_ironEndpoint(newIron, false) - start.point).distance;
      final continueTarget = endTarget ??
          _ConnectionTarget(
            kind: _ConnectionTargetKind.ironEndpoint,
            point: _ironEndpoint(newIron, !startIsLeading),
            distance: 0,
            isExactHit: true,
            ironItemId: id,
            ironLeading: !startIsLeading,
          );
      _applyConnectionTargetToIronEndpoint(newIron, startIsLeading, start);
      if (endTarget != null) {
        _applyConnectionTargetToIronEndpoint(
            newIron, !startIsLeading, endTarget);
      }
      _reflowSnappedFittings();
      _selectedId = id;
      _selectedIds
        ..clear()
        ..add(id);
      _drawIronMode = false;
      _interactionMode = _InteractionMode.idle;
      _drawIronStartTarget = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      _pendingContinueIronTarget = continueTarget;
      _pendingContinueIronSize = _drawIronSize;
      _snapIndicatorScene = null;
    });
    _appendHistoryEntry('Added iron');
  }

  void _applyConnectionTargetToIronEndpoint(
    _LayoutItem item,
    bool leading,
    _ConnectionTarget target,
  ) {
    final snapTarget = _snapTargetFromConnection(target);
    if (snapTarget.endpoint != null) {
      _connectIronEndpoints(item, leading, snapTarget.endpoint!);
      return;
    }
    if (snapTarget.bypass != null) {
      _attachIronEndpointToBypass(item, leading, snapTarget.bypass!);
      return;
    }
    if (snapTarget.equipment != null) {
      _attachIronEndpointToEquipment(item, leading, snapTarget.equipment!);
    }
  }

  void _commitInitialIronConnections(_LayoutItem item) {
    if (!_isStraightIronType(item.type)) return;
    _commitIronEndpointConnection(item, true);
    _commitIronEndpointConnection(item, false);
  }

  void _addItem(
    _EquipmentType type, {
    Offset? preferredScenePoint,
    bool applySpread = true,
    bool? keepLibraryOpen,
  }) {
    final isWide = MediaQuery.of(context).size.width >= 780;
    final center =
        preferredScenePoint ?? _visibleCanvasPlacementCenter(isWide: isWide);
    final spread = applySpread ? (_items.length % 6) * 18.0 : 0.0;
    _runHistoryChange(() {
      final id = _nextId++;
      final rawX = center.dx - type.defaultWidth / 2 + spread;
      final rawY = center.dy - type.defaultHeight / 2 + spread;
      final canvasSize = _virtualCanvasSize;
      final item = _LayoutItem(
        id: id,
        type: type,
        x: _snap(rawX).clamp(0.0, canvasSize.width - type.defaultWidth),
        y: _snap(rawY).clamp(0.0, canvasSize.height - type.defaultHeight),
        width: type.defaultWidth,
        height: type.defaultHeight,
      );
      _items.add(item);
      _commitInitialIronConnections(item);
      _selectedId = id;
      final stayOpen = keepLibraryOpen ?? _libraryKeepOpen;
      _showSideLibrary = stayOpen;
      _selectedIds
        ..clear()
        ..add(id);
    });
    _appendHistoryEntry(type.isIron ? 'Added iron' : 'Added equipment');
  }

  void _addStraightIronFromLibrary({
    required bool horizontal,
    required String size,
  }) {
    final type = horizontal
        ? _EquipmentType.ironHorizontal
        : _EquipmentType.ironVertical;
    final isWide = MediaQuery.of(context).size.width >= 780;
    final center = _visibleCanvasPlacementCenter(isWide: isWide);
    const length = 180.0;
    final width =
        horizontal ? length : _EquipmentType.ironVertical.defaultWidth;
    final height =
        horizontal ? _EquipmentType.ironHorizontal.defaultHeight : length;
    _runHistoryChange(() {
      final id = _nextId++;
      final canvasSize = _virtualCanvasSize;
      final item = _LayoutItem(
        id: id,
        type: type,
        x: (center.dx - width / 2).clamp(0.0, canvasSize.width - width),
        y: (center.dy - height / 2).clamp(0.0, canvasSize.height - height),
        width: width,
        height: height,
        properties: <String, String>{'ironSize': size},
      );
      _items.add(item);
      _commitInitialIronConnections(item);
      _selectedId = id;
      _selectedIds
        ..clear()
        ..add(id);
      _showSideLibrary = _libraryKeepOpen;
    });
    _appendHistoryEntry('Added iron');
  }

  void _selectOnly(int id) {
    _stopArrowRepeat();
    setState(() {
      _selectedId = id;
      _selectedEndpointLeading = null;
      _selectedBypassHandle = null;
      _selectedIds
        ..clear()
        ..add(id);
    });
  }

  void _toggleSelection(int id) {
    _stopArrowRepeat();
    setState(() {
      _selectedEndpointLeading = null;
      _selectedBypassHandle = null;
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      _selectedId = _selectedIds.isEmpty ? null : id;
    });
  }

  void _clearSelection() {
    _stopArrowRepeat();
    setState(() {
      _selectedId = null;
      _selectedEndpointLeading = null;
      _selectedBypassHandle = null;
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
    if (_duplicateInProgress) return;
    final originals = _selectedItems;
    if (originals.isEmpty) return;
    setState(() => _duplicateInProgress = true);
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
          properties: _clonePropertiesWithoutConnections(original.properties),
          rotationTurns: original.rotationTurns,
          locked: false,
        ));
        _selectedIds.add(newId);
        _selectedId = newId;
      }
    });
    if (mounted) {
      setState(() => _duplicateInProgress = false);
    }
    _appendHistoryEntry('Duplicated equipment');
  }

  void _duplicateSingleForQuickDrag(_LayoutItem item) {
    if (_duplicateInProgress) return;
    setState(() => _duplicateInProgress = true);
    _runHistoryChange(() {
      final newId = _nextId++;
      _items.add(_LayoutItem(
        id: newId,
        type: item.type,
        x: _snap(item.x + 42),
        y: _snap(item.y + 42),
        width: item.width,
        height: item.height,
        properties: _clonePropertiesWithoutConnections(item.properties),
        rotationTurns: item.rotationTurns,
        locked: false,
      ));
      _selectedIds
        ..clear()
        ..add(newId);
      _selectedId = newId;
    });
    if (mounted) {
      setState(() => _duplicateInProgress = false);
    }
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
        'libraryKeepOpen': _libraryKeepOpen,
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
    final restoredSelectedIds =
        (data['selectedIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => value as int)
            .toSet();
    final restoredSelectedId = data['selectedId'] as int?;
    final restoredSelectedEndpointLeading =
        data['selectedEndpointLeading'] as bool?;
    final restoredSelectedBypassHandle =
        data['selectedBypassHandle'] as String?;
    setState(() {
      _items
        ..clear()
        ..addAll(items);
      _nextId = data['nextId'] as int? ?? ((_items.length) + 1);
      _snapToGrid = data['snapToGrid'] as bool? ?? false;
      _libraryKeepOpen = data['libraryKeepOpen'] as bool? ?? true;
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
      _selectedId = restoredSelectedId;
      _moveControlsActive =
          restoredSelectedId != null || restoredSelectedIds.isNotEmpty;
      _selectedEndpointLeading = restoredSelectedEndpointLeading;
      _selectedBypassHandle = restoredSelectedBypassHandle;
      _selectedIds
        ..clear()
        ..addAll(restoredSelectedIds);
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
    _commitPendingSelectionConnections();
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
    _showLabels = prefs.getBool(_labelsPrefKey) ?? false;
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
    _commitPendingSelectionConnections();
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
        color: _bg,
        border: Border.all(color: Theme.of(context).dividerColor),
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
      backgroundColor: highlighted ? _gold : _bg,
      foregroundColor: highlighted ? Colors.black : Colors.white,
      minimumSize: const Size(0, 42),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  ButtonStyle _compactOutlineStyle({bool highlighted = false}) {
    return OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(
        color: highlighted ? _gold : Theme.of(context).dividerColor,
        width: highlighted ? 1.4 : 1,
      ),
      minimumSize: const Size(0, 42),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
        backgroundColor: Theme.of(context).colorScheme.surface,
        titleTextStyle: TextStyle(
          color: Theme.of(context).colorScheme.primary,
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
                      color: Theme.of(context).colorScheme.surface,
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
      _reflowSnappedFittings();
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
      _reflowSnappedFittings();
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
      _reflowSnappedFittings();
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
      _reflowSnappedFittings();
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
                                _toggleSnapToGrid();
                                setSheetState(() {});
                              },
                              icon: const Icon(Icons.grid_4x4),
                              label: Text(_snapToGrid
                                  ? 'Align to Grid ON'
                                  : 'Align to Grid OFF'),
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
                                _toggleShowEquipmentLabels();
                                setSheetState(() {});
                              },
                              icon: const Icon(Icons.label_outline),
                              label: Text(
                                _showLabels
                                    ? 'Show Equipment Labels: On'
                                    : 'Show Equipment Labels: Off',
                              ),
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
          _selectionQuickActionsBar(),
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
                if (isWide && !_showSideLibrary)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: FilledButton.icon(
                      onPressed: _toggleSideLibrary,
                      icon: const Icon(Icons.view_sidebar_outlined),
                      label: const Text('Open Library'),
                      style: _compactFilledStyle(highlighted: true),
                    ),
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
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in tabs) ...[
            ChoiceChip(
              key: ValueKey<String>('library-tab-${tab.value.name}'),
              selectedColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.28),
              labelStyle: TextStyle(
                color: _mobileDrawerSection == tab.value
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
              side: BorderSide(
                color: _mobileDrawerSection == tab.value
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
              backgroundColor: Theme.of(context).colorScheme.surface,
              selected: _mobileDrawerSection == tab.value,
              label: Text(tab.key),
              onSelected: (_) {
                setState(() => _mobileDrawerSection = tab.value);
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _equipmentButtonForLibrary(_EquipmentType type,
      {required bool outlined, required bool isMobile}) {
    final isStraightIron = _isStraightIronType(type);
    final screenWidth = MediaQuery.of(context).size.width;
    final narrowMobile = isMobile && screenWidth < 420;
    final buttonWidth = narrowMobile
        ? (screenWidth - 56).clamp(220.0, 360.0)
        : (isMobile ? 162.0 : 138.0);
    final button = SizedBox(
      width: buttonWidth,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: () {
                if (isStraightIron) {
                  _addItem(type);
                } else {
                  _addItem(type);
                }
              },
              icon: _EquipmentSymbol(
                type: type,
                color: _gold,
                size: 18,
                symbolKey:
                    ValueKey<String>('library-symbol-${type.name}-button'),
              ),
              label:
                  Text(type.label, maxLines: 2, overflow: TextOverflow.visible),
              style: _compactOutlineStyle(highlighted: true),
            )
          : FilledButton.icon(
              onPressed: () {
                if (isStraightIron) {
                  _addItem(type);
                } else {
                  _addItem(type);
                }
              },
              icon: _EquipmentSymbol(
                type: type,
                color: _gold,
                size: 18,
                symbolKey:
                    ValueKey<String>('library-symbol-${type.name}-button'),
              ),
              label:
                  Text(type.label, maxLines: 2, overflow: TextOverflow.visible),
              style: _compactFilledStyle(highlighted: true),
            ),
    );
    if (isStraightIron) {
      return button;
    }
    return LongPressDraggable<_EquipmentType>(
      data: type,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => setState(() => _libraryDragScenePoint = null),
      onDragEnd: (_) => setState(() => _libraryDragScenePoint = null),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 130,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF171A1F),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFCDA56A)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _EquipmentSymbol(type: type, color: _gold, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  type.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: button),
      child: button,
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
        types = const <_EquipmentType>[];
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
                    onPressed: () => _addStraightIronFromLibrary(
                      horizontal: true,
                      size: '2',
                    ),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('2" Horizontal Iron'),
                    style: _compactFilledStyle(highlighted: true),
                  ),
                ),
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: FilledButton(
                    onPressed: () => _addStraightIronFromLibrary(
                      horizontal: false,
                      size: '2',
                    ),
                    style: _compactFilledStyle(highlighted: true),
                    child: const Text('2" Vertical Iron'),
                  ),
                ),
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: FilledButton(
                    onPressed: () => _addStraightIronFromLibrary(
                      horizontal: true,
                      size: '3',
                    ),
                    style: _compactFilledStyle(highlighted: true),
                    child: const Text('3" Horizontal Iron'),
                  ),
                ),
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: FilledButton(
                    onPressed: () => _addStraightIronFromLibrary(
                      horizontal: false,
                      size: '3',
                    ),
                    style: _compactFilledStyle(highlighted: true),
                    child: const Text('3" Vertical Iron'),
                  ),
                ),
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: FilledButton(
                    onPressed: () => _addStraightIronFromLibrary(
                      horizontal: true,
                      size: '4',
                    ),
                    style: _compactFilledStyle(highlighted: true),
                    child: const Text('4" Horizontal Iron'),
                  ),
                ),
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: FilledButton(
                    onPressed: () => _addStraightIronFromLibrary(
                      horizontal: false,
                      size: '4',
                    ),
                    style: _compactFilledStyle(highlighted: true),
                    child: const Text('4" Vertical Iron'),
                  ),
                ),
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
                onPressed: () {
                  _resetTransientInteractionState();
                  setState(() => _showSideLibrary = false);
                },
                icon: const Icon(Icons.close, color: Colors.white70),
                tooltip: 'Close library',
              ),
            ],
          ),
          Row(
            children: [
              const Text(
                'Keep Open',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Switch.adaptive(
                value: _libraryKeepOpen,
                activeColor: _gold,
                onChanged: (value) {
                  setState(() => _libraryKeepOpen = value);
                },
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
    final colors = Theme.of(context).colorScheme;
    return [
      SizedBox(
        width: 84,
        child: Center(
          child: Text(group.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: colors.primary, fontWeight: FontWeight.bold)),
        ),
      ),
      for (final type in types)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: SizedBox(
            width: type.isIron ? 104 : 118,
            child: OutlinedButton(
              onPressed: () {
                if (_isStraightIronType(type)) {
                  _addItem(type);
                } else {
                  _addItem(type);
                }
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Theme.of(context).dividerColor),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.all(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _EquipmentSymbol(
                    type: type,
                    color: _gold,
                    size: 24,
                    symbolKey:
                        ValueKey<String>('library-symbol-${type.name}-card'),
                  ),
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
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bg,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Job Info',
              style: TextStyle(
                color: colors.primary,
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
    final labelsLabel = _showLabels
        ? 'Show Equipment Labels: On'
        : 'Show Equipment Labels: Off';
    final gridLabel = _snapToGrid ? 'Align to Grid: On' : 'Align to Grid: Off';
    final anchorLabel = _showConnectionPoints
        ? 'Show Connection Points: On'
        : 'Show Connection Points: Off';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: _bg,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _saveRigUp,
              icon: const Icon(Icons.save_alt),
              label: const Text('Save'),
              style: _compactFilledStyle(highlighted: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _undoStack.isNotEmpty ? _undoLayoutChange : null,
              icon: const Icon(Icons.undo),
              label: const Text('Undo'),
              style: _compactOutlineStyle(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _redoStack.isNotEmpty ? _redoLayoutChange : null,
              icon: const Icon(Icons.redo),
              label: const Text('Redo'),
              style: _compactOutlineStyle(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PopupMenuButton<String>(
              tooltip: 'More actions',
              onSelected: (value) {
                switch (value) {
                  case 'undo':
                    _undoLayoutChange();
                    break;
                  case 'redo':
                    _redoLayoutChange();
                    break;
                  case 'alignGrid':
                    _toggleSnapToGrid();
                    break;
                  case 'labels':
                    _toggleShowEquipmentLabels();
                    break;
                  case 'anchors':
                    _toggleShowConnectionPoints();
                    break;
                  case 'library':
                    _toggleSideLibrary();
                    break;
                  case 'layoutSettings':
                    _showToolsDrawer();
                    break;
                  case 'clear':
                    _confirmClearLayout();
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
                  value: 'undo',
                  enabled: _undoStack.isNotEmpty,
                  child: const Text('Undo'),
                ),
                PopupMenuItem<String>(
                  value: 'redo',
                  enabled: _redoStack.isNotEmpty,
                  child: const Text('Redo'),
                ),
                PopupMenuItem<String>(
                  value: 'alignGrid',
                  child: Text(gridLabel),
                ),
                PopupMenuItem<String>(
                  value: 'labels',
                  child: Text(labelsLabel),
                ),
                PopupMenuItem<String>(
                  value: 'anchors',
                  child: Text(anchorLabel),
                ),
                PopupMenuItem<String>(
                  value: 'library',
                  child: Text(_showSideLibrary
                      ? 'Hide Rig-Up Library'
                      : 'Open Rig-Up Library'),
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
                const PopupMenuItem<String>(
                  value: 'layoutSettings',
                  child: Text('Layout Settings'),
                ),
              ],
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryActionBar({required bool isWide}) {
    final hasSelected = _hasSelectedItem;
    final locked = _selectedItem?.locked ?? false;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: _bg,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilledButton.icon(
              onPressed: () {
                setState(() => _showSideLibrary = true);
                _clearDrawIronSelection(exitMode: true);
              },
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Add Equipment'),
              style: _compactFilledStyle(highlighted: true),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () {
                setState(() => _showSideLibrary = true);
                _enterDrawIronMode(minimizeLibrary: false);
              },
              icon: const Icon(Icons.edit_road),
              label: const Text('Add Iron'),
              style: _compactFilledStyle(highlighted: _drawIronMode),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                if (!_drawIronMode) return;
                _clearDrawIronSelection(exitMode: true);
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
    final expandedHeight = _effectiveMobileLibraryHeight();
    final panelHeight =
        _showSideLibrary ? expandedHeight : _mobileLibraryMinHeight;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: panelHeight,
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) {
              if (!_showSideLibrary) return;
              setState(() {
                _mobileLibraryHeight =
                    (_effectiveMobileLibraryHeight() - details.delta.dy)
                        .clamp(
                          _mobileLibraryMinHeight,
                          _viewportSize.height * _mobileLibraryMaxFraction,
                        )
                        .toDouble();
              });
            },
            child: InkWell(
              onTap: _toggleSideLibrary,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 4,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Icon(Icons.view_carousel_outlined, color: _gold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _showSideLibrary ? 'Rig-Up Library' : 'Open Library',
                        style: TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_showSideLibrary)
                      Row(
                        children: [
                          const Text(
                            'Keep Open',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          Switch.adaptive(
                            value: _libraryKeepOpen,
                            activeColor: _gold,
                            onChanged: (value) {
                              setState(() => _libraryKeepOpen = value);
                            },
                          ),
                        ],
                      ),
                    if (_showSideLibrary)
                      TextButton(
                        onPressed: () => setState(() {
                          _mobileLibraryHeight = _mobileLibraryMinHeight;
                          _showSideLibrary = false;
                        }),
                        child: const Text('Minimize'),
                      ),
                    IconButton(
                      onPressed: () {
                        _resetTransientInteractionState();
                        setState(() => _showSideLibrary = false);
                      },
                      icon: Icon(
                        _showSideLibrary
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
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
    final hasStart = _drawIronStartTarget != null;
    final canContinue = _pendingContinueIronTarget != null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_road, color: _gold),
              const SizedBox(width: 8),
              Text(
                canContinue ? 'IRON SEGMENT COMPLETE' : 'CONNECT IRON ACTIVE',
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
            canContinue
                ? 'Continue Iron starts from the last endpoint. Done exits Connect Iron mode and hides anchors.'
                : hasStart
                    ? 'Select destination. Valid equipment anchors, bypass ports, and iron endpoints stay visible until the segment is created.'
                    : 'Select starting point. Choose an iron size, then tap a valid anchor or existing iron endpoint.',
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
                key: ValueKey<String>(canContinue
                    ? 'connect-iron-continue-button'
                    : 'connect-iron-done-button'),
                onPressed: canContinue ? _continueIronRun : _finishIronDrawing,
                icon: Icon(
                  canContinue
                      ? Icons.trending_flat_rounded
                      : Icons.check_circle_outline,
                ),
                label: Text(canContinue ? 'Continue Iron' : 'Done'),
                style: _compactFilledStyle(highlighted: true),
              ),
              OutlinedButton.icon(
                key: ValueKey<String>(canContinue
                    ? 'connect-iron-finish-button'
                    : 'connect-iron-cancel-button'),
                onPressed: canContinue
                    ? _finishContinueIronPrompt
                    : _cancelIronDrawing,
                icon:
                    Icon(canContinue ? Icons.done_all : Icons.cancel_outlined),
                label: Text(canContinue ? 'Done' : 'Cancel'),
                style: _compactOutlineStyle(highlighted: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _selectionQuickActionsBar() {
    final hasSelection = _hasSelectedItem;
    final selected = _selectedItem;
    final locked = selected?.locked ?? true;
    final canMove = hasSelection && !locked && !_hideFloatingToolbar;
    final canAct = hasSelection && !_hideFloatingToolbar;

    return Container(
      key: const ValueKey<String>('selection-dock-toolbar'),
      width: double.infinity,
      height: _selectionStripHeight,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131519),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Row(
        children: [
          _selectionDPad(disabled: !canMove),
          const SizedBox(width: 8),
          if (!hasSelection)
            const Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No item selected',
                  style: TextStyle(color: Colors.white60),
                ),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxWidth: 170),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1D23),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF3A3A3A)),
                      ),
                      child: Text(
                        selected?.displayLabel ??
                            selected?.type.label ??
                            'Item',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: canAct ? _rotateSelected : null,
                      icon: const Icon(Icons.rotate_right),
                      label: const Text('Rotate'),
                      style: _compactOutlineStyle(),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: canAct ? _duplicateSelected : null,
                      icon: const Icon(Icons.copy),
                      label: const Text('Duplicate'),
                      style: _compactOutlineStyle(),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: canAct ? _toggleSelectedLock : null,
                      icon: Icon(locked ? Icons.lock_open : Icons.lock),
                      label: Text(locked ? 'Unlock' : 'Lock'),
                      style: _compactOutlineStyle(),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: canAct ? _deleteSelected : null,
                      icon: const Icon(Icons.delete),
                      label: const Text('Delete'),
                      style: _compactOutlineStyle(highlighted: true),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _floatingSelectionToolbar(
      _LayoutItem item, Size viewportSize, bool isLocked) {
    final showDisconnect =
        _isStraightIronType(item.type) && _selectedEndpointLeading != null;
    final width = showDisconnect ? 248.0 : 206.0;
    const height = 44.0;
    final media = MediaQuery.of(context);
    final topSafe = media.padding.top + _toolbarViewportPadding;
    final bottomSafe = media.padding.bottom +
        _toolbarViewportPadding +
        _toolbarBottomClearance;
    final sceneOrigin = Offset(item.x, item.y);
    final viewportOrigin = _viewportPointFromScene(sceneOrigin);
    final scale = _canvasTransform.value.getMaxScaleOnAxis().clamp(0.1, 8.0);
    final viewportItemWidth = item.width * scale;
    final viewportItemHeight = item.height * scale;
    final maxLeft = math.max(
      _toolbarViewportPadding,
      viewportSize.width - width - _toolbarViewportPadding,
    );
    final maxTop = math.max(
      topSafe,
      viewportSize.height - height - bottomSafe,
    );
    final itemLeft = viewportOrigin.dx;
    final itemTop = viewportOrigin.dy;
    final itemRight = itemLeft + viewportItemWidth;
    final itemBottom = itemTop + viewportItemHeight;
    final itemCenterX = itemLeft + (viewportItemWidth / 2);
    final canPlaceAbove = itemTop - _toolbarSelectionGap - height >= topSafe;
    final canPlaceBelow = itemBottom + _toolbarSelectionGap + height <=
        viewportSize.height - bottomSafe;
    final canPlaceRight = itemRight + _toolbarSelectionGap + width <=
        viewportSize.width - _toolbarViewportPadding;
    final canPlaceLeft =
        itemLeft - _toolbarSelectionGap - width >= _toolbarViewportPadding;

    double left;
    double top;
    if (canPlaceAbove) {
      left = (itemCenterX - (width / 2))
          .clamp(_toolbarViewportPadding, maxLeft)
          .toDouble();
      top = (itemTop - _toolbarSelectionGap - height)
          .clamp(topSafe, maxTop)
          .toDouble();
    } else if (canPlaceBelow) {
      left = (itemCenterX - (width / 2))
          .clamp(_toolbarViewportPadding, maxLeft)
          .toDouble();
      top =
          (itemBottom + _toolbarSelectionGap).clamp(topSafe, maxTop).toDouble();
    } else if (canPlaceRight) {
      left = (itemRight + _toolbarSelectionGap)
          .clamp(_toolbarViewportPadding, maxLeft)
          .toDouble();
      top = (itemTop + (viewportItemHeight - height) / 2)
          .clamp(topSafe, maxTop)
          .toDouble();
    } else if (canPlaceLeft) {
      left = (itemLeft - _toolbarSelectionGap - width)
          .clamp(_toolbarViewportPadding, maxLeft)
          .toDouble();
      top = (itemTop + (viewportItemHeight - height) / 2)
          .clamp(topSafe, maxTop)
          .toDouble();
    } else {
      left = (itemCenterX - (width / 2))
          .clamp(_toolbarViewportPadding, maxLeft)
          .toDouble();
      top = (itemTop - _toolbarSelectionGap - height)
          .clamp(topSafe, maxTop)
          .toDouble();
    }

    return Positioned(
      left: left,
      top: top,
      child: Container(
        key: const ValueKey<String>('floating-selection-toolbar'),
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 4),
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
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: const Icon(Icons.copy_outlined, color: Colors.white),
                tooltip: 'Duplicate',
              ),
            ),
            Expanded(
              child: IconButton(
                onPressed: _rotateSelected,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: const Icon(Icons.rotate_right, color: Colors.white),
                tooltip: 'Rotate 90°',
              ),
            ),
            Expanded(
              child: IconButton(
                onPressed: _toggleSelectedLock,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
                iconSize: 20,
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
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                tooltip: 'Delete',
              ),
            ),
            if (showDisconnect)
              Expanded(
                child: IconButton(
                  onPressed: _disconnectSelectedConnection,
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  icon: const Icon(Icons.link_off, color: Colors.white),
                  tooltip: 'Disconnect',
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

  List<Widget> _endpointOverlayHandles(Size viewportSize) {
    final item = _selectedStraightIron;
    if (item == null || item.locked) return const <Widget>[];

    Widget buildHandle({required bool leading}) {
      final scenePoint = _ironEndpoint(item, leading);
      final viewportPoint = _viewportPointFromScene(scenePoint);
      const touchHalf = _endpointHandleTouchSize / 2;
      final left = (viewportPoint.dx - touchHalf)
          .clamp(-touchHalf, viewportSize.width - touchHalf)
          .toDouble();
      final top = (viewportPoint.dy - touchHalf)
          .clamp(-touchHalf, viewportSize.height - touchHalf)
          .toDouble();
      final selected = _selectedEndpointLeading == leading;

      return Positioned(
        left: left,
        top: top,
        child: GestureDetector(
          key: ValueKey<String>(
              'iron-handle-${item.id}-${leading ? 'start' : 'end'}'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: () => setState(() {
            _selectedEndpointLeading = leading;
            _selectedBypassHandle = null;
          }),
          onPanStart: (_) => _startEndpointHandleDrag(item, leading),
          onPanUpdate: (details) =>
              _updateEndpointHandleDrag(item, leading, details.delta),
          onPanEnd: (_) => _endEndpointHandleDrag(item, leading),
          onPanCancel: _resetTransientInteractionState,
          child: SizedBox(
            width: _endpointHandleTouchSize,
            height: _endpointHandleTouchSize,
            child: Center(
              child: Container(
                width: _endpointHandleVisibleSize,
                height: _endpointHandleVisibleSize,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFFFC857)
                      : const Color(0xFFE3BE6B),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return <Widget>[
      buildHandle(leading: true),
      buildHandle(leading: false),
    ];
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
                  final allowCanvasPan =
                      _interactionMode == _InteractionMode.idle &&
                          !_drawIronMode;

                  return Stack(
                    children: [
                      DragTarget<_EquipmentType>(
                        onWillAcceptWithDetails: (details) {
                          final scene = _scenePointFromGlobal(details.offset);
                          setState(() => _libraryDragScenePoint = scene);
                          return true;
                        },
                        onMove: (details) {
                          final scene = _scenePointFromGlobal(details.offset);
                          setState(() => _libraryDragScenePoint = scene);
                        },
                        onLeave: (_) {
                          if (_libraryDragScenePoint != null) {
                            setState(() => _libraryDragScenePoint = null);
                          }
                        },
                        onAcceptWithDetails: (details) {
                          final scene = _scenePointFromGlobal(details.offset);
                          _addItem(
                            details.data,
                            preferredScenePoint: scene,
                            applySpread: false,
                          );
                          setState(() => _libraryDragScenePoint = null);
                        },
                        builder: (context, _, __) => GestureDetector(
                          key: _canvasViewportKey,
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) {
                            final scenePoint =
                                _scenePointFromViewport(details.localPosition);
                            _handleCanvasTap(scenePoint);
                          },
                          child: InteractiveViewer(
                            transformationController: _canvasTransform,
                            onInteractionEnd: (_) {
                              if (!mounted) return;
                              setState(() {
                                _interactionMode = _drawIronMode
                                    ? _InteractionMode.placeIron
                                    : _InteractionMode.idle;
                              });
                            },
                            minScale: 0.45,
                            maxScale: 3.5,
                            boundaryMargin: const EdgeInsets.all(420),
                            constrained: false,
                            panEnabled: allowCanvasPan,
                            scaleEnabled: allowCanvasPan,
                            child: SizedBox(
                              width: canvasSize.width,
                              height: canvasSize.height,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: CustomPaint(painter: _GridPainter()),
                                  ),
                                  if (_drawIronMode)
                                    for (final it in _items)
                                      if (!_isStraightIronType(it.type))
                                        for (final anchor
                                            in _equipmentAnchorCandidates(it))
                                          if (_shouldShowAnchorCandidate(
                                              anchor))
                                            Positioned(
                                              key: ValueKey<String>(
                                                  'connect-anchor-${it.id}-${anchor.side}'),
                                              left: anchor.point.dx - 3,
                                              top: anchor.point.dy - 3,
                                              child: IgnorePointer(
                                                child: Container(
                                                  width: 6,
                                                  height: 6,
                                                  decoration: BoxDecoration(
                                                    color: _gold,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ),
                                            ),
                                  if (_drawIronMode)
                                    for (final it in _items)
                                      if (_isStraightIronType(it.type))
                                        for (final leading in const <bool>[
                                          true,
                                          false
                                        ])
                                          Positioned(
                                            key: ValueKey<String>(
                                                'connect-iron-endpoint-${it.id}-${leading ? 'start' : 'end'}'),
                                            left:
                                                _ironEndpoint(it, leading).dx -
                                                    4,
                                            top: _ironEndpoint(it, leading).dy -
                                                4,
                                            child: IgnorePointer(
                                              child: Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: _gold,
                                                  shape: BoxShape.circle,
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Color(0x66000000),
                                                      blurRadius: 3,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                  if (_showAnchorsForConnection &&
                                      !_drawIronMode)
                                    for (final it in _items)
                                      if (!_isStraightIronType(it.type))
                                        for (final anchor
                                            in _equipmentAnchorCandidates(it))
                                          if (_shouldShowAnchorCandidate(
                                              anchor))
                                            Positioned(
                                              left: anchor.point.dx - 3,
                                              top: anchor.point.dy - 3,
                                              child: IgnorePointer(
                                                child: Container(
                                                  width: 6,
                                                  height: 6,
                                                  decoration: BoxDecoration(
                                                    color: _gold,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ),
                                            ),
                                  if (_drawIronMode &&
                                      _drawIronStartTarget != null &&
                                      (_drawIronHoverTarget != null ||
                                          _drawIronPointerScene != null))
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: CustomPaint(
                                          painter: _DrawIronPreviewPainter(
                                            start: _drawIronStartTarget!.point,
                                            end: _drawIronHoverTarget?.point ??
                                                _drawIronPointerScene!,
                                            color: _gold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_libraryDragScenePoint != null)
                                    Positioned(
                                      left: _libraryDragScenePoint!.dx - 12,
                                      top: _libraryDragScenePoint!.dy - 12,
                                      child: IgnorePointer(
                                        child: Container(
                                          width: 24,
                                          height: 24,
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
                                  if (_snapIndicatorScene != null)
                                    Positioned(
                                      left: _snapIndicatorScene!.dx - 11,
                                      top: _snapIndicatorScene!.dy - 11,
                                      child: IgnorePointer(
                                        child: Container(
                                          key: const ValueKey<String>(
                                              'snap-indicator'),
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
                                  if (_drawIronMode)
                                    Positioned(
                                      right: 12,
                                      top: 12,
                                      child: IgnorePointer(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: const Color(0xDD0F1014),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color:
                                                  _gold.withValues(alpha: 0.65),
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            child: Text(
                                              _drawIronStatusText,
                                              style: TextStyle(
                                                color: _gold,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
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
                                          'Add equipment from the library. Pinch to zoom and drag to pan this workspace.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 16),
                                        ),
                                      ),
                                    ),
                                  for (final item in _items)
                                    () {
                                      final interactionPadding =
                                          _interactionPaddingForItem(item);
                                      return Positioned(
                                        left: item.x - interactionPadding,
                                        top: item.y - interactionPadding,
                                        width:
                                            item.width + interactionPadding * 2,
                                        height: item.height +
                                            interactionPadding * 2,
                                        child: GestureDetector(
                                          key: ValueKey<String>(
                                              'item-hitbox-${item.id}'),
                                          behavior: HitTestBehavior.opaque,
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
                                          },
                                          onPanStart: (details) =>
                                              _beginItemDrag(item, details),
                                          onPanUpdate: (details) =>
                                              _updateItemDrag(item, details),
                                          onPanEnd: (_) => _endItemDrag(item),
                                          onPanCancel:
                                              _resetTransientInteractionState,
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Positioned(
                                                left: interactionPadding,
                                                top: interactionPadding,
                                                width: item.width,
                                                height: item.height,
                                                child: _LayoutTile(
                                                  item: item,
                                                  selected: _selectedIds
                                                      .contains(item.id),
                                                  showLabel: _showLabels,
                                                  snapHighlight:
                                                      _snapCandidateIronId ==
                                                          item.id,
                                                ),
                                              ),
                                              if (_selectedIds
                                                      .contains(item.id) &&
                                                  item.type ==
                                                      _EquipmentType
                                                          .bypass) ...[
                                                _BypassAttachmentHandle(
                                                  item: item,
                                                  slot: 'Primary',
                                                  interactionPadding:
                                                      interactionPadding,
                                                  selected:
                                                      _selectedBypassHandle ==
                                                          'Primary',
                                                  onTap: () => setState(() {
                                                    _selectedBypassHandle =
                                                        'Primary';
                                                    _selectedEndpointLeading =
                                                        null;
                                                  }),
                                                  onPanStart: () {
                                                    _recordUndo();
                                                    _selectedBypassHandle =
                                                        'Primary';
                                                    _selectedEndpointLeading =
                                                        null;
                                                  },
                                                  onPanUpdate: (details) =>
                                                      _attachBypassHandleToNearestRail(
                                                          item,
                                                          'Primary',
                                                          details),
                                                  onPanEnd: () => setState(() {
                                                    _commitBypassHandleAttachment(
                                                        item, 'Primary');
                                                  }),
                                                  onPanCancel:
                                                      _resetTransientInteractionState,
                                                ),
                                                _BypassAttachmentHandle(
                                                  item: item,
                                                  slot: 'Secondary',
                                                  interactionPadding:
                                                      interactionPadding,
                                                  selected:
                                                      _selectedBypassHandle ==
                                                          'Secondary',
                                                  trailing: true,
                                                  onTap: () => setState(() {
                                                    _selectedBypassHandle =
                                                        'Secondary';
                                                    _selectedEndpointLeading =
                                                        null;
                                                  }),
                                                  onPanStart: () {
                                                    _recordUndo();
                                                    _selectedBypassHandle =
                                                        'Secondary';
                                                    _selectedEndpointLeading =
                                                        null;
                                                  },
                                                  onPanUpdate: (details) =>
                                                      _attachBypassHandleToNearestRail(
                                                          item,
                                                          'Secondary',
                                                          details),
                                                  onPanEnd: () => setState(() {
                                                    _commitBypassHandleAttachment(
                                                        item, 'Secondary');
                                                  }),
                                                  onPanCancel:
                                                      _resetTransientInteractionState,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      );
                                    }(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_selectedStraightIron != null)
                        ..._endpointOverlayHandles(viewportSize),
                      if (_dragPreviewItemId != null &&
                          _dragPreviewScenePosition != null)
                        () {
                          final previewItem =
                              _findItemById(_dragPreviewItemId!);
                          if (previewItem == null)
                            return const SizedBox.shrink();
                          final vp = _viewportPointFromScene(
                              _dragPreviewScenePosition!);
                          final left = (vp.dx - 30)
                              .clamp(8.0, viewportSize.width - 68.0);
                          final top = (vp.dy - _dragLiftScreenOffsetY)
                              .clamp(8.0, viewportSize.height - 80.0);
                          return Positioned(
                            left: left,
                            top: top,
                            child: IgnorePointer(
                              child: Container(
                                width: 60,
                                height: 52,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xEE121417),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: const Color(0xFFCDA56A)),
                                ),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Center(
                                        child: _EquipmentSymbol(
                                          type: previewItem.type,
                                          color: _gold,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 16,
                                      height: 2,
                                      color: Colors.white54,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }(),
                    ],
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

enum _InteractionMode {
  idle,
  placeIron,
  itemDrag,
  stretchEndpoint,
  attachBypass,
}

enum _LayoutAlign { left, right, top, bottom, horizontalCenter, verticalCenter }

enum _LayoutDistribution { horizontal, vertical }

enum _DrawerLibrarySection { equipment, iron, tees, nineties, bypass }

class _AnchorDefinition {
  final String id;
  final double u;
  final double v;

  const _AnchorDefinition(this.id, this.u, this.v);
}

enum _ConnectionTargetKind {
  equipmentAnchor,
  ironEndpoint,
}

class _ConnectionTarget {
  final _ConnectionTargetKind kind;
  final Offset point;
  final double distance;
  final bool isExactHit;
  final int? equipmentItemId;
  final String? anchorId;
  final int? ironItemId;
  final bool? ironLeading;

  const _ConnectionTarget({
    required this.kind,
    required this.point,
    required this.distance,
    required this.isExactHit,
    this.equipmentItemId,
    this.anchorId,
    this.ironItemId,
    this.ironLeading,
  });
}

class _DrawIronPreviewPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  const _DrawIronPreviewPainter({
    required this.start,
    required this.end,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, paint);

    final halo = Paint()
      ..color = color.withValues(alpha: 0.24)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(end, 10, halo);
    canvas.drawCircle(
      end,
      5,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _DrawIronPreviewPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.color != color;
  }
}

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

class _EndpointCandidate {
  final int itemId;
  final bool leading;
  final Offset point;
  final double score;

  const _EndpointCandidate({
    required this.itemId,
    required this.leading,
    required this.point,
    required this.score,
  });
}

class _EquipmentAnchorCandidate {
  final int itemId;
  final String side;
  final Offset point;
  final double score;

  const _EquipmentAnchorCandidate({
    required this.itemId,
    required this.side,
    required this.point,
    required this.score,
  });
}

class _BypassHandleCandidate {
  final int itemId;
  final String side;
  final Offset point;
  final double score;

  const _BypassHandleCandidate({
    required this.itemId,
    required this.side,
    required this.point,
    required this.score,
  });
}

class _EndpointSnapTarget {
  final Offset point;
  final _EndpointCandidate? endpoint;
  final _EquipmentAnchorCandidate? equipment;
  final _BypassHandleCandidate? bypass;

  const _EndpointSnapTarget({
    required this.point,
    this.endpoint,
    this.equipment,
    this.bypass,
  });
}

class _ActiveEndpointDrag {
  final int ironId;
  final bool leading;
  final Offset worldPosition;
  final _EndpointSnapTarget? target;

  const _ActiveEndpointDrag({
    required this.ironId,
    required this.leading,
    required this.worldPosition,
    required this.target,
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

  bool get usesCompactEquipmentFootprint =>
      !isIron && this != _EquipmentType.facilities;

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
    if (this == _EquipmentType.wellhead) return 30;
    if (this == _EquipmentType.plugCatcher) return 40;
    if (this == _EquipmentType.lineHeater) return 38;
    if (this == _EquipmentType.facilities) return 220;
    if (this == _EquipmentType.sphericalSandSep) return 34;
    if (this == _EquipmentType.cyclonicSandSep) return 34;
    if (this == _EquipmentType.esdValve) return 30;
    if (this == _EquipmentType.chokeManifold) return 38;
    if (this == _EquipmentType.flowbackTank) return 38;
    if (this == _EquipmentType.productionTank) return 38;
    if (this == _EquipmentType.testSeparator) return 36;
    if (this == _EquipmentType.flare) return 32;
    if (this == _EquipmentType.compressor) return 36;
    if (this == _EquipmentType.ironHorizontal) return 150;
    if (this == _EquipmentType.ironVertical) return 28;
    if (this == _EquipmentType.bypass) return 34;
    if (name.startsWith('tee')) return 42;
    if (name.startsWith('elbow')) return 42;
    if (isIron) return 76;
    return 36;
  }

  double get defaultHeight {
    if (this == _EquipmentType.wellhead) return 28;
    if (this == _EquipmentType.plugCatcher) return 26;
    if (this == _EquipmentType.lineHeater) return 26;
    if (this == _EquipmentType.facilities) return 112;
    if (this == _EquipmentType.sphericalSandSep) return 34;
    if (this == _EquipmentType.cyclonicSandSep) return 32;
    if (this == _EquipmentType.esdValve) return 24;
    if (this == _EquipmentType.chokeManifold) return 24;
    if (this == _EquipmentType.flowbackTank) return 28;
    if (this == _EquipmentType.productionTank) return 28;
    if (this == _EquipmentType.testSeparator) return 28;
    if (this == _EquipmentType.flare) return 28;
    if (this == _EquipmentType.compressor) return 28;
    if (this == _EquipmentType.ironHorizontal) return 24;
    if (this == _EquipmentType.ironVertical) return 150;
    if (this == _EquipmentType.bypass) return 32;
    if (name.startsWith('tee')) return 42;
    if (name.startsWith('elbow')) return 42;
    if (isIron) return 76;
    return 28;
  }

  Size get build109LegacySize {
    if (this == _EquipmentType.wellhead) return const Size(98, 64);
    if (this == _EquipmentType.plugCatcher) return const Size(170, 94);
    if (this == _EquipmentType.lineHeater) return const Size(178, 98);
    if (this == _EquipmentType.facilities) return const Size(220, 112);
    if (this == _EquipmentType.sphericalSandSep) return const Size(134, 124);
    if (this == _EquipmentType.cyclonicSandSep) return const Size(116, 110);
    if (this == _EquipmentType.esdValve) return const Size(64, 44);
    if (this == _EquipmentType.ironHorizontal) return const Size(150, 24);
    if (this == _EquipmentType.ironVertical) return const Size(28, 150);
    if (this == _EquipmentType.bypass) return const Size(66, 34);
    if (name.startsWith('tee') || name.startsWith('elbow')) {
      return const Size(42, 42);
    }
    if (isIron) return const Size(76, 76);
    return const Size(116, 72);
  }

  Size get build110LegacySize {
    if (this == _EquipmentType.wellhead) return const Size(74, 58);
    if (this == _EquipmentType.plugCatcher) return const Size(102, 60);
    if (this == _EquipmentType.lineHeater) return const Size(110, 62);
    if (this == _EquipmentType.facilities) return const Size(220, 112);
    if (this == _EquipmentType.sphericalSandSep) return const Size(84, 84);
    if (this == _EquipmentType.cyclonicSandSep) return const Size(82, 78);
    if (this == _EquipmentType.esdValve) return const Size(52, 38);
    if (this == _EquipmentType.ironHorizontal) return const Size(150, 24);
    if (this == _EquipmentType.ironVertical) return const Size(28, 150);
    if (this == _EquipmentType.bypass) return const Size(66, 34);
    if (name.startsWith('tee') || name.startsWith('elbow')) {
      return const Size(42, 42);
    }
    if (isIron) return const Size(76, 76);
    return const Size(86, 56);
  }

  bool matchesLegacyDimensions(double width, double height) {
    final v109 = build109LegacySize;
    final v110 = build110LegacySize;
    final isV109 =
        (width - v109.width).abs() < 0.2 && (height - v109.height).abs() < 0.2;
    final isV110 =
        (width - v110.width).abs() < 0.2 && (height - v110.height).abs() < 0.2;
    return isV109 || isV110;
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
    final rawWidth = (json['width'] as num?)?.toDouble();
    final rawHeight = (json['height'] as num?)?.toDouble();
    var width = rawWidth ?? type.defaultWidth;
    var height = rawHeight ?? type.defaultHeight;
    var x = (json['x'] as num? ?? 20).toDouble();
    var y = (json['y'] as num? ?? 20).toDouble();

    // Keep saved layout centers stable while migrating legacy defaults.
    if (rawWidth != null &&
        rawHeight != null &&
        type.usesCompactEquipmentFootprint &&
        type.matchesLegacyDimensions(width, height)) {
      final centerX = x + width / 2;
      final centerY = y + height / 2;
      width = type.defaultWidth;
      height = type.defaultHeight;
      x = centerX - width / 2;
      y = centerY - height / 2;
    }

    if (rawWidth != null &&
        rawHeight != null &&
        type == _EquipmentType.bypass &&
        (rawWidth - 66.0).abs() < 0.2 &&
        (rawHeight - 34.0).abs() < 0.2) {
      final centerX = x + width / 2;
      final centerY = y + height / 2;
      width = type.defaultWidth;
      height = type.defaultHeight;
      x = centerX - width / 2;
      y = centerY - height / 2;
    }

    if (rawWidth != null &&
        rawHeight != null &&
        type == _EquipmentType.bypass &&
        (rawWidth - 46.0).abs() < 0.2 &&
        (rawHeight - 32.0).abs() < 0.2) {
      final centerX = x + width / 2;
      final centerY = y + height / 2;
      width = type.defaultWidth;
      height = type.defaultHeight;
      x = centerX - width / 2;
      y = centerY - height / 2;
    }

    return _LayoutItem(
      id: json['id'] as int? ?? 0,
      type: type,
      x: x,
      y: y,
      width: width,
      height: height,
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

class _EquipmentSymbol extends StatelessWidget {
  final _EquipmentType type;
  final Color color;
  final double size;
  final Key? symbolKey;

  const _EquipmentSymbol({
    required this.type,
    required this.color,
    required this.size,
    this.symbolKey,
  });

  @override
  Widget build(BuildContext context) {
    if (type == _EquipmentType.wellhead) {
      return SizedBox(
        key: symbolKey,
        width: size,
        height: size,
        child: CustomPaint(
          painter: _WellheadTreePainter(color: color),
        ),
      );
    }
    return Icon(type.icon, key: symbolKey, color: color, size: size);
  }
}

class _WellheadTreePainter extends CustomPainter {
  final Color color;

  const _WellheadTreePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.shortestSide * 0.085).clamp(1.6, 2.8)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final valve = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (stroke.strokeWidth * 0.82).clamp(1.2, 2.2)
      ..strokeCap = StrokeCap.round;

    final centerX = size.width * 0.5;
    final topY = size.height * 0.14;
    final branchY = size.height * 0.38;
    final lowerY = size.height * 0.66;
    final baseY = size.height * 0.84;

    canvas.drawLine(Offset(centerX, topY), Offset(centerX, baseY), stroke);
    canvas.drawLine(Offset(size.width * 0.2, branchY),
        Offset(size.width * 0.8, branchY), stroke);
    canvas.drawLine(Offset(centerX, lowerY), Offset(centerX, baseY), stroke);
    canvas.drawLine(Offset(size.width * 0.28, baseY),
        Offset(size.width * 0.72, baseY), stroke);

    void drawValve(double x, double y) {
      final radius = (size.shortestSide * 0.09).clamp(1.6, 3.2);
      canvas.drawCircle(Offset(x, y), radius, valve);
      canvas.drawLine(
          Offset(x - radius * 0.8, y), Offset(x + radius * 0.8, y), valve);
      canvas.drawLine(
          Offset(x, y - radius * 0.8), Offset(x, y + radius * 0.8), valve);
    }

    drawValve(centerX, topY);
    drawValve(size.width * 0.2, branchY);
    drawValve(size.width * 0.8, branchY);
    drawValve(centerX, lowerY);
  }

  @override
  bool shouldRepaint(covariant _WellheadTreePainter oldDelegate) {
    return oldDelegate.color != color;
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
    if (item.type == _EquipmentType.facilities) return -15;
    if (item.height <= 62) return -18;
    return -16;
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
    final isFacilities = item.type == _EquipmentType.facilities;
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
            width: selected ? 1.2 : (showSnapHighlight ? 1.3 : 1.0)),
        borderRadius: BorderRadius.circular(
            item.type == _EquipmentType.sphericalSandSep ? 999 : 10),
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
                        final inset = isFacilities
                            ? (shortest * 0.12).clamp(4.0, 12.0)
                            : (shortest < 66 ? 2.0 : 3.0);
                        final iconSize = isFacilities
                            ? (shortest * 0.36)
                                .clamp(16.0, compact ? 24.0 : 30.0)
                            : (shortest * 0.62)
                                .clamp(14.0, compact ? 22.0 : 24.0);

                        return Padding(
                          padding: EdgeInsets.all(inset),
                          child: DecoratedBox(
                            key: ValueKey<String>('equipment-shell-${item.id}'),
                            decoration: BoxDecoration(
                              color: isFacilities
                                  ? const Color(0xFF202327)
                                  : const Color(0xFF191B1F),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFFCDA56A)
                                        .withValues(alpha: 0.72)
                                    : const Color(0xFF4A4A4A),
                                width: selected ? 1.2 : 1.0,
                              ),
                              borderRadius: BorderRadius.circular(
                                  item.type == _EquipmentType.sphericalSandSep
                                      ? 999
                                      : (isFacilities ? 12 : 8)),
                            ),
                            child: Center(
                              child: _EquipmentSymbol(
                                type: item.type,
                                color: const Color(0xFFF3C77D),
                                size: iconSize,
                                symbolKey: ValueKey<String>(
                                    'equipment-symbol-${item.id}'),
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
              right: 2,
              top: 2,
              child: Icon(Icons.lock, size: 12, color: Color(0xFFCDA56A)),
            ),
        ],
      ),
    );
  }
}

class _BypassAttachmentHandle extends StatelessWidget {
  final _LayoutItem item;
  final String slot;
  final double interactionPadding;
  final bool selected;
  final bool trailing;
  final VoidCallback onTap;
  final VoidCallback onPanStart;
  final ValueChanged<DragUpdateDetails> onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback? onPanCancel;

  const _BypassAttachmentHandle({
    required this.item,
    required this.slot,
    required this.interactionPadding,
    required this.selected,
    this.trailing = false,
    required this.onTap,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    this.onPanCancel,
  });

  @override
  Widget build(BuildContext context) {
    const handleTouchSize = 38.0;
    const handleVisibleSize = 18.0;
    const edgeInset = 10.0;
    final left =
        trailing ? item.width - handleTouchSize + edgeInset : -edgeInset;
    final top = item.height / 2 - handleTouchSize / 2;
    return Positioned(
      left: left + interactionPadding,
      top: top + interactionPadding,
      child: GestureDetector(
        key: ValueKey<String>('bypass-handle-${item.id}-${slot.toLowerCase()}'),
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onTap: onTap,
        onPanStart: (_) => onPanStart(),
        onPanUpdate: onPanUpdate,
        onPanEnd: (_) => onPanEnd(),
        onPanCancel: onPanCancel,
        child: SizedBox(
          width: handleTouchSize,
          height: handleTouchSize,
          child: Center(
            child: Container(
              width: handleVisibleSize,
              height: handleVisibleSize,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFFFC857)
                    : const Color(0xFFE3BE6B),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1.4),
              ),
            ),
          ),
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
      final leftX = size.width * .3;
      final rightX = size.width * .7;
      final centerY = size.height * .5;
      final branchLength = size.height * .18;
      final stemLength = size.width * .11;
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
      final topY = size.height * .18;
      final branchY = size.height * .4;
      final lowerY = size.height * .66;
      final baseY = size.height * .84;
      final centerX = size.width * .5;

      canvas.drawLine(Offset(centerX, topY), Offset(centerX, baseY), accent);
      canvas.drawLine(Offset(size.width * .24, branchY),
          Offset(size.width * .76, branchY), accent);
      canvas.drawLine(Offset(centerX, lowerY), Offset(centerX, baseY), accent);
      canvas.drawLine(Offset(size.width * .3, baseY),
          Offset(size.width * .7, baseY), accent);

      for (final point in <Offset>[
        Offset(centerX, topY),
        Offset(size.width * .24, branchY),
        Offset(size.width * .76, branchY),
        Offset(centerX, lowerY),
      ]) {
        canvas.drawCircle(point, size.shortestSide * .06, accent);
      }
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
