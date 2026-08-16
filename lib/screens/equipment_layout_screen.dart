// ignore_for_file: unused_element, curly_braces_in_flow_control_structures, prefer_const_constructors, deprecated_member_use, unnecessary_brace_in_string_interps

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
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
import '../models/layout_interchange.dart';
import '../services/job_storage_service.dart';
import '../services/layout_export_service.dart';
import '../services/layout_interchange_codec.dart';
import '../services/recovery_state_service.dart';
import '../widgets/app_header.dart';

class EquipmentLayoutScreen extends StatefulWidget {
  const EquipmentLayoutScreen({super.key});

  @override
  State<EquipmentLayoutScreen> createState() => _EquipmentLayoutScreenState();
}

class _LayoutExportRequest {
  final LayoutExportFormat format;
  final String fileName;

  const _LayoutExportRequest({
    required this.format,
    required this.fileName,
  });
}

class _EquipmentLayoutScreenState extends State<EquipmentLayoutScreen>
    with WidgetsBindingObserver {
  static final LayoutExportService _layoutExportService = LayoutExportService();
  final List<_LayoutItem> _items = [];
  int? _selectedId;
  final Set<int> _selectedIds = <int>{};
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
  List<int> _lastSelectionCandidateIds = <int>[];
  int _lastSelectionCandidateIndex = 0;
  final Map<int, Offset> _dragItemStart = <int, Offset>{};
  final Map<int, _BypassDragContext> _bypassDragContexts =
      <int, _BypassDragContext>{};
  final Map<int, Set<String>> _fittingDragBlockedTargetKeys =
      <int, Set<String>>{};
  final Set<int> _activeFreeDragItemIds = <int>{};
  bool? _selectedEndpointLeading;
  String? _selectedBypassHandle;
  String? _selectedBypassLeadId;
  _ConnectionTarget? _selectedPortTarget;
  _ConnectionTarget? _pendingConnectIronSourceTarget;
  int? _autoConnectDestinationItemId;
  bool _autoConnectMode = false;
  _ActiveEndpointDrag? _activeEndpointDrag;
  _ActiveBypassLeadDrag? _activeBypassLeadDrag;
  _FittingPreviewState? _activeFittingPreview;
  _InteractionMode _interactionMode = _InteractionMode.idle;
  bool _duplicateInProgress = false;
  bool _arrowHoldTriggered = false;
  Timer? _arrowRepeatTimer;
  Timer? _arrowRepeatDelayTimer;
  Timer? _selectedFittingSnapTimer;
  final Set<int> _pendingFittingSnapItemIds = <int>{};
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
  static const double _endpointHandleTouchSize = 56.0;
  static const double _toolbarViewportPadding = 8.0;
  static const double _toolbarSelectionGap = 16.0;
  static const double _toolbarBottomClearance = 84.0;
  static const double _equipmentAnchorSnapRadius = 24.0;
  static const double _selectionStripHeight = 118.0;
  static const double _mobileLibraryMinHeight = 56.0;
  static const double _mobileLibraryDefaultFraction = 0.38;
  static const double _mobileLibraryMaxFraction = 0.82;
  static const double _dragLiftScreenOffsetY = 64.0;
  static const double _connectionPreviewRadiusScreen = 34.0;
  static const double _connectionReleaseRadiusScreen = 18.0;
  static const double _disconnectHoldRadiusScreen = 8.0;
  static const double _disconnectThresholdScreen = 18.0;
  static const double _teeDetachThresholdScreen = 24.0;
  static const double _sameTargetLockoutRadiusScreen = 42.0;
  static const double _ironSelectionCorridorScreen = 22.0;
  static const double _ironBodyHitCorridorScreen = 20.0;
  static const double _endpointResizeHitRadiusScreen = 16.0;
  static const double _itemSelectionCorridorScreen = 16.0;
  static const double _freeIronMinLength = 14.0;
  static const double _portLeadDefaultLength = 28.0;
  static const double _bypassLeadDefaultLength = 28.0;
  static const double _bypassAttachRadiusScreen = 38.0;
  static const double _inlineSpineReleaseRadiusScreen = 18.0;
  static const String _labelsPrefKey = 'wellwerks_layout_show_labels_v1';
  static const String _bypassPortMainTop = 'mainTop';
  static const String _bypassPortMainBottom = 'mainBottom';
  static const String _bypassPortUpperValveOutlet = 'upperValveOutlet';
  static const String _bypassPortLowerValveOutlet = 'lowerValveOutlet';
  static const String _bypassLeadA = 'leadA';
  static const String _bypassLeadB = 'leadB';
  static const String _freeAngleIronKey = 'freeAngleIron';
  static const String _freeAngleStartXKey = 'freeAngleStartX';
  static const String _freeAngleStartYKey = 'freeAngleStartY';
  static const String _freeAngleEndXKey = 'freeAngleEndX';
  static const String _freeAngleEndYKey = 'freeAngleEndY';

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
    _cancelSelectedFittingSnapTimer();
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

  void _clearFittingPreview() {
    _activeFittingPreview = null;
    _snapIndicatorScene = null;
    _snapCandidateIronId = null;
  }

  void _cancelSelectedFittingSnapTimer() {
    _selectedFittingSnapTimer?.cancel();
    _selectedFittingSnapTimer = null;
    _pendingFittingSnapItemIds.clear();
  }

  String _connectionTargetKey(_ConnectionTarget target) {
    if (target.kind == _ConnectionTargetKind.ironEndpoint) {
      return 'joint:${target.ironItemId}:${target.ironLeading == true ? 'start' : 'end'}';
    }
    return 'anchor:${target.equipmentItemId}:${target.anchorId}';
  }

  String _connectionTargetKeyForItem(_LayoutItem item, String side) {
    if (_isStraightIronType(item.type) && (side == 'start' || side == 'end')) {
      return 'joint:${item.id}:$side';
    }
    return 'anchor:${item.id}:$side';
  }

  Set<String> _currentFittingConnectionKeys(_LayoutItem fitting) {
    final keys = <String>{};
    if (!_isFittingEndpointConnectableType(fitting.type)) return keys;
    for (final side in _fittingEndpointSides(fitting)) {
      final anchorItemId =
          int.tryParse(fitting.properties[_fittingAnchorItemKey(side)] ?? '');
      final anchorSide = fitting.properties[_fittingAnchorSideKey(side)];
      if (anchorItemId == null || anchorSide == null || anchorSide.isEmpty) {
        continue;
      }
      final anchorItem = _findItemById(anchorItemId);
      if (anchorItem == null) continue;
      final normalizedSide = anchorItem.type == _EquipmentType.bypass
          ? _normalizedBypassPortId(anchorSide)
          : _normalizedAnchorSide(anchorItem, anchorSide);
      if (normalizedSide == null) continue;
      keys.add(_connectionTargetKeyForItem(anchorItem, normalizedSide));
    }
    return keys;
  }

  void _scheduleSelectedFittingSnap(List<_LayoutItem> moving) {
    final fittingIds = moving
        .where((item) => _isFittingEndpointConnectableType(item.type))
        .map((item) => item.id)
        .toSet();
    if (fittingIds.isEmpty) return;
    _cancelSelectedFittingSnapTimer();
    _pendingFittingSnapItemIds.addAll(fittingIds);
    _selectedFittingSnapTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final items = _pendingFittingSnapItemIds
          .map(_findItemById)
          .whereType<_LayoutItem>()
          .where((item) => _isFittingEndpointConnectableType(item.type))
          .toList(growable: false);
      if (items.isEmpty) return;
      setState(() {
        _finalizeDraggedItemConnections(items);
        _clearFittingPreview();
      });
      _pendingFittingSnapItemIds.clear();
    });
  }

  void _updateFittingPreviewForMovingItems(List<_LayoutItem> moving) {
    _activeFittingPreview = null;
    for (final item in moving) {
      if (!_isFittingEndpointConnectableType(item.type)) continue;
      final blockedKeys = _fittingDragBlockedTargetKeys[item.id];
      final candidate = _nearestFittingEndpointSnapCandidate(
        item,
        radiusScreen: _connectionPreviewRadiusScreen,
        blockedTargetKeys: blockedKeys,
      );
      if (candidate == null) continue;
      _activeFittingPreview = _FittingPreviewState(
        itemId: item.id,
        candidate: candidate,
      );
      _snapIndicatorScene = candidate.target.point;
      if (candidate.target.kind == _ConnectionTargetKind.ironEndpoint) {
        _snapCandidateIronId = candidate.target.ironItemId;
      } else {
        _snapCandidateIronId = candidate.target.equipmentItemId;
      }
      return;
    }
    _clearFittingPreview();
  }

  void _detachConnectionsForFreeFittingDrag(_LayoutItem fitting) {
    _clearFittingAnchors(fitting);
    _clearInlineParentAttachment(fitting);

    for (final other in _items) {
      if (other.id == fitting.id) continue;
      if (_isStraightIronType(other.type)) {
        for (final leading in const <bool>[true, false]) {
          final anchorItemId = int.tryParse(
              other.properties[_endpointAnchorItemKey(leading)] ?? '');
          if (anchorItemId == fitting.id) {
            _clearEndpointAttachment(other, leading);
          }
        }
      }

      if (other.type == _EquipmentType.bypass) {
        for (final leadId in _bypassLeadIds) {
          final target = _bypassLeadStoredTarget(other, leadId);
          if (target?.equipmentItemId == fitting.id) {
            final endpoint = _resolveBypassLeadEndpointWorld(other, leadId);
            _setBypassLeadTarget(
              other,
              leadId,
              kind: null,
              targetItemId: null,
              side: null,
            );
            _setBypassLeadEndpointWorld(other, leadId, endpoint);
          }
        }
      }

      if (_isFittingEndpointConnectableType(other.type)) {
        for (final side in _fittingEndpointSides(other)) {
          final anchorItemId =
              int.tryParse(other.properties[_fittingAnchorItemKey(side)] ?? '');
          if (anchorItemId == fitting.id) {
            _setFittingAnchor(
              other,
              side,
              anchorItemId: null,
              anchorSide: null,
            );
          }
        }
      }
    }
  }

  void _beginFreeItemDrag(List<_LayoutItem> moving, Offset sceneStart) {
    _interactionMode = _InteractionMode.itemDrag;
    _activeEndpointDrag = null;
    _snapIndicatorScene = null;
    _clearFittingPreview();
    _cancelSelectedFittingSnapTimer();
    _dragSceneStart = sceneStart;
    _selectedEndpointLeading = null;
    _dragActive = false;
    _clearDragPreview();
    _bypassDragContexts.clear();
    _activeFreeDragItemIds
      ..clear()
      ..addAll(moving.map((it) => it.id));
    _dragItemStart
      ..clear()
      ..addEntries(moving.map((it) => MapEntry(it.id, Offset(it.x, it.y))));

    for (final it in moving) {
      if (_isFittingEndpointConnectableType(it.type)) {
        _fittingDragBlockedTargetKeys[it.id] =
            _currentFittingConnectionKeys(it);
        final attachedParent = _inlineParentIron(it);
        final attachedT = _inlineParentT(it);
        final keepAttached = _usesInlineParentDragConstraint(it.type) &&
            attachedParent != null &&
            attachedT != null;
        if (!keepAttached) {
          _detachConnectionsForFreeFittingDrag(it);
        }
      }
      if (!_isInlineFittingType(it.type)) continue;
      final parentIron = _inlineParentIron(it);
      final parentT = _inlineParentT(it);
      final attached = parentIron != null && parentT != null;
      if (!_usesInlineParentDragConstraint(it.type) && attached) {
        _clearInlineParentAttachment(it);
      }
      _bypassDragContexts[it.id] = _BypassDragContext(
        startTopLeft: Offset(it.x, it.y),
        startCenter: _attachmentSpineCenterWorld(it, parentIron: parentIron),
        wasAttached: _usesInlineParentDragConstraint(it.type) && attached,
        parentIronId: parentIron?.id,
        startT: parentT,
        attachedSegmentId: _inlineAttachedSegmentId(it),
        blockedParentIronId: parentIron?.id,
        reconnectAllowed:
            !_usesInlineParentDragConstraint(it.type) || !attached,
      );
    }
  }

  void _applyFreeDraggedItemPosition(
    _LayoutItem item,
    Offset desiredTopLeft,
    Size canvasSize,
  ) {
    if (_usesInlineParentDragConstraint(item.type)) {
      final context = _bypassDragContexts[item.id];
      if (context != null) {
        _applyInlineAttachedDrag(
          item,
          context,
          desiredTopLeft - (context.startTopLeft),
          canvasSize,
        );
        return;
      }
    }
    if (_isStraightIronType(item.type)) {
      final origin = _dragItemStart[item.id] ?? Offset(item.x, item.y);
      _translateStraightIronBy(item, desiredTopLeft - origin);
      return;
    }
    _setBypassTopLeft(item, desiredTopLeft, canvasSize);
  }

  void _updateFreeItemDrag(List<_LayoutItem> moving, Offset delta) {
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
        _applyFreeDraggedItemPosition(it, desired, canvasSize);
        if (_isFittingEndpointConnectableType(it.type)) {
          final fittingCandidate = _nearestFittingEndpointSnapCandidate(
            it,
            radiusScreen: _connectionPreviewRadiusScreen,
          );
          if (fittingCandidate != null) {
            _snapIndicatorScene = fittingCandidate.target.point;
          }
        }
        if (it.id == _selectedId && !it.type.isIron) {
          _dragPreviewItemId = it.id;
          _dragPreviewScenePosition =
              Offset(it.x + it.width / 2, it.y + it.height / 2);
        }
      }
      _updateFittingPreviewForMovingItems(moving);
    });
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
    _cancelSelectedFittingSnapTimer();
    setState(() {
      _dragSceneStart = null;
      _dragItemStart.clear();
      _bypassDragContexts.clear();
      _dragActive = false;
      _activeEndpointDrag = null;
      _activeBypassLeadDrag = null;
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
        _selectedBypassLeadId = null;
        _selectedPortTarget = null;
        _pendingConnectIronSourceTarget = null;
        _autoConnectDestinationItemId = null;
        _autoConnectMode = false;
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
    _cancelSelectedFittingSnapTimer();
    setState(() {
      final opening = !_showSideLibrary;
      _dragSceneStart = null;
      _dragItemStart.clear();
      _bypassDragContexts.clear();
      _dragActive = false;
      _activeEndpointDrag = null;
      _activeBypassLeadDrag = null;
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
        _selectedBypassLeadId = null;
        _selectedPortTarget = null;
        _pendingConnectIronSourceTarget = null;
        _autoConnectDestinationItemId = null;
        _autoConnectMode = false;
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
    if (item.type == _EquipmentType.bypass) return 24.0;
    return 12.0;
  }

  bool get _showAnchorsForConnection {
    return _activeEndpointDrag != null;
  }

  bool get _hasSelectedPort => _selectedPortTarget != null;

  bool get _hasPendingConnectIronSource =>
      _pendingConnectIronSourceTarget != null;

  _LayoutItem? get _selectedStraightIron {
    final selected = _selectedItem;
    if (selected == null || !_isStraightIronType(selected.type)) {
      return null;
    }
    return selected;
  }

  bool _shouldShowAnchorCandidate(_EquipmentAnchorCandidate anchor) {
    final active = _activeEndpointDrag;
    if (active == null) return false;
    final target = active.target;
    final equipment = target?.equipment;
    if (equipment == null) {
      return false;
    }
    return equipment.itemId == anchor.itemId && equipment.side == anchor.side;
  }

  void _toggleMoveControls() {
    if (!_hasSelectedItem) return;
    setState(() => _moveControlsActive = !_moveControlsActive);
  }

  void _clearPortSelection({bool clearPendingSource = true}) {
    setState(() {
      _selectedPortTarget = null;
      _autoConnectMode = false;
      _autoConnectDestinationItemId = null;
      if (clearPendingSource) {
        _pendingConnectIronSourceTarget = null;
      }
    });
  }

  void _selectConnectionPort(_ConnectionTarget target) {
    if (target.kind == _ConnectionTargetKind.equipmentAnchor) {
      final item = target.equipmentItemId == null
          ? null
          : _findItemById(target.equipmentItemId!);
      if (item == null) return;
      if (!_isEquipmentAnchorAvailable(item, target.anchorId ?? '')) return;
    } else {
      final item =
          target.ironItemId == null ? null : _findItemById(target.ironItemId!);
      if (item == null || !_isStraightIronType(item.type)) return;
      if (_endpointAnchorTarget(item, target.ironLeading == true) != null) {
        return;
      }
    }
    setState(() {
      _selectedPortTarget = target;
      _autoConnectMode = false;
      _autoConnectDestinationItemId = null;
      _selectedId = target.kind == _ConnectionTargetKind.equipmentAnchor
          ? target.equipmentItemId
          : target.ironItemId;
      _selectedIds.clear();
      if (_selectedId != null) {
        _selectedIds.add(_selectedId!);
      }
      _selectedEndpointLeading =
          target.kind == _ConnectionTargetKind.ironEndpoint
              ? target.ironLeading
              : null;
      _selectedBypassHandle = null;
      _selectedBypassLeadId = null;
    });
  }

  List<_ConnectionTarget> _availablePortsForItem(_LayoutItem item) {
    final ports = <_ConnectionTarget>[];
    if (_isStraightIronType(item.type)) {
      for (final leading in const <bool>[true, false]) {
        if (_endpointIsConnected(item, leading)) continue;
        ports.add(
          _ConnectionTarget(
            kind: _ConnectionTargetKind.ironEndpoint,
            point: _resolveIronEndpoint(item, leading),
            distance: 0,
            isExactHit: true,
            ironItemId: item.id,
            ironLeading: leading,
          ),
        );
      }
      return ports;
    }

    for (final anchor in _equipmentAnchorCandidates(item)) {
      if (!_isEquipmentAnchorAvailable(item, anchor.side)) continue;
      ports.add(
        _ConnectionTarget(
          kind: _ConnectionTargetKind.equipmentAnchor,
          point: anchor.point,
          distance: 0,
          isExactHit: true,
          equipmentItemId: item.id,
          anchorId: anchor.side,
        ),
      );
    }
    return ports;
  }

  _ConnectionTarget? _defaultPortForItem(_LayoutItem item) {
    final ports = _availablePortsForItem(item);
    if (ports.isEmpty) return null;
    for (final port in ports) {
      if (port.kind == _ConnectionTargetKind.equipmentAnchor &&
          port.anchorId == 'right') {
        return port;
      }
    }
    return ports.first;
  }

  _ConnectionTarget? _selectedPortForSelectedItem() {
    final selected = _selectedItem;
    final target = _selectedPortTarget;
    if (selected == null || target == null) return null;
    if (target.kind == _ConnectionTargetKind.equipmentAnchor &&
        target.equipmentItemId == selected.id) {
      return target;
    }
    if (target.kind == _ConnectionTargetKind.ironEndpoint &&
        target.ironItemId == selected.id) {
      return target;
    }
    return null;
  }

  void _startAutoConnectFromSelectedPort() {
    final source = _selectedPortForSelectedItem();
    if (source == null) return;
    setState(() {
      _pendingConnectIronSourceTarget = source;
      _autoConnectDestinationItemId = null;
      _autoConnectMode = true;
      _drawIronMode = false;
      _drawIronStartTarget = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      _interactionMode = _InteractionMode.idle;
    });
  }

  void _cancelAutoConnect({bool clearSelectedPort = false}) {
    setState(() {
      _autoConnectMode = false;
      _autoConnectDestinationItemId = null;
      _pendingConnectIronSourceTarget = null;
      _drawIronStartTarget = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      if (clearSelectedPort) {
        _selectedPortTarget = null;
      }
    });
  }

  void _showPortUnavailableMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _handleAutoConnectDestinationTap(
    _LayoutItem item,
    _EquipmentAnchorCandidate anchor,
  ) {
    final destination = _ConnectionTarget(
      kind: _ConnectionTargetKind.equipmentAnchor,
      point: anchor.point,
      distance: 0,
      isExactHit: true,
      equipmentItemId: item.id,
      anchorId: anchor.side,
    );

    _handleAutoConnectDestinationTarget(destination);
  }

  void _handleAutoConnectDestinationTarget(_ConnectionTarget destination) {
    if (!_autoConnectMode) return;
    final source = _pendingConnectIronSourceTarget;
    if (source == null) {
      _cancelAutoConnect(clearSelectedPort: false);
      return;
    }

    if (!_connectionTargetExists(source) ||
        !_connectionTargetExists(destination)) {
      _showPortUnavailableMessage(
          'Select a valid destination connection point.');
      return;
    }

    final isSource = _connectionTargetsEqual(source, destination);
    if (isSource) {
      return;
    }

    if (!_connectionTargetAvailable(destination)) {
      _showPortUnavailableMessage('That connection point is unavailable.');
      return;
    }

    if (!_connectionTargetsCompatible(source, destination)) {
      _showPortUnavailableMessage(
          'Those connection points are not compatible.');
      return;
    }

    _createIronBetweenPorts(source, destination);
  }

  bool _isFreeAngleIron(_LayoutItem item) {
    return _isStraightIronType(item.type);
  }

  bool _connectionTargetsEqual(_ConnectionTarget a, _ConnectionTarget b) {
    if (a.kind != b.kind) return false;
    if (a.kind == _ConnectionTargetKind.equipmentAnchor) {
      return a.equipmentItemId == b.equipmentItemId && a.anchorId == b.anchorId;
    }
    return a.ironItemId == b.ironItemId && a.ironLeading == b.ironLeading;
  }

  bool _connectionTargetExists(_ConnectionTarget target) {
    if (target.kind == _ConnectionTargetKind.equipmentAnchor) {
      final item = target.equipmentItemId == null
          ? null
          : _findItemById(target.equipmentItemId!);
      if (item == null || target.anchorId == null || target.anchorId!.isEmpty) {
        return false;
      }
      return _equipmentAnchorPointOrNull(item, target.anchorId!) != null;
    }
    final iron =
        target.ironItemId == null ? null : _findItemById(target.ironItemId!);
    return iron != null && _isStraightIronType(iron.type);
  }

  bool _connectionTargetAvailable(_ConnectionTarget target) {
    if (target.kind == _ConnectionTargetKind.equipmentAnchor) {
      final item = target.equipmentItemId == null
          ? null
          : _findItemById(target.equipmentItemId!);
      if (item == null || target.anchorId == null) return false;
      return _isEquipmentAnchorAvailable(item, target.anchorId!);
    }
    final iron =
        target.ironItemId == null ? null : _findItemById(target.ironItemId!);
    final leading = target.ironLeading;
    if (iron == null || leading == null || !_isStraightIronType(iron.type)) {
      return false;
    }
    return !_endpointIsConnected(iron, leading);
  }

  bool _connectionTargetsCompatible(
    _ConnectionTarget source,
    _ConnectionTarget destination,
  ) {
    return _connectionTargetExists(source) &&
        _connectionTargetExists(destination);
  }

  List<_ConnectionTarget> _compatibleDestinationPortsForItem(
    _LayoutItem item,
    _ConnectionTarget source,
  ) {
    return _availablePortsForItem(item)
        .where((port) =>
            !_connectionTargetsEqual(port, source) &&
            _connectionTargetsCompatible(source, port))
        .toList(growable: false);
  }

  List<_ConnectionTarget> _allPortsForItem(_LayoutItem item) {
    final ports = <_ConnectionTarget>[];
    if (_isStraightIronType(item.type)) {
      for (final leading in const <bool>[true, false]) {
        ports.add(
          _ConnectionTarget(
            kind: _ConnectionTargetKind.ironEndpoint,
            point: _resolveIronEndpoint(item, leading),
            distance: 0,
            isExactHit: true,
            ironItemId: item.id,
            ironLeading: leading,
          ),
        );
      }
      return ports;
    }
    for (final anchor in _equipmentAnchorCandidates(item)) {
      ports.add(
        _ConnectionTarget(
          kind: _ConnectionTargetKind.equipmentAnchor,
          point: anchor.point,
          distance: 0,
          isExactHit: true,
          equipmentItemId: item.id,
          anchorId: anchor.side,
        ),
      );
    }
    return ports;
  }

  _ConnectionTarget? _nearestPortOnItem(
    _LayoutItem item,
    Offset scenePoint,
  ) {
    _ConnectionTarget? best;
    var bestDistance = double.infinity;
    for (final port in _allPortsForItem(item)) {
      final distance =
          _screenDistanceBetweenScenePoints(scenePoint, port.point);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = port;
      }
    }
    return best;
  }

  void _toggleShowConnectionPoints() {
    setState(() => _showConnectionPoints = !_showConnectionPoints);
  }

  double _distanceToRect(Offset point, Rect rect) {
    final dx = point.dx < rect.left
        ? rect.left - point.dx
        : (point.dx > rect.right ? point.dx - rect.right : 0.0);
    final dy = point.dy < rect.top
        ? rect.top - point.dy
        : (point.dy > rect.bottom ? point.dy - rect.bottom : 0.0);
    return math.sqrt((dx * dx) + (dy * dy));
  }

  List<_SelectionCandidate> _resolveSelectionCandidates(Offset scenePoint) {
    final viewportPoint = _viewportPointFromScene(scenePoint);
    final candidates = <_SelectionCandidate>[];
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (!_itemIsVisible(item)) continue;
      if (_isStraightIronType(item.type)) {
        final start = _viewportPointFromScene(_resolveIronEndpoint(item, true));
        final end = _viewportPointFromScene(_resolveIronEndpoint(item, false));
        final distance = _distancePointToSegment(viewportPoint, start, end);
        if (distance <= _ironSelectionCorridorScreen) {
          candidates.add(_SelectionCandidate(
            itemId: item.id,
            distance: distance,
            zIndex: i,
            directHit: distance <= (_ironSelectionCorridorScreen / 2),
          ));
        }
        continue;
      }

      final topLeft = _viewportPointFromScene(Offset(item.x, item.y));
      final bottomRight = _viewportPointFromScene(
          Offset(item.x + item.width, item.y + item.height));
      final rect = Rect.fromLTRB(
        math.min(topLeft.dx, bottomRight.dx),
        math.min(topLeft.dy, bottomRight.dy),
        math.max(topLeft.dx, bottomRight.dx),
        math.max(topLeft.dy, bottomRight.dy),
      );
      final distance = _distanceToRect(viewportPoint, rect);
      if (distance <= _itemSelectionCorridorScreen) {
        candidates.add(_SelectionCandidate(
          itemId: item.id,
          distance: distance,
          zIndex: i,
          directHit: rect.contains(viewportPoint),
        ));
      }
    }

    candidates.sort((a, b) {
      if (a.directHit != b.directHit) {
        return a.directHit ? -1 : 1;
      }
      final byDistance = a.distance.compareTo(b.distance);
      if (byDistance != 0) return byDistance;
      return b.zIndex.compareTo(a.zIndex);
    });
    return candidates;
  }

  bool get _canSelectNextCandidate =>
      _lastSelectionCandidateIds.length > 1 && _selectedId != null;

  void _rebuildSelectionCandidatesAt(Offset scenePoint) {
    final candidates = _resolveSelectionCandidates(scenePoint)
        .map((candidate) => candidate.itemId)
        .toList(growable: false);
    _lastSelectionCandidateIds = candidates;
    _lastSelectionCandidateIndex = 0;
  }

  void _selectNextCandidateFromLastHit() {
    if (_lastSelectionCandidateIds.length <= 1) return;
    final currentId = _selectedId;
    var index = _lastSelectionCandidateIndex;
    if (currentId != null) {
      final found = _lastSelectionCandidateIds.indexOf(currentId);
      if (found >= 0) {
        index = found;
      }
    }
    index = (index + 1) % _lastSelectionCandidateIds.length;
    final nextId = _lastSelectionCandidateIds[index];
    _lastSelectionCandidateIndex = index;
    _selectOnly(nextId);
  }

  Future<void> _showSelectionPickerForScenePoint(Offset scenePoint) async {
    final candidates = _resolveSelectionCandidates(scenePoint);
    if (candidates.isEmpty) return;
    _lastSelectionCandidateIds =
        candidates.map((candidate) => candidate.itemId).toList(growable: false);
    _lastSelectionCandidateIndex = 0;
    if (candidates.length == 1) {
      _selectOnly(candidates.first.itemId);
      return;
    }

    final items = <_LayoutItem>[];
    for (final candidate in candidates) {
      final item = _findItemById(candidate.itemId);
      if (item != null) items.add(item);
    }
    if (items.length <= 1) {
      if (items.isNotEmpty) {
        _selectOnly(items.first.id);
      }
      return;
    }

    final labelCounts = <String, int>{};
    for (final item in items) {
      final label = item.type.isIron
          ? '${item.displayLabel} ${item.ironSize}"'
          : item.displayLabel;
      labelCounts[label] = (labelCounts[label] ?? 0) + 1;
    }
    final nextLabelIndex = <String, int>{};

    final selectedId = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF0F1114),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Item',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final item in items)
                  () {
                    final base = item.type.isIron
                        ? '${item.displayLabel} ${item.ironSize}"'
                        : item.displayLabel;
                    final duplicate = (labelCounts[base] ?? 0) > 1;
                    final idx = (nextLabelIndex[base] ?? 0) + 1;
                    nextLabelIndex[base] = idx;
                    final label = duplicate ? '$base $idx' : base;
                    return ListTile(
                      dense: true,
                      minTileHeight: 46,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(
                        label,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      onTap: () => Navigator.pop(context, item.id),
                    );
                  }(),
              ],
            ),
          ),
        );
      },
    );
    if (selectedId != null) {
      _selectOnly(selectedId);
      final selectedIndex = _lastSelectionCandidateIds.indexOf(selectedId);
      if (selectedIndex >= 0) {
        _lastSelectionCandidateIndex = selectedIndex;
      }
    }
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
    _cancelSelectedFittingSnapTimer();
    if (!mounted) {
      _dragSceneStart = null;
      _dragItemStart.clear();
      _dragActive = false;
      _activeEndpointDrag = null;
      _activeBypassLeadDrag = null;
      _fittingDragBlockedTargetKeys.clear();
      _snapCandidateIronId = null;
      _snapIndicatorScene = null;
      _activeFittingPreview = null;
      _clearDragPreview();
      _libraryDragScenePoint = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      _selectedEndpointLeading = null;
      _selectedBypassHandle = null;
      _selectedBypassLeadId = null;
      _interactionMode =
          _drawIronMode ? _InteractionMode.placeIron : _InteractionMode.idle;
      return;
    }
    setState(() {
      _dragSceneStart = null;
      _dragItemStart.clear();
      _dragActive = false;
      _activeEndpointDrag = null;
      _activeBypassLeadDrag = null;
      _fittingDragBlockedTargetKeys.clear();
      _snapCandidateIronId = null;
      _snapIndicatorScene = null;
      _activeFittingPreview = null;
      _clearDragPreview();
      _libraryDragScenePoint = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      _selectedEndpointLeading = null;
      _selectedBypassHandle = null;
      _selectedBypassLeadId = null;
      _interactionMode =
          _drawIronMode ? _InteractionMode.placeIron : _InteractionMode.idle;
    });
  }

  void _toggleSnapToGrid() {
    _stopArrowRepeat();
    _cancelSelectedFittingSnapTimer();
    setState(() {
      _snapToGrid = !_snapToGrid;
      _activeEndpointDrag = null;
      _activeBypassLeadDrag = null;
      _snapCandidateIronId = null;
      _snapIndicatorScene = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      _selectedEndpointLeading = null;
      _selectedBypassHandle = null;
      _selectedBypassLeadId = null;
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

  void _moveSelectedBy(
    Offset delta, {
    bool recordHistory = true,
    bool scheduleFittingSnap = false,
  }) {
    final moving = _selectedItems;
    if (moving.isEmpty) return;
    if (moving.every(_segmentMoveBlocked)) return;

    void applyMove() {
      final canvasSize = _virtualCanvasSize;
      for (final item in moving) {
        if (_segmentMoveBlocked(item)) continue;
        final origin = Offset(item.x, item.y);
        if (_isFittingEndpointConnectableType(item.type)) {
          _fittingDragBlockedTargetKeys[item.id] =
              _currentFittingConnectionKeys(item);
          final isInlineAttached = _usesInlineParentDragConstraint(item.type) &&
              _inlineParentIron(item) != null &&
              _inlineParentT(item) != null;
          if (!isInlineAttached) {
            _detachConnectionsForFreeFittingDrag(item);
          }
        }
        if (_isInlineFittingType(item.type)) {
          final parentIron = _inlineParentIron(item);
          final parentT = _inlineParentT(item);
          if (parentIron != null && parentT != null) {
            final parentStart = _resolveIronEndpoint(parentIron, true);
            final parentEnd = _resolveIronEndpoint(parentIron, false);
            final parentVector = parentEnd - parentStart;
            final parentLength = parentVector.distance;
            if (parentLength < 1e-6) {
              continue;
            }
            final parentDir = Offset(
              parentVector.dx / parentLength,
              parentVector.dy / parentLength,
            );
            final alongDelta =
                (delta.dx * parentDir.dx) + (delta.dy * parentDir.dy);
            if (alongDelta.abs() < 0.0001) {
              continue;
            }
            final center = _pointOnIronCenterline(parentIron, parentT);
            final projected = center +
                Offset(parentDir.dx * alongDelta, parentDir.dy * alongDelta);
            final t = _normalizedPositionAlongIron(parentIron, projected);
            _setInlineParentAttachment(item, parentIron, t);
            _alignInlineToParent(item, parentIron, t);
            _setBypassTopLeft(item, Offset(item.x, item.y), canvasSize);
            continue;
          }
        }
        final desired = Offset(origin.dx + delta.dx, origin.dy + delta.dy);
        if (_isStraightIronType(item.type)) {
          _translateStraightIronBy(item, delta);
        } else {
          item.x = desired.dx.clamp(0.0, canvasSize.width - item.width);
          item.y = desired.dy.clamp(0.0, canvasSize.height - item.height);
        }
      }
      _reflowSnappedFittings();
    }

    if (recordHistory) {
      _runHistoryChange(applyMove);
    } else {
      setState(applyMove);
    }

    if (scheduleFittingSnap) {
      _scheduleSelectedFittingSnap(moving);
    }
  }

  Offset _nudgeDelta(Offset directionUnit) {
    final step = _snapToGrid ? 2.0 : 1.0;
    return Offset(directionUnit.dx * step, directionUnit.dy * step);
  }

  void _nudgeSelectionBy(Offset directionUnit) {
    final selectedIron = _selectedStraightIron;
    final selectedEndpoint = _selectedEndpointLeading;
    if (selectedIron != null &&
        selectedEndpoint != null &&
        !selectedIron.locked) {
      _nudgeSelectedEndpoint(directionUnit, recordHistory: true);
      return;
    }
    _moveSelectedBy(_nudgeDelta(directionUnit), scheduleFittingSnap: true);
  }

  void _nudgeSelectedEndpoint(
    Offset directionUnit, {
    required bool recordHistory,
  }) {
    final item = _selectedStraightIron;
    final leading = _selectedEndpointLeading;
    if (item == null || leading == null || item.locked) return;
    final delta = _nudgeDelta(directionUnit);
    final endpointDelta = delta;
    if (endpointDelta == Offset.zero) return;
    if (recordHistory) {
      _recordUndo();
    }
    _updateEndpointHandleDrag(item, leading, endpointDelta);
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
      if (_selectedStraightIron != null && _selectedEndpointLeading != null) {
        _nudgeSelectedEndpoint(directionUnit, recordHistory: false);
      } else {
        _moveSelectedBy(
          _nudgeDelta(directionUnit),
          recordHistory: false,
          scheduleFittingSnap: true,
        );
      }
      _arrowRepeatTimer =
          Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted ||
            _selectedItems.isEmpty ||
            _selectedItems.every(_segmentMoveBlocked)) {
          _stopArrowRepeat();
          return;
        }
        if (_selectedStraightIron != null && _selectedEndpointLeading != null) {
          _nudgeSelectedEndpoint(directionUnit, recordHistory: false);
        } else {
          _moveSelectedBy(
            _nudgeDelta(directionUnit),
            recordHistory: false,
            scheduleFittingSnap: true,
          );
        }
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

  bool _isInlineFittingType(_EquipmentType type) {
    return type == _EquipmentType.bypass || type.name.startsWith('tee');
  }

  bool _usesInlineParentDragConstraint(_EquipmentType type) {
    return type == _EquipmentType.bypass || type.name.startsWith('tee');
  }

  bool _isElbowFittingType(_EquipmentType type) {
    return type.name.startsWith('elbow');
  }

  bool _isFittingEndpointConnectableType(_EquipmentType type) {
    return type.name.startsWith('tee') || type.name.startsWith('elbow');
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
      'snapT',
      'snapAxis',
      'bypassParentIronId',
      'bypassParentT',
      'bypassParentOrientation',
      'bypassPrimaryIronId',
      'bypassPrimaryT',
      'bypassPrimaryOrientation',
      'bypassSecondaryIronId',
      'bypassSecondaryT',
      'bypassSecondaryOrientation',
      'inlineParentIronId',
      'inlineParentT',
      'inlineParentOrientation',
      'inlineAttachedSegmentId',
      'inlineAttached',
    ]) {
      copy.remove(key);
    }
    copy.removeWhere((key, _) => key.startsWith('fittingAnchor_'));
    copy.removeWhere(
        (key, _) => key.startsWith('bypassLead') && key.contains('Target'));
    return copy;
  }

  bool _isBypassPortId(String side) {
    return _canonicalBypassPort(side) != null;
  }

  String? _canonicalBypassPort(String side) {
    switch (side) {
      case 'bypassPrimary':
      case 'leftEnd':
      case _bypassPortMainTop:
        return _bypassPortMainTop;
      case 'bypassSecondary':
      case 'rightEnd':
      case _bypassPortMainBottom:
        return _bypassPortMainBottom;
      case 'upperValve':
      case _bypassPortUpperValveOutlet:
        return _bypassPortUpperValveOutlet;
      case 'lowerValve':
      case _bypassPortLowerValveOutlet:
        return _bypassPortLowerValveOutlet;
      default:
        return null;
    }
  }

  String? _normalizedBypassPortId(String? side) {
    if (side == null || side.isEmpty) return null;
    return _canonicalBypassPort(side);
  }

  String _normalizedAnchorSide(_LayoutItem item, String side) {
    if (item.type == _EquipmentType.chokeManifold) {
      switch (side) {
        case 'inlet':
        case 'top':
        case 'left':
        case 'inletTopCenter':
          return 'inletTopCenter';
        case 'outlet':
        case 'bottom':
        case 'right':
        case 'outletBottomCenter':
          return 'outletBottomCenter';
        default:
          return side;
      }
    }
    if (item.type == _EquipmentType.facilities) {
      switch (side) {
        case 'inlet':
        case 'left':
          return 'leftCenter';
        case 'outlet':
        case 'right':
          return 'rightCenter';
        case 'top':
          return 'topCenter';
        case 'bottom':
          return 'bottomCenter';
        default:
          return side;
      }
    }
    if (item.type != _EquipmentType.bypass) {
      if (_usesFourSideEquipmentPorts(item.type)) {
        switch (side) {
          case 'inlet':
            return 'left';
          case 'outlet':
            return 'right';
          case 'upperBypass':
            return 'top';
          case 'lowerBypass':
            return 'bottom';
          default:
            return side;
        }
      }
      return side;
    }
    final canonical = _normalizedBypassPortId(side);
    if (canonical != null) return canonical;
    return _bypassPortMainTop;
  }

  bool _usesFourSideEquipmentPorts(_EquipmentType type) {
    if (_isStraightIronType(type) ||
        type == _EquipmentType.bypass ||
        type.name.startsWith('tee') ||
        type.name.startsWith('elbow')) {
      return false;
    }
    return true;
  }

  bool _isSingleInletEquipmentType(_EquipmentType type) {
    return type == _EquipmentType.flowbackTank ||
        type == _EquipmentType.productionTank ||
        type == _EquipmentType.facilities;
  }

  String _singleInletAnchorSide(_EquipmentType type) {
    if (_isSingleInletEquipmentType(type)) {
      return 'left';
    }
    return 'left';
  }

  bool _isEquipmentAnchorOccupied(
    int itemId,
    String side, {
    int? ignoreIronId,
    bool? ignoreLeading,
  }) {
    for (final item in _items) {
      if (!_isStraightIronType(item.type)) continue;
      for (final leading in const <bool>[true, false]) {
        if (ignoreIronId != null &&
            ignoreLeading != null &&
            item.id == ignoreIronId &&
            leading == ignoreLeading) {
          continue;
        }
        final anchorItemId = int.tryParse(
            item.properties[_endpointAnchorItemKey(leading)] ?? '');
        final anchorSide = item.properties[_endpointAnchorSideKey(leading)];
        if (anchorItemId == itemId && anchorSide == side) {
          return true;
        }
      }
    }
    for (final item in _items) {
      if (item.type != _EquipmentType.bypass) continue;
      for (final leadId in _bypassLeadIds) {
        final target = _bypassLeadStoredTarget(item, leadId);
        if (target == null ||
            target.kind != _ConnectionTargetKind.equipmentAnchor) {
          continue;
        }
        if (target.equipmentItemId == itemId && target.anchorId == side) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isEquipmentInletOccupied(
    int itemId, {
    int? ignoreIronId,
    bool? ignoreLeading,
  }) {
    for (final item in _items) {
      if (!_isStraightIronType(item.type)) continue;
      for (final leading in const <bool>[true, false]) {
        if (ignoreIronId != null &&
            ignoreLeading != null &&
            item.id == ignoreIronId &&
            leading == ignoreLeading) {
          continue;
        }
        final anchorItemId = int.tryParse(
            item.properties[_endpointAnchorItemKey(leading)] ?? '');
        final anchorSide = item.properties[_endpointAnchorSideKey(leading)];
        if (anchorItemId == itemId &&
            anchorSide != null &&
            anchorSide.isNotEmpty) {
          return true;
        }
      }
    }
    for (final item in _items) {
      if (item.type != _EquipmentType.bypass) continue;
      for (final leadId in _bypassLeadIds) {
        final target = _bypassLeadStoredTarget(item, leadId);
        if (target == null ||
            target.kind != _ConnectionTargetKind.equipmentAnchor) {
          continue;
        }
        if (target.equipmentItemId == itemId) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isEquipmentAnchorAvailable(
    _LayoutItem item,
    String side, {
    int? movingIronId,
    bool? movingIronLeading,
  }) {
    if (_isSingleInletEquipmentType(item.type)) {
      if (item.type != _EquipmentType.facilities) {
        final canonicalSide = _normalizedAnchorSide(item, side);
        if (canonicalSide != _singleInletAnchorSide(item.type)) {
          return false;
        }
      }
      return !_isEquipmentInletOccupied(
        item.id,
        ignoreIronId: movingIronId,
        ignoreLeading: movingIronLeading,
      );
    }
    return !_isEquipmentAnchorOccupied(
      item.id,
      side,
      ignoreIronId: movingIronId,
      ignoreLeading: movingIronLeading,
    );
  }

  _ConnectionTarget? _endpointAnchorTarget(_LayoutItem item, bool leading) {
    final anchorItemId =
        int.tryParse(item.properties[_endpointAnchorItemKey(leading)] ?? '');
    final anchorSide = item.properties[_endpointAnchorSideKey(leading)];
    if (anchorItemId == null || anchorSide == null || anchorSide.isEmpty) {
      return null;
    }
    final point = _resolveIronEndpoint(item, leading);
    return _ConnectionTarget(
      kind: _ConnectionTargetKind.ironEndpoint,
      point: point,
      distance: 0,
      isExactHit: true,
      ironItemId: item.id,
      ironLeading: leading,
    );
  }

  double _screenDistanceBetweenScenePoints(Offset a, Offset b) {
    final av = _viewportPointFromScene(a);
    final bv = _viewportPointFromScene(b);
    return (av - bv).distance;
  }

  String _endpointJointKey(bool leading) => leading ? 'jointStart' : 'jointEnd';

  String _endpointAnchorItemKey(bool leading) =>
      leading ? 'anchorStartItemId' : 'anchorEndItemId';

  String _endpointAnchorSideKey(bool leading) =>
      leading ? 'anchorStartSide' : 'anchorEndSide';

  String _bypassIronKey(String slot) => 'bypass${slot}IronId';

  String _bypassTKey(String slot) => 'bypass${slot}T';

  String _bypassOrientationKey(String slot) => 'bypass${slot}Orientation';

  String get _bypassParentIronKey => 'bypassParentIronId';

  String get _bypassParentTKey => 'bypassParentT';

  String get _bypassParentOrientationKey => 'bypassParentOrientation';

  String get _inlineParentIronKey => 'inlineParentIronId';

  String get _inlineParentTKey => 'inlineParentT';

  String get _inlineParentOrientationKey => 'inlineParentOrientation';

  String get _inlineAttachedSegmentKey => 'inlineAttachedSegmentId';

  String _bypassLeadOriginKey(String leadId) =>
      'bypassLead${leadId}OriginPortId';

  String _bypassLeadEndXKey(String leadId) => 'bypassLead${leadId}EndX';

  String _bypassLeadEndYKey(String leadId) => 'bypassLead${leadId}EndY';

  String _bypassLeadTargetItemKey(String leadId) =>
      'bypassLead${leadId}TargetItemId';

  String _bypassLeadTargetKindKey(String leadId) =>
      'bypassLead${leadId}TargetKind';

  String _bypassLeadTargetSideKey(String leadId) =>
      'bypassLead${leadId}TargetSide';

  Iterable<String> get _bypassLeadIds =>
      const <String>[_bypassLeadA, _bypassLeadB];

  String? _inlineAttachedSegmentId(_LayoutItem item) {
    final id = item.properties[_inlineAttachedSegmentKey];
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Offset _storedIronEndpoint(_LayoutItem item, bool leading) {
    final x = double.tryParse(
      item.properties[leading ? _freeAngleStartXKey : _freeAngleEndXKey] ?? '',
    );
    final y = double.tryParse(
      item.properties[leading ? _freeAngleStartYKey : _freeAngleEndYKey] ?? '',
    );
    if (x != null && y != null) {
      return Offset(x, y);
    }
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

  Offset _ironEndpoint(_LayoutItem item, bool leading) {
    return _storedIronEndpoint(item, leading);
  }

  void _storeIronEndpoints(_LayoutItem item, Offset start, Offset end) {
    final minX = math.min(start.dx, end.dx);
    final minY = math.min(start.dy, end.dy);
    final maxX = math.max(start.dx, end.dx);
    final maxY = math.max(start.dy, end.dy);
    item.properties[_freeAngleIronKey] = 'true';
    item.properties[_freeAngleStartXKey] = start.dx.toStringAsFixed(4);
    item.properties[_freeAngleStartYKey] = start.dy.toStringAsFixed(4);
    item.properties[_freeAngleEndXKey] = end.dx.toStringAsFixed(4);
    item.properties[_freeAngleEndYKey] = end.dy.toStringAsFixed(4);
    item.x = minX;
    item.y = minY;
    item.width = math.max(1.0, maxX - minX);
    item.height = math.max(1.0, maxY - minY);
  }

  void _translateStraightIronBy(_LayoutItem item, Offset delta) {
    if (!_isStraightIronType(item.type) || delta == Offset.zero) return;
    final start = _storedIronEndpoint(item, true) + delta;
    final end = _storedIronEndpoint(item, false) + delta;
    _storeIronEndpoints(item, _clampToCanvas(start), _clampToCanvas(end));
  }

  Offset _resolveIronEndpoint(_LayoutItem item, bool leading) {
    final anchorItemId =
        int.tryParse(item.properties[_endpointAnchorItemKey(leading)] ?? '');
    final anchorSide = item.properties[_endpointAnchorSideKey(leading)];
    if (anchorItemId != null && anchorSide != null && anchorSide.isNotEmpty) {
      final anchorItem = _findItemById(anchorItemId);
      if (anchorItem != null) {
        if (anchorItem.type == _EquipmentType.bypass) {
          final bypassPort = _normalizedBypassPortId(anchorSide);
          if (bypassPort == null) {
            if (kDebugMode) {
              debugPrint(
                'Unsupported bypass port "$anchorSide" on bypass '
                '${anchorItem.id}; treating iron endpoint as disconnected.',
              );
            }
            return _storedIronEndpoint(item, leading);
          }
          return _equipmentAnchorPoint(anchorItem, bypassPort);
        }
        final normalizedSide = _normalizedAnchorSide(anchorItem, anchorSide);
        final resolved =
            _equipmentAnchorPointOrNull(anchorItem, normalizedSide);
        if (resolved != null) {
          return resolved;
        }
        if (kDebugMode) {
          debugPrint(
            'Unsupported anchor side "$anchorSide" on ${anchorItem.type.name} '
            '(${anchorItem.id}); treating iron endpoint as disconnected.',
          );
        }
        return _storedIronEndpoint(item, leading);
      }
    }

    final jointId = _jointId(item, leading);
    if (jointId != null && jointId.isNotEmpty) {
      for (final other in _items) {
        if (other.id == item.id || !_isStraightIronType(other.type)) continue;
        if (_jointId(other, true) == jointId) {
          return _storedIronEndpoint(other, true);
        }
        if (_jointId(other, false) == jointId) {
          return _storedIronEndpoint(other, false);
        }
      }
    }

    return _storedIronEndpoint(item, leading);
  }

  Offset _equipmentAnchorPoint(_LayoutItem item, String side) {
    final resolved = _equipmentAnchorPointOrNull(item, side);
    if (resolved != null) {
      return resolved;
    }
    throw StateError(
      'Unsupported anchor side "$side" for ${item.type.name} (${item.id}).',
    );
  }

  Offset? _equipmentAnchorPointOrNull(_LayoutItem item, String side) {
    final normalizedSide = _normalizedAnchorSide(item, side);
    if (_isStraightIronType(item.type)) {
      switch (normalizedSide) {
        case 'start':
          return _resolveIronEndpoint(item, true);
        case 'end':
          return _resolveIronEndpoint(item, false);
      }
    }
    for (final anchor in _equipmentAnchorCandidates(item)) {
      if (anchor.side == normalizedSide) {
        return anchor.point;
      }
    }
    return null;
  }

  List<_AnchorDefinition> _anchorDefinitionsForType(_EquipmentType type) {
    switch (type) {
      case _EquipmentType.bypass:
        return const <_AnchorDefinition>[
          _AnchorDefinition('mainTop', 0.28, 0.14),
          _AnchorDefinition('mainBottom', 0.28, 0.86),
          _AnchorDefinition('upperValveOutlet', 0.82, 0.34),
          _AnchorDefinition('lowerValveOutlet', 0.82, 0.66),
        ];
      case _EquipmentType.wellhead:
        return const <_AnchorDefinition>[
          _AnchorDefinition('top', 0.5, 0.08),
          _AnchorDefinition('right', 0.92, 0.5),
          _AnchorDefinition('bottom', 0.5, 0.92),
          _AnchorDefinition('left', 0.08, 0.5),
        ];
      case _EquipmentType.chokeManifold:
        return const <_AnchorDefinition>[
          _AnchorDefinition('inletTopCenter', 0.50, 0.08),
          _AnchorDefinition('outletBottomCenter', 0.50, 0.92),
        ];
      case _EquipmentType.plugCatcher:
      case _EquipmentType.testSeparator:
        return const <_AnchorDefinition>[
          _AnchorDefinition('left', 0.08, 0.5),
          _AnchorDefinition('right', 0.92, 0.5),
        ];
      case _EquipmentType.flowbackTank:
      case _EquipmentType.productionTank:
        return const <_AnchorDefinition>[
          _AnchorDefinition('top', 0.5, 0.08),
          _AnchorDefinition('right', 0.92, 0.5),
          _AnchorDefinition('bottom', 0.5, 0.92),
          _AnchorDefinition('left', 0.08, 0.5),
        ];
      case _EquipmentType.facilities:
        return const <_AnchorDefinition>[
          _AnchorDefinition('topLeft', 0.24, 0.16),
          _AnchorDefinition('topCenter', 0.50, 0.16),
          _AnchorDefinition('topRight', 0.76, 0.16),
          _AnchorDefinition('rightTop', 0.84, 0.30),
          _AnchorDefinition('rightCenter', 0.84, 0.50),
          _AnchorDefinition('rightBottom', 0.84, 0.70),
          _AnchorDefinition('bottomRight', 0.76, 0.84),
          _AnchorDefinition('bottomCenter', 0.50, 0.84),
          _AnchorDefinition('bottomLeft', 0.24, 0.84),
          _AnchorDefinition('leftBottom', 0.16, 0.70),
          _AnchorDefinition('leftCenter', 0.16, 0.50),
          _AnchorDefinition('leftTop', 0.16, 0.30),
        ];
      case _EquipmentType.esdValve:
      case _EquipmentType.lineHeater:
      case _EquipmentType.cyclonicSandSep:
      case _EquipmentType.sphericalSandSep:
      case _EquipmentType.flare:
      case _EquipmentType.compressor:
        return const <_AnchorDefinition>[
          _AnchorDefinition('top', 0.5, 0.08),
          _AnchorDefinition('right', 0.92, 0.5),
          _AnchorDefinition('bottom', 0.5, 0.92),
          _AnchorDefinition('left', 0.08, 0.5),
        ];
      case _EquipmentType.teeUp:
        return const <_AnchorDefinition>[
          _AnchorDefinition('runStart', 0.08, 0.5),
          _AnchorDefinition('runEnd', 0.92, 0.5),
          _AnchorDefinition('branch', 0.5, 0.08),
        ];
      case _EquipmentType.teeRight:
        return const <_AnchorDefinition>[
          _AnchorDefinition('runStart', 0.5, 0.08),
          _AnchorDefinition('runEnd', 0.5, 0.92),
          _AnchorDefinition('branch', 0.92, 0.5),
        ];
      case _EquipmentType.teeDown:
        return const <_AnchorDefinition>[
          _AnchorDefinition('runStart', 0.08, 0.5),
          _AnchorDefinition('runEnd', 0.92, 0.5),
          _AnchorDefinition('branch', 0.5, 0.92),
        ];
      case _EquipmentType.teeLeft:
        return const <_AnchorDefinition>[
          _AnchorDefinition('runStart', 0.5, 0.08),
          _AnchorDefinition('runEnd', 0.5, 0.92),
          _AnchorDefinition('branch', 0.08, 0.5),
        ];
      case _EquipmentType.coilTubingUnit:
      case _EquipmentType.mixingPlant:
      case _EquipmentType.pump:
      case _EquipmentType.crane:
      case _EquipmentType.lightPlant:
      case _EquipmentType.wireline:
      case _EquipmentType.dateVan:
      case _EquipmentType.fuelTrailer:
      case _EquipmentType.chemicalTrailer:
      case _EquipmentType.nitrogen:
      case _EquipmentType.generator:
        return const <_AnchorDefinition>[];
      case _EquipmentType.elbowUpRight:
        return const <_AnchorDefinition>[
          _AnchorDefinition('inlet', 0.5, 0.92),
          _AnchorDefinition('outlet', 0.92, 0.5),
        ];
      case _EquipmentType.elbowRightDown:
        return const <_AnchorDefinition>[
          _AnchorDefinition('inlet', 0.08, 0.5),
          _AnchorDefinition('outlet', 0.5, 0.92),
        ];
      case _EquipmentType.elbowDownLeft:
        return const <_AnchorDefinition>[
          _AnchorDefinition('inlet', 0.5, 0.08),
          _AnchorDefinition('outlet', 0.08, 0.5),
        ];
      case _EquipmentType.elbowLeftUp:
        return const <_AnchorDefinition>[
          _AnchorDefinition('inlet', 0.92, 0.5),
          _AnchorDefinition('outlet', 0.5, 0.08),
        ];
      default:
        return const <_AnchorDefinition>[
          _AnchorDefinition('top', 0.5, 0.08),
          _AnchorDefinition('right', 0.92, 0.5),
          _AnchorDefinition('bottom', 0.5, 0.92),
          _AnchorDefinition('left', 0.08, 0.5),
        ];
    }
  }

  Offset _rotatedLocalAnchorPoint(_LayoutItem item, _AnchorDefinition anchor) {
    var local = Offset(item.width * anchor.u, item.height * anchor.v);

    // Tee/90 symbols are rendered inside an inset shell; map anchors into that
    // same inset so visual endpoints and connection math coincide.
    if (_isFittingEndpointConnectableType(item.type)) {
      final shortest = math.min(item.width, item.height);
      final inset = shortest < 66 ? 2.0 : 3.0;
      final usableWidth = math.max(0.0, item.width - inset * 2);
      final usableHeight = math.max(0.0, item.height - inset * 2);
      local = Offset(
        inset + anchor.u * usableWidth,
        inset + anchor.v * usableHeight,
      );
    }

    return _rotateLocalPoint(item, local);
  }

  Offset _rotateLocalPoint(_LayoutItem item, Offset local) {
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

  Offset _inverseRotateLocalPoint(_LayoutItem item, Offset rotatedLocal) {
    final center = Offset(item.width / 2, item.height / 2);
    final turns = ((item.rotationTurns % 4) + 4) % 4;
    final delta = rotatedLocal - center;
    Offset unrotated;
    switch (turns) {
      case 1:
        unrotated = Offset(delta.dy, -delta.dx);
        break;
      case 2:
        unrotated = Offset(-delta.dx, -delta.dy);
        break;
      case 3:
        unrotated = Offset(-delta.dy, delta.dx);
        break;
      default:
        unrotated = delta;
    }
    return center + unrotated;
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

  String _bypassLeadOriginPortId(_LayoutItem item, String leadId) {
    final stored = item.properties[_bypassLeadOriginKey(leadId)];
    if (stored != null && stored.isNotEmpty) return stored;
    return leadId == _bypassLeadA
        ? _bypassPortUpperValveOutlet
        : _bypassPortLowerValveOutlet;
  }

  Offset _defaultBypassLeadEndpointLocal(_LayoutItem item, String leadId) {
    final origin =
        _attachmentSpineLocalPoint(item, _bypassLeadOriginPortId(item, leadId));
    return origin + const Offset(_bypassLeadDefaultLength, 0);
  }

  void _ensureBypassLeadData(_LayoutItem item) {
    if (item.type != _EquipmentType.bypass) return;
    for (final leadId in _bypassLeadIds) {
      item.properties[_bypassLeadOriginKey(leadId)] =
          _bypassLeadOriginPortId(item, leadId);
      final endX = item.properties[_bypassLeadEndXKey(leadId)];
      final endY = item.properties[_bypassLeadEndYKey(leadId)];
      if (endX == null || endY == null) {
        final local = _defaultBypassLeadEndpointLocal(item, leadId);
        item.properties[_bypassLeadEndXKey(leadId)] =
            local.dx.toStringAsFixed(4);
        item.properties[_bypassLeadEndYKey(leadId)] =
            local.dy.toStringAsFixed(4);
      }
    }
  }

  Offset _bypassLeadEndpointLocal(_LayoutItem item, String leadId) {
    _ensureBypassLeadData(item);
    final defaultLocal = _defaultBypassLeadEndpointLocal(item, leadId);
    final x =
        double.tryParse(item.properties[_bypassLeadEndXKey(leadId)] ?? '');
    final y =
        double.tryParse(item.properties[_bypassLeadEndYKey(leadId)] ?? '');
    return Offset(x ?? defaultLocal.dx, y ?? defaultLocal.dy);
  }

  void _setBypassLeadEndpointLocal(
      _LayoutItem item, String leadId, Offset local) {
    item.properties[_bypassLeadEndXKey(leadId)] = local.dx.toStringAsFixed(4);
    item.properties[_bypassLeadEndYKey(leadId)] = local.dy.toStringAsFixed(4);
  }

  Offset _bypassLeadOriginWorld(_LayoutItem item, String leadId) {
    return _equipmentAnchorPoint(item, _bypassLeadOriginPortId(item, leadId));
  }

  void _setBypassLeadEndpointWorld(
      _LayoutItem item, String leadId, Offset world) {
    final localRotated = world - Offset(item.x, item.y);
    final local = _inverseRotateLocalPoint(item, localRotated);
    _setBypassLeadEndpointLocal(item, leadId, local);
  }

  String? _bypassLeadTargetKey(_ConnectionTarget? target) {
    if (target == null) return null;
    if (target.kind == _ConnectionTargetKind.ironEndpoint) {
      return 'joint:${target.ironItemId}:${target.ironLeading == true ? 'start' : 'end'}';
    }
    return 'anchor:${target.equipmentItemId}:${target.anchorId}';
  }

  void _setBypassLeadTarget(
    _LayoutItem item,
    String leadId, {
    String? kind,
    int? targetItemId,
    String? side,
  }) {
    if (kind == null || targetItemId == null || side == null || side.isEmpty) {
      item.properties.remove(_bypassLeadTargetKindKey(leadId));
      item.properties.remove(_bypassLeadTargetItemKey(leadId));
      item.properties.remove(_bypassLeadTargetSideKey(leadId));
      return;
    }
    item.properties[_bypassLeadTargetKindKey(leadId)] = kind;
    item.properties[_bypassLeadTargetItemKey(leadId)] = targetItemId.toString();
    item.properties[_bypassLeadTargetSideKey(leadId)] = side;
  }

  _ConnectionTarget? _bypassLeadStoredTarget(_LayoutItem item, String leadId) {
    final kind = item.properties[_bypassLeadTargetKindKey(leadId)];
    final targetItemId =
        int.tryParse(item.properties[_bypassLeadTargetItemKey(leadId)] ?? '');
    final side = item.properties[_bypassLeadTargetSideKey(leadId)];
    if (kind == null || targetItemId == null || side == null || side.isEmpty) {
      return null;
    }
    if (kind == 'ironEndpoint') {
      final iron = _findItemById(targetItemId);
      final leading = side == 'start';
      if (iron == null || !_isStraightIronType(iron.type)) return null;
      final point = _resolveIronEndpoint(iron, leading);
      return _ConnectionTarget(
        kind: _ConnectionTargetKind.ironEndpoint,
        point: point,
        distance: 0,
        isExactHit: true,
        ironItemId: targetItemId,
        ironLeading: leading,
      );
    }
    final anchorItem = _findItemById(targetItemId);
    if (anchorItem == null) return null;
    final point = _equipmentAnchorPointOrNull(anchorItem, side);
    if (point == null) return null;
    return _ConnectionTarget(
      kind: _ConnectionTargetKind.equipmentAnchor,
      point: point,
      distance: 0,
      isExactHit: true,
      equipmentItemId: targetItemId,
      anchorId: side,
    );
  }

  Offset _resolveBypassLeadEndpointWorld(_LayoutItem item, String leadId) {
    final target = _bypassLeadStoredTarget(item, leadId);
    if (target != null) return target.point;
    final local = _bypassLeadEndpointLocal(item, leadId);
    final rotated = _rotateLocalPoint(item, local);
    return Offset(item.x + rotated.dx, item.y + rotated.dy);
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
    final anchorItem = _findItemById(anchorItemId);
    final normalizedSide = anchorItem == null
        ? side
        : anchorItem.type == _EquipmentType.bypass
            ? _normalizedBypassPortId(side)
            : _normalizedAnchorSide(anchorItem, side);
    if (anchorItem != null &&
        anchorItem.type == _EquipmentType.bypass &&
        normalizedSide == null) {
      if (kDebugMode) {
        debugPrint(
          'Unsupported bypass port "$side" for bypass ${anchorItem.id}; '
          'clearing attachment.',
        );
      }
      item.properties.remove(itemKey);
      item.properties.remove(sideKey);
      return;
    }
    if (anchorItem != null &&
        normalizedSide != null &&
        _equipmentAnchorPointOrNull(anchorItem, normalizedSide) == null) {
      if (kDebugMode) {
        debugPrint(
          'Unsupported anchor side "$side" for ${anchorItem.type.name} '
          '${anchorItem.id}; clearing attachment.',
        );
      }
      item.properties.remove(itemKey);
      item.properties.remove(sideKey);
      return;
    }
    item.properties[itemKey] = anchorItemId.toString();
    item.properties[sideKey] = normalizedSide ?? side;
  }

  void _clearEndpointAttachment(_LayoutItem item, bool leading) {
    if (_isFreeAngleIron(item)) {
      final resolved = _resolveIronEndpoint(item, leading);
      item.properties[leading ? _freeAngleStartXKey : _freeAngleEndXKey] =
          resolved.dx.toStringAsFixed(4);
      item.properties[leading ? _freeAngleStartYKey : _freeAngleEndYKey] =
          resolved.dy.toStringAsFixed(4);
    }
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
    if (_isFreeAngleIron(item) &&
        _endpointIsConnected(item, true) &&
        _endpointIsConnected(item, false)) {
      return true;
    }
    return _endpointHasLockedPeer(item, true) ||
        _endpointHasLockedPeer(item, false);
  }

  bool _endpointIsConnected(_LayoutItem item, bool leading) {
    final joint = _jointId(item, leading);
    if (joint != null && joint.isNotEmpty) return true;
    final anchorItemId =
        int.tryParse(item.properties[_endpointAnchorItemKey(leading)] ?? '');
    final anchorSide = item.properties[_endpointAnchorSideKey(leading)];
    return anchorItemId != null && anchorSide != null && anchorSide.isNotEmpty;
  }

  double _effectiveIronMinLength(_LayoutItem item) {
    final bothConnected =
        _endpointIsConnected(item, true) && _endpointIsConnected(item, false);
    return bothConnected ? 0.0 : _freeIronMinLength;
  }

  void _setIronEndpointPosition(_LayoutItem item, bool leading, Offset point) {
    if (_isFreeAngleIron(item)) {
      final clampedPoint = _clampToCanvas(point);
      var start = _storedIronEndpoint(item, true);
      var end = _storedIronEndpoint(item, false);
      if (leading) {
        start = clampedPoint;
      } else {
        end = clampedPoint;
      }
      final minLength = _effectiveIronMinLength(item);
      final delta = end - start;
      final length = delta.distance;
      if (length < minLength) {
        if (length < 1e-6) {
          if (leading) {
            start = Offset(end.dx - minLength, end.dy);
          } else {
            end = Offset(start.dx + minLength, start.dy);
          }
        } else {
          final dir = Offset(delta.dx / length, delta.dy / length);
          if (leading) {
            start = end - Offset(dir.dx * minLength, dir.dy * minLength);
          } else {
            end = start + Offset(dir.dx * minLength, dir.dy * minLength);
          }
        }
      }
      _storeIronEndpoints(item, start, end);
      return;
    }
    final minLength = _effectiveIronMinLength(item);
    if (item.type == _EquipmentType.ironHorizontal) {
      final opposite = _ironEndpoint(item, !leading);
      final newX = leading
          ? point.dx.clamp(0.0, opposite.dx - minLength)
          : point.dx.clamp(item.x + minLength, _virtualCanvasSize.width);
      if (leading) {
        item.width = opposite.dx - newX;
        item.x = newX;
      } else {
        item.width = newX - item.x;
      }
      item.y = (point.dy - item.height / 2)
          .clamp(0.0, _virtualCanvasSize.height - item.height);
      return;
    }

    final opposite = _ironEndpoint(item, !leading);
    final newY = leading
        ? point.dy.clamp(0.0, opposite.dy - minLength)
        : point.dy.clamp(item.y + minLength, _virtualCanvasSize.height);
    if (leading) {
      item.height = opposite.dy - newY;
      item.y = newY;
    } else {
      item.height = newY - item.y;
    }
    item.x = (point.dx - item.width / 2)
        .clamp(0.0, _virtualCanvasSize.width - item.width);
  }

  String _newJointId() =>
      'joint_${DateTime.now().microsecondsSinceEpoch}_${_nextId}';

  Offset _pointAlongIron(_LayoutItem iron, double t) {
    final clampedT = t.clamp(0.0, 1.0);
    final start = _resolveIronEndpoint(iron, true);
    final end = _resolveIronEndpoint(iron, false);
    return Offset(
      start.dx + (end.dx - start.dx) * clampedT,
      start.dy + (end.dy - start.dy) * clampedT,
    );
  }

  double _normalizedPositionAlongIron(_LayoutItem iron, Offset point) {
    final start = _resolveIronEndpoint(iron, true);
    final end = _resolveIronEndpoint(iron, false);
    final delta = end - start;
    final lengthSquared = delta.dx * delta.dx + delta.dy * delta.dy;
    if (lengthSquared <= 1e-6) return 0.0;
    final t =
        ((point.dx - start.dx) * delta.dx + (point.dy - start.dy) * delta.dy) /
            lengthSquared;
    return t.clamp(0.0, 1.0).toDouble();
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
        final point = _resolveIronEndpoint(other, otherLeading);
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
    int? excludedItemId,
    int? movingIronId,
    bool? movingIronLeading,
  }) {
    _ConnectionTarget? best;
    var bestDistance = double.infinity;
    for (final item in _items) {
      if (_isStraightIronType(item.type)) continue;
      if (excludedItemId != null && item.id == excludedItemId) continue;
      for (final anchor in _equipmentAnchorCandidates(item)) {
        if (!_isEquipmentAnchorAvailable(
          item,
          anchor.side,
          movingIronId: movingIronId,
          movingIronLeading: movingIronLeading,
        )) {
          continue;
        }
        final distance =
            _screenDistanceBetweenScenePoints(anchor.point, target);
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
        final point = _resolveIronEndpoint(other, leading);
        final distance = _screenDistanceBetweenScenePoints(point, target);
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
    required double radiusScreen,
    int? movingIronId,
    bool? movingIronLeading,
    int? excludedAnchorItemId,
  }) {
    final nearestAnchor = _nearestAnchorTarget(
      target,
      radius: radiusScreen,
      exact: false,
      excludedItemId: excludedAnchorItemId,
      movingIronId: movingIronId,
      movingIronLeading: movingIronLeading,
    );
    final nearestEndpoint = _nearestIronEndpointTarget(
      target,
      radius: radiusScreen,
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
    final anchorId = target.anchorId;
    final anchorItem = target.equipmentItemId == null
        ? null
        : _findItemById(target.equipmentItemId!);
    final normalizedAnchorId = anchorItem == null || anchorId == null
        ? anchorId
        : anchorItem.type == _EquipmentType.bypass
            ? _normalizedBypassPortId(anchorId)
            : _normalizedAnchorSide(anchorItem, anchorId);
    if (anchorItem != null && anchorItem.type == _EquipmentType.bypass) {
      if (normalizedAnchorId == null) {
        if (kDebugMode) {
          debugPrint(
            'Unsupported bypass port "$anchorId" on bypass ${anchorItem.id}; '
            'treating as disconnected.',
          );
        }
        return _EndpointSnapTarget(point: target.point);
      }
      return _EndpointSnapTarget(
        point: target.point,
        bypass: _BypassHandleCandidate(
          itemId: target.equipmentItemId!,
          side: normalizedAnchorId,
          point: target.point,
          score: target.distance,
        ),
      );
    }
    return _EndpointSnapTarget(
      point: target.point,
      equipment: _EquipmentAnchorCandidate(
        itemId: target.equipmentItemId!,
        side: normalizedAnchorId ?? target.anchorId!,
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
        radius: 40, exact: false, movingIronId: iron.id);
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
    final handleRadius = _sceneRadiusFromScreen(_disconnectHoldRadiusScreen);
    _BypassHandleCandidate? best;
    for (final item in _items) {
      if (item.type != _EquipmentType.bypass) continue;
      for (final side in const <String>[
        _bypassPortMainTop,
        _bypassPortMainBottom,
        _bypassPortUpperValveOutlet,
        _bypassPortLowerValveOutlet,
      ]) {
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
    Offset target, {
    required double radiusScreen,
  }) {
    final resolved = _findBestConnectionTarget(
      target,
      radiusScreen: radiusScreen,
      movingIronId: item.id,
      movingIronLeading: leading,
    );
    if (resolved == null) return null;
    return _snapTargetFromConnection(resolved);
  }

  List<String> _fittingEndpointSides(_LayoutItem item) {
    if (_isElbowFittingType(item.type)) {
      return const <String>['inlet', 'outlet'];
    }
    if (item.type.name.startsWith('tee')) {
      return const <String>['runStart', 'runEnd', 'branch'];
    }
    return const <String>[];
  }

  _FittingEndpointSnapCandidate? _nearestFittingEndpointSnapCandidate(
    _LayoutItem fitting, {
    required double radiusScreen,
    Set<String>? blockedTargetKeys,
    double sameTargetLockoutRadiusScreen = _sameTargetLockoutRadiusScreen,
  }) {
    if (!_isFittingEndpointConnectableType(fitting.type)) return null;
    _FittingEndpointSnapCandidate? best;
    for (final side in _fittingEndpointSides(fitting)) {
      final point = _equipmentAnchorPointOrNull(fitting, side);
      if (point == null) continue;
      final target = _findBestConnectionTarget(
        point,
        radiusScreen: radiusScreen,
        excludedAnchorItemId: fitting.id,
      );
      if (target == null) continue;
      final targetKey = _connectionTargetKey(target);
      if (blockedTargetKeys != null &&
          blockedTargetKeys.contains(targetKey) &&
          target.distance <= sameTargetLockoutRadiusScreen) {
        continue;
      }
      final distance = target.distance;
      if (best == null || distance < best.distance) {
        best = _FittingEndpointSnapCandidate(
          fittingSide: side,
          fittingPoint: point,
          target: target,
          distance: distance,
        );
      }
    }
    return best;
  }

  Offset _fittingTopLeftForSnapCandidate(
    _LayoutItem fitting,
    _FittingEndpointSnapCandidate candidate,
  ) {
    var snappedTopLeft = Offset(
      fitting.x + candidate.target.point.dx - candidate.fittingPoint.dx,
      fitting.y + candidate.target.point.dy - candidate.fittingPoint.dy,
    );
    final originalX = fitting.x;
    final originalY = fitting.y;
    fitting.x = snappedTopLeft.dx;
    fitting.y = snappedTopLeft.dy;
    final resolvedPoint =
        _equipmentAnchorPointOrNull(fitting, candidate.fittingSide);
    if (resolvedPoint != null) {
      snappedTopLeft = Offset(
        fitting.x + candidate.target.point.dx - resolvedPoint.dx,
        fitting.y + candidate.target.point.dy - resolvedPoint.dy,
      );
    }
    fitting.x = originalX;
    fitting.y = originalY;
    return snappedTopLeft;
  }

  String _fittingAnchorItemKey(String side) => 'fittingAnchor_${side}ItemId';

  String _fittingAnchorSideKey(String side) => 'fittingAnchor_${side}Side';

  void _setFittingAnchor(
    _LayoutItem fitting,
    String fittingSide, {
    int? anchorItemId,
    String? anchorSide,
  }) {
    if (anchorItemId == null || anchorSide == null || anchorSide.isEmpty) {
      fitting.properties.remove(_fittingAnchorItemKey(fittingSide));
      fitting.properties.remove(_fittingAnchorSideKey(fittingSide));
      return;
    }
    fitting.properties[_fittingAnchorItemKey(fittingSide)] =
        anchorItemId.toString();
    fitting.properties[_fittingAnchorSideKey(fittingSide)] = anchorSide;
  }

  void _clearFittingAnchors(_LayoutItem fitting) {
    for (final side in _fittingEndpointSides(fitting)) {
      _setFittingAnchor(fitting, side, anchorItemId: null, anchorSide: null);
    }
  }

  void _attachIronEndpointToFitting(
    _LayoutItem iron,
    bool leading,
    _LayoutItem fitting,
    String fittingSide,
  ) {
    final anchorPoint = _equipmentAnchorPointOrNull(fitting, fittingSide);
    if (anchorPoint == null) return;
    _clearEndpointAttachment(iron, leading);
    _setEndpointAnchor(
      iron,
      leading,
      anchorItemId: fitting.id,
      side: fittingSide,
    );
    _setIronEndpointPosition(iron, leading, anchorPoint);
    _snapIndicatorScene = anchorPoint;
  }

  void _commitFittingEndpointConnections(_LayoutItem fitting) {
    final blockedTargetKeys = _fittingDragBlockedTargetKeys[fitting.id];
    final candidate = _nearestFittingEndpointSnapCandidate(
      fitting,
      radiusScreen: _connectionReleaseRadiusScreen,
      blockedTargetKeys: blockedTargetKeys,
    );
    if (candidate == null) {
      _clearFittingAnchors(fitting);
      return;
    }

    final shifted = _fittingTopLeftForSnapCandidate(fitting, candidate);
    fitting.x = shifted.dx;
    fitting.y = shifted.dy;

    final fittedPoint =
        _equipmentAnchorPointOrNull(fitting, candidate.fittingSide);
    if (fittedPoint == null) return;
    if ((fittedPoint - candidate.target.point).distance > 0.01) {
      fitting.x += candidate.target.point.dx - fittedPoint.dx;
      fitting.y += candidate.target.point.dy - fittedPoint.dy;
    }

    if (candidate.target.kind == _ConnectionTargetKind.ironEndpoint) {
      final iron = candidate.target.ironItemId == null
          ? null
          : _findItemById(candidate.target.ironItemId!);
      final leading = candidate.target.ironLeading;
      if (iron != null && _isStraightIronType(iron.type) && leading != null) {
        _setFittingAnchor(
          fitting,
          candidate.fittingSide,
          anchorItemId: iron.id,
          anchorSide: leading ? 'start' : 'end',
        );
        _attachIronEndpointToFitting(
            iron, leading, fitting, candidate.fittingSide);
      }
    } else if (candidate.target.kind == _ConnectionTargetKind.equipmentAnchor) {
      final anchorItemId = candidate.target.equipmentItemId;
      final anchorSide = candidate.target.anchorId;
      if (anchorItemId != null && anchorSide != null && anchorSide.isNotEmpty) {
        _setFittingAnchor(
          fitting,
          candidate.fittingSide,
          anchorItemId: anchorItemId,
          anchorSide: anchorSide,
        );
      }
    }
    _snapIndicatorScene = candidate.target.point;
  }

  _IronDragIntent _resolveIronDragIntent(
    _LayoutItem iron,
    Offset scenePoint,
  ) {
    final startPoint = _resolveIronEndpoint(iron, true);
    final endPoint = _resolveIronEndpoint(iron, false);
    final resizeRadius = _sceneRadiusFromScreen(_endpointResizeHitRadiusScreen);
    final bodyRadius = _sceneRadiusFromScreen(_ironBodyHitCorridorScreen);
    final startDistance = (scenePoint - startPoint).distance;
    final endDistance = (scenePoint - endPoint).distance;
    if (startDistance <= resizeRadius && startDistance <= endDistance) {
      return const _IronDragIntent.resizeStart();
    }
    if (endDistance <= resizeRadius) {
      return const _IronDragIntent.resizeEnd();
    }
    final bodyDistance =
        _distancePointToSegment(scenePoint, startPoint, endPoint);
    if (bodyDistance <= bodyRadius) {
      return const _IronDragIntent.moveBody();
    }
    return const _IronDragIntent.none();
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
    const switchBias = 4.0;
    final previousDistance =
        _screenDistanceBetweenScenePoints(previous.point, sourcePoint);
    final candidateDistance =
        _screenDistanceBetweenScenePoints(candidate.point, sourcePoint);
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
    final targetItem = _findItemById(candidate.itemId);
    if (targetItem == null ||
        !_isEquipmentAnchorAvailable(
          targetItem,
          candidate.side,
          movingIronId: item.id,
          movingIronLeading: leading,
        )) {
      return;
    }
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
      item.properties.remove(_bypassOrientationKey(slot));
      return;
    }
    item.properties[_bypassIronKey(slot)] = iron.id.toString();
    item.properties[_bypassTKey(slot)] = t.clamp(0.0, 1.0).toStringAsFixed(4);
    item.properties[_bypassOrientationKey(slot)] =
        iron.type == _EquipmentType.ironHorizontal ? 'horizontal' : 'vertical';
  }

  Offset _ironCenterlineStart(_LayoutItem iron) {
    if (iron.type == _EquipmentType.ironHorizontal) {
      return Offset(iron.x, iron.y + iron.height / 2);
    }
    return Offset(iron.x + iron.width / 2, iron.y);
  }

  Offset _ironCenterlineEnd(_LayoutItem iron) {
    if (iron.type == _EquipmentType.ironHorizontal) {
      return Offset(iron.x + iron.width, iron.y + iron.height / 2);
    }
    return Offset(iron.x + iron.width / 2, iron.y + iron.height);
  }

  Offset _nearestPointOnSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final denom = ab.dx * ab.dx + ab.dy * ab.dy;
    if (denom <= 1e-6) return a;
    final ap = p - a;
    final t = ((ap.dx * ab.dx) + (ap.dy * ab.dy)) / denom;
    final clampedT = t.clamp(0.0, 1.0).toDouble();
    return Offset(a.dx + ab.dx * clampedT, a.dy + ab.dy * clampedT);
  }

  double _distancePointToSegment(Offset p, Offset a, Offset b) {
    final nearest = _nearestPointOnSegment(p, a, b);
    return (p - nearest).distance;
  }

  double _distanceBetweenSegments(Offset a1, Offset a2, Offset b1, Offset b2) {
    if (_segmentsIntersect(a1, a2, b1, b2)) return 0.0;
    return math.min(
      math.min(
        _distancePointToSegment(a1, b1, b2),
        _distancePointToSegment(a2, b1, b2),
      ),
      math.min(
        _distancePointToSegment(b1, a1, a2),
        _distancePointToSegment(b2, a1, a2),
      ),
    );
  }

  Offset _attachmentSpineLocalPoint(_LayoutItem item, String side) {
    final anchors = _anchorDefinitionsForType(item.type);
    for (final anchor in anchors) {
      if (anchor.id == side) {
        return Offset(anchor.u * item.width, anchor.v * item.height);
      }
    }
    throw StateError(
      'Unsupported inline attachment side "$side" for ${item.type.name}.',
    );
  }

  List<_InlineSegment> _inlineAttachmentSegmentsLocal(_LayoutItem item) {
    switch (item.type) {
      case _EquipmentType.bypass:
        return <_InlineSegment>[
          _InlineSegment(
            id: 'mainSpine',
            start: _attachmentSpineLocalPoint(item, 'mainTop'),
            end: _attachmentSpineLocalPoint(item, 'mainBottom'),
          ),
        ];
      case _EquipmentType.teeUp:
      case _EquipmentType.teeRight:
      case _EquipmentType.teeDown:
      case _EquipmentType.teeLeft:
        return <_InlineSegment>[
          _InlineSegment(
            id: 'run',
            start: _attachmentSpineLocalPoint(item, 'runStart'),
            end: _attachmentSpineLocalPoint(item, 'runEnd'),
          ),
        ];
      case _EquipmentType.elbowUpRight:
      case _EquipmentType.elbowRightDown:
      case _EquipmentType.elbowDownLeft:
      case _EquipmentType.elbowLeftUp:
        final corner = Offset(item.width * 0.5, item.height * 0.5);
        final inlet = _attachmentSpineLocalPoint(item, 'inlet');
        final outlet = _attachmentSpineLocalPoint(item, 'outlet');
        final inletIsVertical =
            (inlet.dy - corner.dy).abs() >= (inlet.dx - corner.dx).abs();
        return <_InlineSegment>[
          _InlineSegment(
            id: inletIsVertical ? 'verticalLeg' : 'horizontalLeg',
            start: corner,
            end: inlet,
          ),
          _InlineSegment(
            id: inletIsVertical ? 'horizontalLeg' : 'verticalLeg',
            start: corner,
            end: outlet,
          ),
        ];
      default:
        return <_InlineSegment>[
          _InlineSegment(
            id: 'defaultSpine',
            start: Offset(item.width / 2, 0),
            end: Offset(item.width / 2, item.height),
          ),
        ];
    }
  }

  List<_InlineSegment> _inlineAttachmentSegmentsWorld(
    _LayoutItem item, {
    Offset? topLeft,
  }) {
    final origin = topLeft ?? Offset(item.x, item.y);
    return _inlineAttachmentSegmentsLocal(item)
        .map(
          (segment) => _InlineSegment(
            id: segment.id,
            start: origin + segment.start,
            end: origin + segment.end,
          ),
        )
        .toList(growable: false);
  }

  bool _segmentCompatibleWithIron(_InlineSegment segment, _LayoutItem iron) {
    if (_isFreeAngleIron(iron)) {
      return true;
    }
    final horizontal = iron.type == _EquipmentType.ironHorizontal;
    final dx = (segment.end.dx - segment.start.dx).abs();
    final dy = (segment.end.dy - segment.start.dy).abs();
    if (horizontal) {
      return dy <= dx;
    }
    return dx <= dy;
  }

  Offset _segmentCenter(_InlineSegment segment) {
    return Offset(
      (segment.start.dx + segment.end.dx) / 2,
      (segment.start.dy + segment.end.dy) / 2,
    );
  }

  _InlineSegment _activeInlineAttachmentSegmentWorld(
    _LayoutItem item, {
    Offset? topLeft,
    _LayoutItem? parentIron,
  }) {
    final segments = _inlineAttachmentSegmentsWorld(item, topLeft: topLeft);
    final attachedSegmentId = _inlineAttachedSegmentId(item);
    if (attachedSegmentId != null) {
      for (final segment in segments) {
        if (segment.id == attachedSegmentId) {
          if (parentIron == null ||
              _segmentCompatibleWithIron(segment, parentIron)) {
            return segment;
          }
          break;
        }
      }
    }
    if (parentIron == null || !_isStraightIronType(parentIron.type)) {
      return segments.first;
    }

    final parentStart = _resolveIronEndpoint(parentIron, true);
    final parentEnd = _resolveIronEndpoint(parentIron, false);
    _InlineSegment? best;
    var bestDistance = double.infinity;
    for (final segment in segments) {
      if (!_segmentCompatibleWithIron(segment, parentIron)) continue;
      final distance = _distanceBetweenSegments(
        segment.start,
        segment.end,
        parentStart,
        parentEnd,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        best = segment;
      }
    }
    return best ?? segments.first;
  }

  _AttachmentSpine _attachmentSpineLocal(_LayoutItem item) {
    switch (item.type) {
      case _EquipmentType.bypass:
        return _AttachmentSpine(
          startLocal: _attachmentSpineLocalPoint(item, 'mainTop'),
          endLocal: _attachmentSpineLocalPoint(item, 'mainBottom'),
        );
      case _EquipmentType.teeUp:
      case _EquipmentType.teeRight:
      case _EquipmentType.teeDown:
      case _EquipmentType.teeLeft:
        return _AttachmentSpine(
          startLocal: _attachmentSpineLocalPoint(item, 'runStart'),
          endLocal: _attachmentSpineLocalPoint(item, 'runEnd'),
        );
      case _EquipmentType.elbowUpRight:
      case _EquipmentType.elbowRightDown:
      case _EquipmentType.elbowDownLeft:
      case _EquipmentType.elbowLeftUp:
        return _AttachmentSpine(
          startLocal: _attachmentSpineLocalPoint(item, 'inlet'),
          endLocal: _attachmentSpineLocalPoint(item, 'outlet'),
        );
      default:
        return _AttachmentSpine(
          startLocal: Offset(item.width / 2, 0),
          endLocal: Offset(item.width / 2, item.height),
        );
    }
  }

  _AttachmentSpine _attachmentSpineWorld(
    _LayoutItem item, {
    Offset? topLeft,
    _LayoutItem? parentIron,
  }) {
    final active = _activeInlineAttachmentSegmentWorld(
      item,
      topLeft: topLeft,
      parentIron: parentIron,
    );
    return _AttachmentSpine(
      startLocal: active.start,
      endLocal: active.end,
    );
  }

  Offset _attachmentSpineCenterWorld(
    _LayoutItem item, {
    Offset? topLeft,
    _LayoutItem? parentIron,
  }) {
    final spine =
        _attachmentSpineWorld(item, topLeft: topLeft, parentIron: parentIron);
    return Offset(
      (spine.startLocal.dx + spine.endLocal.dx) / 2,
      (spine.startLocal.dy + spine.endLocal.dy) / 2,
    );
  }

  double _cross2d(Offset a, Offset b, Offset c) {
    return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  }

  bool _segmentsIntersect(Offset a1, Offset a2, Offset b1, Offset b2) {
    final d1 = _cross2d(a1, a2, b1);
    final d2 = _cross2d(a1, a2, b2);
    final d3 = _cross2d(b1, b2, a1);
    final d4 = _cross2d(b1, b2, a2);

    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }

    bool onSegment(Offset p, Offset q, Offset r) {
      return q.dx <= math.max(p.dx, r.dx) + 1e-6 &&
          q.dx + 1e-6 >= math.min(p.dx, r.dx) &&
          q.dy <= math.max(p.dy, r.dy) + 1e-6 &&
          q.dy + 1e-6 >= math.min(p.dy, r.dy);
    }

    if (d1.abs() < 1e-6 && onSegment(a1, b1, a2)) return true;
    if (d2.abs() < 1e-6 && onSegment(a1, b2, a2)) return true;
    if (d3.abs() < 1e-6 && onSegment(b1, a1, b2)) return true;
    if (d4.abs() < 1e-6 && onSegment(b1, a2, b2)) return true;
    return false;
  }

  _SnapCandidate? _nearestBypassRail(
    _LayoutItem item,
    Offset desiredTopLeft, {
    int? excludedIronId,
    double? maxDistance,
  }) {
    final maxDistanceValue =
        maxDistance ?? _sceneRadiusFromScreen(_bypassAttachRadiusScreen);
    final segments =
        _inlineAttachmentSegmentsWorld(item, topLeft: desiredTopLeft);
    _SnapCandidate? best;
    for (final iron in _items) {
      if (!_isStraightIronType(iron.type)) continue;
      if (excludedIronId != null && iron.id == excludedIronId) continue;
      final start = _resolveIronEndpoint(iron, true);
      final end = _resolveIronEndpoint(iron, false);
      final horizontal = iron.type == _EquipmentType.ironHorizontal;
      for (final segment in segments) {
        if (!_segmentCompatibleWithIron(segment, iron)) continue;
        final center = _segmentCenter(segment);
        final projected = _nearestPointOnSegment(center, start, end);
        final distance =
            _distanceBetweenSegments(segment.start, segment.end, start, end);
        if (distance > maxDistanceValue) continue;
        final score = distance;
        if (best == null || score < best.score) {
          best = _SnapCandidate(
            ironId: iron.id,
            horizontal: horizontal,
            indicator: projected,
            score: score,
            segmentId: segment.id,
          );
        }
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
    final occupiedEquipmentPorts = <String>{};
    final occupiedSingleInletItems = <int>{};
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
            final normalizedSide =
                _normalizedAnchorSide(anchorItem, anchorSide);
            final normalizedPortKey = '${anchorItem.id}:$normalizedSide';
            final singleInlet = _isSingleInletEquipmentType(anchorItem.type);
            if (singleInlet) {
              if (occupiedSingleInletItems.contains(anchorItem.id)) {
                _setEndpointAnchor(item, leading,
                    anchorItemId: null, side: null);
                continue;
              }
              occupiedSingleInletItems.add(anchorItem.id);
            } else {
              if (occupiedEquipmentPorts.contains(normalizedPortKey)) {
                _setEndpointAnchor(item, leading,
                    anchorItemId: null, side: null);
                continue;
              }
              occupiedEquipmentPorts.add(normalizedPortKey);
            }
            final resolved =
                _equipmentAnchorPointOrNull(anchorItem, normalizedSide);
            if (resolved == null) {
              _setEndpointAnchor(item, leading, anchorItemId: null, side: null);
              continue;
            }
            if (normalizedSide != anchorSide) {
              _setEndpointAnchor(
                item,
                leading,
                anchorItemId: anchorItem.id,
                side: normalizedSide,
              );
            }
            _setIronEndpointPosition(
              item,
              leading,
              resolved,
            );
          } else if (anchorItemId != null) {
            _setEndpointAnchor(item, leading, anchorItemId: null, side: null);
          }
        }
      }

      if (_isFittingEndpointConnectableType(item.type) &&
          !_usesInlineParentDragConstraint(item.type)) {
        _clearInlineParentAttachment(item);
      }

      if (!_isInlineFittingType(item.type)) continue;

      final parentIron = _inlineParentIron(item);
      final parentT = _inlineParentT(item);
      if (parentIron == null || parentT == null) {
        _clearInlineParentAttachment(item);
        continue;
      }
      _setInlineParentAttachment(item, parentIron, parentT);
      _alignInlineToParent(item, parentIron, parentT);

      if (item.type == _EquipmentType.bypass) {
        _ensureBypassLeadData(item);
        final primaryIron = _bypassAttachmentIron(item, 'Primary');
        final secondaryIron = _bypassAttachmentIron(item, 'Secondary');
        final primaryT = _bypassAttachmentT(item, 'Primary');
        final secondaryT = _bypassAttachmentT(item, 'Secondary');
        if (primaryIron == null || primaryT == null) {
          if (item.properties[_bypassIronKey('Primary')] != null) {
            _setBypassAttachment(item, 'Primary', null, null);
          }
        }
        if (secondaryIron == null || secondaryT == null) {
          if (item.properties[_bypassIronKey('Secondary')] != null) {
            _setBypassAttachment(item, 'Secondary', null, null);
          }
        }
        for (final leadId in _bypassLeadIds) {
          final target = _bypassLeadStoredTarget(item, leadId);
          if (target == null) continue;
          if (target.kind == _ConnectionTargetKind.ironEndpoint) {
            if (target.ironItemId == null || target.ironLeading == null) {
              _setBypassLeadTarget(item, leadId,
                  kind: null, targetItemId: null, side: null);
              continue;
            }
            _setBypassLeadEndpointWorld(item, leadId, target.point);
            continue;
          }
          if (target.equipmentItemId == null ||
              target.anchorId == null ||
              target.anchorId!.isEmpty) {
            _setBypassLeadTarget(item, leadId,
                kind: null, targetItemId: null, side: null);
            continue;
          }
          final anchorItem = _findItemById(target.equipmentItemId!);
          final normalizedSide = anchorItem == null
              ? target.anchorId!
              : _normalizedAnchorSide(anchorItem, target.anchorId!);
          final point = anchorItem == null
              ? null
              : _equipmentAnchorPointOrNull(anchorItem, normalizedSide);
          if (point == null) {
            _setBypassLeadTarget(item, leadId,
                kind: null, targetItemId: null, side: null);
            continue;
          }
          if (normalizedSide != target.anchorId) {
            _setBypassLeadTarget(
              item,
              leadId,
              kind: 'equipmentAnchor',
              targetItemId: target.equipmentItemId,
              side: normalizedSide,
            );
          }
          _setBypassLeadEndpointWorld(item, leadId, point);
        }
      }

      if (_isFittingEndpointConnectableType(item.type)) {
        var repositioned = false;
        for (final side in _fittingEndpointSides(item)) {
          final anchorItemId =
              int.tryParse(item.properties[_fittingAnchorItemKey(side)] ?? '');
          final anchorSide = item.properties[_fittingAnchorSideKey(side)];
          if (anchorItemId == null ||
              anchorSide == null ||
              anchorSide.isEmpty) {
            continue;
          }
          final anchorItem = _findItemById(anchorItemId);
          final anchorPoint = anchorItem == null
              ? null
              : _equipmentAnchorPointOrNull(
                  anchorItem,
                  _normalizedAnchorSide(anchorItem, anchorSide),
                );
          final normalizedSide = anchorItem == null
              ? anchorSide
              : _normalizedAnchorSide(anchorItem, anchorSide);
          final normalizedPortKey =
              anchorItem == null ? '' : '${anchorItem.id}:$normalizedSide';
          if (anchorPoint == null) {
            _setFittingAnchor(item, side, anchorItemId: null, anchorSide: null);
            continue;
          }
          if (anchorItem != null) {
            if (_isSingleInletEquipmentType(anchorItem.type)) {
              if (occupiedSingleInletItems.contains(anchorItem.id)) {
                _setFittingAnchor(item, side,
                    anchorItemId: null, anchorSide: null);
                continue;
              }
              occupiedSingleInletItems.add(anchorItem.id);
            } else {
              if (occupiedEquipmentPorts.contains(normalizedPortKey)) {
                _setFittingAnchor(item, side,
                    anchorItemId: null, anchorSide: null);
                continue;
              }
              occupiedEquipmentPorts.add(normalizedPortKey);
            }
          }
          if (anchorItem != null && normalizedSide != anchorSide) {
            _setFittingAnchor(
              item,
              side,
              anchorItemId: anchorItem.id,
              anchorSide: normalizedSide,
            );
          }
          // Only reposition from the first resolvable anchor. Correcting
          // for every connected side in sequence would shift the item once
          // per side, silently undoing the alignment of any side handled
          // just before it.
          if (repositioned) continue;
          final currentPoint = _equipmentAnchorPointOrNull(item, side);
          if (currentPoint == null) continue;
          final delta = anchorPoint - currentPoint;
          item.x += delta.dx;
          item.y += delta.dy;
          repositioned = true;
        }
      }
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

  void _setBypassTopLeft(_LayoutItem item, Offset desiredTopLeft, Size canvas) {
    item.x = desiredTopLeft.dx.clamp(0.0, canvas.width - item.width);
    item.y = desiredTopLeft.dy.clamp(0.0, canvas.height - item.height);
  }

  Offset _pointOnIronCenterline(_LayoutItem iron, double t) {
    return _pointAlongIron(iron, t);
  }

  _LayoutItem? _inlineParentIron(_LayoutItem item) {
    final parentIronId = int.tryParse(item.properties[_inlineParentIronKey] ??
        item.properties[_bypassParentIronKey] ??
        item.properties['snapIronId'] ??
        item.properties[_bypassIronKey('Primary')] ??
        '');
    if (parentIronId == null) return null;
    final iron = _findItemById(parentIronId);
    if (iron == null || !_isStraightIronType(iron.type)) return null;
    return iron;
  }

  double? _inlineParentT(_LayoutItem item) {
    final value = item.properties[_inlineParentTKey] ??
        item.properties[_bypassParentTKey] ??
        item.properties['snapT'] ??
        item.properties[_bypassTKey('Primary')] ??
        '';
    final parsed = double.tryParse(value);
    return parsed?.clamp(0.0, 1.0);
  }

  _LayoutItem? _bypassParentIron(_LayoutItem item) => _inlineParentIron(item);

  double? _bypassParentT(_LayoutItem item) => _inlineParentT(item);

  void _clearInlineParentAttachment(_LayoutItem item) {
    item.properties.remove(_inlineParentIronKey);
    item.properties.remove(_inlineParentTKey);
    item.properties.remove(_inlineParentOrientationKey);
    item.properties.remove(_inlineAttachedSegmentKey);
    item.properties.remove(_bypassParentIronKey);
    item.properties.remove(_bypassParentTKey);
    item.properties.remove(_bypassParentOrientationKey);
    item.properties.remove('snapIronId');
    item.properties.remove('snapT');
    item.properties.remove('snapAxis');
    if (item.type == _EquipmentType.bypass) {
      _setBypassAttachment(item, 'Primary', null, null);
      _setBypassAttachment(item, 'Secondary', null, null);
    }
  }

  void _clearBypassParentAttachment(_LayoutItem item) {
    _clearInlineParentAttachment(item);
  }

  void _setInlineParentAttachment(
    _LayoutItem item,
    _LayoutItem iron,
    double normalizedT, {
    String? segmentId,
  }) {
    final t = normalizedT.clamp(0.0, 1.0).toDouble();
    item.properties[_inlineParentIronKey] = iron.id.toString();
    item.properties[_inlineParentTKey] = t.toStringAsFixed(4);
    final ironStart = _resolveIronEndpoint(iron, true);
    final ironEnd = _resolveIronEndpoint(iron, false);
    final horizontal =
        (ironEnd.dx - ironStart.dx).abs() >= (ironEnd.dy - ironStart.dy).abs();
    item.properties[_inlineParentOrientationKey] =
        horizontal ? 'horizontal' : 'vertical';
    item.properties[_bypassParentIronKey] = iron.id.toString();
    item.properties[_bypassParentTKey] = t.toStringAsFixed(4);
    item.properties[_bypassParentOrientationKey] =
        horizontal ? 'horizontal' : 'vertical';
    item.properties['snapIronId'] = iron.id.toString();
    item.properties['snapT'] = t.toStringAsFixed(4);
    item.properties['snapAxis'] = horizontal ? 'horizontal' : 'vertical';
    final chosenSegment = segmentId ??
        _activeInlineAttachmentSegmentWorld(
          item,
          parentIron: iron,
        ).id;
    item.properties[_inlineAttachedSegmentKey] = chosenSegment;
    if (item.type == _EquipmentType.bypass) {
      _setBypassAttachment(item, 'Primary', iron, t);
      _setBypassAttachment(item, 'Secondary', null, null);
    }
  }

  void _setBypassParentAttachment(
      _LayoutItem item, _LayoutItem iron, double normalizedT) {
    _setInlineParentAttachment(item, iron, normalizedT);
  }

  void _alignInlineToParent(_LayoutItem item, _LayoutItem iron, double t) {
    final center = _pointOnIronCenterline(iron, t);
    final activeSegment =
        _activeInlineAttachmentSegmentWorld(item, parentIron: iron);
    final delta = center - _segmentCenter(activeSegment);
    item.x += delta.dx;
    item.y += delta.dy;
  }

  void _alignBypassToParent(_LayoutItem item, _LayoutItem iron, double t) {
    _alignInlineToParent(item, iron, t);
  }

  bool _applyInlineAttachedDrag(
    _LayoutItem item,
    _BypassDragContext context,
    Offset delta,
    Size canvasSize,
  ) {
    assert(
      !_activeFreeDragItemIds.contains(item.id) ||
          _usesInlineParentDragConstraint(item.type),
      'Only the shared free-drag controller may move an active Tee/90.',
    );
    final desiredTopLeft = Offset(
      context.startTopLeft.dx + delta.dx,
      context.startTopLeft.dy + delta.dy,
    );
    if (!context.wasAttached || context.detached) {
      _setBypassTopLeft(item, desiredTopLeft, canvasSize);
      if (!context.reconnectAllowed && context.blockedParentIronId != null) {
        final blockedIron = _findItemById(context.blockedParentIronId!);
        if (blockedIron != null && _isStraightIronType(blockedIron.type)) {
          final lockoutRadius =
              _sceneRadiusFromScreen(_sameTargetLockoutRadiusScreen);
          final distance =
              _inlineDistanceToIron(item, Offset(item.x, item.y), blockedIron);
          context.reconnectAllowed = distance >= lockoutRadius;
        }
      }
      return false;
    }

    final parentIron = context.parentIronId == null
        ? null
        : _findItemById(context.parentIronId!);
    if (parentIron == null || !_isStraightIronType(parentIron.type)) {
      context.detached = true;
      _clearInlineParentAttachment(item);
      _setBypassTopLeft(item, desiredTopLeft, canvasSize);
      return true;
    }

    final parentStart = _resolveIronEndpoint(parentIron, true);
    final parentEnd = _resolveIronEndpoint(parentIron, false);
    final parentVector = parentEnd - parentStart;
    final parentLength = parentVector.distance;
    if (parentLength < 1e-6) {
      context.detached = true;
      _clearInlineParentAttachment(item);
      _setBypassTopLeft(item, desiredTopLeft, canvasSize);
      return true;
    }
    final parentDir = Offset(
      parentVector.dx / parentLength,
      parentVector.dy / parentLength,
    );
    final parentNormal = Offset(-parentDir.dy, parentDir.dx);
    final alongDelta = (delta.dx * parentDir.dx) + (delta.dy * parentDir.dy);
    final perpendicular =
        ((delta.dx * parentNormal.dx) + (delta.dy * parentNormal.dy)).abs();
    final detachThreshold = _sceneRadiusFromScreen(
      item.type.name.startsWith('tee')
          ? _teeDetachThresholdScreen
          : _disconnectThresholdScreen,
    );
    if (perpendicular > detachThreshold) {
      context.detached = true;
      context.blockedParentIronId = parentIron.id;
      context.reconnectAllowed = false;
      _clearInlineParentAttachment(item);
      _setBypassTopLeft(item, desiredTopLeft, canvasSize);
      return true;
    }

    final startT = context.startT ??
        _normalizedPositionAlongIron(parentIron, context.startCenter);
    final startCenter = _pointOnIronCenterline(parentIron, startT);
    final projected = startCenter +
        Offset(parentDir.dx * alongDelta, parentDir.dy * alongDelta);
    final t = _normalizedPositionAlongIron(parentIron, projected);
    _setInlineParentAttachment(
      item,
      parentIron,
      t,
      segmentId: context.attachedSegmentId,
    );
    _alignInlineToParent(item, parentIron, t);
    _setBypassTopLeft(item, Offset(item.x, item.y), canvasSize);
    return false;
  }

  bool _applyBypassAttachedDrag(
    _LayoutItem item,
    _BypassDragContext context,
    Offset delta,
    Size canvasSize,
  ) {
    return _applyInlineAttachedDrag(item, context, delta, canvasSize);
  }

  double _inlineDistanceToIron(
    _LayoutItem item,
    Offset topLeft,
    _LayoutItem iron,
  ) {
    final start = _resolveIronEndpoint(iron, true);
    final end = _resolveIronEndpoint(iron, false);
    var bestDistance = double.infinity;
    for (final segment
        in _inlineAttachmentSegmentsWorld(item, topLeft: topLeft)) {
      if (!_segmentCompatibleWithIron(segment, iron)) continue;
      final distance =
          _distanceBetweenSegments(segment.start, segment.end, start, end);
      if (distance < bestDistance) {
        bestDistance = distance;
      }
    }
    return bestDistance;
  }

  void _attachInlineToNearestRailOnDrop(
    _LayoutItem item, {
    _BypassDragContext? context,
  }) {
    final lockoutIronId = context != null && !context.reconnectAllowed
        ? context.blockedParentIronId
        : null;
    var candidate = _nearestBypassRail(
      item,
      Offset(item.x, item.y),
      excludedIronId: lockoutIronId,
      maxDistance: _sceneRadiusFromScreen(_inlineSpineReleaseRadiusScreen),
    );
    candidate ??= _nearestBypassRail(
      item,
      Offset(item.x, item.y),
      maxDistance: _sceneRadiusFromScreen(_inlineSpineReleaseRadiusScreen),
    );
    if (candidate != null &&
        lockoutIronId != null &&
        candidate.ironId == lockoutIronId &&
        context != null &&
        !context.reconnectAllowed) {
      return;
    }
    if (candidate == null) return;
    final iron = _findItemById(candidate.ironId);
    if (iron == null || !_isStraightIronType(iron.type)) return;
    final segment = _activeInlineAttachmentSegmentWorld(
      item,
      parentIron: iron,
    );
    final center = _segmentCenter(segment);
    final t = _normalizedPositionAlongIron(iron, center);
    _setInlineParentAttachment(item, iron, t, segmentId: candidate.segmentId);
    _alignInlineToParent(item, iron, t);
  }

  void _attachBypassToNearestRailOnDrop(_LayoutItem item) {
    _attachInlineToNearestRailOnDrop(item);
  }

  void _beginItemDrag(_LayoutItem anchor, DragStartDetails details) {
    if (_isStraightIronType(anchor.type) && !anchor.locked) {
      final sceneStart = _scenePointFromGlobal(details.globalPosition);
      switch (_resolveIronDragIntent(anchor, sceneStart).type) {
        case _IronDragIntentType.resizeStart:
          _startEndpointHandleDrag(anchor, true);
          _dragSceneStart = sceneStart;
          _dragItemStart.clear();
          _dragActive = false;
          return;
        case _IronDragIntentType.resizeEnd:
          _startEndpointHandleDrag(anchor, false);
          _dragSceneStart = sceneStart;
          _dragItemStart.clear();
          _dragActive = false;
          return;
        case _IronDragIntentType.moveBody:
          break;
        case _IronDragIntentType.none:
          return;
      }
    }

    if (anchor.type == _EquipmentType.bypass && !anchor.locked) {
      final sceneStart = _scenePointFromGlobal(details.globalPosition);
      final hitRadius = _sceneRadiusFromScreen(_endpointHandleTouchSize / 2);
      String? chosenLeadId;
      var bestDistance = double.infinity;
      for (final leadId in _bypassLeadIds) {
        final point = _resolveBypassLeadEndpointWorld(anchor, leadId);
        final distance = (sceneStart - point).distance;
        if (distance <= hitRadius && distance < bestDistance) {
          bestDistance = distance;
          chosenLeadId = leadId;
        }
      }
      if (chosenLeadId != null) {
        _startBypassLeadDrag(anchor, chosenLeadId);
        _dragSceneStart = sceneStart;
        _dragItemStart.clear();
        _dragActive = false;
        return;
      }
    }

    final moving = _selectedIds.contains(anchor.id) ? _selectedItems : [anchor];
    if (moving.every((it) => it.locked)) {
      _interactionMode =
          _drawIronMode ? _InteractionMode.placeIron : _InteractionMode.idle;
      return;
    }
    _interactionMode = _InteractionMode.itemDrag;
    _beginFreeItemDrag(moving, _scenePointFromGlobal(details.globalPosition));
    if (mounted) {
      setState(() {});
    }
  }

  void _updateItemDrag(_LayoutItem anchor, DragUpdateDetails details) {
    if (_interactionMode == _InteractionMode.stretchEndpoint &&
        _isStraightIronType(anchor.type) &&
        _selectedEndpointLeading != null) {
      _updateEndpointHandleDrag(
          anchor, _selectedEndpointLeading!, details.delta);
      return;
    }

    final moving = _selectedIds.contains(anchor.id) ? _selectedItems : [anchor];
    if (moving.every((it) => _segmentMoveBlocked(it))) return;

    final start = _dragSceneStart;
    if (start == null) return;
    final scenePoint = _scenePointFromGlobal(details.globalPosition);
    final delta = scenePoint - start;

    _updateFreeItemDrag(moving, delta);
  }

  void _endItemDrag(_LayoutItem anchor) {
    if (_interactionMode == _InteractionMode.stretchEndpoint &&
        _isStraightIronType(anchor.type) &&
        _selectedEndpointLeading != null) {
      _endEndpointHandleDrag(anchor, _selectedEndpointLeading!);
      _dragSceneStart = null;
      _dragItemStart.clear();
      _dragActive = false;
      return;
    }

    final moving = _selectedIds.contains(anchor.id) ? _selectedItems : [anchor];
    if (moving.every((it) => _segmentMoveBlocked(it))) {
      _dragSceneStart = null;
      _dragItemStart.clear();
      _dragActive = false;
      return;
    }

    if (_dragActive && _snapToGrid) {
      setState(() {
        final canvasSize = _virtualCanvasSize;
        for (final it in moving) {
          if (_segmentMoveBlocked(it)) continue;
          if (_usesInlineParentDragConstraint(it.type) &&
              _inlineParentIron(it) != null) {
            continue;
          }
          it.x = _snap(it.x).clamp(0.0, canvasSize.width - it.width);
          it.y = _snap(it.y).clamp(0.0, canvasSize.height - it.height);
        }
      });
    }

    if (_dragActive) {
      setState(() {
        _finalizeDraggedItemConnections(moving);
      });
    }

    setState(() {
      _dragSceneStart = null;
      _dragItemStart.clear();
      _activeFreeDragItemIds.clear();
      _bypassDragContexts.clear();
      _fittingDragBlockedTargetKeys.clear();
      _clearFittingPreview();
      _cancelSelectedFittingSnapTimer();
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

  void _finalizeDraggedItemConnections(List<_LayoutItem> moving) {
    for (final it in moving) {
      if (_segmentMoveBlocked(it)) continue;
      if (_isInlineFittingType(it.type)) {
        final parentIron = _inlineParentIron(it);
        final parentT = _inlineParentT(it);
        final context = _bypassDragContexts[it.id];
        if (_usesInlineParentDragConstraint(it.type) &&
            parentIron != null &&
            parentT != null) {
          _setInlineParentAttachment(it, parentIron, parentT);
          _alignInlineToParent(it, parentIron, parentT);
        } else {
          _clearInlineParentAttachment(it);
          _attachInlineToNearestRailOnDrop(it, context: context);
        }
      }
      if (_isFittingEndpointConnectableType(it.type)) {
        _commitFittingEndpointConnections(it);
      }
    }
    _reflowSnappedFittings();
  }

  void _commitIronEndpointConnection(
    _LayoutItem item,
    bool leading, {
    _EndpointSnapTarget? target,
  }) {
    final effectiveTarget = target ??
        _nearestEndpointSnapTarget(
          item,
          leading,
          _ironEndpoint(item, leading),
          radiusScreen: _connectionReleaseRadiusScreen,
        );
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
    final center = _attachmentSpineCenterWorld(item);
    _setBypassAttachment(
      item,
      slot,
      iron,
      _normalizedPositionAlongIron(iron, center),
    );
    _reflowSnappedFittings();
  }

  String? _currentBypassLeadConnectionKey(_LayoutItem item, String leadId) {
    return _bypassLeadTargetKey(_bypassLeadStoredTarget(item, leadId));
  }

  void _commitBypassLeadConnection(
    _LayoutItem item,
    String leadId,
    _ConnectionTarget? target,
  ) {
    final effectiveTarget = target ??
        _findBestConnectionTarget(
          _resolveBypassLeadEndpointWorld(item, leadId),
          radiusScreen: _connectionReleaseRadiusScreen,
          excludedAnchorItemId: item.id,
        );
    if (effectiveTarget == null) {
      _setBypassLeadTarget(item, leadId,
          kind: null, targetItemId: null, side: null);
      return;
    }
    _setBypassLeadEndpointWorld(item, leadId, effectiveTarget.point);
    if (effectiveTarget.kind == _ConnectionTargetKind.ironEndpoint) {
      _setBypassLeadTarget(
        item,
        leadId,
        kind: 'ironEndpoint',
        targetItemId: effectiveTarget.ironItemId,
        side: effectiveTarget.ironLeading == true ? 'start' : 'end',
      );
    } else {
      _setBypassLeadTarget(
        item,
        leadId,
        kind: 'equipmentAnchor',
        targetItemId: effectiveTarget.equipmentItemId,
        side: effectiveTarget.anchorId,
      );
    }
    _snapIndicatorScene = effectiveTarget.point;
  }

  void _startBypassLeadDrag(_LayoutItem item, String leadId) {
    if (item.locked || item.type != _EquipmentType.bypass) return;
    setState(() {
      _selectedBypassLeadId = leadId;
      _selectedEndpointLeading = null;
      _selectedBypassHandle = null;
      _interactionMode = _InteractionMode.attachBypass;
      _activeBypassLeadDrag = _ActiveBypassLeadDrag(
        itemId: item.id,
        leadId: leadId,
        worldPosition: _resolveBypassLeadEndpointWorld(item, leadId),
        target: null,
        detached: false,
        blockedTargetKey: _currentBypassLeadConnectionKey(item, leadId),
        blockedOrigin: _resolveBypassLeadEndpointWorld(item, leadId),
        reconnectAllowed: false,
        historyRecorded: false,
      );
    });
  }

  void _updateBypassLeadDrag(
      _LayoutItem item, String leadId, Offset screenDelta) {
    if (item.locked || item.type != _EquipmentType.bypass) return;
    setState(() {
      _selectedBypassLeadId = leadId;
      final sceneDelta = _sceneDeltaFromScreen(screenDelta);
      final prior = (_activeBypassLeadDrag != null &&
              _activeBypassLeadDrag!.itemId == item.id &&
              _activeBypassLeadDrag!.leadId == leadId)
          ? _activeBypassLeadDrag!
          : null;
      final current = _resolveBypassLeadEndpointWorld(item, leadId);
      final desired = (prior?.worldPosition ?? current) + sceneDelta;
      final connectedTarget = _bypassLeadStoredTarget(item, leadId);
      final isAttached = connectedTarget != null;
      final holdRadius = _sceneRadiusFromScreen(_disconnectHoldRadiusScreen);
      final detachThreshold =
          _sceneRadiusFromScreen(_disconnectThresholdScreen);
      final reconnectReleaseDistance =
          _sceneRadiusFromScreen(_sameTargetLockoutRadiusScreen);

      final shouldRecordHistory =
          !(prior?.historyRecorded ?? false) && desired != current;
      if (shouldRecordHistory) {
        _recordUndo();
      }

      if (isAttached && (prior?.detached ?? false) == false) {
        final anchorPoint = connectedTarget.point;
        final distanceFromAnchor = (desired - anchorPoint).distance;
        _activeBypassLeadDrag = _ActiveBypassLeadDrag(
          itemId: item.id,
          leadId: leadId,
          worldPosition: desired,
          target: null,
          detached: false,
          blockedTargetKey: prior?.blockedTargetKey,
          blockedOrigin: prior?.blockedOrigin,
          reconnectAllowed: prior?.reconnectAllowed ?? false,
          historyRecorded:
              shouldRecordHistory || (prior?.historyRecorded ?? false),
        );
        if (distanceFromAnchor <= holdRadius ||
            distanceFromAnchor < detachThreshold) {
          _snapIndicatorScene = null;
          return;
        }

        _setBypassLeadTarget(item, leadId,
            kind: null, targetItemId: null, side: null);
        _setBypassLeadEndpointWorld(item, leadId, desired);
        final candidate = _findBestConnectionTarget(
          desired,
          radiusScreen: _connectionPreviewRadiusScreen,
          excludedAnchorItemId: item.id,
        );
        _activeBypassLeadDrag = _ActiveBypassLeadDrag(
          itemId: item.id,
          leadId: leadId,
          worldPosition: desired,
          target: candidate,
          detached: true,
          blockedTargetKey: prior?.blockedTargetKey,
          blockedOrigin: prior?.blockedOrigin ?? anchorPoint,
          reconnectAllowed: false,
          historyRecorded:
              shouldRecordHistory || (prior?.historyRecorded ?? false),
        );
        _snapIndicatorScene = candidate?.point;
        return;
      }

      _setBypassLeadEndpointWorld(item, leadId, desired);
      final candidate = _findBestConnectionTarget(
        desired,
        radiusScreen: _connectionPreviewRadiusScreen,
        excludedAnchorItemId: item.id,
      );
      final priorBlockedTargetKey = prior?.blockedTargetKey;
      final priorBlockedOrigin = prior?.blockedOrigin;
      var reconnectAllowed = prior?.reconnectAllowed ?? false;
      if (!reconnectAllowed && priorBlockedOrigin != null) {
        reconnectAllowed =
            (desired - priorBlockedOrigin).distance >= reconnectReleaseDistance;
      }
      final filteredCandidate = (!reconnectAllowed &&
              priorBlockedTargetKey != null &&
              _bypassLeadTargetKey(candidate) == priorBlockedTargetKey)
          ? null
          : candidate;
      _activeBypassLeadDrag = _ActiveBypassLeadDrag(
        itemId: item.id,
        leadId: leadId,
        worldPosition: desired,
        target: filteredCandidate,
        detached: true,
        blockedTargetKey: priorBlockedTargetKey,
        blockedOrigin: priorBlockedOrigin,
        reconnectAllowed: reconnectAllowed,
        historyRecorded:
            shouldRecordHistory || (prior?.historyRecorded ?? false),
      );
      _snapIndicatorScene = filteredCandidate?.point;
    });
  }

  void _endBypassLeadDrag(_LayoutItem item, String leadId) {
    setState(() {
      final active = _activeBypassLeadDrag;
      final releaseTarget = (active != null &&
              active.itemId == item.id &&
              active.leadId == leadId &&
              active.detached)
          ? _findBestConnectionTarget(
              _resolveBypassLeadEndpointWorld(item, leadId),
              radiusScreen: _connectionReleaseRadiusScreen,
              excludedAnchorItemId: item.id,
            )
          : null;
      final filteredTarget = (!((active?.reconnectAllowed) ?? true) &&
              active?.blockedTargetKey != null &&
              _bypassLeadTargetKey(releaseTarget) == active?.blockedTargetKey)
          ? null
          : releaseTarget;
      _commitBypassLeadConnection(item, leadId, filteredTarget);
      _activeBypassLeadDrag = null;
      _interactionMode = _InteractionMode.idle;
      _snapIndicatorScene = null;
    });
    _persistWorkingLayoutSnapshot();
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
        (_resolveIronEndpoint(item, false) - _resolveIronEndpoint(item, true))
            .distance;
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

    final newPixels = (result * 6).clamp(_freeIronMinLength, 1200.0).toDouble();
    _runHistoryChange(() {
      final start = _resolveIronEndpoint(item, true);
      final end = _resolveIronEndpoint(item, false);
      final delta = end - start;
      final length = delta.distance;
      final dir = length < 1e-6
          ? const Offset(1, 0)
          : Offset(delta.dx / length, delta.dy / length);
      final newEnd = start + Offset(dir.dx * newPixels, dir.dy * newPixels);
      _storeIronEndpoints(item, start, _clampToCanvas(newEnd));
      if (_endpointIsConnected(item, false)) {
        _clearEndpointAttachment(item, false);
      }
    });
  }

  void _quickSetIronLength(double feet) {
    final item = _selectedItem;
    if (item == null ||
        !(item.type == _EquipmentType.ironHorizontal ||
            item.type == _EquipmentType.ironVertical)) return;
    final newPixels = (feet * 6).clamp(_freeIronMinLength, 1200.0).toDouble();
    _runHistoryChange(() {
      final start = _resolveIronEndpoint(item, true);
      final end = _resolveIronEndpoint(item, false);
      final delta = end - start;
      final length = delta.distance;
      final dir = length < 1e-6
          ? const Offset(1, 0)
          : Offset(delta.dx / length, delta.dy / length);
      final newEnd = start + Offset(dir.dx * newPixels, dir.dy * newPixels);
      _storeIronEndpoints(item, start, _clampToCanvas(newEnd));
      if (_endpointIsConnected(item, false)) {
        _clearEndpointAttachment(item, false);
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
      final prior = (_activeEndpointDrag != null &&
              _activeEndpointDrag!.ironId == item.id &&
              _activeEndpointDrag!.leading == leading)
          ? _activeEndpointDrag!
          : null;
      final desired = (prior?.worldPosition ?? current) + sceneDelta;
      final anchorItemId =
          int.tryParse(item.properties[_endpointAnchorItemKey(leading)] ?? '');
      final anchorSide = item.properties[_endpointAnchorSideKey(leading)];
      final isAttached =
          anchorItemId != null && anchorSide != null && anchorSide.isNotEmpty;
      final holdRadius = _sceneRadiusFromScreen(_disconnectHoldRadiusScreen);
      final detachThreshold =
          _sceneRadiusFromScreen(_disconnectThresholdScreen);
      final reconnectReleaseDistance =
          _sceneRadiusFromScreen(_sameTargetLockoutRadiusScreen);

      final shouldRecordHistory =
          !(prior?.historyRecorded ?? false) && desired != current;
      if (shouldRecordHistory) {
        _recordUndo();
      }

      if (isAttached && (prior?.detached ?? false) == false) {
        final anchorPoint = current;
        final distanceFromAnchor = (desired - anchorPoint).distance;
        _activeEndpointDrag = _ActiveEndpointDrag(
          ironId: item.id,
          leading: leading,
          worldPosition: desired,
          target: null,
          detached: false,
          blockedTargetKey: prior?.blockedTargetKey,
          blockedOrigin: prior?.blockedOrigin,
          reconnectAllowed: prior?.reconnectAllowed ?? false,
          historyRecorded:
              shouldRecordHistory || (prior?.historyRecorded ?? false),
        );
        if (distanceFromAnchor <= holdRadius) {
          _snapIndicatorScene = null;
          return;
        }
        if (distanceFromAnchor < detachThreshold) {
          _snapIndicatorScene = null;
          return;
        }

        _clearEndpointAttachment(item, leading);
        _setIronEndpointPosition(item, leading, desired);
        final snappedPoint = _ironEndpoint(item, leading);
        final candidate = _nearestEndpointSnapTarget(
          item,
          leading,
          snappedPoint,
          radiusScreen: _connectionPreviewRadiusScreen,
        );
        final target = _stabilizeEndpointSnapTarget(
          sourcePoint: snappedPoint,
          previous: prior?.target,
          candidate: candidate,
        );
        _activeEndpointDrag = _ActiveEndpointDrag(
          ironId: item.id,
          leading: leading,
          worldPosition: snappedPoint,
          target: target,
          detached: true,
          blockedTargetKey: prior?.blockedTargetKey,
          blockedOrigin: prior?.blockedOrigin ?? anchorPoint,
          reconnectAllowed: false,
          historyRecorded:
              shouldRecordHistory || (prior?.historyRecorded ?? false),
        );
        _snapIndicatorScene = target?.point;
        _reflowSnappedFittings();
        return;
      }

      _setIronEndpointPosition(item, leading, desired);
      final snappedPoint = _ironEndpoint(item, leading);
      final candidate = _nearestEndpointSnapTarget(
        item,
        leading,
        snappedPoint,
        radiusScreen: _connectionPreviewRadiusScreen,
      );
      final priorBlockedTargetKey = prior?.blockedTargetKey;
      final priorBlockedOrigin = prior?.blockedOrigin;
      var reconnectAllowed = prior?.reconnectAllowed ?? false;
      if (!reconnectAllowed && priorBlockedOrigin != null) {
        reconnectAllowed = (snappedPoint - priorBlockedOrigin).distance >=
            reconnectReleaseDistance;
      }
      final filteredCandidate = (!reconnectAllowed &&
              priorBlockedTargetKey != null &&
              _endpointSnapTargetKey(candidate) == priorBlockedTargetKey)
          ? null
          : candidate;
      final target = _stabilizeEndpointSnapTarget(
        sourcePoint: snappedPoint,
        previous: prior?.target,
        candidate: filteredCandidate,
      );
      _activeEndpointDrag = _ActiveEndpointDrag(
        ironId: item.id,
        leading: leading,
        worldPosition: snappedPoint,
        target: target,
        detached: true,
        blockedTargetKey: priorBlockedTargetKey,
        blockedOrigin: priorBlockedOrigin,
        reconnectAllowed: reconnectAllowed,
        historyRecorded:
            shouldRecordHistory || (prior?.historyRecorded ?? false),
      );
      _snapIndicatorScene = target?.point;
      _reflowSnappedFittings();
    });
  }

  void _startEndpointHandleDrag(_LayoutItem item, bool leading) {
    if (item.locked || !_isStraightIronType(item.type)) return;
    setState(() {
      _selectedEndpointLeading = leading;
      _selectedBypassHandle = null;
      _interactionMode = _InteractionMode.stretchEndpoint;
      _activeEndpointDrag = _ActiveEndpointDrag(
        ironId: item.id,
        leading: leading,
        worldPosition: _ironEndpoint(item, leading),
        target: null,
        detached: false,
        blockedTargetKey: _currentEndpointConnectionKey(item, leading),
        blockedOrigin: _ironEndpoint(item, leading),
        reconnectAllowed: false,
        historyRecorded: false,
      );
    });
  }

  String? _currentEndpointConnectionKey(_LayoutItem item, bool leading) {
    final anchorItemId =
        int.tryParse(item.properties[_endpointAnchorItemKey(leading)] ?? '');
    final anchorSide = item.properties[_endpointAnchorSideKey(leading)];
    if (anchorItemId != null && anchorSide != null && anchorSide.isNotEmpty) {
      return 'anchor:$anchorItemId:$anchorSide';
    }
    final jointId = _jointId(item, leading);
    if (jointId == null || jointId.isEmpty) return null;
    for (final other in _items) {
      if (other.id == item.id || !_isStraightIronType(other.type)) continue;
      for (final otherLeading in const <bool>[true, false]) {
        if (_jointId(other, otherLeading) == jointId) {
          return 'joint:${other.id}:${otherLeading ? 'start' : 'end'}';
        }
      }
    }
    return null;
  }

  String? _endpointSnapTargetKey(_EndpointSnapTarget? target) {
    if (target == null) return null;
    if (target.endpoint != null) {
      return 'joint:${target.endpoint!.itemId}:${target.endpoint!.leading ? 'start' : 'end'}';
    }
    if (target.equipment != null) {
      return 'anchor:${target.equipment!.itemId}:${target.equipment!.side}';
    }
    if (target.bypass != null) {
      return 'anchor:${target.bypass!.itemId}:${target.bypass!.side}';
    }
    return null;
  }

  void _updateEndpointHandleDrag(_LayoutItem item, bool leading, Offset delta) {
    _stretchStraightIronByScreenDelta(item, delta, leading);
  }

  void _endEndpointHandleDrag(_LayoutItem item, bool leading) {
    setState(() {
      final active = _activeEndpointDrag;
      final releaseTarget = (active != null &&
              active.ironId == item.id &&
              active.leading == leading &&
              active.detached)
          ? _nearestEndpointSnapTarget(
              item,
              leading,
              _ironEndpoint(item, leading),
              radiusScreen: _connectionReleaseRadiusScreen,
            )
          : null;
      final filteredTarget = (!((active?.reconnectAllowed) ?? true) &&
              active?.blockedTargetKey != null &&
              _endpointSnapTargetKey(releaseTarget) == active?.blockedTargetKey)
          ? null
          : releaseTarget;
      if (filteredTarget != null) {
        _commitIronEndpointConnection(item, leading, target: filteredTarget);
      }
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
    final leadId = _selectedBypassLeadId;
    if (item == null) return;
    _runHistoryChange(() {
      if (leading != null) {
        _clearEndpointAttachment(item, leading);
        _selectedEndpointLeading = null;
      } else if (item.type == _EquipmentType.bypass && leadId != null) {
        _setBypassLeadTarget(item, leadId,
            kind: null, targetItemId: null, side: null);
        _selectedBypassLeadId = null;
      }
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
      if (candidate == null) return;
      final iron = _findItemById(candidate.ironId);
      if (iron == null) return;
      final center = _attachmentSpineCenterWorld(item, topLeft: desired);
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
      final active = _activeEndpointDrag;
      if (active == null ||
          active.ironId != selected.id ||
          active.leading != _selectedEndpointLeading ||
          !active.detached) {
        return;
      }
      _recordUndo();
      _commitIronEndpointConnection(selected, _selectedEndpointLeading!);
      return;
    }

    if (selected.type == _EquipmentType.bypass &&
        _selectedBypassLeadId != null &&
        _activeBypassLeadDrag != null) {
      final active = _activeBypassLeadDrag!;
      if (active.itemId != selected.id ||
          active.leadId != _selectedBypassLeadId ||
          !active.detached) {
        return;
      }
      _recordUndo();
      _commitBypassLeadConnection(
          selected, _selectedBypassLeadId!, active.target);
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

    if (_autoConnectMode) {
      _rebuildSelectionCandidatesAt(clampedPoint);
      if (_lastSelectionCandidateIds.isEmpty) {
        setState(() => _autoConnectDestinationItemId = null);
        return;
      }
      final tappedItem = _findItemById(_lastSelectionCandidateIds.first);
      final source = _pendingConnectIronSourceTarget;
      if (tappedItem == null || source == null) {
        return;
      }
      final nearest = _nearestPortOnItem(tappedItem, clampedPoint);
      final nearestDistance = nearest == null
          ? double.infinity
          : _screenDistanceBetweenScenePoints(clampedPoint, nearest.point);
      if (nearest != null && nearestDistance <= 10.0) {
        if (_connectionTargetsEqual(nearest, source)) {
          return;
        }
        if (_connectionTargetAvailable(nearest) &&
            _connectionTargetsCompatible(source, nearest)) {
          _handleAutoConnectDestinationTarget(nearest);
          return;
        }
        _showPortUnavailableMessage('That connection point is unavailable.');
        return;
      }
      setState(() => _autoConnectDestinationItemId = tappedItem.id);
      return;
    }

    if (!_drawIronMode) {
      _rebuildSelectionCandidatesAt(clampedPoint);
      if (_lastSelectionCandidateIds.isNotEmpty) {
        _selectOnly(_lastSelectionCandidateIds.first);
      } else if (_selectedPortForSelectedItem() != null && !_autoConnectMode) {
        _clearPortSelection();
      } else if (_selectedIds.isNotEmpty) {
        _clearSelection();
      }
      return;
    }
    if (_drawIronStartTarget == null) {
      final startTarget = _findBestConnectionTarget(
        clampedPoint,
        radiusScreen: _connectionPreviewRadiusScreen,
      );
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

  void _handleAutoConnectTapOnItem(_LayoutItem item, Offset scenePoint) {
    if (!_autoConnectMode) return;
    final source = _pendingConnectIronSourceTarget;
    if (source == null) return;
    final availablePorts = _availablePortsForItem(item)
        .where((port) => !_connectionTargetsEqual(port, source))
        .toList(growable: false);
    final nearest = _nearestPortOnItem(item, scenePoint);
    final nearestDistance = nearest == null
        ? double.infinity
        : _screenDistanceBetweenScenePoints(scenePoint, nearest.point);
    if (nearest != null && nearestDistance <= 10.0) {
      if (_connectionTargetsEqual(nearest, source)) {
        return;
      }
      if (_connectionTargetAvailable(nearest) &&
          _connectionTargetsCompatible(source, nearest)) {
        _handleAutoConnectDestinationTarget(nearest);
        return;
      }
      _showPortUnavailableMessage('That connection point is unavailable.');
      return;
    }
    if (_autoConnectDestinationItemId == item.id && availablePorts.isNotEmpty) {
      _ConnectionTarget? best;
      var bestDistance = double.infinity;
      for (final port in availablePorts) {
        final distance =
            _screenDistanceBetweenScenePoints(scenePoint, port.point);
        if (distance < bestDistance) {
          bestDistance = distance;
          best = port;
        }
      }
      if (best != null) {
        _handleAutoConnectDestinationTarget(best);
        return;
      }
    }
    setState(() => _autoConnectDestinationItemId = item.id);
  }

  void _updateDrawIronPreview(Offset scenePoint) {
    if (!_drawIronMode || _drawIronStartTarget == null) return;
    final clamped = _clampToCanvas(scenePoint);
    final hover = _findBestConnectionTarget(
      clamped,
      radiusScreen: _connectionPreviewRadiusScreen,
    );
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
      final start = _findBestConnectionTarget(
        scenePoint,
        radiusScreen: _connectionPreviewRadiusScreen,
      );
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
    final endTarget = _findBestConnectionTarget(
      clamped,
      radiusScreen: _connectionPreviewRadiusScreen,
    );
    final startPoint = start.point;
    final endPoint = endTarget?.point ?? clamped;
    final dx = endPoint.dx - startPoint.dx;
    final dy = endPoint.dy - startPoint.dy;
    if (dx.abs() < 12 && dy.abs() < 12) {
      return;
    }

    final startClamped = _clampToCanvas(startPoint);
    final endClamped = _clampToCanvas(endPoint);

    _runHistoryChange(() {
      final id = _nextId++;
      final newIron = _LayoutItem(
        id: id,
        type: _EquipmentType.ironHorizontal,
        x: math.min(startClamped.dx, endClamped.dx),
        y: math.min(startClamped.dy, endClamped.dy),
        width: math.max(1.0, (endClamped.dx - startClamped.dx).abs()),
        height: math.max(1.0, (endClamped.dy - startClamped.dy).abs()),
        properties: <String, String>{
          'ironSize': _drawIronSize,
          _freeAngleIronKey: 'true',
          _freeAngleStartXKey: startClamped.dx.toStringAsFixed(4),
          _freeAngleStartYKey: startClamped.dy.toStringAsFixed(4),
          _freeAngleEndXKey: endClamped.dx.toStringAsFixed(4),
          _freeAngleEndYKey: endClamped.dy.toStringAsFixed(4),
        },
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

  Offset _portOutwardVector(_ConnectionTarget target) {
    if (target.kind == _ConnectionTargetKind.ironEndpoint) {
      final item =
          target.ironItemId == null ? null : _findItemById(target.ironItemId!);
      if (item == null || !_isStraightIronType(item.type)) return Offset.zero;
      final start = _resolveIronEndpoint(item, true);
      final end = _resolveIronEndpoint(item, false);
      final delta = end - start;
      final length = delta.distance;
      if (length < 1e-6) return const Offset(1, 0);
      final dir = Offset(delta.dx / length, delta.dy / length);
      return target.ironLeading == true ? Offset(-dir.dx, -dir.dy) : dir;
    }

    final item = target.equipmentItemId == null
        ? null
        : _findItemById(target.equipmentItemId!);
    if (item == null || target.anchorId == null || target.anchorId!.isEmpty) {
      return Offset.zero;
    }
    final anchorPoint = _equipmentAnchorPointOrNull(item, target.anchorId!);
    if (anchorPoint == null) return Offset.zero;
    final center = Offset(item.x + item.width / 2, item.y + item.height / 2);
    final vector = anchorPoint - center;
    if (vector.distance <= 1e-6) return Offset.zero;
    return Offset(vector.dx / vector.distance, vector.dy / vector.distance);
  }

  Offset _normalizedDirection(Offset value) {
    final length = value.distance;
    if (length <= 1e-6) {
      return const Offset(1, 0);
    }
    return Offset(value.dx / length, value.dy / length);
  }

  Offset? _fittingAnchorLocalPoint(_EquipmentType type, String side) {
    final prototype = _LayoutItem(
      id: -1,
      type: type,
      x: 0,
      y: 0,
      width: type.defaultWidth,
      height: type.defaultHeight,
    );
    return _equipmentAnchorPointOrNull(prototype, side);
  }

  Offset _fittingSideOutwardDirection(_EquipmentType type, String side) {
    final anchor = _fittingAnchorLocalPoint(type, side);
    if (anchor == null) return const Offset(1, 0);
    final center = Offset(type.defaultWidth / 2, type.defaultHeight / 2);
    return _normalizedDirection(anchor - center);
  }

  void _createStraightIronFromPort(_ConnectionTarget source) {
    final vector = _portOutwardVector(source);
    if (vector == Offset.zero) return;
    const leadLength = _portLeadDefaultLength;
    final dir = _normalizedDirection(vector);
    final start = _clampToCanvas(source.point);
    final end = _clampToCanvas(
      start + Offset(dir.dx * leadLength, dir.dy * leadLength),
    );

    _runHistoryChange(() {
      final id = _nextId++;
      final newIron = _LayoutItem(
        id: id,
        type: _EquipmentType.ironHorizontal,
        x: math.min(start.dx, end.dx),
        y: math.min(start.dy, end.dy),
        width: math.max(1.0, (end.dx - start.dx).abs()),
        height: math.max(1.0, (end.dy - start.dy).abs()),
        properties: <String, String>{
          'ironSize': _drawIronSize,
          _freeAngleIronKey: 'true',
          _freeAngleStartXKey: start.dx.toStringAsFixed(4),
          _freeAngleStartYKey: start.dy.toStringAsFixed(4),
          _freeAngleEndXKey: end.dx.toStringAsFixed(4),
          _freeAngleEndYKey: end.dy.toStringAsFixed(4),
        },
      );
      _items.add(newIron);
      _applyConnectionTargetToIronEndpoint(newIron, true, source);
      _selectedId = id;
      _selectedIds
        ..clear()
        ..add(id);
      _selectedEndpointLeading = false;
      _selectedPortTarget = null;
      _pendingConnectIronSourceTarget = null;
      _autoConnectDestinationItemId = null;
      _autoConnectMode = false;
      _drawIronMode = false;
      _interactionMode = _InteractionMode.idle;
      _snapIndicatorScene = null;
      _drawIronStartTarget = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      _pendingContinueIronTarget = null;
      _pendingContinueIronSize = null;
    });
    _appendHistoryEntry('Added iron');
  }

  void _createFittingFromPort(
    _ConnectionTarget source, {
    required bool tee,
  }) {
    final sourceDirection = _normalizedDirection(_portOutwardVector(source));
    final desiredAttachDirection =
        Offset(-sourceDirection.dx, -sourceDirection.dy);
    final candidateTypes = tee
        ? const <_EquipmentType>[
            _EquipmentType.teeUp,
            _EquipmentType.teeRight,
            _EquipmentType.teeDown,
            _EquipmentType.teeLeft,
          ]
        : const <_EquipmentType>[
            _EquipmentType.elbowUpRight,
            _EquipmentType.elbowRightDown,
            _EquipmentType.elbowDownLeft,
            _EquipmentType.elbowLeftUp,
          ];
    final attachSide = tee ? 'branch' : 'inlet';

    _EquipmentType bestType = candidateTypes.first;
    var bestScore = -double.infinity;
    for (final type in candidateTypes) {
      final outward = _fittingSideOutwardDirection(type, attachSide);
      final score = (outward.dx * desiredAttachDirection.dx) +
          (outward.dy * desiredAttachDirection.dy);
      if (score > bestScore) {
        bestScore = score;
        bestType = type;
      }
    }

    final anchorPoint = _fittingAnchorLocalPoint(bestType, attachSide);
    if (anchorPoint == null) return;
    final canvasSize = _virtualCanvasSize;
    final rawX = source.point.dx - anchorPoint.dx;
    final rawY = source.point.dy - anchorPoint.dy;

    _runHistoryChange(() {
      final id = _nextId++;
      final fitting = _LayoutItem(
        id: id,
        type: bestType,
        x: rawX.clamp(0.0, canvasSize.width - bestType.defaultWidth),
        y: rawY.clamp(0.0, canvasSize.height - bestType.defaultHeight),
        width: bestType.defaultWidth,
        height: bestType.defaultHeight,
        properties: <String, String>{'ironSize': _drawIronSize},
      );
      _items.add(fitting);

      if (source.kind == _ConnectionTargetKind.equipmentAnchor) {
        final sourceItemId = source.equipmentItemId;
        final sourceSide = source.anchorId;
        if (sourceItemId != null &&
            sourceSide != null &&
            sourceSide.isNotEmpty) {
          _setFittingAnchor(
            fitting,
            attachSide,
            anchorItemId: sourceItemId,
            anchorSide: sourceSide,
          );
        }
      } else {
        final sourceIron = source.ironItemId == null
            ? null
            : _findItemById(source.ironItemId!);
        final sourceLeading = source.ironLeading;
        if (sourceIron != null &&
            sourceLeading != null &&
            _isStraightIronType(sourceIron.type)) {
          _setFittingAnchor(
            fitting,
            attachSide,
            anchorItemId: sourceIron.id,
            anchorSide: sourceLeading ? 'start' : 'end',
          );
          _attachIronEndpointToFitting(
            sourceIron,
            sourceLeading,
            fitting,
            attachSide,
          );
        }
      }

      _reflowSnappedFittings();
      _selectedId = id;
      _selectedIds
        ..clear()
        ..add(id);
      _selectedEndpointLeading = null;
      _selectedPortTarget = null;
      _pendingConnectIronSourceTarget = null;
      _autoConnectDestinationItemId = null;
      _autoConnectMode = false;
      _drawIronMode = false;
      _interactionMode = _InteractionMode.idle;
      _drawIronStartTarget = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      _pendingContinueIronTarget = null;
      _pendingContinueIronSize = null;
      _snapIndicatorScene = null;
    });
    _appendHistoryEntry(tee ? 'Added tee' : 'Added 90° fitting');
  }

  void _createNinetyFromPort(_ConnectionTarget source) {
    _createFittingFromPort(source, tee: false);
  }

  void _createTeeFromPort(_ConnectionTarget source) {
    _createFittingFromPort(source, tee: true);
  }

  void _createIronBetweenPorts(
    _ConnectionTarget start,
    _ConnectionTarget end,
  ) {
    final startPoint = _clampToCanvas(start.point);
    final endPoint = _clampToCanvas(end.point);
    final minX = math.min(startPoint.dx, endPoint.dx);
    final minY = math.min(startPoint.dy, endPoint.dy);
    final maxX = math.max(startPoint.dx, endPoint.dx);
    final maxY = math.max(startPoint.dy, endPoint.dy);
    final width = math.max(1.0, maxX - minX);
    final height = math.max(1.0, maxY - minY);
    final canvasSize = _virtualCanvasSize;

    _runHistoryChange(() {
      final id = _nextId++;
      final newIron = _LayoutItem(
        id: id,
        type: _EquipmentType.ironHorizontal,
        x: _snap(minX).clamp(0.0, canvasSize.width - width),
        y: _snap(minY).clamp(0.0, canvasSize.height - height),
        width: width,
        height: height,
        properties: <String, String>{
          'ironSize': _drawIronSize,
          _freeAngleIronKey: 'true',
          _freeAngleStartXKey: startPoint.dx.toStringAsFixed(4),
          _freeAngleStartYKey: startPoint.dy.toStringAsFixed(4),
          _freeAngleEndXKey: endPoint.dx.toStringAsFixed(4),
          _freeAngleEndYKey: endPoint.dy.toStringAsFixed(4),
        },
      );
      _items.add(newIron);
      _applyConnectionTargetToIronEndpoint(newIron, true, start);
      _applyConnectionTargetToIronEndpoint(newIron, false, end);
      _selectedId = id;
      _selectedIds
        ..clear()
        ..add(id);
      _selectedEndpointLeading = null;
      _selectedPortTarget = null;
      _pendingConnectIronSourceTarget = null;
      _autoConnectDestinationItemId = null;
      _autoConnectMode = false;
      _drawIronMode = false;
      _interactionMode = _InteractionMode.idle;
      _drawIronStartTarget = null;
      _drawIronHoverTarget = null;
      _drawIronPointerScene = null;
      _pendingContinueIronTarget = _ConnectionTarget(
        kind: _ConnectionTargetKind.ironEndpoint,
        point: _ironEndpoint(newIron, false),
        distance: 0,
        isExactHit: true,
        ironItemId: id,
        ironLeading: false,
      );
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
    Map<String, String>? initialProperties,
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
        properties: Map<String, String>.from(initialProperties ?? const {}),
      );
      if (_isStraightIronType(item.type)) {
        final start = _storedIronEndpoint(item, true);
        final end = _storedIronEndpoint(item, false);
        _storeIronEndpoints(item, _clampToCanvas(start), _clampToCanvas(end));
      }
      if (item.type == _EquipmentType.bypass) {
        _ensureBypassLeadData(item);
      }
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
    bool horizontal = true,
    required String size,
  }) {
    final isWide = MediaQuery.of(context).size.width >= 780;
    final center = _visibleCanvasPlacementCenter(isWide: isWide);
    const length = 180.0;
    final start = horizontal
        ? Offset(center.dx - (length / 2), center.dy)
        : Offset(center.dx, center.dy - (length / 2));
    final end = horizontal
        ? Offset(center.dx + (length / 2), center.dy)
        : Offset(center.dx, center.dy + (length / 2));
    final clampedStart = _clampToCanvas(start);
    final clampedEnd = _clampToCanvas(end);
    _runHistoryChange(() {
      final id = _nextId++;
      final item = _LayoutItem(
        id: id,
        type: _EquipmentType.ironHorizontal,
        x: math.min(clampedStart.dx, clampedEnd.dx),
        y: math.min(clampedStart.dy, clampedEnd.dy),
        width: math.max(1.0, (clampedEnd.dx - clampedStart.dx).abs()),
        height: math.max(1.0, (clampedEnd.dy - clampedStart.dy).abs()),
        properties: <String, String>{
          'ironSize': size,
          _freeAngleIronKey: 'true',
          _freeAngleStartXKey: clampedStart.dx.toStringAsFixed(4),
          _freeAngleStartYKey: clampedStart.dy.toStringAsFixed(4),
          _freeAngleEndXKey: clampedEnd.dx.toStringAsFixed(4),
          _freeAngleEndYKey: clampedEnd.dy.toStringAsFixed(4),
        },
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
    if (_lastSelectionCandidateIds.contains(id)) {
      _lastSelectionCandidateIndex = _lastSelectionCandidateIds.indexOf(id);
    } else {
      _lastSelectionCandidateIds = <int>[id];
      _lastSelectionCandidateIndex = 0;
    }
    setState(() {
      _selectedId = id;
      _selectedEndpointLeading = null;
      _selectedBypassHandle = null;
      _selectedBypassLeadId = null;
      _selectedIds
        ..clear()
        ..add(id);
      _selectedPortTarget = null;
      _autoConnectMode = false;
      _autoConnectDestinationItemId = null;
      _pendingConnectIronSourceTarget = null;
    });
  }

  void _toggleSelection(int id) {
    _stopArrowRepeat();
    _lastSelectionCandidateIds = <int>[id];
    _lastSelectionCandidateIndex = 0;
    setState(() {
      _selectedEndpointLeading = null;
      _selectedBypassHandle = null;
      _selectedBypassLeadId = null;
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
    _lastSelectionCandidateIds = <int>[];
    _lastSelectionCandidateIndex = 0;
    setState(() {
      _selectedId = null;
      _selectedEndpointLeading = null;
      _selectedBypassHandle = null;
      _selectedBypassLeadId = null;
      _selectedPortTarget = null;
      _autoConnectMode = false;
      _autoConnectDestinationItemId = null;
      _pendingConnectIronSourceTarget = null;
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
          rotationDegrees: original.rotationDegrees,
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
        rotationDegrees: item.rotationDegrees,
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

    // Persist the cleared working canvas immediately so stale layouts
    // are not restored after app restart.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'wellwerks_layout_designer_v2', jsonEncode(_payload()));
    await prefs.remove('wellwerks_layout_designer_v1');
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
      for (final item in _items) {
        if (_isStraightIronType(item.type)) {
          final start = _storedIronEndpoint(item, true);
          final end = _storedIronEndpoint(item, false);
          _storeIronEndpoints(item, start, end);
        }
        if (item.type == _EquipmentType.bypass) {
          _ensureBypassLeadData(item);
        }
        if (_isElbowFittingType(item.type)) {
          _clearInlineParentAttachment(item);
        }
        if (_isInlineFittingType(item.type)) {
          final parentIron = _inlineParentIron(item);
          final parentT = _inlineParentT(item);
          if (parentIron == null || parentT == null) {
            _clearInlineParentAttachment(item);
          } else {
            _setInlineParentAttachment(
              item,
              parentIron,
              parentT,
              segmentId: _inlineAttachedSegmentId(item),
            );
          }
        }
        for (final leading in <bool>[true, false]) {
          final anchorItemId = int.tryParse(
              item.properties[_endpointAnchorItemKey(leading)] ?? '');
          final anchorSide = item.properties[_endpointAnchorSideKey(leading)];
          if (anchorItemId == null ||
              anchorSide == null ||
              anchorSide.isEmpty) {
            continue;
          }
          final anchorItem = _findItemById(anchorItemId);
          if (anchorItem == null) {
            item.properties.remove(_endpointAnchorItemKey(leading));
            item.properties.remove(_endpointAnchorSideKey(leading));
            continue;
          }
          if (anchorItem.type == _EquipmentType.bypass) {
            final canonical = _normalizedBypassPortId(anchorSide);
            if (canonical == null ||
                _equipmentAnchorPointOrNull(anchorItem, canonical) == null) {
              item.properties.remove(_endpointAnchorItemKey(leading));
              item.properties.remove(_endpointAnchorSideKey(leading));
            } else {
              item.properties[_endpointAnchorSideKey(leading)] = canonical;
            }
          } else {
            final canonical = _normalizedAnchorSide(anchorItem, anchorSide);
            if (_equipmentAnchorPointOrNull(anchorItem, canonical) == null) {
              item.properties.remove(_endpointAnchorItemKey(leading));
              item.properties.remove(_endpointAnchorSideKey(leading));
            } else {
              item.properties[_endpointAnchorSideKey(leading)] = canonical;
            }
          }
        }

        if (_isFittingEndpointConnectableType(item.type)) {
          // Only reposition from the first resolvable anchor. Correcting
          // for every connected side in sequence would shift the item once
          // per side, silently undoing the alignment of any side handled
          // just before it (visible as connections detaching after undo).
          var repositioned = false;
          for (final side in _fittingEndpointSides(item)) {
            final anchorItemId = int.tryParse(
                item.properties[_fittingAnchorItemKey(side)] ?? '');
            final anchorSide = item.properties[_fittingAnchorSideKey(side)];
            if (anchorItemId == null ||
                anchorSide == null ||
                anchorSide.isEmpty) {
              continue;
            }
            final anchorItem = _findItemById(anchorItemId);
            final anchorPoint = anchorItem == null
                ? null
                : _equipmentAnchorPointOrNull(anchorItem, anchorSide);
            if (anchorPoint == null) {
              _setFittingAnchor(item, side,
                  anchorItemId: null, anchorSide: null);
              continue;
            }
            if (repositioned) continue;
            final currentPoint = _equipmentAnchorPointOrNull(item, side);
            if (currentPoint == null) continue;
            final delta = anchorPoint - currentPoint;
            item.x += delta.dx;
            item.y += delta.dy;
            repositioned = true;
          }
        }
      }
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
      _selectedPortTarget = null;
      _autoConnectMode = false;
      _autoConnectDestinationItemId = null;
      _pendingConnectIronSourceTarget = null;
      _reflowSnappedFittings();
    });
  }

  Widget _activeJobBanner() {
    final scheme = Theme.of(context).colorScheme;
    final activeJob = _activeJob;
    if (activeJob == null) {
      return Card(
        margin: EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Active Job',
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'No active job found. Start a job first so saved layout drawings can attach to the current job.',
                style: TextStyle(color: Color(0xFFB0B0B0)),
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
            Text(
              'Active Job',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              activeJob.company.trim().isEmpty
                  ? 'No company entered'
                  : activeJob.company,
              style: TextStyle(
                color: scheme.primary,
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        '$label: ${value.trim().isEmpty ? 'Not entered' : value.trim()}',
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
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
          rotationDegrees: item.rotationDegrees,
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

  WellWerksLayoutInterchange _currentInterchangeModel() {
    _commitPendingSelectionConnections();
    return LayoutInterchangeCodec.fromDesignerPayload(
      _payload(),
      canvasWidth: _virtualCanvasSize.width,
      canvasHeight: _virtualCanvasSize.height,
      showGrid: _showGrid,
    );
  }

  String _defaultExchangeFileName() {
    final base = _layoutName.text.trim().isEmpty
        ? LayoutExportService.fallbackFileName
        : _layoutName.text.trim();
    return _layoutExportService.sanitizeFileName(base);
  }

  String _fileNameWithExtension(String raw, String extension) {
    return _layoutExportService.fileNameWithExtension(raw, extension);
  }

  Rect _shareOriginForContext(BuildContext sourceContext) {
    final sourceBox = sourceContext.findRenderObject() as RenderBox?;
    if (sourceBox != null) {
      return sourceBox.localToGlobal(Offset.zero) & sourceBox.size;
    }
    final screenBox = context.findRenderObject() as RenderBox?;
    if (screenBox != null) {
      return screenBox.localToGlobal(Offset.zero) & screenBox.size;
    }
    return const Rect.fromLTWH(0, 0, 1, 1);
  }

  Future<void> _shareLayoutExport(
    LayoutExportArtifact artifact, {
    required BuildContext sourceContext,
  }) async {
    final shareOrigin = _shareOriginForContext(sourceContext);
    final exportedFile =
        await _layoutExportService.writeTemporaryFile(artifact);
    final exists = await exportedFile.exists();
    if (!exists) {
      throw const LayoutExportException(
        'The export file could not be written.',
      );
    }
    final length = await exportedFile.length();
    if (length <= 0) {
      throw const LayoutExportException(
        'The export file could not be written.',
      );
    }

    final result = await Share.shareXFiles(
      <XFile>[
        XFile(
          exportedFile.path,
          mimeType: artifact.mimeType,
          name: artifact.fileName,
        ),
      ],
      subject: artifact.shareSubject,
      text: artifact.shareText,
      sharePositionOrigin: shareOrigin,
    );
    if (result.status == ShareResultStatus.unavailable) {
      throw const LayoutExportException(
        'The iOS share sheet could not be opened.',
      );
    }
  }

  Future<void> _performLayoutExport(
    _LayoutExportRequest request, {
    required BuildContext sourceContext,
  }) async {
    final model = _currentInterchangeModel();
    final artifact = switch (request.format) {
      LayoutExportFormat.visioSvg => _layoutExportService.buildSvgArtifact(
          model,
          requestedFileName: request.fileName,
        ),
      LayoutExportFormat.visioToolkit =>
        _layoutExportService.buildVisioToolkitArtifact(
          requestedFileName: request.fileName,
        ),
      LayoutExportFormat.wellWerksEditable =>
        _layoutExportService.buildEditableArtifact(
          model,
          requestedFileName: request.fileName,
        ),
    };
    await _shareLayoutExport(artifact, sourceContext: sourceContext);
  }

  Future<void> _showExportLayoutDialog() async {
    final controller = TextEditingController(text: _defaultExchangeFileName());
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var isExporting = false;
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> runExport(LayoutExportFormat format) async {
              if (isExporting) return;
              final messenger = ScaffoldMessenger.of(this.context);
              FocusScope.of(dialogContext).unfocus();
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() => isExporting = true);
              try {
                await _performLayoutExport(
                  _LayoutExportRequest(
                    format: format,
                    fileName: controller.text,
                  ),
                  sourceContext: dialogContext,
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      switch (format) {
                        LayoutExportFormat.visioSvg =>
                          'Layout exported as Microsoft Visio SVG.',
                        LayoutExportFormat.visioToolkit =>
                          'WellWerks Visio Toolkit exported.',
                        LayoutExportFormat.wellWerksEditable =>
                          'Layout exported as WellWerks editable file.',
                      },
                    ),
                  ),
                );
              } on LayoutExportException catch (error, stackTrace) {
                debugPrint('Layout export failed: ${error.message}');
                debugPrintStack(stackTrace: stackTrace);
                if (!mounted) return;
                messenger.showSnackBar(SnackBar(content: Text(error.message)));
              } catch (error, stackTrace) {
                debugPrint('Unexpected layout export failure: $error');
                debugPrintStack(stackTrace: stackTrace);
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('The iOS share sheet could not be opened.'),
                  ),
                );
              } finally {
                if (dialogContext.mounted) {
                  setState(() => isExporting = false);
                }
              }
            }

            return AlertDialog(
              title: const Text('Export Layout'),
              content: SizedBox(
                width: _dialogWidth(dialogContext, max: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      enabled: !isExporting,
                      decoration: const InputDecoration(
                        labelText: 'File Name',
                        hintText: 'Rig Up',
                      ),
                      onSubmitted: (_) {},
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: isExporting
                          ? null
                          : () =>
                              runExport(LayoutExportFormat.wellWerksEditable),
                      icon: isExporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.data_object),
                      label: Text(
                        isExporting
                            ? 'Exporting...'
                            : 'WellWerks Editable File',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: _gold,
                        foregroundColor: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: isExporting
                          ? null
                          : () => runExport(LayoutExportFormat.visioSvg),
                      icon: const Icon(Icons.draw),
                      label: const Text('Microsoft Visio SVG'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: isExporting
                          ? null
                          : () => runExport(LayoutExportFormat.visioToolkit),
                      icon: const Icon(Icons.folder_zip),
                      label: const Text('WellWerks Visio Toolkit'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isExporting ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }

  Future<bool> _confirmLayoutImport(String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Layout'),
        content: Text(
          'Importing $fileName will replace the current canvas. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: _gold),
            child: const Text('Import', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _showUnsupportedSvgDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsupported SVG'),
        content: const Text(
          'This SVG does not contain editable WellWerks layout data.',
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

  Future<void> _showImportLayoutDialog() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'WellWerks Layout Files',
            extensions: <String>['wwlayout', 'json', 'svg'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      final confirmed = await _confirmLayoutImport(file.name);
      if (!confirmed || !mounted) return;

      final source = await file.readAsString();
      final lowerName = file.name.toLowerCase();
      final model = lowerName.endsWith('.svg')
          ? LayoutInterchangeCodec.decodeVisioSvg(source)
          : LayoutInterchangeCodec.decodeWellWerksJson(source);
      final payload = LayoutInterchangeCodec.toDesignerPayload(model);
      _recordUndo();
      _applyPayload(payload);
      await _persistWorkingLayoutSnapshot();
      _appendHistoryEntry('Imported layout');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported layout: ${model.layoutName}')),
      );
    } on LayoutInterchangeException catch (error) {
      if (error.message
          .contains('does not contain editable WellWerks layout data')) {
        await _showUnsupportedSvgDialog();
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to import the selected file.')),
      );
    }
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

  List<_EquipmentType> get _completionsTypes => const [
        _EquipmentType.coilTubingUnit,
        _EquipmentType.mixingPlant,
        _EquipmentType.pump,
        _EquipmentType.crane,
        _EquipmentType.lightPlant,
        _EquipmentType.wireline,
        _EquipmentType.dateVan,
        _EquipmentType.nitrogen,
        _EquipmentType.sandX,
        _EquipmentType.superLoop,
        _EquipmentType.sandXSuperLoopCombo,
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
        backgroundColor: Theme.of(context).cardColor,
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
                      color: Theme.of(context).cardColor,
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
        if (item.type.isCompletions) {
          item.rotationDegrees = (item.rotationDegrees + 15) % 360;
          item.rotationTurns = (item.rotationDegrees ~/ 90) % 4;
        } else {
          item.rotationTurns = (item.rotationTurns + 1) % 4;
          item.rotationDegrees = item.rotationTurns * 90.0;
        }
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
    final rotationController = item.type.isCompletions
        ? TextEditingController(
            text: item.rotationDegrees.toStringAsFixed(0),
          )
        : null;
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
                if (rotationController != null) ...[
                  TextField(
                    controller: rotationController,
                    decoration: const InputDecoration(
                      labelText: 'Rotation Degrees',
                      helperText: '0 to 359 degrees',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 10),
                ],
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
        if (rotationController != null) {
          final rotation = double.tryParse(rotationController.text.trim());
          if (rotation != null) {
            item.rotationDegrees = rotation % 360;
            item.rotationTurns = (item.rotationDegrees ~/ 90) % 4;
          }
        }
      });
    }
    rotationController?.dispose();
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
          'Completions', _DrawerLibrarySection.completions),
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
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHigh
                  .withValues(alpha: 0.5),
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

  void _addLabeledEquipmentFromLibrary(
    _EquipmentType type, {
    required String label,
    Map<String, String>? properties,
  }) {
    _addItem(
      type,
      initialProperties: <String, String>{
        'displayLabel': label,
        ...?properties,
      },
    );
  }

  Widget _equipmentVariantButton({
    required bool isMobile,
    required String label,
    required _EquipmentType type,
    Map<String, String>? properties,
    double? iconSize,
    double? buttonWidth,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final narrowMobile = isMobile && screenWidth < 420;
    final resolvedButtonWidth = buttonWidth ??
        (narrowMobile
            ? (screenWidth - 56).clamp(220.0, 360.0)
            : (isMobile ? 162.0 : 138.0));
    return SizedBox(
      width: resolvedButtonWidth,
      child: FilledButton.icon(
        onPressed: () => _addLabeledEquipmentFromLibrary(
          type,
          label: label,
          properties: properties,
        ),
        icon: _EquipmentSymbol(
          type: type,
          color: _gold,
          size: iconSize ?? 18,
          symbolKey: ValueKey<String>('library-symbol-${type.name}-$label'),
        ),
        label: Text(label, maxLines: 2, overflow: TextOverflow.visible),
        style: _compactFilledStyle(highlighted: true),
      ),
    );
  }

  Widget _completionsVariantButton({
    required bool isMobile,
    required String label,
    required _EquipmentType type,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final narrowMobile = isMobile && screenWidth < 420;
    final width = narrowMobile
        ? (screenWidth - 56).clamp(220.0, 360.0)
        : (isMobile ? 196.0 : 184.0);
    return SizedBox(
      width: width,
      child: FilledButton(
        onPressed: () => _addLabeledEquipmentFromLibrary(type, label: label),
        style: _compactFilledStyle(highlighted: true).copyWith(
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _EquipmentSymbol(
              type: type,
              color: _gold,
              size: 34,
              symbolKey: ValueKey<String>('library-symbol-${type.name}-$label'),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _equipmentCategoryBody({required bool isMobile}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Equipment',
          style: TextStyle(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'Wellhead',
              type: _EquipmentType.wellhead,
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'ESD Valve',
              type: _EquipmentType.esdValve,
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: '2" Choke Manifold',
              type: _EquipmentType.chokeManifold,
              properties: const <String, String>{'chokeSize': '2'},
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: '3" Choke Manifold',
              type: _EquipmentType.chokeManifold,
              properties: const <String, String>{'chokeSize': '3'},
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'Double Plug Catcher',
              type: _EquipmentType.plugCatcher,
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'Flowback Tank',
              type: _EquipmentType.flowbackTank,
              properties: const <String, String>{
                'equipmentVariant': 'flowbackStandard'
              },
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'Flowback Tank with Gas Busters',
              type: _EquipmentType.flowbackTank,
              properties: const <String, String>{
                'equipmentVariant': 'flowbackGasBusters'
              },
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'Half Flowback Tank',
              type: _EquipmentType.flowbackTank,
              properties: const <String, String>{
                'equipmentVariant': 'flowbackHalf'
              },
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'Quarter Flowback Tank',
              type: _EquipmentType.flowbackTank,
              properties: const <String, String>{
                'equipmentVariant': 'flowbackQuarter'
              },
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'Test Separator',
              type: _EquipmentType.testSeparator,
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'Facilities',
              type: _EquipmentType.facilities,
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'Line Heater',
              type: _EquipmentType.lineHeater,
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'Cyclonic Sand Separator',
              type: _EquipmentType.cyclonicSandSep,
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'Spherical Sand Separator',
              type: _EquipmentType.sphericalSandSep,
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'Production Tank',
              type: _EquipmentType.productionTank,
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'Flare',
              type: _EquipmentType.flare,
            ),
            _equipmentVariantButton(
              isMobile: isMobile,
              label: 'Compressor',
              type: _EquipmentType.compressor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _completionsCategoryBody({required bool isMobile}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Completions',
          style: TextStyle(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final type in _completionsTypes)
              _completionsVariantButton(
                isMobile: isMobile,
                label: type.label,
                type: type,
              ),
          ],
        ),
      ],
    );
  }

  Widget _libraryCategoryBody({required bool isMobile}) {
    List<_EquipmentType> types;
    var outlined = false;
    String title;

    switch (_mobileDrawerSection) {
      case _DrawerLibrarySection.equipment:
        return _equipmentCategoryBody(isMobile: isMobile);
      case _DrawerLibrarySection.completions:
        return _completionsCategoryBody(isMobile: isMobile);
      case _DrawerLibrarySection.iron:
        types = const <_EquipmentType>[];
        outlined = true;
        title = 'Straight Iron';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Straight Iron',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
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
                      size: '2',
                    ),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('2" Straight Iron'),
                    style: _compactFilledStyle(highlighted: true),
                  ),
                ),
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: FilledButton(
                    onPressed: () => _addStraightIronFromLibrary(
                      size: '3',
                    ),
                    style: _compactFilledStyle(highlighted: true),
                    child: const Text('3" Straight Iron'),
                  ),
                ),
                SizedBox(
                  width: isMobile ? 162 : 138,
                  child: FilledButton(
                    onPressed: () => _addStraightIronFromLibrary(
                      size: '4',
                    ),
                    style: _compactFilledStyle(highlighted: true),
                    child: const Text('4" Straight Iron'),
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
      case _DrawerLibrarySection.labels:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Labels',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: isMobile ? MediaQuery.of(context).size.width - 56 : 138,
              child: FilledButton.icon(
                onPressed: _toggleShowEquipmentLabels,
                icon: const Icon(Icons.label_outline),
                label: Text(_showLabels
                    ? 'Equipment Labels On'
                    : 'Equipment Labels Off'),
                style: _compactFilledStyle(highlighted: _showLabels),
              ),
            ),
          ],
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 8, 12),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Rig-Up Library',
                  style: TextStyle(
                    color: scheme.primary,
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
                icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                tooltip: 'Close library',
              ),
            ],
          ),
          Row(
            children: [
              Text(
                'Keep Open',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              Switch(
                value: _libraryKeepOpen,
                onChanged: (value) {
                  setState(() => _libraryKeepOpen = value);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to place multiple pieces quickly. Panel stays open while you build.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.45),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
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
                  case 'exportLayout':
                    _showExportLayoutDialog();
                    break;
                  case 'importLayout':
                    _showImportLayoutDialog();
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
                  value: 'exportLayout',
                  child: Text('Export Layout'),
                ),
                const PopupMenuItem<String>(
                  value: 'importLayout',
                  child: Text('Import Layout'),
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
    final scheme = Theme.of(context).colorScheme;
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
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
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
                          Text(
                            'Keep Open',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          Switch(
                            value: _libraryKeepOpen,
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
                        color: scheme.onSurfaceVariant,
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
    final scheme = Theme.of(context).colorScheme;
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
                style: TextStyle(
                  color: scheme.onSurface,
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
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12.5,
            ),
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
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHigh
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
                  style: TextStyle(color: Colors.white70),
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
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
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
                    if (_canSelectNextCandidate) ...[
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        key: const ValueKey<String>('select-next-button'),
                        onPressed:
                            canAct ? _selectNextCandidateFromLastHit : null,
                        icon: const Icon(Icons.swap_vert),
                        label: const Text('Select Next'),
                        style: _compactOutlineStyle(),
                      ),
                    ],
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
    final scheme = Theme.of(context).colorScheme;
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
          color: scheme.surfaceContainerHigh.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.72)),
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
                icon: Icon(Icons.copy_outlined, color: scheme.onSurface),
                tooltip: 'Duplicate',
              ),
            ),
            Expanded(
              child: IconButton(
                onPressed: _rotateSelected,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: Icon(Icons.rotate_right, color: scheme.onSurface),
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
                  color: scheme.onSurface,
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
                icon: Icon(Icons.delete_outline, color: scheme.onSurface),
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
                  icon: Icon(Icons.link_off, color: scheme.onSurface),
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
      final scenePoint = _resolveIronEndpoint(item, leading);
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

  List<Widget> _resolvedBypassLeadWidgets() {
    final widgets = <Widget>[];
    for (final item in _items) {
      if (!_itemIsVisible(item) || item.type != _EquipmentType.bypass) continue;
      _ensureBypassLeadData(item);
      for (final leadId in _bypassLeadIds) {
        final start = _bypassLeadOriginWorld(item, leadId);
        final end = _resolveBypassLeadEndpointWorld(item, leadId);
        final bounds = Rect.fromPoints(start, end).inflate(4.0);
        widgets.add(
          Positioned(
            left: bounds.left,
            top: bounds.top,
            width: bounds.width,
            height: bounds.height,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ResolvedStraightIronPainter(
                  start: start - bounds.topLeft,
                  end: end - bounds.topLeft,
                  strokeWidth: 1.7,
                ),
              ),
            ),
          ),
        );

        final connected = _bypassLeadStoredTarget(item, leadId) != null;
        widgets.add(
          Positioned(
            left: end.dx - 3.5,
            top: end.dy - 3.5,
            child: IgnorePointer(
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected
                      ? const Color(0xFFCDA56A).withValues(alpha: 0.28)
                      : const Color(0xFFCDA56A).withValues(alpha: 0.48),
                  border: Border.all(
                    color: const Color(0xFF111111).withValues(alpha: 0.65),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  List<Widget> _bypassLeadHandleSceneWidgets() {
    final item = _selectedItem;
    if (item == null || item.type != _EquipmentType.bypass || item.locked) {
      return const <Widget>[];
    }

    Widget buildHandle(String leadId) {
      final scenePoint = _resolveBypassLeadEndpointWorld(item, leadId);
      const touchHalf = _endpointHandleTouchSize / 2;
      final selected = _selectedBypassLeadId == leadId;

      return Positioned(
        left: scenePoint.dx - touchHalf,
        top: scenePoint.dy - touchHalf,
        child: GestureDetector(
          key: ValueKey<String>('bypass-lead-handle-${item.id}-$leadId'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: () => setState(() {
            _selectedBypassLeadId = leadId;
            _selectedEndpointLeading = null;
            _selectedBypassHandle = null;
          }),
          onPanStart: (_) => _startBypassLeadDrag(item, leadId),
          onPanUpdate: (details) =>
              _updateBypassLeadDrag(item, leadId, details.delta),
          onPanEnd: (_) => _endBypassLeadDrag(item, leadId),
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
                ),
              ),
            ),
          ),
        ),
      );
    }

    return <Widget>[
      buildHandle(_bypassLeadA),
      buildHandle(_bypassLeadB),
    ];
  }

  List<Widget> _fittingConnectionPointIndicators() {
    final indicatorItems = <_LayoutItem>{};
    final selected = _selectedItem;
    if (selected != null &&
        (_isStraightIronType(selected.type) ||
            _isFittingEndpointConnectableType(selected.type))) {
      indicatorItems.add(selected);
    }
    if (_interactionMode == _InteractionMode.itemDrag) {
      for (final id in _dragItemStart.keys) {
        final item = _findItemById(id);
        if (item == null) continue;
        if (_isStraightIronType(item.type) ||
            _isFittingEndpointConnectableType(item.type)) {
          indicatorItems.add(item);
        }
      }
    }

    final points = <Offset>[];
    for (final item in indicatorItems) {
      if (_isStraightIronType(item.type)) {
        points.add(_resolveIronEndpoint(item, true));
        points.add(_resolveIronEndpoint(item, false));
      } else {
        for (final side in _fittingEndpointSides(item)) {
          final point = _equipmentAnchorPointOrNull(item, side);
          if (point != null) points.add(point);
        }
      }
    }

    return points
        .map(
          (point) => Positioned(
            left: point.dx - 5,
            top: point.dy - 5,
            child: IgnorePointer(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFCDA56A).withValues(alpha: 0.18),
                  border: Border.all(
                    color: const Color(0xFFCDA56A).withValues(alpha: 0.92),
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
        )
        .toList(growable: false);
  }

  List<Widget> _fittingDestinationPreviewWidgets() {
    final preview = _activeFittingPreview;
    if (preview == null) return const <Widget>[];
    final item = _findItemById(preview.itemId);
    if (item == null || !_isFittingEndpointConnectableType(item.type)) {
      return const <Widget>[];
    }

    final topLeft = _fittingTopLeftForSnapCandidate(item, preview.candidate);
    return <Widget>[
      Positioned(
        key: ValueKey<String>('fitting-destination-preview-${item.id}'),
        left: topLeft.dx,
        top: topLeft.dy,
        width: item.width,
        height: item.height,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.28,
            child: _LayoutTile(
              item: item,
              selected: false,
              showLabel: false,
              snapHighlight: true,
              renderStraightIronInternally: !_isStraightIronType(item.type),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _selectedPortWidgets() {
    final selected = _selectedItem;
    if (selected == null || selected.locked) return const <Widget>[];
    final ports = _availablePortsForItem(selected);
    if (ports.isEmpty) return const <Widget>[];
    final selectedPort = _selectedPortForSelectedItem();
    final sourcePort = _pendingConnectIronSourceTarget;

    return ports.map((port) {
      final active = selectedPort != null &&
          selectedPort.kind == port.kind &&
          selectedPort.point == port.point;
      final isAutoConnectSource = _autoConnectMode &&
          sourcePort != null &&
          sourcePort.kind == port.kind &&
          sourcePort.point == port.point;
      return Positioned(
        key: ValueKey<String>(
          'selected-port-${selected.id}-${port.kind.name}-${port.equipmentItemId ?? port.ironItemId}-${port.anchorId ?? (port.ironLeading == true ? 'start' : 'end')}',
        ),
        left: port.point.dx - 7,
        top: port.point.dy - 7,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _selectConnectionPort(port),
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? const Color(0xFFCDA56A).withValues(
                      alpha: isAutoConnectSource ? 0.46 : 0.34,
                    )
                  : Colors.transparent,
              border: Border.all(
                color: (active || isAutoConnectSource)
                    ? const Color(0xFFCDA56A)
                    : const Color(0xFFCDA56A).withValues(alpha: 0.7),
                width: isAutoConnectSource ? 2.8 : (active ? 2.0 : 1.4),
              ),
            ),
          ),
        ),
      );
    }).toList(growable: false);
  }

  List<Widget> _autoConnectDestinationPortWidgets() {
    if (!_autoConnectMode) return const <Widget>[];
    final source = _pendingConnectIronSourceTarget;
    final destinationItemId = _autoConnectDestinationItemId;
    if (source == null || destinationItemId == null) return const <Widget>[];
    final destinationItem = _findItemById(destinationItemId);
    if (destinationItem == null || destinationItem.locked) {
      return const <Widget>[];
    }

    final ports = _availablePortsForItem(destinationItem)
        .where((port) => !_connectionTargetsEqual(port, source))
        .toList(growable: false);
    if (ports.isEmpty) return const <Widget>[];

    return ports
        .map(
          (port) => Positioned(
            key: ValueKey<String>(
              'auto-connect-port-${destinationItem.id}-${port.kind.name}-${port.equipmentItemId ?? port.ironItemId}-${port.anchorId ?? (port.ironLeading == true ? 'start' : 'end')}',
            ),
            left: port.point.dx - 8,
            top: port.point.dy - 8,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _handleAutoConnectDestinationTarget(port),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFCDA56A).withValues(alpha: 0.22),
                  border: Border.all(
                    color: const Color(0xFFCDA56A),
                    width: 2.0,
                  ),
                ),
              ),
            ),
          ),
        )
        .toList(growable: false);
  }

  Widget _portActionMenuOverlay(Size viewportSize) {
    final selectedPort = _selectedPortForSelectedItem();
    if (selectedPort == null) {
      return const SizedBox.shrink();
    }

    final menuEntries = <_PortBuildActionEntry>[
      _PortBuildActionEntry(
        key: 'auto-connect',
        label: 'Auto Connect',
        icon: Icons.auto_fix_high,
        enabled: true,
        onTap: _startAutoConnectFromSelectedPort,
      ),
      _PortBuildActionEntry(
        key: 'straight-iron',
        label: 'Straight Iron',
        icon: Icons.edit_road,
        enabled: true,
        highlighted: true,
        onTap: () => _createStraightIronFromPort(selectedPort),
      ),
      _PortBuildActionEntry(
        key: 'add-90',
        label: '90°',
        icon: Icons.turn_right,
        enabled: true,
        onTap: () => _createNinetyFromPort(selectedPort),
      ),
      _PortBuildActionEntry(
        key: 'add-tee',
        label: 'Tee',
        icon: Icons.call_split,
        enabled: true,
        onTap: () => _createTeeFromPort(selectedPort),
      ),
      const _PortBuildActionEntry(
        key: 'valve-placeholder',
        label: 'Valve',
        icon: Icons.tune,
        enabled: false,
      ),
      const _PortBuildActionEntry(
        key: 'blind-placeholder',
        label: 'Blind',
        icon: Icons.block,
        enabled: false,
      ),
      const _PortBuildActionEntry(
        key: 'cap-placeholder',
        label: 'Cap',
        icon: Icons.circle,
        enabled: false,
      ),
      const _PortBuildActionEntry(
        key: 'reducer-placeholder',
        label: 'Reducer',
        icon: Icons.straighten,
        enabled: false,
      ),
      _PortBuildActionEntry(
        key: 'cancel',
        label: 'Cancel',
        icon: Icons.cancel_outlined,
        enabled: true,
        onTap: () => _clearPortSelection(),
      ),
    ];
    final visibleEntries =
        menuEntries.where((entry) => entry.enabled).toList(growable: false);

    final anchor = _viewportPointFromScene(selectedPort.point);
    const menuWidth = 176.0;
    const rowHeight = 44.0;
    const verticalPadding = 8.0;
    final menuHeight =
        rowHeight * visibleEntries.length + (verticalPadding * 2);
    const edgePadding = 8.0;
    const gap = 14.0;

    final maxLeft =
        math.max(edgePadding, viewportSize.width - menuWidth - edgePadding);
    final maxTop =
        math.max(edgePadding, viewportSize.height - menuHeight - edgePadding);

    final canRight =
        anchor.dx + gap + menuWidth <= viewportSize.width - edgePadding;
    final canLeft = anchor.dx - gap - menuWidth >= edgePadding;
    final canBelow =
        anchor.dy + gap + menuHeight <= viewportSize.height - edgePadding;
    final canAbove = anchor.dy - gap - menuHeight >= edgePadding;

    double left;
    double top;
    if (canRight || canLeft) {
      left = (canRight ? anchor.dx + gap : anchor.dx - gap - menuWidth)
          .clamp(edgePadding, maxLeft)
          .toDouble();
      top = (anchor.dy - menuHeight / 2).clamp(edgePadding, maxTop).toDouble();
    } else {
      left = (anchor.dx - menuWidth / 2).clamp(edgePadding, maxLeft).toDouble();
      top = (canBelow
              ? anchor.dy + gap
              : (canAbove ? anchor.dy - gap - menuHeight : anchor.dy + gap))
          .clamp(edgePadding, maxTop)
          .toDouble();
    }

    final rowText = TextStyle(
      color: _gold,
      fontWeight: FontWeight.w700,
      fontSize: 13,
    );

    Widget actionRow({
      required Key key,
      required String label,
      required VoidCallback onTap,
      IconData? icon,
      bool highlighted = false,
    }) {
      return SizedBox(
        key: key,
        width: menuWidth - 16,
        height: rowHeight,
        child: Material(
          color:
              highlighted ? _gold.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: _gold),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: Text(label, style: rowText)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Positioned(
      key: const ValueKey<String>('port-action-menu'),
      left: left,
      top: top,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: menuWidth,
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: verticalPadding),
          decoration: BoxDecoration(
            color: const Color(0xEE101216),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _gold.withValues(alpha: 0.9), width: 1.2),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 12,
                  offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in visibleEntries)
                actionRow(
                  key: ValueKey<String>('port-action-${entry.key}'),
                  label: entry.label,
                  icon: entry.icon,
                  highlighted: entry.highlighted,
                  onTap: entry.onTap!,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _autoConnectInstructionOverlay(Size viewportSize) {
    if (!_autoConnectMode || _pendingConnectIronSourceTarget == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      key: const ValueKey<String>('auto-connect-instruction'),
      right: 10,
      top: 10,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xEE101216),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _gold.withValues(alpha: 0.88), width: 1.2),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select destination connection point',
                style: TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                key: const ValueKey<String>('auto-connect-cancel'),
                onPressed: () => _cancelAutoConnect(clearSelectedPort: true),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(76, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: BorderSide(color: _gold.withValues(alpha: 0.9)),
                  foregroundColor: _gold,
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _resolvedStraightIronWidgets() {
    final widgets = <Widget>[];
    for (final item in _items) {
      if (!_itemIsVisible(item) || !_isStraightIronType(item.type)) continue;
      final start = _resolveIronEndpoint(item, true);
      final end = _resolveIronEndpoint(item, false);
      final strokeWidth =
          item.ironSize == '2' ? 1.4 : (item.ironSize == '4' ? 2.0 : 1.7);
      final bounds = Rect.fromPoints(start, end).inflate(4.0);
      widgets.add(
        Positioned(
          left: bounds.left,
          top: bounds.top,
          width: bounds.width,
          height: bounds.height,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ResolvedStraightIronPainter(
                start: start - bounds.topLeft,
                end: end - bounds.topLeft,
                strokeWidth: strokeWidth,
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
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
                          !_drawIronMode &&
                          _selectedIds.isEmpty;

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
                          onLongPressStart: (details) {
                            final scenePoint =
                                _scenePointFromGlobal(details.globalPosition);
                            _showSelectionPickerForScenePoint(scenePoint);
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
                                          if (_drawIronMode)
                                            Positioned(
                                              key: ValueKey<String>(
                                                  'connect-anchor-${it.id}-${anchor.side}'),
                                              left: anchor.point.dx - 3,
                                              top: anchor.point.dy - 3,
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTap: () {
                                                  if (_autoConnectMode) {
                                                    _handleAutoConnectDestinationTap(
                                                        it, anchor);
                                                    return;
                                                  }

                                                  final target =
                                                      _ConnectionTarget(
                                                    kind: _ConnectionTargetKind
                                                        .equipmentAnchor,
                                                    point: anchor.point,
                                                    distance: 0,
                                                    isExactHit: true,
                                                    equipmentItemId: it.id,
                                                    anchorId: anchor.side,
                                                  );
                                                  final startTarget =
                                                      _drawIronStartTarget;
                                                  if (startTarget == null) {
                                                    setState(() {
                                                      _drawIronStartTarget =
                                                          target;
                                                      _drawIronPointerScene =
                                                          target.point;
                                                      _drawIronHoverTarget =
                                                          null;
                                                      _pendingContinueIronTarget =
                                                          null;
                                                      _pendingContinueIronSize =
                                                          null;
                                                    });
                                                  } else {
                                                    _finalizeDrawIron(
                                                        target.point);
                                                  }
                                                },
                                                child: Container(
                                                  width: 10,
                                                  height: 10,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: () {
                                                        final source =
                                                            _pendingConnectIronSourceTarget;
                                                        final isSource = _autoConnectMode &&
                                                            source != null &&
                                                            source.kind ==
                                                                _ConnectionTargetKind
                                                                    .equipmentAnchor &&
                                                            source.equipmentItemId ==
                                                                it.id &&
                                                            source.anchorId ==
                                                                anchor.side;
                                                        if (isSource) {
                                                          return _gold;
                                                        }
                                                        if (_autoConnectMode &&
                                                            !_isEquipmentAnchorAvailable(
                                                                it,
                                                                anchor.side)) {
                                                          return const Color(
                                                              0xFF666666);
                                                        }
                                                        return _gold;
                                                      }(),
                                                      width: () {
                                                        final source =
                                                            _pendingConnectIronSourceTarget;
                                                        final isSource = _autoConnectMode &&
                                                            source != null &&
                                                            source.kind ==
                                                                _ConnectionTargetKind
                                                                    .equipmentAnchor &&
                                                            source.equipmentItemId ==
                                                                it.id &&
                                                            source.anchorId ==
                                                                anchor.side;
                                                        return isSource
                                                            ? 2.8
                                                            : 1.8;
                                                      }(),
                                                    ),
                                                    color: _autoConnectMode &&
                                                            !_isEquipmentAnchorAvailable(
                                                                it, anchor.side)
                                                        ? const Color(
                                                            0x55353535)
                                                        : Colors.transparent,
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
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                final target =
                                                    _ConnectionTarget(
                                                  kind: _ConnectionTargetKind
                                                      .ironEndpoint,
                                                  point: _ironEndpoint(
                                                      it, leading),
                                                  distance: 0,
                                                  isExactHit: true,
                                                  ironItemId: it.id,
                                                  ironLeading: leading,
                                                );
                                                if (_drawIronStartTarget ==
                                                    null) {
                                                  setState(() {
                                                    _drawIronStartTarget =
                                                        target;
                                                    _drawIronPointerScene =
                                                        target.point;
                                                    _drawIronHoverTarget = null;
                                                  });
                                                } else {
                                                  _finalizeDrawIron(
                                                      target.point);
                                                }
                                              },
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
                                                  width: 10,
                                                  height: 10,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: _gold,
                                                      width: 1.8,
                                                    ),
                                                    color: Colors.transparent,
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
                                  ..._resolvedStraightIronWidgets(),
                                  ..._resolvedBypassLeadWidgets(),
                                  ..._fittingConnectionPointIndicators(),
                                  ..._fittingDestinationPreviewWidgets(),
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
                                          onTapUp: (details) {
                                            final scenePoint =
                                                _scenePointFromGlobal(
                                                    details.globalPosition);
                                            if (_autoConnectMode) {
                                              _handleAutoConnectTapOnItem(
                                                  item, scenePoint);
                                              return;
                                            }
                                            _handleCanvasTap(scenePoint);
                                          },
                                          onDoubleTap: () {
                                            _selectOnly(item.id);
                                            if (!item.locked) {
                                              _rotateSelected();
                                            }
                                          },
                                          onLongPressStart: (details) {
                                            final scenePoint =
                                                _scenePointFromGlobal(
                                                    details.globalPosition);
                                            _showSelectionPickerForScenePoint(
                                                scenePoint);
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
                                                  renderStraightIronInternally:
                                                      !_isStraightIronType(
                                                          item.type),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }(),
                                  ..._bypassLeadHandleSceneWidgets(),
                                  ..._selectedPortWidgets(),
                                  ..._autoConnectDestinationPortWidgets(),
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
                      _portActionMenuOverlay(viewportSize),
                      _autoConnectInstructionOverlay(viewportSize),
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

enum _DrawerLibrarySection {
  equipment,
  completions,
  iron,
  tees,
  nineties,
  bypass,
  labels,
}

class _AnchorDefinition {
  final String id;
  final double u;
  final double v;

  const _AnchorDefinition(this.id, this.u, this.v);
}

class _AttachmentSpine {
  final Offset startLocal;
  final Offset endLocal;

  const _AttachmentSpine({
    required this.startLocal,
    required this.endLocal,
  });
}

class _InlineSegment {
  final String id;
  final Offset start;
  final Offset end;

  const _InlineSegment({
    required this.id,
    required this.start,
    required this.end,
  });
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

class _FittingEndpointSnapCandidate {
  final String fittingSide;
  final Offset fittingPoint;
  final _ConnectionTarget target;
  final double distance;

  const _FittingEndpointSnapCandidate({
    required this.fittingSide,
    required this.fittingPoint,
    required this.target,
    required this.distance,
  });
}

class _FittingPreviewState {
  final int itemId;
  final _FittingEndpointSnapCandidate candidate;

  const _FittingPreviewState({
    required this.itemId,
    required this.candidate,
  });
}

class _SelectionCandidate {
  final int itemId;
  final double distance;
  final int zIndex;
  final bool directHit;

  const _SelectionCandidate({
    required this.itemId,
    required this.distance,
    required this.zIndex,
    required this.directHit,
  });
}

enum _IronDragIntentType { none, moveBody, resizeStart, resizeEnd }

class _IronDragIntent {
  final _IronDragIntentType type;

  const _IronDragIntent._(this.type);

  const _IronDragIntent.none() : this._(_IronDragIntentType.none);
  const _IronDragIntent.moveBody() : this._(_IronDragIntentType.moveBody);
  const _IronDragIntent.resizeStart() : this._(_IronDragIntentType.resizeStart);
  const _IronDragIntent.resizeEnd() : this._(_IronDragIntentType.resizeEnd);
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
  final String? segmentId;

  const _SnapCandidate({
    required this.ironId,
    required this.horizontal,
    required this.indicator,
    required this.score,
    this.segmentId,
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
  final bool detached;
  final String? blockedTargetKey;
  final Offset? blockedOrigin;
  final bool reconnectAllowed;
  final bool historyRecorded;

  const _ActiveEndpointDrag({
    required this.ironId,
    required this.leading,
    required this.worldPosition,
    required this.target,
    required this.detached,
    required this.blockedTargetKey,
    required this.blockedOrigin,
    required this.reconnectAllowed,
    required this.historyRecorded,
  });
}

class _ActiveBypassLeadDrag {
  final int itemId;
  final String leadId;
  final Offset worldPosition;
  final _ConnectionTarget? target;
  final bool detached;
  final String? blockedTargetKey;
  final Offset? blockedOrigin;
  final bool reconnectAllowed;
  final bool historyRecorded;

  const _ActiveBypassLeadDrag({
    required this.itemId,
    required this.leadId,
    required this.worldPosition,
    required this.target,
    required this.detached,
    required this.blockedTargetKey,
    required this.blockedOrigin,
    required this.reconnectAllowed,
    required this.historyRecorded,
  });
}

class _PortBuildActionEntry {
  final String key;
  final String label;
  final IconData icon;
  final bool enabled;
  final bool highlighted;
  final VoidCallback? onTap;

  const _PortBuildActionEntry({
    required this.key,
    required this.label,
    required this.icon,
    required this.enabled,
    this.highlighted = false,
    this.onTap,
  });
}

class _BypassDragContext {
  final Offset startTopLeft;
  final Offset startCenter;
  final bool wasAttached;
  final int? parentIronId;
  final double? startT;
  final String? attachedSegmentId;
  bool detached = false;
  int? blockedParentIronId;
  bool reconnectAllowed;

  _BypassDragContext({
    required this.startTopLeft,
    required this.startCenter,
    required this.wasAttached,
    required this.parentIronId,
    required this.startT,
    required this.attachedSegmentId,
    this.blockedParentIronId,
    this.reconnectAllowed = true,
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
  sandX,
  superLoop,
  sandXSuperLoopCombo,
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
  coilTubingUnit,
  mixingPlant,
  pump,
  crane,
  lightPlant,
  wireline,
  dateVan,
  fuelTrailer,
  chemicalTrailer,
  nitrogen,
  generator,
}

extension _EquipmentTypeInfo on _EquipmentType {
  bool get isIron =>
      name.startsWith('iron') ||
      name.startsWith('elbow') ||
      name.startsWith('tee') ||
      this == _EquipmentType.bypass;

  bool get isCompletions =>
      this == _EquipmentType.coilTubingUnit ||
      this == _EquipmentType.mixingPlant ||
      this == _EquipmentType.pump ||
      this == _EquipmentType.crane ||
      this == _EquipmentType.lightPlant ||
      this == _EquipmentType.wireline ||
      this == _EquipmentType.dateVan ||
      this == _EquipmentType.fuelTrailer ||
      this == _EquipmentType.chemicalTrailer ||
      this == _EquipmentType.nitrogen ||
      this == _EquipmentType.generator ||
      this == _EquipmentType.sandX ||
      this == _EquipmentType.superLoop ||
      this == _EquipmentType.sandXSuperLoopCombo;

  bool get usesCompactEquipmentFootprint =>
      !isIron && !isCompletions && this != _EquipmentType.facilities;

  String get label {
    switch (this) {
      case _EquipmentType.wellhead:
        return 'Wellhead';
      case _EquipmentType.esdValve:
        return 'ESD Valve';
      case _EquipmentType.lineHeater:
        return 'Line Heater';
      case _EquipmentType.plugCatcher:
        return 'Double Plug Catcher';
      case _EquipmentType.cyclonicSandSep:
        return 'Cyclonic Sand Sep';
      case _EquipmentType.sphericalSandSep:
        return 'Spherical Sand Sep';
      case _EquipmentType.chokeManifold:
        return 'Choke Manifold';
      case _EquipmentType.flowbackTank:
        return 'Flowback Tank';
      case _EquipmentType.sandX:
        return 'SandX';
      case _EquipmentType.superLoop:
        return 'Super Loop';
      case _EquipmentType.sandXSuperLoopCombo:
        return 'SandX + Super Loop';
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
      case _EquipmentType.coilTubingUnit:
        return 'Coiled Tubing Unit';
      case _EquipmentType.mixingPlant:
        return 'Mixing Plant';
      case _EquipmentType.pump:
        return 'Pressure Pump';
      case _EquipmentType.crane:
        return 'Crane';
      case _EquipmentType.lightPlant:
        return 'Light Plant';
      case _EquipmentType.wireline:
        return 'Wireline Unit';
      case _EquipmentType.dateVan:
        return 'Data Van';
      case _EquipmentType.fuelTrailer:
        return 'Fuel Trailer';
      case _EquipmentType.chemicalTrailer:
        return 'Chemical Trailer';
      case _EquipmentType.nitrogen:
        return 'Nitrogen Unit';
      case _EquipmentType.generator:
        return 'Generator';
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
      case _EquipmentType.sandX:
      case _EquipmentType.superLoop:
      case _EquipmentType.sandXSuperLoopCombo:
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
      case _EquipmentType.coilTubingUnit:
        return Icons.autorenew;
      case _EquipmentType.mixingPlant:
        return Icons.construction;
      case _EquipmentType.pump:
        return Icons.water;
      case _EquipmentType.crane:
        return Icons.architecture;
      case _EquipmentType.lightPlant:
        return Icons.lightbulb;
      case _EquipmentType.wireline:
        return Icons.lan;
      case _EquipmentType.dateVan:
        return Icons.local_shipping;
      case _EquipmentType.fuelTrailer:
        return Icons.local_gas_station;
      case _EquipmentType.chemicalTrailer:
        return Icons.science;
      case _EquipmentType.nitrogen:
        return Icons.air;
      case _EquipmentType.generator:
        return Icons.electrical_services;
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
    if (this == _EquipmentType.flowbackTank || this == _EquipmentType.sandX)
      return 48;
    if (this == _EquipmentType.superLoop) return 46;
    if (this == _EquipmentType.sandXSuperLoopCombo) return 96;
    if (this == _EquipmentType.productionTank) return 38;
    if (this == _EquipmentType.testSeparator) return 36;
    if (this == _EquipmentType.flare) return 32;
    if (this == _EquipmentType.compressor) return 36;
    if (this == _EquipmentType.coilTubingUnit) return 98;
    if (this == _EquipmentType.mixingPlant) return 92;
    if (this == _EquipmentType.pump) return 72;
    if (this == _EquipmentType.crane) return 92;
    if (this == _EquipmentType.lightPlant) return 86;
    if (this == _EquipmentType.wireline) return 94;
    if (this == _EquipmentType.dateVan) return 80;
    if (this == _EquipmentType.fuelTrailer) return 94;
    if (this == _EquipmentType.chemicalTrailer) return 96;
    if (this == _EquipmentType.nitrogen) return 84;
    if (this == _EquipmentType.generator) return 78;
    if (this == _EquipmentType.ironHorizontal) return 150;
    if (this == _EquipmentType.ironVertical) return 28;
    if (this == _EquipmentType.bypass) return 30;
    if (name.startsWith('tee')) return 21;
    if (name.startsWith('elbow')) return 21;
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
    if (this == _EquipmentType.flowbackTank || this == _EquipmentType.sandX)
      return 96;
    if (this == _EquipmentType.superLoop) return 110;
    if (this == _EquipmentType.sandXSuperLoopCombo) return 100;
    if (this == _EquipmentType.productionTank) return 28;
    if (this == _EquipmentType.testSeparator) return 28;
    if (this == _EquipmentType.flare) return 28;
    if (this == _EquipmentType.compressor) return 28;
    if (this == _EquipmentType.coilTubingUnit) return 54;
    if (this == _EquipmentType.mixingPlant) return 50;
    if (this == _EquipmentType.pump) return 38;
    if (this == _EquipmentType.crane) return 46;
    if (this == _EquipmentType.lightPlant) return 56;
    if (this == _EquipmentType.wireline) return 50;
    if (this == _EquipmentType.dateVan) return 34;
    if (this == _EquipmentType.fuelTrailer) return 36;
    if (this == _EquipmentType.chemicalTrailer) return 36;
    if (this == _EquipmentType.nitrogen) return 38;
    if (this == _EquipmentType.generator) return 42;
    if (this == _EquipmentType.ironHorizontal) return 24;
    if (this == _EquipmentType.ironVertical) return 150;
    if (this == _EquipmentType.bypass) return 32;
    if (name.startsWith('tee')) return 21;
    if (name.startsWith('elbow')) return 21;
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
  double rotationDegrees;
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
      this.rotationDegrees = 0,
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
        'rotationDegrees': rotationDegrees,
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
        type == _EquipmentType.flowbackTank &&
        (rawWidth - 38.0).abs() < 0.2 &&
        (rawHeight - 28.0).abs() < 0.2) {
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
        (rawWidth - 30.0).abs() < 0.2 &&
        (rawHeight - 32.0).abs() < 0.2) {
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

    if (rawWidth != null &&
        rawHeight != null &&
        type == _EquipmentType.bypass &&
        (rawWidth - 34.0).abs() < 0.2 &&
        (rawHeight - 32.0).abs() < 0.2) {
      final centerX = x + width / 2;
      final centerY = y + height / 2;
      width = type.defaultWidth;
      height = type.defaultHeight;
      x = centerX - width / 2;
      y = centerY - height / 2;
    }

    if (rawWidth != null &&
        rawHeight != null &&
        (type.name.startsWith('tee') || type.name.startsWith('elbow')) &&
        (rawWidth - 42.0).abs() < 0.2 &&
        (rawHeight - 42.0).abs() < 0.2) {
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
      rotationDegrees: (json['rotationDegrees'] as num?)?.toDouble() ??
          (((json['rotationTurns'] as int?) ?? 0) * 90).toDouble(),
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
  String get equipmentVariant {
    final value = properties['equipmentVariant'];
    if (value == null || value.trim().isEmpty) return '';
    return value.trim();
  }

  String get displayLabel {
    final custom = properties['displayLabel'];
    if (custom != null && custom.trim().isNotEmpty) {
      final normalized = custom.trim().toLowerCase();
      if (normalized == 'single plug catcher' ||
          normalized == 'single barrel plug catcher') {
        return 'Double Plug Catcher';
      }
      return custom.trim();
    }
    if (type == _EquipmentType.sandX) {
      return 'SandX';
    }
    if (type == _EquipmentType.chokeManifold) {
      final chokeSize = properties['chokeSize']?.trim();
      if (chokeSize == '2' || chokeSize == '3') {
        return '$chokeSize" Choke Manifold';
      }
      return '3" Choke Manifold';
    }
    if (type == _EquipmentType.flowbackTank) {
      switch (equipmentVariant) {
        case 'flowbackGasBusters':
          return 'Flowback Tank with Gas Busters';
        case 'flowbackHalf':
          return 'Half Flowback Tank';
        case 'flowbackQuarter':
          return 'Quarter Flowback Tank';
        default:
          return 'Flowback Tank';
      }
    }
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
    if (type.isCompletions) {
      return SizedBox(
        key: symbolKey,
        width: size,
        height: size,
        child: CustomPaint(
          painter: _CompletionsArtworkPainter(
            type: type,
            color: color,
            rotationDegrees: 0,
          ),
        ),
      );
    }
    return Icon(type.icon, key: symbolKey, color: color, size: size);
  }
}

class _CompletionsArtworkPainter extends CustomPainter {
  final _EquipmentType type;
  final Color color;
  final double rotationDegrees;

  const _CompletionsArtworkPainter({
    required this.type,
    required this.color,
    required this.rotationDegrees,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotationDegrees * math.pi / 180);
    canvas.translate(-center.dx, -center.dy);

    final stroke = (size.shortestSide * 0.054).clamp(1.2, 2.2);
    final detailStroke = (stroke * 0.72).clamp(0.9, 1.7);
    final bodyFill = Paint()
      ..color = const Color(0xFF101317)
      ..style = PaintingStyle.fill;
    final accentFill = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final detail = Paint()
      ..color = color.withValues(alpha: 0.94)
      ..style = PaintingStyle.stroke
      ..strokeWidth = detailStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void drawWheel(Offset wheelCenter, double radius) {
      canvas.drawCircle(wheelCenter, radius, outline);
      canvas.drawCircle(wheelCenter, radius * 0.52, accentFill);
    }

    void drawRightCab(Rect rect) {
      canvas.drawRect(rect, bodyFill);
      canvas.drawRect(rect, outline);
      final glass = Rect.fromLTWH(
        rect.left + rect.width * 0.44,
        rect.top + rect.height * 0.12,
        rect.width * 0.38,
        rect.height * 0.30,
      );
      canvas.drawRect(glass, accentFill);
      canvas.drawRect(glass, outline);
    }

    void drawAxles(List<double> xCenters, double y, double radius) {
      for (final x in xCenters) {
        drawWheel(Offset(x, y), radius);
      }
    }

    if (type == _EquipmentType.dateVan) {
      final trailer = Rect.fromLTWH(
        size.width * 0.16,
        size.height * 0.34,
        size.width * 0.56,
        size.height * 0.30,
      );
      canvas.drawRect(trailer, bodyFill);
      canvas.drawRect(trailer, outline);
      for (final x in <double>[0.24, 0.38, 0.52]) {
        final window = Rect.fromLTWH(
          size.width * x,
          size.height * 0.40,
          size.width * 0.10,
          size.height * 0.08,
        );
        canvas.drawRect(window, accentFill);
        canvas.drawRect(window, outline);
      }
      canvas.drawLine(
        Offset(size.width * 0.72, size.height * 0.49),
        Offset(size.width * 0.84, size.height * 0.49),
        outline,
      );
      drawAxles(<double>[size.width * 0.34, size.width * 0.56],
          size.height * 0.74, size.shortestSide * 0.05);
      canvas.restore();
      return;
    }

    Rect drawSandXArt(Rect bounds) {
      // Trailer footprint with a discharge spout nub on top and a control box.
      final left = bounds.left + bounds.width * 0.30;
      final right = bounds.left + bounds.width * 0.70;
      final bodyTop = bounds.top + bounds.height * 0.30;
      final bodyRect = Rect.fromLTRB(
          left, bodyTop, right, bounds.top + bounds.height * 0.92);
      canvas.drawRect(bodyRect, outline);
      final pillWidth = (right - left) * 0.55;
      final pillHeight = bounds.height * 0.16;
      final pill = RRect.fromRectAndRadius(
        Rect.fromLTWH(bounds.center.dx - pillWidth / 2,
            bodyTop - pillHeight * 0.85, pillWidth, pillHeight),
        Radius.circular(pillWidth / 2),
      );
      canvas.drawRRect(pill, bodyFill);
      canvas.drawRRect(pill, outline);

      final squareWidth = (right - left) * 0.62;
      final squareHeight = bounds.height * 0.14;
      final squareRect = Rect.fromLTWH(bounds.center.dx - squareWidth / 2,
          bodyTop + bounds.height * 0.10, squareWidth, squareHeight);
      final square = RRect.fromRectAndRadius(
          squareRect, Radius.circular(bounds.shortestSide * 0.04));
      canvas.drawRRect(square, bodyFill);
      canvas.drawRRect(square, outline);
      return squareRect;
    }

    Rect drawSuperLoopArt(Rect bounds) {
      // Trailer footprint with a fed inlet and a two-stage separator vessel.
      final left = bounds.left + bounds.width * 0.32;
      final right = bounds.left + bounds.width * 0.68;
      final bodyRect = Rect.fromLTRB(left, bounds.top + bounds.height * 0.06,
          right, bounds.top + bounds.height * 0.94);
      canvas.drawRect(bodyRect, outline);
      final pillWidth = (right - left) * 0.7;
      final pillHeight = bounds.height * 0.12;
      final pillTop = bounds.top + bounds.height * 0.16;
      final pillCenterX = left + (right - left) * 0.60;
      final pillRect = Rect.fromLTWH(
          pillCenterX - pillWidth / 2, pillTop, pillWidth, pillHeight);
      final pill = RRect.fromRectAndRadius(
        pillRect,
        Radius.circular(pillWidth / 2),
      );
      canvas.drawLine(
        Offset(left - bounds.width * 0.10, pillTop + pillHeight * 0.5),
        Offset(pillCenterX - pillWidth / 2, pillTop + pillHeight * 0.4),
        outline,
      );
      canvas.drawRRect(pill, bodyFill);
      canvas.drawRRect(pill, outline);
      final midCenter =
          Offset(pillCenterX, pillTop + pillHeight + bounds.height * 0.10);
      final midRadius = bounds.shortestSide * 0.09;
      canvas.drawCircle(midCenter, midRadius, bodyFill);
      canvas.drawCircle(midCenter, midRadius, outline);
      final bigCenter =
          Offset(midCenter.dx, midCenter.dy + midRadius + bounds.height * 0.09);
      final bigRadius = bounds.shortestSide * 0.14;
      canvas.drawCircle(bigCenter, bigRadius, bodyFill);
      canvas.drawCircle(bigCenter, bigRadius, outline);
      final dischargeStart =
          Offset(bigCenter.dx, bigCenter.dy + bigRadius * 0.8);
      final dischargeEnd = Offset(
          right + bounds.width * 0.06, bounds.top + bounds.height * 0.92);
      final dischargePath = Path()
        ..moveTo(dischargeStart.dx, dischargeStart.dy)
        ..quadraticBezierTo(
            right + bounds.width * 0.02,
            bounds.top + bounds.height * 0.90,
            dischargeEnd.dx,
            dischargeEnd.dy);
      canvas.drawPath(dischargePath, outline);
      return pillRect;
    }

    switch (type) {
      case _EquipmentType.sandX:
        drawSandXArt(Rect.fromLTWH(0, 0, size.width, size.height));
        break;
      case _EquipmentType.superLoop:
        drawSuperLoopArt(Rect.fromLTWH(0, 0, size.width, size.height));
        break;
      case _EquipmentType.sandXSuperLoopCombo:
        // Two separate footprints side by side, connected by a feed tube.
        final comboGap = size.width * 0.04;
        final comboLeftWidth = size.width * 0.46;
        final comboRightWidth = size.width - comboLeftWidth - comboGap;
        final comboLeftBounds =
            Rect.fromLTWH(0, 0, comboLeftWidth, size.height);
        final comboRightBounds = Rect.fromLTWH(
            comboLeftWidth + comboGap, 0, comboRightWidth, size.height);
        final comboSquare = drawSandXArt(comboLeftBounds);
        final comboPill = drawSuperLoopArt(comboRightBounds);
        canvas.drawLine(
          Offset(comboSquare.right, comboSquare.top + comboSquare.height * 0.4),
          Offset(comboPill.left, comboPill.top + comboPill.height * 0.4),
          outline,
        );
        break;
      case _EquipmentType.coilTubingUnit:
        canvas.drawLine(Offset(size.width * 0.12, size.height * 0.62),
            Offset(size.width * 0.88, size.height * 0.62), outline);
        drawRightCab(Rect.fromLTWH(size.width * 0.72, size.height * 0.36,
            size.width * 0.14, size.height * 0.22));
        final reelCenter = Offset(size.width * 0.36, size.height * 0.46);
        canvas.drawCircle(reelCenter, size.shortestSide * 0.22, outline);
        canvas.drawCircle(reelCenter, size.shortestSide * 0.15, bodyFill);
        canvas.drawCircle(reelCenter, size.shortestSide * 0.06, outline);
        // Tubing exits from the top of the reel and extends outward.
        canvas.drawLine(Offset(size.width * 0.36, size.height * 0.24),
            Offset(size.width * 0.36, size.height * 0.13), detail);
        canvas.drawLine(Offset(size.width * 0.36, size.height * 0.13),
            Offset(size.width * 0.20, size.height * 0.10), detail);
        canvas.drawLine(Offset(size.width * 0.20, size.height * 0.10),
            Offset(size.width * 0.12, size.height * 0.15), detail);
        drawAxles(
            <double>[size.width * 0.24, size.width * 0.42, size.width * 0.60],
            size.height * 0.74,
            size.shortestSide * 0.052);
        break;
      case _EquipmentType.mixingPlant:
        drawRightCab(Rect.fromLTWH(size.width * 0.72, size.height * 0.36,
            size.width * 0.14, size.height * 0.22));
        final blender = Rect.fromLTWH(size.width * 0.46, size.height * 0.38,
            size.width * 0.20, size.height * 0.20);
        canvas.drawRect(blender, bodyFill);
        canvas.drawRect(blender, outline);
        final tubLeft = Offset(size.width * 0.12, size.height * 0.36);
        final tubRight = Offset(size.width * 0.38, size.height * 0.36);
        final tubBottomY = size.height * 0.58;
        canvas.drawLine(tubLeft, Offset(tubLeft.dx, tubBottomY), outline);
        canvas.drawLine(tubRight, Offset(tubRight.dx, tubBottomY), outline);
        canvas.drawLine(Offset(tubLeft.dx, tubBottomY),
            Offset(tubRight.dx, tubBottomY), outline);
        final spiral = Path()
          ..moveTo(size.width * 0.16, size.height * 0.54)
          ..quadraticBezierTo(size.width * 0.22, size.height * 0.40,
              size.width * 0.30, size.height * 0.48)
          ..quadraticBezierTo(size.width * 0.34, size.height * 0.54,
              size.width * 0.36, size.height * 0.44);
        canvas.drawPath(spiral, detail);
        canvas.drawLine(Offset(size.width * 0.38, size.height * 0.46),
            Offset(size.width * 0.46, size.height * 0.46), outline);
        drawAxles(
            <double>[size.width * 0.28, size.width * 0.52, size.width * 0.74],
            size.height * 0.74,
            size.shortestSide * 0.05);
        break;
      case _EquipmentType.pump:
        canvas.drawLine(Offset(size.width * 0.10, size.height * 0.62),
            Offset(size.width * 0.90, size.height * 0.62), outline);
        drawRightCab(Rect.fromLTWH(size.width * 0.74, size.height * 0.36,
            size.width * 0.14, size.height * 0.22));
        final pumpOne = Rect.fromLTWH(size.width * 0.16, size.height * 0.38,
            size.width * 0.22, size.height * 0.20);
        final pumpTwo = Rect.fromLTWH(size.width * 0.42, size.height * 0.38,
            size.width * 0.22, size.height * 0.20);
        canvas.drawRect(pumpOne, bodyFill);
        canvas.drawRect(pumpOne, outline);
        canvas.drawRect(pumpTwo, bodyFill);
        canvas.drawRect(pumpTwo, outline);
        canvas.drawLine(Offset(size.width * 0.18, size.height * 0.58),
            Offset(size.width * 0.66, size.height * 0.58), detail);
        for (final x in <double>[0.24, 0.30, 0.50, 0.56]) {
          canvas.drawLine(Offset(size.width * x, size.height * 0.40),
              Offset(size.width * x, size.height * 0.56), detail);
        }
        canvas.drawLine(Offset(size.width * 0.66, size.height * 0.58),
            Offset(size.width * 0.80, size.height * 0.54), detail);
        drawAxles(
            <double>[size.width * 0.22, size.width * 0.46, size.width * 0.70],
            size.height * 0.75,
            size.shortestSide * 0.05);
        break;
      case _EquipmentType.crane:
        final chassis = Rect.fromLTWH(size.width * 0.12, size.height * 0.58,
            size.width * 0.74, size.height * 0.10);
        canvas.drawRect(chassis, bodyFill);
        canvas.drawRect(chassis, outline);
        final frontCab = Rect.fromLTWH(size.width * 0.74, size.height * 0.40,
            size.width * 0.14, size.height * 0.18);
        canvas.drawRect(frontCab, bodyFill);
        canvas.drawRect(frontCab, outline);
        final craneBody = Rect.fromLTWH(size.width * 0.38, size.height * 0.42,
            size.width * 0.26, size.height * 0.16);
        canvas.drawRect(craneBody, bodyFill);
        canvas.drawRect(craneBody, outline);
        final boom = Path()
          ..moveTo(size.width * 0.46, size.height * 0.44)
          ..lineTo(size.width * 0.86, size.height * 0.20)
          ..lineTo(size.width * 0.89, size.height * 0.24)
          ..lineTo(size.width * 0.49, size.height * 0.48)
          ..close();
        canvas.drawPath(boom, bodyFill);
        canvas.drawPath(boom, outline);
        canvas.drawLine(Offset(size.width * 0.89, size.height * 0.24),
            Offset(size.width * 0.89, size.height * 0.40), detail);
        canvas.drawRect(
            Rect.fromLTWH(size.width * 0.87, size.height * 0.40,
                size.width * 0.04, size.height * 0.07),
            bodyFill);
        canvas.drawRect(
            Rect.fromLTWH(size.width * 0.87, size.height * 0.40,
                size.width * 0.04, size.height * 0.07),
            outline);
        canvas.drawCircle(Offset(size.width * 0.89, size.height * 0.49),
            size.shortestSide * 0.018, outline);
        drawAxles(<double>[
          size.width * 0.20,
          size.width * 0.36,
          size.width * 0.56,
          size.width * 0.74
        ], size.height * 0.74, size.shortestSide * 0.04);
        break;
      case _EquipmentType.lightPlant:
        final trailer = Rect.fromLTWH(size.width * 0.20, size.height * 0.56,
            size.width * 0.26, size.height * 0.12);
        canvas.drawRect(trailer, bodyFill);
        canvas.drawRect(trailer, outline);
        canvas.drawLine(Offset(size.width * 0.46, size.height * 0.62),
            Offset(size.width * 0.58, size.height * 0.62), outline);
        drawAxles(<double>[size.width * 0.24, size.width * 0.42],
            size.height * 0.75, size.shortestSide * 0.042);
        canvas.drawLine(Offset(size.width * 0.33, size.height * 0.56),
            Offset(size.width * 0.33, size.height * 0.16), outline);
        canvas.drawLine(Offset(size.width * 0.22, size.height * 0.16),
            Offset(size.width * 0.44, size.height * 0.16), outline);
        for (final head in <Offset>[
          Offset(size.width * 0.24, size.height * 0.12),
          Offset(size.width * 0.30, size.height * 0.12),
          Offset(size.width * 0.36, size.height * 0.12),
          Offset(size.width * 0.42, size.height * 0.12),
        ]) {
          final lamp = Rect.fromCenter(
              center: head,
              width: size.width * 0.050,
              height: size.height * 0.034);
          canvas.drawRect(lamp, bodyFill);
          canvas.drawRect(lamp, outline);
        }
        break;
      case _EquipmentType.wireline:
        canvas.drawLine(Offset(size.width * 0.10, size.height * 0.62),
            Offset(size.width * 0.90, size.height * 0.62), outline);
        drawRightCab(Rect.fromLTWH(size.width * 0.74, size.height * 0.38,
            size.width * 0.14, size.height * 0.20));
        final wirelineBody = Rect.fromLTWH(size.width * 0.34,
            size.height * 0.36, size.width * 0.34, size.height * 0.24);
        canvas.drawRect(wirelineBody, bodyFill);
        canvas.drawRect(wirelineBody, outline);
        canvas.drawLine(Offset(size.width * 0.34, size.height * 0.42),
            Offset(size.width * 0.22, size.height * 0.34), detail);
        canvas.drawLine(Offset(size.width * 0.22, size.height * 0.34),
            Offset(size.width * 0.18, size.height * 0.28), detail);
        drawAxles(
            <double>[size.width * 0.26, size.width * 0.48, size.width * 0.70],
            size.height * 0.76,
            size.shortestSide * 0.048);
        break;
      case _EquipmentType.fuelTrailer:
        canvas.drawRect(
            Rect.fromLTWH(size.width * 0.18, size.height * 0.40,
                size.width * 0.54, size.height * 0.18),
            bodyFill);
        canvas.drawRect(
            Rect.fromLTWH(size.width * 0.18, size.height * 0.40,
                size.width * 0.54, size.height * 0.18),
            outline);
        drawAxles(<double>[size.width * 0.30, size.width * 0.56],
            size.height * 0.76, size.shortestSide * 0.05);
        break;
      case _EquipmentType.chemicalTrailer:
        canvas.drawRect(
            Rect.fromLTWH(size.width * 0.18, size.height * 0.38,
                size.width * 0.24, size.height * 0.22),
            bodyFill);
        canvas.drawRect(
            Rect.fromLTWH(size.width * 0.18, size.height * 0.38,
                size.width * 0.24, size.height * 0.22),
            outline);
        canvas.drawRect(
            Rect.fromLTWH(size.width * 0.48, size.height * 0.38,
                size.width * 0.24, size.height * 0.22),
            bodyFill);
        canvas.drawRect(
            Rect.fromLTWH(size.width * 0.48, size.height * 0.38,
                size.width * 0.24, size.height * 0.22),
            outline);
        drawAxles(<double>[size.width * 0.26, size.width * 0.56],
            size.height * 0.76, size.shortestSide * 0.05);
        break;
      case _EquipmentType.nitrogen:
        final tank = RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width * 0.10, size.height * 0.34,
                size.width * 0.30, size.height * 0.24),
            const Radius.circular(12));
        canvas.drawRRect(tank, bodyFill);
        canvas.drawRRect(tank, outline);
        final cab = Rect.fromLTWH(size.width * 0.44, size.height * 0.36,
            size.width * 0.16, size.height * 0.22);
        canvas.drawRect(cab, bodyFill);
        canvas.drawRect(cab, outline);
        final pump = Rect.fromLTWH(size.width * 0.64, size.height * 0.40,
            size.width * 0.22, size.height * 0.16);
        canvas.drawRect(pump, bodyFill);
        canvas.drawRect(pump, outline);
        canvas.drawLine(Offset(size.width * 0.74, size.height * 0.40),
            Offset(size.width * 0.88, size.height * 0.30), outline);
        drawAxles(
            <double>[size.width * 0.22, size.width * 0.50, size.width * 0.76],
            size.height * 0.75,
            size.shortestSide * 0.05);
        break;
      case _EquipmentType.generator:
        final generatorBody = Rect.fromLTWH(size.width * 0.22,
            size.height * 0.36, size.width * 0.44, size.height * 0.24);
        canvas.drawRect(generatorBody, bodyFill);
        canvas.drawRect(generatorBody, outline);
        for (var i = 0; i < 4; i++) {
          final x = size.width * (0.28 + i * 0.08);
          canvas.drawLine(Offset(x, size.height * 0.40),
              Offset(x, size.height * 0.56), detail);
        }
        drawAxles(<double>[size.width * 0.30, size.width * 0.58],
            size.height * 0.74, size.shortestSide * 0.05);
        break;
      default:
        break;
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CompletionsArtworkPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.color != color ||
        oldDelegate.rotationDegrees != rotationDegrees;
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
  final bool renderStraightIronInternally;

  const _LayoutTile(
      {required this.item,
      required this.selected,
      this.showLabel = true,
      this.snapHighlight = false,
      this.renderStraightIronInternally = true});

  bool _usesCustomEquipmentArtwork(_LayoutItem item) {
    return item.type == _EquipmentType.chokeManifold ||
        item.type == _EquipmentType.plugCatcher ||
        item.type == _EquipmentType.flowbackTank ||
        item.type == _EquipmentType.sandX ||
        item.type == _EquipmentType.testSeparator ||
        item.type == _EquipmentType.facilities ||
        item.type.isCompletions;
  }

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
    final useCustomEquipmentArtwork = _usesCustomEquipmentArtwork(item);
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
                  turns: item.rotationTurns,
                  rotationDegrees: item.rotationDegrees,
                  ironSize: item.ironSize,
                  properties: item.properties,
                  renderStraightIronInternally: renderStraightIronInternally),
              child: (isIron || useCustomEquipmentArtwork)
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

class _ShapePainter extends CustomPainter {
  final _EquipmentType type;
  final int turns;
  final double rotationDegrees;
  final String ironSize;
  final Map<String, String> properties;
  final bool renderStraightIronInternally;

  _ShapePainter(this.type,
      {this.turns = 0,
      this.rotationDegrees = 0,
      this.ironSize = '3',
      Map<String, String>? properties,
      this.renderStraightIronInternally = true})
      : properties = properties ?? const <String, String>{};

  @override
  void paint(Canvas canvas, Size size) {
    final accent = Paint()
      ..color = const Color(0xFFCDA56A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final bodyFill = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill;
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

    final rotationRadians = rotationDegrees != 0
        ? rotationDegrees * math.pi / 180
        : (turns % 4) * 1.57079632679;
    if (rotationRadians != 0) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(rotationRadians);
      canvas.translate(-size.width / 2, -size.height / 2);
    }

    void drawIron(Path p) {
      canvas.drawPath(p, shadow);
      canvas.drawPath(p, iron);
    }

    String variant() {
      final value = properties['equipmentVariant'];
      if (value == null || value.trim().isEmpty) return '';
      return value.trim();
    }

    if (type == _EquipmentType.ironHorizontal) {
      if (!renderStraightIronInternally) return;
      final p = Path()
        ..moveTo(0, size.height * .5)
        ..lineTo(size.width, size.height * .5);
      drawIron(p);
      return;
    }
    if (type == _EquipmentType.ironVertical) {
      if (!renderStraightIronInternally) return;
      final p = Path()
        ..moveTo(size.width * .5, 0)
        ..lineTo(size.width * .5, size.height);
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
      final mainX = size.width * .28;
      final topY = size.height * .14;
      final bottomY = size.height * .86;
      final upperY = size.height * .34;
      final lowerY = size.height * .66;
      final branchEndX = size.width * .82;
      final valveX = (mainX + branchEndX) / 2;
      final valveRadius = ironSize == '4' ? 3.3 : (ironSize == '2' ? 2.5 : 2.9);

      final manifold = Path()
        ..moveTo(mainX, topY)
        ..lineTo(mainX, bottomY)
        ..moveTo(mainX, upperY)
        ..lineTo(branchEndX, upperY)
        ..moveTo(mainX, lowerY)
        ..lineTo(branchEndX, lowerY);
      drawIron(manifold);

      final valveFill = Paint()
        ..color = const Color(0xFF8D939C)
        ..style = PaintingStyle.fill;
      final valveBorder = Paint()
        ..color = Colors.black.withOpacity(.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      final valveHighlight = Paint()
        ..color = const Color(0xFFC8CDD4)
        ..style = PaintingStyle.fill;

      void drawValve(double y) {
        final center = Offset(valveX, y);
        canvas.drawCircle(center, valveRadius, valveFill);
        canvas.drawCircle(center, valveRadius, valveBorder);
        canvas.drawCircle(
          Offset(center.dx - valveRadius * .28, center.dy - valveRadius * .28),
          valveRadius * .34,
          valveHighlight,
        );
      }

      drawValve(upperY);
      drawValve(lowerY);
      return;
    }

    if (type == _EquipmentType.chokeManifold) {
      final bodyRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .16,
          size.height * .16,
          size.width * .68,
          size.height * .68,
        ),
        Radius.circular(size.shortestSide * .14),
      );
      canvas.drawRRect(bodyRect, bodyFill);
      canvas.drawRRect(bodyRect, accent);

      final linePaint = Paint()
        ..color = const Color(0xFFCDA56A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (size.shortestSide * .075).clamp(1.7, 2.8)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final centerX = size.width * .50;
      final inletY = size.height * .08;
      final outletY = size.height * .92;
      final bodyTop = bodyRect.top;
      final bodyBottom = bodyRect.bottom;
      final leftPathX = size.width * .32;
      final rightPathX = size.width * .68;
      final topCrossY = size.height * .28;
      final bottomCrossY = size.height * .72;

      canvas.drawLine(
          Offset(centerX, inletY), Offset(centerX, bodyTop), linePaint);
      canvas.drawLine(
          Offset(centerX, bodyBottom), Offset(centerX, outletY), linePaint);
      canvas.drawLine(
          Offset(leftPathX, bodyTop), Offset(leftPathX, bodyBottom), linePaint);
      canvas.drawLine(Offset(rightPathX, bodyTop),
          Offset(rightPathX, bodyBottom), linePaint);
      canvas.drawLine(Offset(leftPathX, topCrossY),
          Offset(rightPathX, topCrossY), linePaint);
      canvas.drawLine(Offset(leftPathX, bottomCrossY),
          Offset(rightPathX, bottomCrossY), linePaint);
      canvas.drawLine(
        Offset(centerX, topCrossY),
        Offset(centerX, bottomCrossY),
        linePaint,
      );

      final wheelRadius = (size.shortestSide * .15).clamp(2.9, 5.2);
      final wheelPaint = Paint()
        ..color = const Color(0xFFCDA56A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (size.shortestSide * .055).clamp(1.3, 2.3);

      void drawWheel(Offset center) {
        canvas.drawCircle(center, wheelRadius, wheelPaint);
        canvas.drawLine(
          Offset(center.dx - wheelRadius, center.dy),
          Offset(center.dx + wheelRadius, center.dy),
          wheelPaint,
        );
        canvas.drawLine(
          Offset(center.dx, center.dy - wheelRadius),
          Offset(center.dx, center.dy + wheelRadius),
          wheelPaint,
        );
      }

      void drawValveX(Offset center) {
        final arm = (size.shortestSide * .07).clamp(1.6, 3.0);
        canvas.drawLine(
          Offset(center.dx - arm, center.dy - arm),
          Offset(center.dx + arm, center.dy + arm),
          linePaint,
        );
        canvas.drawLine(
          Offset(center.dx - arm, center.dy + arm),
          Offset(center.dx + arm, center.dy - arm),
          linePaint,
        );
      }

      drawWheel(Offset(size.width * .30, size.height * .22));
      drawWheel(Offset(size.width * .70, size.height * .22));

      drawValveX(Offset(leftPathX, size.height * .36));
      drawValveX(Offset(rightPathX, size.height * .36));
      drawValveX(Offset(centerX, size.height * .50));
      drawValveX(Offset(leftPathX, size.height * .64));
      drawValveX(Offset(rightPathX, size.height * .64));
      return;
    }

    if (type == _EquipmentType.plugCatcher) {
      final bodyRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .14,
          size.height * .22,
          size.width * .72,
          size.height * .56,
        ),
        Radius.circular(size.shortestSide * .12),
      );
      canvas.drawRRect(bodyRect, bodyFill);
      canvas.drawRRect(bodyRect, accent);

      final linePaint = Paint()
        ..color = const Color(0xFFCDA56A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (size.shortestSide * .08).clamp(1.8, 3.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final inletX = size.width * .08;
      final outletX = size.width * .92;
      final centerY = size.height * .50;
      final branchX = size.width * .28;
      final rejoinX = size.width * .72;
      final upperY = size.height * .36;
      final lowerY = size.height * .64;

      canvas.drawLine(
          Offset(inletX, centerY), Offset(outletX, centerY), linePaint);

      final upperPath = Path()
        ..moveTo(branchX, centerY)
        ..lineTo(branchX, upperY)
        ..lineTo(rejoinX, upperY)
        ..lineTo(rejoinX, centerY);
      final lowerPath = Path()
        ..moveTo(branchX, centerY)
        ..lineTo(branchX, lowerY)
        ..lineTo(rejoinX, lowerY)
        ..lineTo(rejoinX, centerY);
      canvas.drawPath(upperPath, linePaint);
      canvas.drawPath(lowerPath, linePaint);
      return;
    }

    if (type == _EquipmentType.flowbackTank) {
      final v = variant();
      var bodyStart = 0.08;
      var bodyWidth = 0.84;
      if (v == 'flowbackHalf') {
        bodyWidth = 0.44;
        bodyStart = 0.28;
      } else if (v == 'flowbackQuarter') {
        bodyWidth = 0.30;
        bodyStart = 0.35;
      }
      final bodyRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * bodyStart,
          size.height * .08,
          size.width * bodyWidth,
          size.height * .84,
        ),
        Radius.circular(size.shortestSide * .08),
      );
      canvas.drawRRect(bodyRect, bodyFill);
      canvas.drawRRect(bodyRect, accent);

      if (v == 'flowbackGasBusters') {
        final barPaint = Paint()
          ..color = const Color(0xFFCDA56A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (size.shortestSide * .09).clamp(1.8, 3.2)
          ..strokeCap = StrokeCap.round;
        final x1 = bodyRect.left + bodyRect.width * .36;
        final x2 = bodyRect.left + bodyRect.width * .64;
        const barHalfLength = 24.0;
        final yCenter = (bodyRect.top + bodyRect.bottom) / 2;
        final yTop = math.max(bodyRect.top + 4.0, yCenter - barHalfLength);
        final yBottom =
            math.min(bodyRect.bottom - 4.0, yCenter + barHalfLength);
        canvas.drawLine(Offset(x1, yTop), Offset(x1, yBottom), barPaint);
        canvas.drawLine(Offset(x2, yTop), Offset(x2, yBottom), barPaint);
      }
      return;
    }

    Rect drawSandXArt(Rect bounds) {
      // Trailer footprint with a discharge spout nub on top and a control box.
      // bodyTop is tuned so the rect + pill are balanced around the
      // rotation pivot (bounds center) to avoid an off-axis wobble.
      final bodyTop = bounds.top + bounds.height * .162;
      final bodyRect = Rect.fromLTWH(
          bounds.left, bodyTop, bounds.width, bounds.height * .82);
      canvas.drawRect(bodyRect, accent);

      final pillWidth = bounds.width * .30;
      final pillHeight = bounds.height * .18;
      final pill = RRect.fromRectAndRadius(
        Rect.fromLTWH(bounds.center.dx - pillWidth / 2,
            bodyTop - pillHeight * .8, pillWidth, pillHeight),
        Radius.circular(pillWidth / 2),
      );
      canvas.drawRRect(pill, bodyFill);
      canvas.drawRRect(pill, accent);

      final squareWidth = bounds.width * .34;
      final squareHeight = bounds.height * .16;
      final squareRect = Rect.fromLTWH(bounds.center.dx - squareWidth / 2,
          bodyTop + bounds.height * .10, squareWidth, squareHeight);
      final square = RRect.fromRectAndRadius(
          squareRect, Radius.circular(bounds.shortestSide * .04));
      canvas.drawRRect(square, bodyFill);
      canvas.drawRRect(square, accent);
      return squareRect;
    }

    Rect drawSuperLoopArt(Rect bounds) {
      // Trailer footprint with a fed inlet and a two-stage separator vessel.
      // Every offset below is chosen so the stack is balanced around the
      // rotation pivot (bounds center), keeping it in sync with the
      // footprint while rotating instead of orbiting off-axis.
      canvas.drawRect(bounds, accent);

      final pillWidth = bounds.width * .34;
      final pillHeight = bounds.height * .13;
      final pillCenterX = bounds.left + bounds.width * .5;
      final pillTop = bounds.top + bounds.height * .10;
      final pillRect = Rect.fromLTWH(
          pillCenterX - pillWidth / 2, pillTop, pillWidth, pillHeight);
      final pill = RRect.fromRectAndRadius(
        pillRect,
        Radius.circular(pillWidth / 2),
      );

      final tubePaint = Paint()
        ..color = const Color(0xFFCDA56A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (bounds.shortestSide * .08).clamp(1.6, 2.6)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(bounds.left + bounds.width * .04, pillTop + pillHeight * .5),
        Offset(pillCenterX - pillWidth / 2, pillTop + pillHeight * .4),
        tubePaint,
      );

      canvas.drawRRect(pill, bodyFill);
      canvas.drawRRect(pill, accent);

      final midCenter =
          Offset(pillCenterX, pillTop + pillHeight + bounds.height * .12);
      final midRadius = bounds.shortestSide * .13;
      canvas.drawCircle(midCenter, midRadius, bodyFill);
      canvas.drawCircle(midCenter, midRadius, accent);

      final bigCenter =
          Offset(midCenter.dx, midCenter.dy + midRadius + bounds.height * .11);
      final bigRadius = bounds.shortestSide * .20;
      canvas.drawCircle(bigCenter, bigRadius, bodyFill);
      canvas.drawCircle(bigCenter, bigRadius, accent);

      final dischargeStart =
          Offset(bigCenter.dx, bigCenter.dy + bigRadius * .8);
      final dischargeEnd = Offset(
          bounds.left + bounds.width * .96, bounds.top + bounds.height * .90);
      final dischargePath = Path()
        ..moveTo(dischargeStart.dx, dischargeStart.dy)
        ..quadraticBezierTo(bounds.left + bounds.width * .82,
            bounds.top + bounds.height * .88, dischargeEnd.dx, dischargeEnd.dy);
      canvas.drawPath(dischargePath, tubePaint);

      return pillRect;
    }

    if (type == _EquipmentType.sandX) {
      drawSandXArt(Rect.fromLTWH(0, 0, size.width, size.height));
      return;
    }

    if (type == _EquipmentType.superLoop) {
      drawSuperLoopArt(Rect.fromLTWH(0, 0, size.width, size.height));
      return;
    }

    if (type == _EquipmentType.sandXSuperLoopCombo) {
      // Two separate footprints side by side, connected by a feed tube.
      final gap = size.width * .04;
      final leftWidth = size.width * .46;
      final rightWidth = size.width - leftWidth - gap;
      final leftBounds = Rect.fromLTWH(0, 0, leftWidth, size.height);
      final rightBounds =
          Rect.fromLTWH(leftWidth + gap, 0, rightWidth, size.height);
      final square = drawSandXArt(leftBounds);
      final pill = drawSuperLoopArt(rightBounds);

      final tubePaint = Paint()
        ..color = const Color(0xFFCDA56A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (size.shortestSide * .06).clamp(1.4, 2.3)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(square.right, square.top + square.height * .4),
        Offset(pill.left, pill.top + pill.height * .4),
        tubePaint,
      );
      return;
    }

    if (type == _EquipmentType.testSeparator) {
      final vesselRect = Rect.fromLTWH(
        size.width * .16,
        size.height * .26,
        size.width * .68,
        size.height * .48,
      );
      final portPaint = Paint()
        ..color = const Color(0xFFCDA56A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (size.shortestSide * .08).clamp(1.8, 3.0)
        ..strokeCap = StrokeCap.round;
      final centerY = size.height * .50;
      canvas.drawLine(
        Offset(size.width * .08, centerY),
        Offset(vesselRect.left, centerY),
        portPaint,
      );
      canvas.drawLine(
        Offset(vesselRect.right, centerY),
        Offset(size.width * .92, centerY),
        portPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          vesselRect,
          Radius.circular(vesselRect.height / 2),
        ),
        bodyFill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          vesselRect,
          Radius.circular(vesselRect.height / 2),
        ),
        accent,
      );

      final legPaint = Paint()
        ..color = const Color(0xFFCDA56A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (size.shortestSide * .07).clamp(1.4, 2.4)
        ..strokeCap = StrokeCap.round;
      final legTop = vesselRect.bottom;
      final legBottom = size.height * .86;
      canvas.drawLine(
        Offset(size.width * .36, legTop),
        Offset(size.width * .36, legBottom),
        legPaint,
      );
      canvas.drawLine(
        Offset(size.width * .64, legTop),
        Offset(size.width * .64, legBottom),
        legPaint,
      );
      return;
    }

    if (type == _EquipmentType.facilities) {
      final bodyRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .16,
          size.height * .16,
          size.width * .68,
          size.height * .68,
        ),
        Radius.circular(size.shortestSide * .08),
      );
      canvas.drawRRect(bodyRect, bodyFill);
      canvas.drawRRect(bodyRect, accent);
      return;
    }

    if (type.isCompletions) {
      _CompletionsArtworkPainter(
        type: type,
        color: const Color(0xFFCDA56A),
        rotationDegrees: 0,
      ).paint(canvas, size);
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
    } else if (type == _EquipmentType.productionTank) {
      final rect = Rect.fromLTWH(size.width * .18, size.height * .16,
          size.width * .64, size.height * .68);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(18)), accent);
      canvas.drawLine(Offset(size.width * .25, size.height * .28),
          Offset(size.width * .75, size.height * .28), accent);
      canvas.drawLine(Offset(size.width * .25, size.height * .72),
          Offset(size.width * .75, size.height * .72), accent);
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePainter oldDelegate) =>
      oldDelegate.type != type ||
      oldDelegate.turns != turns ||
      oldDelegate.rotationDegrees != rotationDegrees ||
      oldDelegate.ironSize != ironSize ||
      oldDelegate.properties != properties ||
      oldDelegate.renderStraightIronInternally != renderStraightIronInternally;
}

class _ResolvedStraightIronPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final double strokeWidth;

  const _ResolvedStraightIronPainter({
    required this.start,
    required this.end,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 1.0
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    final iron = Paint()
      ..color = const Color(0xFFD7D7D7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    canvas.drawLine(start, end, shadow);
    canvas.drawLine(start, end, iron);
  }

  @override
  bool shouldRepaint(covariant _ResolvedStraightIronPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.strokeWidth != strokeWidth;
  }
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
