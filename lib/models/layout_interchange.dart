import 'dart:convert';

class LayoutInterchangeException implements Exception {
  final String message;

  const LayoutInterchangeException(this.message);

  @override
  String toString() => message;
}

class InterchangeCanvas {
  final double width;
  final double height;
  final double gridSize;
  final bool showGrid;

  const InterchangeCanvas({
    required this.width,
    required this.height,
    required this.gridSize,
    required this.showGrid,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'width': width,
        'height': height,
        'gridSize': gridSize,
        'showGrid': showGrid,
      };

  factory InterchangeCanvas.fromJson(Map<String, dynamic> json) {
    return InterchangeCanvas(
      width: (json['width'] as num?)?.toDouble() ?? 0,
      height: (json['height'] as num?)?.toDouble() ?? 0,
      gridSize: (json['gridSize'] as num?)?.toDouble() ?? 24,
      showGrid: json['showGrid'] as bool? ?? false,
    );
  }
}

class InterchangePoint {
  final double x;
  final double y;

  const InterchangePoint({required this.x, required this.y});

  Map<String, dynamic> toJson() => <String, dynamic>{'x': x, 'y': y};

  factory InterchangePoint.fromJson(Map<String, dynamic> json) {
    return InterchangePoint(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
    );
  }
}

class InterchangePort {
  final String id;
  final double x;
  final double y;
  final bool connectable;

  const InterchangePort({
    required this.id,
    required this.x,
    required this.y,
    this.connectable = true,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'x': x,
        'y': y,
        'connectable': connectable,
      };

  factory InterchangePort.fromJson(Map<String, dynamic> json) {
    return InterchangePort(
      id: json['id'] as String? ?? '',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      connectable: json['connectable'] as bool? ?? true,
    );
  }
}

class InterchangeEquipmentItem {
  final int id;
  final String stableTypeId;
  final String internalType;
  final double x;
  final double y;
  final double width;
  final double height;
  final int rotationTurns;
  final String label;
  final bool locked;
  final Map<String, String> properties;
  final List<InterchangePort> ports;

  const InterchangeEquipmentItem({
    required this.id,
    required this.stableTypeId,
    required this.internalType,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rotationTurns,
    required this.label,
    required this.locked,
    required this.properties,
    required this.ports,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'typeId': stableTypeId,
        'internalType': internalType,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'rotationTurns': rotationTurns,
        'label': label,
        'locked': locked,
        'properties': properties,
        'ports': ports.map((port) => port.toJson()).toList(),
      };

  factory InterchangeEquipmentItem.fromJson(Map<String, dynamic> json) {
    return InterchangeEquipmentItem(
      id: json['id'] as int? ?? 0,
      stableTypeId: json['typeId'] as String? ?? '',
      internalType: json['internalType'] as String? ?? '',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 0,
      height: (json['height'] as num?)?.toDouble() ?? 0,
      rotationTurns: json['rotationTurns'] as int? ?? 0,
      label: json['label'] as String? ?? '',
      locked: json['locked'] as bool? ?? false,
      properties: Map<String, String>.from(
          json['properties'] as Map? ?? const <String, String>{}),
      ports: (json['ports'] as List<dynamic>? ?? const <dynamic>[])
          .map((port) =>
              InterchangePort.fromJson(Map<String, dynamic>.from(port as Map)))
          .toList(growable: false),
    );
  }
}

class InterchangeIronSegment {
  final int id;
  final String stableTypeId;
  final String internalType;
  final String ironSize;
  final InterchangePoint start;
  final InterchangePoint end;
  final bool locked;
  final Map<String, String> properties;
  final int? startEquipmentId;
  final String? startPortId;
  final int? endEquipmentId;
  final String? endPortId;
  final String? startJointId;
  final String? endJointId;

  const InterchangeIronSegment({
    required this.id,
    required this.stableTypeId,
    required this.internalType,
    required this.ironSize,
    required this.start,
    required this.end,
    required this.locked,
    required this.properties,
    this.startEquipmentId,
    this.startPortId,
    this.endEquipmentId,
    this.endPortId,
    this.startJointId,
    this.endJointId,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'typeId': stableTypeId,
        'internalType': internalType,
        'ironSize': ironSize,
        'start': start.toJson(),
        'end': end.toJson(),
        'locked': locked,
        'properties': properties,
        'startEquipmentId': startEquipmentId,
        'startPortId': startPortId,
        'endEquipmentId': endEquipmentId,
        'endPortId': endPortId,
        'startJointId': startJointId,
        'endJointId': endJointId,
      };

  factory InterchangeIronSegment.fromJson(Map<String, dynamic> json) {
    return InterchangeIronSegment(
      id: json['id'] as int? ?? 0,
      stableTypeId: json['typeId'] as String? ?? '',
      internalType: json['internalType'] as String? ?? '',
      ironSize: json['ironSize'] as String? ?? '3',
      start: InterchangePoint.fromJson(Map<String, dynamic>.from(
          json['start'] as Map? ?? const <String, dynamic>{})),
      end: InterchangePoint.fromJson(Map<String, dynamic>.from(
          json['end'] as Map? ?? const <String, dynamic>{})),
      locked: json['locked'] as bool? ?? false,
      properties: Map<String, String>.from(
          json['properties'] as Map? ?? const <String, String>{}),
      startEquipmentId: json['startEquipmentId'] as int?,
      startPortId: json['startPortId'] as String?,
      endEquipmentId: json['endEquipmentId'] as int?,
      endPortId: json['endPortId'] as String?,
      startJointId: json['startJointId'] as String?,
      endJointId: json['endJointId'] as String?,
    );
  }
}

class InterchangeFittingItem {
  final int id;
  final String stableTypeId;
  final String internalType;
  final double x;
  final double y;
  final double width;
  final double height;
  final int rotationTurns;
  final String label;
  final bool locked;
  final Map<String, String> properties;
  final List<InterchangePort> ports;

