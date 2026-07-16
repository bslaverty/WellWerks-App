import 'dart:convert';
import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../models/layout_interchange.dart';

class LayoutInterchangeCodec {
  static const String svgFormatName = 'wellwerks-layout-svg';

  const LayoutInterchangeCodec._();

  static WellWerksLayoutInterchange fromDesignerPayload(
    Map<String, dynamic> payload, {
    required double canvasWidth,
    required double canvasHeight,
    required bool showGrid,
  }) {
    final rawItems = (payload['items'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);

    final equipment = <InterchangeEquipmentItem>[];
    final iron = <InterchangeIronSegment>[];
    final fittings = <InterchangeFittingItem>[];

    for (final item in rawItems) {
      final internalType = item['type'] as String? ?? '';
      final stableTypeId = _stableTypeIdForItem(item);
      if (_isStraightIronType(internalType)) {
        iron.add(_ironFromPayloadItem(item, stableTypeId));
        continue;
      }
      if (_isFittingType(internalType)) {
        fittings.add(_fittingFromPayloadItem(item, stableTypeId));
        continue;
      }
      equipment.add(_equipmentFromPayloadItem(item, stableTypeId));
    }

    final model = WellWerksLayoutInterchange(
      format: WellWerksLayoutInterchange.formatName,
      version: WellWerksLayoutInterchange.currentVersion,
      layoutName: (payload['name'] as String? ?? 'New Layout').trim().isEmpty
          ? 'New Layout'
          : (payload['name'] as String).trim(),
      canvas: InterchangeCanvas(
        width: canvasWidth,
        height: canvasHeight,
        gridSize: 24,
        showGrid: showGrid,
      ),
      nextId: payload['nextId'] as int? ?? 1,
      snapToGrid: payload['snapToGrid'] as bool? ?? false,
      libraryKeepOpen: payload['libraryKeepOpen'] as bool? ?? true,
      company: payload['company'] as String? ?? '',
      padName: payload['padName'] as String? ?? '',
      wellName: payload['wellName'] as String? ?? '',
      date: payload['date'] as String? ?? '',
      preparedBy: ((payload['preparedBy'] as String?) ??
              (payload['createdBy'] as String?) ??
              '')
          .trim(),
      notes: payload['notes'] as String? ?? '',
      selectedId: payload['selectedId'] as int?,
      selectedIds:
          (payload['selectedIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => value as int)
              .toList(growable: false),
      selectedEndpointLeading: payload['selectedEndpointLeading'] as bool?,
      selectedBypassHandle: payload['selectedBypassHandle'] as String?,
      equipment: equipment,
      iron: iron,
      fittings: fittings,
      metadata: Map<String, dynamic>.from(
          payload['metadata'] as Map? ?? const <String, dynamic>{}),
    );
    validate(model);
    return model;
  }

  static Map<String, dynamic> toDesignerPayload(
      WellWerksLayoutInterchange model) {
    validate(model);
    final items = <Map<String, dynamic>>[
      ...model.equipment.map(_equipmentToPayloadItem),
      ...model.iron.map(_ironToPayloadItem),
      ...model.fittings.map(_fittingToPayloadItem),
    ]..sort(
        (a, b) => ((a['id'] as int?) ?? 0).compareTo((b['id'] as int?) ?? 0));

    return <String, dynamic>{
      'name': model.layoutName,
      'company': model.company,
      'padName': model.padName,
      'wellName': model.wellName,
      'date': model.date,
      'createdBy': model.preparedBy,
      'preparedBy': model.preparedBy,
      'notes': model.notes,
      'nextId': model.nextId,
      'snapToGrid': model.snapToGrid,
      'libraryKeepOpen': model.libraryKeepOpen,
      if (model.selectedId != null) 'selectedId': model.selectedId,
      if (model.selectedIds.isNotEmpty) 'selectedIds': model.selectedIds,
      if (model.selectedEndpointLeading != null)
        'selectedEndpointLeading': model.selectedEndpointLeading,
      if (model.selectedBypassHandle != null)
        'selectedBypassHandle': model.selectedBypassHandle,
      'items': items,
      'metadata': <String, dynamic>{
        ...model.metadata,
        'version': model.metadata['version'] ?? 1,
        'interchangeCanvas': model.canvas.toJson(),
      },
    };
  }

  static String encodeWellWerksJson(WellWerksLayoutInterchange model) {
    validate(model);
    return model.toPrettyJson();
  }

  static WellWerksLayoutInterchange decodeWellWerksJson(String source) {
    late final dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      throw const LayoutInterchangeException('Invalid JSON file.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const LayoutInterchangeException('Invalid layout file structure.');
    }
    final model = WellWerksLayoutInterchange.fromJson(decoded);
    validate(model);
    return model;
  }

  static String encodeVisioSvg(WellWerksLayoutInterchange model) {
    validate(model);
    final encodedPayload = base64Encode(
      utf8.encode(jsonEncode(model.toJson())),
    );
    final width = model.canvas.width.toStringAsFixed(2);
    final height = model.canvas.height.toStringAsFixed(2);
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
          '<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="$width" height="$height" viewBox="0 0 $width $height" data-wellwerks-format="$svgFormatName" data-wellwerks-version="${model.version}">')
      ..writeln(
          '<metadata id="wellwerks-layout-interchange" data-wellwerks-format="${WellWerksLayoutInterchange.formatName}" data-wellwerks-version="${model.version}">$encodedPayload</metadata>');

    for (final item in model.equipment) {
      buffer.writeln(_svgGroupForEquipment(item));
    }
    for (final item in model.fittings) {
      buffer.writeln(_svgGroupForFitting(item));
    }
    for (final item in model.iron) {
      buffer.writeln(_svgGroupForIron(item));
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }

  static WellWerksLayoutInterchange decodeVisioSvg(String source) {
    late final XmlDocument document;
    try {
      document = XmlDocument.parse(source);
    } catch (_) {
      throw const LayoutInterchangeException('Corrupted SVG file.');
    }
    final root = document.rootElement;
    if (root.name.local != 'svg') {
      throw const LayoutInterchangeException('Unsupported SVG document.');
    }
    final format = root.getAttribute('data-wellwerks-format');
    if (format != svgFormatName) {
      throw const LayoutInterchangeException(
          'This SVG was not created with WellWerks-compatible equipment data.');
    }

    final metadataNode = document.findAllElements('metadata').firstWhere(
          (node) => node.getAttribute('id') == 'wellwerks-layout-interchange',
          orElse: () => XmlElement(XmlName('missing')),
        );
    if (metadataNode.name.local == 'missing') {
      throw const LayoutInterchangeException(
          'This SVG was not created with WellWerks-compatible equipment data.');
    }
    final encoded = metadataNode.innerText.trim();
    if (encoded.isEmpty) {
      throw const LayoutInterchangeException(
          'WellWerks SVG metadata is empty.');
    }

    String decoded;
    try {
      decoded = utf8.decode(base64Decode(encoded));
    } catch (_) {
      throw const LayoutInterchangeException(
          'Corrupted WellWerks SVG metadata.');
    }

    final model = decodeWellWerksJson(decoded);
    final exportedGroups = document
        .findAllElements('g')
        .where((node) => node.getAttribute('data-wellwerks-id') != null)
        .length;
    final expectedGroups =
        model.equipment.length + model.fittings.length + model.iron.length;
    if (exportedGroups < expectedGroups) {
      throw const LayoutInterchangeException(
          'WellWerks SVG metadata is incomplete.');
    }
    return model;
  }

  static void validate(WellWerksLayoutInterchange model) {
    if (model.format != WellWerksLayoutInterchange.formatName) {
      throw const LayoutInterchangeException('Unsupported layout format.');
    }
    if (model.version != WellWerksLayoutInterchange.currentVersion) {
      throw LayoutInterchangeException(
          'Unsupported layout version: ${model.version}.');
    }
    if (model.canvas.width <= 0 || model.canvas.height <= 0) {
      throw const LayoutInterchangeException('Canvas size is invalid.');
    }
    if (model.equipment.isEmpty &&
        model.iron.isEmpty &&
        model.fittings.isEmpty) {
      throw const LayoutInterchangeException('Layout file is empty.');
    }

    final ids = <int>{};
    final portMap = <int, Set<String>>{};
    for (final item in model.equipment) {
      _validateType(item.stableTypeId, item.internalType);
      if (!ids.add(item.id)) {
        throw LayoutInterchangeException('Duplicate ID detected: ${item.id}.');
      }
      portMap[item.id] = item.ports.map((port) => port.id).toSet();
    }
    for (final item in model.fittings) {
      _validateType(item.stableTypeId, item.internalType);
      if (!ids.add(item.id)) {
        throw LayoutInterchangeException('Duplicate ID detected: ${item.id}.');
      }
      portMap[item.id] = item.ports.map((port) => port.id).toSet();
    }
    for (final segment in model.iron) {
      _validateType(segment.stableTypeId, segment.internalType);
      if (!ids.add(segment.id)) {
        throw LayoutInterchangeException(
            'Duplicate ID detected: ${segment.id}.');
      }
      _validateConnectionReference(segment.startEquipmentId,
          segment.startPortId, portMap, 'start', segment.id);
      _validateConnectionReference(segment.endEquipmentId, segment.endPortId,
          portMap, 'end', segment.id);
    }
  }

  static void _validateType(String stableTypeId, String internalType) {
    if (stableTypeId.isEmpty || internalType.isEmpty) {
      throw const LayoutInterchangeException('Unknown equipment type.');
    }
    if (!_stableToInternalDefaults.containsKey(stableTypeId) &&
        !_knownInternalTypes.contains(internalType)) {
      throw LayoutInterchangeException(
          'Unknown equipment type: $stableTypeId.');
    }
  }

  static void _validateConnectionReference(
    int? itemId,
    String? portId,
    Map<int, Set<String>> portMap,
    String endpoint,
    int ironId,
  ) {
    if (itemId == null && (portId == null || portId.isEmpty)) {
      return;
    }
    if (itemId == null || portId == null || portId.isEmpty) {
      throw LayoutInterchangeException(
          'Iron $ironId has incomplete $endpoint connection metadata.');
    }
    final ports = portMap[itemId];
    if (ports == null) {
      throw LayoutInterchangeException(
          'Iron $ironId references missing equipment ID $itemId.');
    }
    if (!ports.contains(portId)) {
      throw LayoutInterchangeException(
          'Iron $ironId references missing port $portId on equipment $itemId.');
    }
  }

  static InterchangeEquipmentItem _equipmentFromPayloadItem(
    Map<String, dynamic> item,
    String stableTypeId,
  ) {
    final ports = _portsForItem(item);
    return InterchangeEquipmentItem(
      id: item['id'] as int? ?? 0,
      stableTypeId: stableTypeId,
      internalType: item['type'] as String? ?? '',
      x: (item['x'] as num?)?.toDouble() ?? 0,
      y: (item['y'] as num?)?.toDouble() ?? 0,
      width: (item['width'] as num?)?.toDouble() ?? 0,
      height: (item['height'] as num?)?.toDouble() ?? 0,
      rotationTurns: item['rotationTurns'] as int? ?? 0,
      label: _displayLabelForPayloadItem(item),
      locked: item['locked'] as bool? ?? false,
      properties: Map<String, String>.from(
          item['properties'] as Map? ?? const <String, String>{}),
      ports: ports,
    );
  }

  static InterchangeFittingItem _fittingFromPayloadItem(
    Map<String, dynamic> item,
    String stableTypeId,
  ) {
    final ports = _portsForItem(item);
    return InterchangeFittingItem(
      id: item['id'] as int? ?? 0,
      stableTypeId: stableTypeId,
      internalType: item['type'] as String? ?? '',
      x: (item['x'] as num?)?.toDouble() ?? 0,
      y: (item['y'] as num?)?.toDouble() ?? 0,
      width: (item['width'] as num?)?.toDouble() ?? 0,
      height: (item['height'] as num?)?.toDouble() ?? 0,
      rotationTurns: item['rotationTurns'] as int? ?? 0,
      label: _displayLabelForPayloadItem(item),
      locked: item['locked'] as bool? ?? false,
      properties: Map<String, String>.from(
          item['properties'] as Map? ?? const <String, String>{}),
      ports: ports,
    );
  }

  static InterchangeIronSegment _ironFromPayloadItem(
    Map<String, dynamic> item,
    String stableTypeId,
  ) {
    final props = Map<String, String>.from(
        item['properties'] as Map? ?? const <String, String>{});
    final start = _ironEndpointFromPayload(item, true);
    final end = _ironEndpointFromPayload(item, false);
    return InterchangeIronSegment(
      id: item['id'] as int? ?? 0,
      stableTypeId: stableTypeId,
      internalType: item['type'] as String? ?? 'ironHorizontal',
      ironSize: props['ironSize'] ?? '3',
      start: InterchangePoint(x: start.$1, y: start.$2),
      end: InterchangePoint(x: end.$1, y: end.$2),
      locked: item['locked'] as bool? ?? false,
      properties: props,
      startEquipmentId: int.tryParse(props['anchorStartItemId'] ?? ''),
      startPortId: props['anchorStartSide'],
      endEquipmentId: int.tryParse(props['anchorEndItemId'] ?? ''),
      endPortId: props['anchorEndSide'],
      startJointId: props['jointStart'],
      endJointId: props['jointEnd'],
    );
  }

  static Map<String, dynamic> _equipmentToPayloadItem(
      InterchangeEquipmentItem item) {
    final props = Map<String, String>.from(item.properties);
    _applyStableDefaults(item.stableTypeId, props);
    return <String, dynamic>{
      'id': item.id,
      'type': item.internalType,
      'x': item.x,
      'y': item.y,
      'width': item.width,
      'height': item.height,
      'rotationTurns': item.rotationTurns,
      'locked': item.locked,
      'properties': props,
    };
  }

  static Map<String, dynamic> _fittingToPayloadItem(
      InterchangeFittingItem item) {
    return <String, dynamic>{
      'id': item.id,
      'type': item.internalType,
      'x': item.x,
      'y': item.y,
      'width': item.width,
      'height': item.height,
      'rotationTurns': item.rotationTurns,
      'locked': item.locked,
      'properties': Map<String, String>.from(item.properties),
    };
  }

  static Map<String, dynamic> _ironToPayloadItem(InterchangeIronSegment item) {
    final minX = math.min(item.start.x, item.end.x);
    final minY = math.min(item.start.y, item.end.y);
    final maxX = math.max(item.start.x, item.end.x);
    final maxY = math.max(item.start.y, item.end.y);
    final props = Map<String, String>.from(item.properties)
      ..['ironSize'] = item.ironSize
      ..['freeAngleIron'] = 'true'
      ..['freeAngleStartX'] = item.start.x.toStringAsFixed(4)
      ..['freeAngleStartY'] = item.start.y.toStringAsFixed(4)
      ..['freeAngleEndX'] = item.end.x.toStringAsFixed(4)
      ..['freeAngleEndY'] = item.end.y.toStringAsFixed(4);
    if (item.startEquipmentId != null && item.startPortId != null) {
      props['anchorStartItemId'] = item.startEquipmentId.toString();
      props['anchorStartSide'] = item.startPortId!;
    }
    if (item.endEquipmentId != null && item.endPortId != null) {
      props['anchorEndItemId'] = item.endEquipmentId.toString();
      props['anchorEndSide'] = item.endPortId!;
    }
    return <String, dynamic>{
      'id': item.id,
      'type': item.internalType,
      'x': minX,
      'y': minY,
      'width': math.max(1.0, maxX - minX),
      'height': math.max(1.0, maxY - minY),
      'rotationTurns': 0,
      'locked': item.locked,
      'properties': props,
    };
  }

  static String _stableTypeIdForItem(Map<String, dynamic> item) {
    final internalType = item['type'] as String? ?? '';
    final props = Map<String, String>.from(
        item['properties'] as Map? ?? const <String, String>{});
    switch (internalType) {
      case 'chokeManifold':
        return props['chokeSize'] == '2'
            ? 'choke_manifold_2'
            : 'choke_manifold_3';
      case 'plugCatcher':
        return 'double_plug_catcher';
      case 'lineHeater':
        return 'line_heater';
      case 'esdValve':
        return 'esd_valve';
      case 'testSeparator':
        return 'test_separator';
      case 'sphericalSandSep':
        return 'spherical_sand_separator';
      case 'cyclonicSandSep':
        return 'cyclonic_sand_separator';
      case 'flowbackTank':
        switch (props['equipmentVariant']) {
          case 'flowbackGasBusters':
            return 'flowback_tank_gas_busters';
          case 'flowbackHalf':
            return 'half_flowback_tank';
          case 'flowbackQuarter':
            return 'quarter_flowback_tank';
          default:
            return 'flowback_tank';
        }
      case 'productionTank':
        return 'production_tank';
      case 'facilities':
        return 'facilities';
      case 'flare':
        return 'flare';
      case 'compressor':
        return 'compressor';
      case 'wellhead':
        return 'wellhead';
      case 'ironHorizontal':
      case 'ironVertical':
        return 'straight_iron';
      case 'teeUp':
        return 'tee_up';
      case 'teeRight':
        return 'tee_right';
      case 'teeDown':
        return 'tee_down';
      case 'teeLeft':
        return 'tee_left';
      case 'elbowUpRight':
        return 'elbow_up_right';
      case 'elbowRightDown':
        return 'elbow_right_down';
      case 'elbowDownLeft':
        return 'elbow_down_left';
      case 'elbowLeftUp':
        return 'elbow_left_up';
      case 'bypass':
        return 'equipment_bypass';
      default:
        if (internalType.isEmpty) {
          throw const LayoutInterchangeException('Unknown equipment type.');
        }
        return internalType;
    }
  }

  static String _displayLabelForPayloadItem(Map<String, dynamic> item) {
    final internalType = item['type'] as String? ?? '';
    final props = Map<String, String>.from(
        item['properties'] as Map? ?? const <String, String>{});
    final custom = props['displayLabel']?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    switch (internalType) {
      case 'chokeManifold':
        final size = props['chokeSize'] == '2' ? '2' : '3';
        return '$size" Choke Manifold';
      case 'flowbackTank':
        switch (props['equipmentVariant']) {
          case 'flowbackGasBusters':
            return 'Flowback Tank with Gas Busters';
          case 'flowbackHalf':
            return 'Half Flowback Tank';
          case 'flowbackQuarter':
            return 'Quarter Flowback Tank';
          default:
            return 'Flowback Tank';
        }
      case 'plugCatcher':
        return 'Double Plug Catcher';
      case 'lineHeater':
        return 'Line Heater';
      case 'esdValve':
        return 'ESD Valve';
      case 'testSeparator':
        return 'Test Separator';
      case 'sphericalSandSep':
        return 'Spherical Sand Sep';
      case 'cyclonicSandSep':
        return 'Cyclonic Sand Sep';
      case 'productionTank':
        return 'Production Tank';
      case 'facilities':
        return 'Facilities';
      case 'flare':
        return 'Flare';
      case 'compressor':
        return 'Compressor';
      case 'wellhead':
        return 'Wellhead';
      case 'bypass':
        return 'Bypass';
      case 'teeUp':
        return 'Tee Up';
      case 'teeRight':
        return 'Tee Right';
      case 'teeDown':
        return 'Tee Down';
      case 'teeLeft':
        return 'Tee Left';
      case 'elbowUpRight':
      case 'elbowRightDown':
      case 'elbowDownLeft':
      case 'elbowLeftUp':
        return '90° Fitting';
      default:
        return internalType;
    }
  }

  static void _applyStableDefaults(
      String stableTypeId, Map<String, String> props) {
    final defaults = _stableToInternalDefaults[stableTypeId];
    if (defaults == null) return;
    for (final entry in defaults.entries) {
      props.putIfAbsent(entry.key, () => entry.value);
    }
  }

  static bool _isStraightIronType(String internalType) {
    return internalType == 'ironHorizontal' || internalType == 'ironVertical';
  }

  static bool _isFittingType(String internalType) {
    return internalType == 'bypass' ||
        internalType.startsWith('tee') ||
        internalType.startsWith('elbow');
  }

  static (double, double) _ironEndpointFromPayload(
      Map<String, dynamic> item, bool leading) {
    final props = Map<String, String>.from(
        item['properties'] as Map? ?? const <String, String>{});
    final xKey = leading ? 'freeAngleStartX' : 'freeAngleEndX';
    final yKey = leading ? 'freeAngleStartY' : 'freeAngleEndY';
    final x = double.tryParse(props[xKey] ?? '');
    final y = double.tryParse(props[yKey] ?? '');
    if (x != null && y != null) {
      return (x, y);
    }
    final baseX = (item['x'] as num?)?.toDouble() ?? 0;
    final baseY = (item['y'] as num?)?.toDouble() ?? 0;
    final width = (item['width'] as num?)?.toDouble() ?? 0;
    final height = (item['height'] as num?)?.toDouble() ?? 0;
    final internalType = item['type'] as String? ?? '';
    if (internalType == 'ironHorizontal') {
      return (leading ? baseX : baseX + width, baseY + height / 2);
    }
    return (baseX + width / 2, leading ? baseY : baseY + height);
  }

  static List<InterchangePort> _portsForItem(Map<String, dynamic> item) {
    final definitions = _portFractionsForType(item['type'] as String? ?? '');
    final width = (item['width'] as num?)?.toDouble() ?? 0;
    final height = (item['height'] as num?)?.toDouble() ?? 0;
    final turns = item['rotationTurns'] as int? ?? 0;
    final x = (item['x'] as num?)?.toDouble() ?? 0;
    final y = (item['y'] as num?)?.toDouble() ?? 0;
    return definitions.entries.map((entry) {
      final local = _rotatedLocalPoint(
        width: width,
        height: height,
        turns: turns,
        point: (entry.value.$1 * width, entry.value.$2 * height),
        insetFitting: (item['type'] as String? ?? '').startsWith('tee') ||
            (item['type'] as String? ?? '').startsWith('elbow'),
      );
      return InterchangePort(
        id: entry.key,
        x: x + local.$1,
        y: y + local.$2,
      );
    }).toList(growable: false);
  }

  static (double, double) _rotatedLocalPoint({
    required double width,
    required double height,
    required int turns,
    required (double, double) point,
    required bool insetFitting,
  }) {
    var px = point.$1;
    var py = point.$2;
    if (insetFitting) {
      final shortest = math.min(width, height);
      final inset = shortest < 66 ? 2.0 : 3.0;
      final usableWidth = math.max(0.0, width - inset * 2);
      final usableHeight = math.max(0.0, height - inset * 2);
      final u = width == 0 ? 0.0 : point.$1 / width;
      final v = height == 0 ? 0.0 : point.$2 / height;
      px = inset + u * usableWidth;
      py = inset + v * usableHeight;
    }
    final centerX = width / 2;
    final centerY = height / 2;
    final dx = px - centerX;
    final dy = py - centerY;
    switch (((turns % 4) + 4) % 4) {
      case 1:
        return (centerX - dy, centerY + dx);
      case 2:
        return (centerX - dx, centerY - dy);
      case 3:
        return (centerX + dy, centerY - dx);
      default:
        return (px, py);
    }
  }

  static Map<String, (double, double)> _portFractionsForType(String type) {
    switch (type) {
      case 'wellhead':
      case 'esdValve':
      case 'lineHeater':
      case 'cyclonicSandSep':
      case 'sphericalSandSep':
      case 'flare':
      case 'compressor':
        return const <String, (double, double)>{
          'top': (0.5, 0.08),
          'right': (0.92, 0.5),
          'bottom': (0.5, 0.92),
          'left': (0.08, 0.5),
        };
      case 'chokeManifold':
        return const <String, (double, double)>{
          'inletTopCenter': (0.5, 0.08),
          'outletBottomCenter': (0.5, 0.92),
        };
      case 'plugCatcher':
      case 'testSeparator':
        return const <String, (double, double)>{
          'left': (0.08, 0.5),
          'right': (0.92, 0.5),
        };
      case 'flowbackTank':
      case 'productionTank':
        return const <String, (double, double)>{
          'top': (0.5, 0.08),
          'right': (0.92, 0.5),
          'bottom': (0.5, 0.92),
          'left': (0.08, 0.5),
        };
      case 'facilities':
        return const <String, (double, double)>{
          'topLeft': (0.24, 0.16),
          'topCenter': (0.50, 0.16),
          'topRight': (0.76, 0.16),
          'rightTop': (0.84, 0.30),
          'rightCenter': (0.84, 0.50),
          'rightBottom': (0.84, 0.70),
          'bottomRight': (0.76, 0.84),
          'bottomCenter': (0.50, 0.84),
          'bottomLeft': (0.24, 0.84),
          'leftBottom': (0.16, 0.70),
          'leftCenter': (0.16, 0.50),
          'leftTop': (0.16, 0.30),
        };
      case 'bypass':
        return const <String, (double, double)>{
          'mainTop': (0.28, 0.14),
          'mainBottom': (0.28, 0.86),
          'upperValveOutlet': (0.82, 0.34),
          'lowerValveOutlet': (0.82, 0.66),
        };
      case 'teeUp':
        return const <String, (double, double)>{
          'runStart': (0.08, 0.5),
          'runEnd': (0.92, 0.5),
          'branch': (0.5, 0.08),
        };
      case 'teeRight':
        return const <String, (double, double)>{
          'runStart': (0.5, 0.08),
          'runEnd': (0.5, 0.92),
          'branch': (0.92, 0.5),
        };
      case 'teeDown':
        return const <String, (double, double)>{
          'runStart': (0.08, 0.5),
          'runEnd': (0.92, 0.5),
          'branch': (0.5, 0.92),
        };
      case 'teeLeft':
        return const <String, (double, double)>{
          'runStart': (0.5, 0.08),
          'runEnd': (0.5, 0.92),
          'branch': (0.08, 0.5),
        };
      case 'elbowUpRight':
        return const <String, (double, double)>{
          'inlet': (0.5, 0.92),
          'outlet': (0.92, 0.5),
        };
      case 'elbowRightDown':
        return const <String, (double, double)>{
          'inlet': (0.08, 0.5),
          'outlet': (0.5, 0.92),
        };
      case 'elbowDownLeft':
        return const <String, (double, double)>{
          'inlet': (0.5, 0.08),
          'outlet': (0.08, 0.5),
        };
      case 'elbowLeftUp':
        return const <String, (double, double)>{
          'inlet': (0.92, 0.5),
          'outlet': (0.5, 0.08),
        };
      default:
        return const <String, (double, double)>{};
    }
  }

  static String _svgGroupForEquipment(InterchangeEquipmentItem item) {
    final buffer = StringBuffer()
      ..write('<g data-wellwerks-kind="equipment"')
      ..write(' data-wellwerks-type="${_escapeAttr(item.stableTypeId)}"')
      ..write(
          ' data-wellwerks-internal-type="${_escapeAttr(item.internalType)}"')
      ..write(' data-wellwerks-id="${item.id}"')
      ..write(' data-wellwerks-version="1"')
      ..write(' data-wellwerks-rotation="${item.rotationTurns}"')
      ..write(
          ' transform="translate(${item.x.toStringAsFixed(2)} ${item.y.toStringAsFixed(2)}) rotate(${(item.rotationTurns * 90).toStringAsFixed(0)} ${(item.width / 2).toStringAsFixed(2)} ${(item.height / 2).toStringAsFixed(2)})">');
    buffer.write(_svgShapeForBoxItem(
      item.id,
      item.x,
      item.y,
      item.internalType,
      item.width,
      item.height,
      item.properties,
      item.label,
      item.ports,
    ));
    buffer.write('</g>');
    return buffer.toString();
  }

  static String _svgGroupForFitting(InterchangeFittingItem item) {
    final buffer = StringBuffer()
      ..write('<g data-wellwerks-kind="fitting"')
      ..write(' data-wellwerks-type="${_escapeAttr(item.stableTypeId)}"')
      ..write(
          ' data-wellwerks-internal-type="${_escapeAttr(item.internalType)}"')
      ..write(' data-wellwerks-id="${item.id}"')
      ..write(' data-wellwerks-version="1"')
      ..write(' data-wellwerks-rotation="${item.rotationTurns}"')
      ..write(
          ' transform="translate(${item.x.toStringAsFixed(2)} ${item.y.toStringAsFixed(2)}) rotate(${(item.rotationTurns * 90).toStringAsFixed(0)} ${(item.width / 2).toStringAsFixed(2)} ${(item.height / 2).toStringAsFixed(2)})">');
    buffer.write(_svgShapeForBoxItem(
      item.id,
      item.x,
      item.y,
      item.internalType,
      item.width,
      item.height,
      item.properties,
      item.label,
      item.ports,
    ));
    buffer.write('</g>');
    return buffer.toString();
  }

  static String _svgGroupForIron(InterchangeIronSegment item) {
    final buffer = StringBuffer()
      ..write('<g data-wellwerks-kind="iron"')
      ..write(' data-wellwerks-type="${_escapeAttr(item.stableTypeId)}"')
      ..write(
          ' data-wellwerks-internal-type="${_escapeAttr(item.internalType)}"')
      ..write(' data-wellwerks-id="${item.id}"')
      ..write(' data-wellwerks-iron-size="${_escapeAttr(item.ironSize)}"');
    if (item.startEquipmentId != null) {
      buffer
          .write(' data-wellwerks-start-equipment="${item.startEquipmentId}"');
    }
    if (item.startPortId != null) {
      buffer.write(
          ' data-wellwerks-start-port="${_escapeAttr(item.startPortId!)}"');
    }
    if (item.endEquipmentId != null) {
      buffer.write(' data-wellwerks-end-equipment="${item.endEquipmentId}"');
    }
    if (item.endPortId != null) {
      buffer
          .write(' data-wellwerks-end-port="${_escapeAttr(item.endPortId!)}"');
    }
    buffer.write('>');
    buffer.write(
        '<path d="M ${item.start.x.toStringAsFixed(2)} ${item.start.y.toStringAsFixed(2)} L ${item.end.x.toStringAsFixed(2)} ${item.end.y.toStringAsFixed(2)}" stroke="#D7D7D7" stroke-width="2" fill="none" stroke-linecap="square" />');
    buffer.write('</g>');
    return buffer.toString();
  }

  static String _svgShapeForBoxItem(
    int itemId,
    double originX,
    double originY,
    String internalType,
    double width,
    double height,
    Map<String, String> properties,
    String label,
    List<InterchangePort> ports,
  ) {
    final buffer = StringBuffer();
    const gold = '#CDA56A';
    const black = '#000000';
    switch (internalType) {
      case 'chokeManifold':
        buffer
          ..write(
              '<rect x="${(width * 0.16).toStringAsFixed(2)}" y="${(height * 0.16).toStringAsFixed(2)}" width="${(width * 0.68).toStringAsFixed(2)}" height="${(height * 0.68).toStringAsFixed(2)}" rx="4" fill="$black" stroke="$gold" stroke-width="1.6" />')
          ..write(
              '<line x1="${(width * 0.50).toStringAsFixed(2)}" y1="${(height * 0.08).toStringAsFixed(2)}" x2="${(width * 0.50).toStringAsFixed(2)}" y2="${(height * 0.16).toStringAsFixed(2)}" stroke="$gold" stroke-width="1.6" />')
          ..write(
              '<line x1="${(width * 0.50).toStringAsFixed(2)}" y1="${(height * 0.84).toStringAsFixed(2)}" x2="${(width * 0.50).toStringAsFixed(2)}" y2="${(height * 0.92).toStringAsFixed(2)}" stroke="$gold" stroke-width="1.6" />')
          ..write(
              '<line x1="${(width * 0.32).toStringAsFixed(2)}" y1="${(height * 0.16).toStringAsFixed(2)}" x2="${(width * 0.32).toStringAsFixed(2)}" y2="${(height * 0.84).toStringAsFixed(2)}" stroke="$gold" stroke-width="1.6" />')
          ..write(
              '<line x1="${(width * 0.68).toStringAsFixed(2)}" y1="${(height * 0.16).toStringAsFixed(2)}" x2="${(width * 0.68).toStringAsFixed(2)}" y2="${(height * 0.84).toStringAsFixed(2)}" stroke="$gold" stroke-width="1.6" />')
          ..write(
              '<line x1="${(width * 0.32).toStringAsFixed(2)}" y1="${(height * 0.28).toStringAsFixed(2)}" x2="${(width * 0.68).toStringAsFixed(2)}" y2="${(height * 0.28).toStringAsFixed(2)}" stroke="$gold" stroke-width="1.6" />')
          ..write(
              '<line x1="${(width * 0.32).toStringAsFixed(2)}" y1="${(height * 0.72).toStringAsFixed(2)}" x2="${(width * 0.68).toStringAsFixed(2)}" y2="${(height * 0.72).toStringAsFixed(2)}" stroke="$gold" stroke-width="1.6" />')
          ..write(
              '<line x1="${(width * 0.50).toStringAsFixed(2)}" y1="${(height * 0.28).toStringAsFixed(2)}" x2="${(width * 0.50).toStringAsFixed(2)}" y2="${(height * 0.72).toStringAsFixed(2)}" stroke="$gold" stroke-width="1.6" />');
        for (final center in const <(double, double)>[
          (0.30, 0.22),
          (0.70, 0.22)
        ]) {
          buffer
            ..write(
                '<circle cx="${(width * center.$1).toStringAsFixed(2)}" cy="${(height * center.$2).toStringAsFixed(2)}" r="3.6" fill="none" stroke="$gold" stroke-width="1.4" />')
            ..write(
                '<line x1="${(width * center.$1 - 3.6).toStringAsFixed(2)}" y1="${(height * center.$2).toStringAsFixed(2)}" x2="${(width * center.$1 + 3.6).toStringAsFixed(2)}" y2="${(height * center.$2).toStringAsFixed(2)}" stroke="$gold" stroke-width="1.2" />')
            ..write(
                '<line x1="${(width * center.$1).toStringAsFixed(2)}" y1="${(height * center.$2 - 3.6).toStringAsFixed(2)}" x2="${(width * center.$1).toStringAsFixed(2)}" y2="${(height * center.$2 + 3.6).toStringAsFixed(2)}" stroke="$gold" stroke-width="1.2" />');
        }
        for (final center in const <(double, double)>[
          (0.32, 0.36),
          (0.68, 0.36),
          (0.50, 0.50),
          (0.32, 0.64),
          (0.68, 0.64)
        ]) {
          buffer
            ..write(
                '<line x1="${(width * center.$1 - 2.2).toStringAsFixed(2)}" y1="${(height * center.$2 - 2.2).toStringAsFixed(2)}" x2="${(width * center.$1 + 2.2).toStringAsFixed(2)}" y2="${(height * center.$2 + 2.2).toStringAsFixed(2)}" stroke="$gold" stroke-width="1.1" />')
            ..write(
                '<line x1="${(width * center.$1 - 2.2).toStringAsFixed(2)}" y1="${(height * center.$2 + 2.2).toStringAsFixed(2)}" x2="${(width * center.$1 + 2.2).toStringAsFixed(2)}" y2="${(height * center.$2 - 2.2).toStringAsFixed(2)}" stroke="$gold" stroke-width="1.1" />');
        }
        break;
      case 'flowbackTank':
      case 'productionTank':
        buffer.write(
            '<rect x="${(width * 0.08).toStringAsFixed(2)}" y="${(height * 0.08).toStringAsFixed(2)}" width="${(width * 0.84).toStringAsFixed(2)}" height="${(height * 0.84).toStringAsFixed(2)}" rx="4" fill="$black" stroke="$gold" stroke-width="1.6" />');
        if (properties['equipmentVariant'] == 'flowbackGasBusters') {
          for (final xFactor in const <double>[0.36, 0.64]) {
            buffer.write(
                '<line x1="${(width * xFactor).toStringAsFixed(2)}" y1="${(height * 0.25).toStringAsFixed(2)}" x2="${(width * xFactor).toStringAsFixed(2)}" y2="${(height * 0.75).toStringAsFixed(2)}" stroke="$gold" stroke-width="2.0" stroke-linecap="round" />');
          }
        }
        break;
      case 'plugCatcher':
        buffer
          ..write(
              '<rect x="${(width * 0.14).toStringAsFixed(2)}" y="${(height * 0.22).toStringAsFixed(2)}" width="${(width * 0.72).toStringAsFixed(2)}" height="${(height * 0.56).toStringAsFixed(2)}" rx="4" fill="$black" stroke="$gold" stroke-width="1.6" />')
          ..write(
              '<line x1="${(width * 0.08).toStringAsFixed(2)}" y1="${(height * 0.50).toStringAsFixed(2)}" x2="${(width * 0.92).toStringAsFixed(2)}" y2="${(height * 0.50).toStringAsFixed(2)}" stroke="$gold" stroke-width="1.6" />');
        break;
      case 'testSeparator':
        buffer
          ..write(
              '<ellipse cx="${(width * 0.50).toStringAsFixed(2)}" cy="${(height * 0.50).toStringAsFixed(2)}" rx="${(width * 0.34).toStringAsFixed(2)}" ry="${(height * 0.24).toStringAsFixed(2)}" fill="$black" stroke="$gold" stroke-width="1.6" />')
          ..write(
              '<line x1="${(width * 0.08).toStringAsFixed(2)}" y1="${(height * 0.50).toStringAsFixed(2)}" x2="${(width * 0.16).toStringAsFixed(2)}" y2="${(height * 0.50).toStringAsFixed(2)}" stroke="$gold" stroke-width="1.6" />')
          ..write(
              '<line x1="${(width * 0.84).toStringAsFixed(2)}" y1="${(height * 0.50).toStringAsFixed(2)}" x2="${(width * 0.92).toStringAsFixed(2)}" y2="${(height * 0.50).toStringAsFixed(2)}" stroke="$gold" stroke-width="1.6" />');
        break;
      case 'bypass':
        buffer
          ..write(
              '<line x1="${(width * 0.28).toStringAsFixed(2)}" y1="${(height * 0.14).toStringAsFixed(2)}" x2="${(width * 0.28).toStringAsFixed(2)}" y2="${(height * 0.86).toStringAsFixed(2)}" stroke="#D7D7D7" stroke-width="2" />')
          ..write(
              '<line x1="${(width * 0.28).toStringAsFixed(2)}" y1="${(height * 0.34).toStringAsFixed(2)}" x2="${(width * 0.82).toStringAsFixed(2)}" y2="${(height * 0.34).toStringAsFixed(2)}" stroke="#D7D7D7" stroke-width="2" />')
          ..write(
              '<line x1="${(width * 0.28).toStringAsFixed(2)}" y1="${(height * 0.66).toStringAsFixed(2)}" x2="${(width * 0.82).toStringAsFixed(2)}" y2="${(height * 0.66).toStringAsFixed(2)}" stroke="#D7D7D7" stroke-width="2" />');
        break;
      case 'teeUp':
      case 'teeRight':
      case 'teeDown':
      case 'teeLeft':
      case 'elbowUpRight':
      case 'elbowRightDown':
      case 'elbowDownLeft':
      case 'elbowLeftUp':
        buffer.write(_svgFittingStroke(internalType, width, height));
        break;
      case 'facilities':
        buffer.write(
            '<rect x="0" y="0" width="${width.toStringAsFixed(2)}" height="${height.toStringAsFixed(2)}" rx="8" fill="$black" stroke="$gold" stroke-width="1.8" />');
        break;
      default:
        buffer.write(
            '<rect x="0" y="0" width="${width.toStringAsFixed(2)}" height="${height.toStringAsFixed(2)}" rx="6" fill="$black" stroke="$gold" stroke-width="1.6" />');
        break;
    }
    buffer.write(_svgPorts(itemId, ports, originX, originY));
    if (label.isNotEmpty) {
      buffer.write(
          '<text x="${(width / 2).toStringAsFixed(2)}" y="${(height + 14).toStringAsFixed(2)}" fill="#FFFFFF" font-size="10" text-anchor="middle">${_escapeText(label)}</text>');
    }
    return buffer.toString();
  }

  static String _svgPorts(
      int itemId, List<InterchangePort> ports, double originX, double originY) {
    final buffer = StringBuffer();
    for (final port in ports) {
      buffer.write(
          '<circle cx="${(port.x - originX).toStringAsFixed(2)}" cy="${(port.y - originY).toStringAsFixed(2)}" r="2" fill="#CDA56A" fill-opacity="0" stroke="none" data-wellwerks-port-id="${_escapeAttr(port.id)}" data-wellwerks-equipment-id="$itemId" />');
    }
    return buffer.toString();
  }

  static String _svgFittingStroke(
      String internalType, double width, double height) {
    const stroke = '#D7D7D7';
    switch (internalType) {
      case 'teeUp':
        return '<path d="M ${(width * 0.08).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)} L ${(width * 0.92).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)} M ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)} L ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.08).toStringAsFixed(2)}" stroke="$stroke" stroke-width="2" fill="none" />';
      case 'teeRight':
        return '<path d="M ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.08).toStringAsFixed(2)} L ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.92).toStringAsFixed(2)} M ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)} L ${(width * 0.92).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)}" stroke="$stroke" stroke-width="2" fill="none" />';
      case 'teeDown':
        return '<path d="M ${(width * 0.08).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)} L ${(width * 0.92).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)} M ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)} L ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.92).toStringAsFixed(2)}" stroke="$stroke" stroke-width="2" fill="none" />';
      case 'teeLeft':
        return '<path d="M ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.08).toStringAsFixed(2)} L ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.92).toStringAsFixed(2)} M ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)} L ${(width * 0.08).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)}" stroke="$stroke" stroke-width="2" fill="none" />';
      case 'elbowUpRight':
        return '<path d="M ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.92).toStringAsFixed(2)} L ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)} L ${(width * 0.92).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)}" stroke="$stroke" stroke-width="2" fill="none" />';
      case 'elbowRightDown':
        return '<path d="M ${(width * 0.08).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)} L ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)} L ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.92).toStringAsFixed(2)}" stroke="$stroke" stroke-width="2" fill="none" />';
      case 'elbowDownLeft':
        return '<path d="M ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.08).toStringAsFixed(2)} L ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)} L ${(width * 0.08).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)}" stroke="$stroke" stroke-width="2" fill="none" />';
      case 'elbowLeftUp':
        return '<path d="M ${(width * 0.92).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)} L ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.50).toStringAsFixed(2)} L ${(width * 0.50).toStringAsFixed(2)} ${(height * 0.08).toStringAsFixed(2)}" stroke="$stroke" stroke-width="2" fill="none" />';
      default:
        return '';
    }
  }

  static String _escapeAttr(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  static String _escapeText(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  static const Set<String> _knownInternalTypes = <String>{
    'wellhead',
    'esdValve',
    'lineHeater',
    'plugCatcher',
    'cyclonicSandSep',
    'sphericalSandSep',
    'chokeManifold',
    'flowbackTank',
    'productionTank',
    'testSeparator',
    'flare',
    'compressor',
    'facilities',
    'ironHorizontal',
    'ironVertical',
    'teeUp',
    'teeRight',
    'teeDown',
    'teeLeft',
    'elbowUpRight',
    'elbowRightDown',
    'elbowDownLeft',
    'elbowLeftUp',
    'bypass',
  };

  static const Map<String, Map<String, String>> _stableToInternalDefaults =
      <String, Map<String, String>>{
    'choke_manifold_2': <String, String>{'chokeSize': '2'},
    'choke_manifold_3': <String, String>{'chokeSize': '3'},
    'flowback_tank': <String, String>{'equipmentVariant': 'flowbackStandard'},
    'flowback_tank_gas_busters': <String, String>{
      'equipmentVariant': 'flowbackGasBusters',
    },
    'half_flowback_tank': <String, String>{'equipmentVariant': 'flowbackHalf'},
    'quarter_flowback_tank': <String, String>{
      'equipmentVariant': 'flowbackQuarter',
    },
  };
}