  const InterchangeFittingItem({
    required this.id,
    required this.stableTypeId,
    required this.internalType,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rotationTurns,
    required this.label,
    required this.locked,
    required this.properties,
    required this.ports,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'typeId': stableTypeId,
        'internalType': internalType,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'rotationTurns': rotationTurns,
        'label': label,
        'locked': locked,
        'properties': properties,
        'ports': ports.map((port) => port.toJson()).toList(),
      };

  factory InterchangeFittingItem.fromJson(Map<String, dynamic> json) {
    return InterchangeFittingItem(
      id: json['id'] as int? ?? 0,
      stableTypeId: json['typeId'] as String? ?? '',
      internalType: json['internalType'] as String? ?? '',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 0,
      height: (json['height'] as num?)?.toDouble() ?? 0,
      rotationTurns: json['rotationTurns'] as int? ?? 0,
      label: json['label'] as String? ?? '',
      locked: json['locked'] as bool? ?? false,
      properties: Map<String, String>.from(
          json['properties'] as Map? ?? const <String, String>{}),
      ports: (json['ports'] as List<dynamic>? ?? const <dynamic>[])
          .map((port) =>
              InterchangePort.fromJson(Map<String, dynamic>.from(port as Map)))
          .toList(growable: false),
    );
  }
}

class WellWerksLayoutInterchange {
  static const String formatName = 'wellwerks-layout';
  static const int currentVersion = 1;

  final String format;
  final int version;
  final String layoutName;
  final InterchangeCanvas canvas;
  final int nextId;
  final bool snapToGrid;
  final bool libraryKeepOpen;
  final String company;
  final String padName;
  final String wellName;
  final String date;
  final String preparedBy;
  final String notes;
  final int? selectedId;
  final List<int> selectedIds;
  final bool? selectedEndpointLeading;
  final String? selectedBypassHandle;
  final List<InterchangeEquipmentItem> equipment;
  final List<InterchangeIronSegment> iron;
  final List<InterchangeFittingItem> fittings;
  final Map<String, dynamic> metadata;

  const WellWerksLayoutInterchange({
    required this.format,
    required this.version,
    required this.layoutName,
    required this.canvas,
    required this.nextId,
    required this.snapToGrid,
    required this.libraryKeepOpen,
    required this.company,
    required this.padName,
    required this.wellName,
    required this.date,
    required this.preparedBy,
    required this.notes,
    required this.selectedId,
    required this.selectedIds,
    required this.selectedEndpointLeading,
    required this.selectedBypassHandle,
    required this.equipment,
    required this.iron,
    required this.fittings,
    required this.metadata,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'format': format,
        'version': version,
        'layoutName': layoutName,
        'canvas': canvas.toJson(),
        'nextId': nextId,
        'snapToGrid': snapToGrid,
        'libraryKeepOpen': libraryKeepOpen,
        'company': company,
        'padName': padName,
        'wellName': wellName,
        'date': date,
        'preparedBy': preparedBy,
        'notes': notes,
        'selectedId': selectedId,
        'selectedIds': selectedIds,
        'selectedEndpointLeading': selectedEndpointLeading,
        'selectedBypassHandle': selectedBypassHandle,
        'equipment': equipment.map((item) => item.toJson()).toList(),
        'iron': iron.map((item) => item.toJson()).toList(),
        'fittings': fittings.map((item) => item.toJson()).toList(),
        'metadata': metadata,
      };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory WellWerksLayoutInterchange.fromJson(Map<String, dynamic> json) {
    return WellWerksLayoutInterchange(
      format: json['format'] as String? ?? '',
      version: json['version'] as int? ?? 0,
      layoutName: json['layoutName'] as String? ?? 'New Layout',
      canvas: InterchangeCanvas.fromJson(Map<String, dynamic>.from(
          json['canvas'] as Map? ?? const <String, dynamic>{})),
      nextId: json['nextId'] as int? ?? 1,
      snapToGrid: json['snapToGrid'] as bool? ?? false,
      libraryKeepOpen: json['libraryKeepOpen'] as bool? ?? true,
      company: json['company'] as String? ?? '',
      padName: json['padName'] as String? ?? '',
      wellName: json['wellName'] as String? ?? '',
      date: json['date'] as String? ?? '',
      preparedBy: json['preparedBy'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      selectedId: json['selectedId'] as int?,
      selectedIds: (json['selectedIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value as int)
          .toList(growable: false),
      selectedEndpointLeading: json['selectedEndpointLeading'] as bool?,
      selectedBypassHandle: json['selectedBypassHandle'] as String?,
      equipment: (json['equipment'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => InterchangeEquipmentItem.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
      iron: (json['iron'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => InterchangeIronSegment.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
      fittings: (json['fittings'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => InterchangeFittingItem.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
      metadata: Map<String, dynamic>.from(
          json['metadata'] as Map? ?? const <String, dynamic>{}),
    );
  }
}
