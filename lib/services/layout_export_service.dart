import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/layout_interchange.dart';
import 'layout_interchange_codec.dart';

enum LayoutExportFormat { wellWerksEditable, visioSvg, visioToolkit }

class LayoutExportException implements Exception {
  final String message;

  const LayoutExportException(this.message);

  @override
  String toString() => message;
}

class LayoutExportArtifact {
  final LayoutExportFormat format;
  final String fileName;
  final String mimeType;
  final String contents;
  final List<int>? binaryContents;
  final String shareSubject;
  final String shareText;

  const LayoutExportArtifact({
    required this.format,
    required this.fileName,
    required this.mimeType,
    required this.contents,
    this.binaryContents,
    required this.shareSubject,
    required this.shareText,
  });
}

class LayoutExportService {
  static const String fallbackFileName = 'WellWerks Layout';

  LayoutExportService();

  String sanitizeFileName(String raw) {
    final trimmed = raw.trim();
    final base = trimmed.isEmpty ? fallbackFileName : trimmed;
    final sanitized = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? fallbackFileName : sanitized;
  }

  String fileNameWithExtension(String raw, String extension) {
    final normalized = sanitizeFileName(raw);
    final suffix = '.${extension.toLowerCase()}';
    if (normalized.toLowerCase().endsWith(suffix)) {
      return normalized;
    }
    return '$normalized$suffix';
  }

  LayoutExportArtifact buildEditableArtifact(
    WellWerksLayoutInterchange model, {
    required String requestedFileName,
  }) {
    final contents = LayoutInterchangeCodec.encodeWellWerksJson(model);
    if (contents.trim().isEmpty) {
      throw const LayoutExportException(
        'Unable to create the editable layout file.',
      );
    }

    late final dynamic decoded;
    try {
      decoded = jsonDecode(contents);
    } catch (_) {
      throw const LayoutExportException(
        'Unable to create the editable layout file.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const LayoutExportException(
        'Unable to create the editable layout file.',
      );
    }
    if (decoded['format'] != WellWerksLayoutInterchange.formatName ||
        decoded['version'] != WellWerksLayoutInterchange.currentVersion) {
      throw const LayoutExportException(
        'Unable to create the editable layout file.',
      );
    }

    return LayoutExportArtifact(
      format: LayoutExportFormat.wellWerksEditable,
      fileName: fileNameWithExtension(requestedFileName, 'wwlayout'),
      mimeType: 'application/octet-stream',
      contents: contents,
      shareSubject: 'WellWerks Editable Layout',
      shareText: 'Editable WellWerks layout export.',
    );
  }

  LayoutExportArtifact buildSvgArtifact(
    WellWerksLayoutInterchange model, {
    required String requestedFileName,
  }) {
    final contents = LayoutInterchangeCodec.encodeVisioSvg(model);
    final trimmed = contents.trimLeft();
    if (trimmed.isEmpty || !trimmed.contains('<svg')) {
      throw const LayoutExportException('Unable to generate the Visio SVG.');
    }
    if (!(trimmed.startsWith('<?xml') || trimmed.startsWith('<svg'))) {
      throw const LayoutExportException('Unable to generate the Visio SVG.');
    }
    if (!contents.contains('wellwerks-layout-interchange')) {
      throw const LayoutExportException('Unable to generate the Visio SVG.');
    }

    return LayoutExportArtifact(
      format: LayoutExportFormat.visioSvg,
      fileName: fileNameWithExtension(requestedFileName, 'svg'),
      mimeType: 'image/svg+xml',
      contents: contents,
      shareSubject: 'WellWerks Layout SVG',
      shareText: 'Microsoft Visio SVG exported from WellWerks.',
    );
  }

  LayoutExportArtifact buildVisioToolkitArtifact({
    required String requestedFileName,
  }) {
    final packageName = sanitizeFileName(requestedFileName);
    final rootFolder = packageName;
    final archive = Archive();

    void addTextFile(String relativePath, String data) {
      final bytes = utf8.encode(data);
      archive.addFile(
          ArchiveFile('$rootFolder/$relativePath', bytes.length, bytes));
    }

    for (final asset in _equipmentLibraryAssets) {
      addTextFile(
        'WellWerks Equipment SVG Library/${asset.fileName}',
        _buildToolkitModelSvg(
          _singleEquipmentModel(
            stableTypeId: asset.stableTypeId,
            internalType: asset.internalType,
            label: asset.label,
            width: asset.width,
            height: asset.height,
            properties: asset.properties,
            ports: _portsForItem(
              internalType: asset.internalType,
              width: asset.width,
              height: asset.height,
              x: 24,
              y: 24,
            ),
          ),
        ),
      );
    }

    for (final asset in _ironLibraryAssets) {
      addTextFile(
        'WellWerks Iron Library/${asset.fileName}',
        asset.builder(),
      );
    }

    for (final asset in _fittingsLibraryAssets) {
      addTextFile(
        'WellWerks Fittings Library/${asset.fileName}',
        asset.builder(),
      );
    }

    addTextFile('README.md', _toolkitReadme(packageName));

    final bytes = ZipEncoder().encode(archive);
    if (bytes == null || bytes.isEmpty) {
      throw const LayoutExportException(
        'Unable to create the WellWerks Visio Toolkit.',
      );
    }

    return LayoutExportArtifact(
      format: LayoutExportFormat.visioToolkit,
      fileName: fileNameWithExtension(packageName, 'zip'),
      mimeType: 'application/zip',
      contents: '',
      binaryContents: bytes,
      shareSubject: 'WellWerks Visio Toolkit',
      shareText:
          'WellWerks Visio Toolkit package with SVG libraries and README.',
    );
  }

  Future<File> writeTemporaryFile(
    LayoutExportArtifact artifact, {
    Directory? directory,
  }) async {
    final tempDirectory = directory ?? await getTemporaryDirectory();
    final file = File('${tempDirectory.path}/${artifact.fileName}');
    if (artifact.binaryContents != null) {
      await file.writeAsBytes(artifact.binaryContents!, flush: true);
    } else {
      await file.writeAsString(artifact.contents, flush: true);
    }
    final exists = await file.exists();
    final length = exists ? await file.length() : 0;
    if (!exists || length <= 0) {
      throw const LayoutExportException(
          'The export file could not be written.');
    }
    return file;
  }

  WellWerksLayoutInterchange _singleEquipmentModel({
    required String stableTypeId,
    required String internalType,
    required String label,
    required double width,
    required double height,
    required Map<String, String> properties,
    required List<InterchangePort> ports,
  }) {
    return WellWerksLayoutInterchange(
      format: WellWerksLayoutInterchange.formatName,
      version: WellWerksLayoutInterchange.currentVersion,
      layoutName: label,
      canvas: InterchangeCanvas(
        width: width + 48,
        height: height + 72,
        gridSize: 24,
        showGrid: false,
      ),
      nextId: 2,
      snapToGrid: false,
      libraryKeepOpen: true,
      company: 'WellWerks',
      padName: '',
      wellName: '',
      date: '',
      preparedBy: '',
      notes: '',
      selectedId: null,
      selectedIds: const <int>[],
      selectedEndpointLeading: null,
      selectedBypassHandle: null,
      equipment: <InterchangeEquipmentItem>[
        InterchangeEquipmentItem(
          id: 1,
          stableTypeId: stableTypeId,
          internalType: internalType,
          x: 24,
          y: 24,
          width: width,
          height: height,
          rotationTurns: 0,
          label: label,
          locked: false,
          properties: properties,
          ports: ports,
        ),
      ],
      iron: const <InterchangeIronSegment>[],
      fittings: const <InterchangeFittingItem>[],
      metadata: const <String, dynamic>{'version': 1},
    );
  }

  WellWerksLayoutInterchange _singleFittingModel({
    required String stableTypeId,
    required String internalType,
    required String label,
    required double width,
    required double height,
    required List<InterchangePort> ports,
  }) {
    return WellWerksLayoutInterchange(
      format: WellWerksLayoutInterchange.formatName,
      version: WellWerksLayoutInterchange.currentVersion,
      layoutName: label,
      canvas: InterchangeCanvas(
        width: width + 48,
        height: height + 72,
        gridSize: 24,
        showGrid: false,
      ),
      nextId: 2,
      snapToGrid: false,
      libraryKeepOpen: true,
      company: 'WellWerks',
      padName: '',
      wellName: '',
      date: '',
      preparedBy: '',
      notes: '',
      selectedId: null,
      selectedIds: const <int>[],
      selectedEndpointLeading: null,
      selectedBypassHandle: null,
      equipment: const <InterchangeEquipmentItem>[],
      iron: const <InterchangeIronSegment>[],
      fittings: <InterchangeFittingItem>[
        InterchangeFittingItem(
          id: 1,
          stableTypeId: stableTypeId,
          internalType: internalType,
          x: 24,
          y: 24,
          width: width,
          height: height,
          rotationTurns: 0,
          label: label,
          locked: false,
          properties: const <String, String>{},
          ports: ports,
        ),
      ],
      metadata: const <String, dynamic>{'version': 1},
    );
  }

  WellWerksLayoutInterchange _singleIronModel({
    required String stableTypeId,
    required String label,
    required double width,
  }) {
    return WellWerksLayoutInterchange(
      format: WellWerksLayoutInterchange.formatName,
      version: WellWerksLayoutInterchange.currentVersion,
      layoutName: label,
      canvas: const InterchangeCanvas(
        width: 240,
        height: 96,
        gridSize: 24,
        showGrid: false,
      ),
      nextId: 2,
      snapToGrid: false,
      libraryKeepOpen: true,
      company: 'WellWerks',
      padName: '',
      wellName: '',
      date: '',
      preparedBy: '',
      notes: '',
      selectedId: null,
      selectedIds: const <int>[],
      selectedEndpointLeading: null,
      selectedBypassHandle: null,
      equipment: const <InterchangeEquipmentItem>[],
      iron: <InterchangeIronSegment>[
        InterchangeIronSegment(
          id: 1,
          stableTypeId: stableTypeId,
          internalType: 'ironHorizontal',
          ironSize: '3',
          start: const InterchangePoint(x: 24, y: 48),
          end: InterchangePoint(x: 24 + width, y: 48),
          locked: false,
          properties: const <String, String>{'ironSize': '3'},
        ),
      ],
      fittings: const <InterchangeFittingItem>[],
      metadata: const <String, dynamic>{'version': 1},
    );
  }

  String _buildToolkitModelSvg(WellWerksLayoutInterchange model) {
    final contents = LayoutInterchangeCodec.encodeVisioSvg(model);
    if (contents.trim().isEmpty || !contents.contains('<svg')) {
      throw const LayoutExportException(
        'Unable to create the WellWerks Visio Toolkit.',
      );
    }
    return contents;
  }

  String _buildPrimitiveSvg({
    required String stableTypeId,
    required String label,
    required String body,
    required List<Map<String, Object>> ports,
  }) {
    final metadataJson = jsonEncode(<String, dynamic>{
      'format': WellWerksLayoutInterchange.formatName,
      'version': WellWerksLayoutInterchange.currentVersion,
      'layoutName': label,
      'primitive': stableTypeId,
    });
    final encoded = base64Encode(utf8.encode(metadataJson));
    final portMarkup = ports
        .map(
          (port) =>
              '<circle cx="${port['x']}" cy="${port['y']}" r="2" fill="#CDA56A" fill-opacity="0" stroke="none" data-wellwerks-port-id="${port['id']}" data-wellwerks-equipment-id="1" />',
        )
        .join();
    return '''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="96" height="96" viewBox="0 0 96 96" data-wellwerks-format="${LayoutInterchangeCodec.svgFormatName}" data-wellwerks-version="1">
  <metadata id="wellwerks-layout-interchange" data-wellwerks-format="${WellWerksLayoutInterchange.formatName}" data-wellwerks-version="1">$encoded</metadata>
  <g data-wellwerks-kind="fitting" data-wellwerks-type="$stableTypeId" data-wellwerks-id="1" data-wellwerks-version="1" data-wellwerks-rotation="0">
    $body
    $portMarkup
    <text x="48" y="86" fill="#FFFFFF" font-size="10" text-anchor="middle">$label</text>
  </g>
</svg>''';
  }

  String _toolkitReadme(String packageName) {
    return '''# $packageName

## Contents

- WellWerks Equipment SVG Library
- WellWerks Iron Library
- WellWerks Fittings Library

## Import into Microsoft Visio

1. Extract this toolkit zip.
2. Open Microsoft Visio.
3. Create or open a stencil workspace.
4. Drag the SVG files from each WellWerks library folder into Visio.
5. Arrange the imported SVGs in a custom stencil.
6. Save the stencil as `WellWerks.vssx`.

## Recommended workflow

1. Use the equipment library for process equipment shapes.
2. Use the iron library for straight iron and connection-end shapes.
3. Use the fittings library for bypass and fitting-related assets.
4. Preserve the embedded WellWerks metadata when possible so future WellWerks builds can support improved round-trip import.

## Future-ready structure

This package is intentionally organized into library folders so a future WellWerks build can automatically generate a native `.vssx` stencil from the same source set.
''';
  }

  List<InterchangePort> _portsForItem({
    required String internalType,
    required double width,
    required double height,
    required double x,
    required double y,
  }) {
    final definitions = <String, List<double>>{};
    switch (internalType) {
      case 'chokeManifold':
        definitions.addAll(<String, List<double>>{
          'inletTopCenter': <double>[0.5, 0.08],
          'outletBottomCenter': <double>[0.5, 0.92],
        });
        break;
      case 'plugCatcher':
      case 'testSeparator':
        definitions.addAll(<String, List<double>>{
          'left': <double>[0.08, 0.5],
          'right': <double>[0.92, 0.5],
        });
        break;
      case 'flowbackTank':
      case 'productionTank':
      case 'wellhead':
      case 'esdValve':
      case 'lineHeater':
      case 'cyclonicSandSep':
      case 'sphericalSandSep':
      case 'flare':
      case 'compressor':
        definitions.addAll(<String, List<double>>{
          'top': <double>[0.5, 0.08],
          'right': <double>[0.92, 0.5],
          'bottom': <double>[0.5, 0.92],
          'left': <double>[0.08, 0.5],
        });
        break;
      case 'facilities':
        definitions.addAll(<String, List<double>>{
          'topLeft': <double>[0.24, 0.16],
          'topCenter': <double>[0.50, 0.16],
          'topRight': <double>[0.76, 0.16],
          'rightTop': <double>[0.84, 0.30],
          'rightCenter': <double>[0.84, 0.50],
          'rightBottom': <double>[0.84, 0.70],
          'bottomRight': <double>[0.76, 0.84],
          'bottomCenter': <double>[0.50, 0.84],
          'bottomLeft': <double>[0.24, 0.84],
          'leftBottom': <double>[0.16, 0.70],
          'leftCenter': <double>[0.16, 0.50],
          'leftTop': <double>[0.16, 0.30],
        });
        break;
      case 'bypass':
        definitions.addAll(<String, List<double>>{
          'mainTop': <double>[0.28, 0.14],
          'mainBottom': <double>[0.28, 0.86],
          'upperValveOutlet': <double>[0.82, 0.34],
          'lowerValveOutlet': <double>[0.82, 0.66],
        });
        break;
      case 'teeUp':
        definitions.addAll(<String, List<double>>{
          'runStart': <double>[0.08, 0.5],
          'runEnd': <double>[0.92, 0.5],
          'branch': <double>[0.5, 0.08],
        });
        break;
      case 'elbowUpRight':
        definitions.addAll(<String, List<double>>{
          'inlet': <double>[0.5, 0.92],
          'outlet': <double>[0.92, 0.5],
        });
        break;
    }
    return definitions.entries
        .map(
          (entry) => InterchangePort(
            id: entry.key,
            x: x + (width * entry.value[0]),
            y: y + (height * entry.value[1]),
          ),
        )
        .toList(growable: false);
  }

  static const List<_ToolkitEquipmentAsset> _equipmentLibraryAssets =
      <_ToolkitEquipmentAsset>[
    _ToolkitEquipmentAsset(
        '2in Choke Manifold.svg',
        '2" Choke Manifold',
        'choke_manifold_2',
        'chokeManifold',
        38,
        24,
        <String, String>{'chokeSize': '2'}),
    _ToolkitEquipmentAsset(
        '3in Choke Manifold.svg',
        '3" Choke Manifold',
        'choke_manifold_3',
        'chokeManifold',
        38,
        24,
        <String, String>{'chokeSize': '3'}),
    _ToolkitEquipmentAsset('Double Plug Catcher.svg', 'Double Plug Catcher',
        'double_plug_catcher', 'plugCatcher', 40, 26, <String, String>{}),
    _ToolkitEquipmentAsset(
        'ESD.svg', 'ESD', 'esd', 'esdValve', 30, 24, <String, String>{}),
    _ToolkitEquipmentAsset('Test Separator.svg', 'Test Separator',
        'test_separator', 'testSeparator', 36, 28, <String, String>{}),
    _ToolkitEquipmentAsset(
        'Spherical Sand Separator.svg',
        'Spherical Sand Separator',
        'spherical_sand_separator',
        'sphericalSandSep',
        34,
        34, <String, String>{}),
    _ToolkitEquipmentAsset(
        'Cyclonic Sand Separator.svg',
        'Cyclonic Sand Separator',
        'cyclonic_sand_separator',
        'cyclonicSandSep',
        34,
        32, <String, String>{}),
    _ToolkitEquipmentAsset(
        'Standard Sand Separator.svg',
        'Standard Sand Separator',
        'standard_sand_separator',
        'testSeparator',
        36,
        28,
        <String, String>{'displayLabel': 'Standard Sand Separator'}),
    _ToolkitEquipmentAsset(
        'Flowback Tank.svg',
        'Flowback Tank',
        'flowback_tank',
        'flowbackTank',
        48,
        96,
        <String, String>{'equipmentVariant': 'flowbackStandard'}),
    _ToolkitEquipmentAsset(
        'Flowback Tank with Gas Busters.svg',
        'Flowback Tank with Gas Busters',
        'flowback_tank_gas_busters',
        'flowbackTank',
        48,
        96,
        <String, String>{'equipmentVariant': 'flowbackGasBusters'}),
    _ToolkitEquipmentAsset(
        'Half Tank.svg',
        'Half Tank',
        'half_flowback_tank',
        'flowbackTank',
        48,
        96,
        <String, String>{'equipmentVariant': 'flowbackHalf'}),
    _ToolkitEquipmentAsset(
        'Quarter Tank.svg',
        'Quarter Tank',
        'quarter_flowback_tank',
        'flowbackTank',
        48,
        96,
        <String, String>{'equipmentVariant': 'flowbackQuarter'}),
    _ToolkitEquipmentAsset('Production Tank.svg', 'Production Tank',
        'production_tank', 'productionTank', 38, 28, <String, String>{}),
    _ToolkitEquipmentAsset('Facilities.svg', 'Facilities', 'facilities',
        'facilities', 220, 112, <String, String>{}),
    _ToolkitEquipmentAsset('Line Heater.svg', 'Line Heater', 'line_heater',
        'lineHeater', 38, 26, <String, String>{}),
  ];

  late final List<_ToolkitGeneratedAsset> _ironLibraryAssets =
      <_ToolkitGeneratedAsset>[
    _ToolkitGeneratedAsset(
      fileName: 'Straight Iron.svg',
      builder: () => _buildToolkitModelSvg(
        _singleIronModel(
          stableTypeId: 'straight_iron',
          label: 'Straight Iron',
          width: 172,
        ),
      ),
    ),
    _ToolkitGeneratedAsset(
      fileName: 'Tee.svg',
      builder: () => _buildToolkitModelSvg(
        _singleFittingModel(
          stableTypeId: 'tee_up',
          internalType: 'teeUp',
          label: 'Tee',
          width: 21,
          height: 21,
          ports: _portsForItem(
            internalType: 'teeUp',
            width: 21,
            height: 21,
            x: 24,
            y: 24,
          ),
        ),
      ),
    ),
    _ToolkitGeneratedAsset(
      fileName: '90 Degree.svg',
      builder: () => _buildToolkitModelSvg(
        _singleFittingModel(
          stableTypeId: 'elbow_up_right',
          internalType: 'elbowUpRight',
          label: '90°',
          width: 21,
          height: 21,
          ports: _portsForItem(
            internalType: 'elbowUpRight',
            width: 21,
            height: 21,
            x: 24,
            y: 24,
          ),
        ),
      ),
    ),
    _ToolkitGeneratedAsset(
      fileName: 'Dead Plug.svg',
      builder: () => _buildPrimitiveSvg(
        stableTypeId: 'dead_plug',
        label: 'Dead Plug',
        body:
            '<circle cx="48" cy="48" r="18" fill="#000000" stroke="#CDA56A" stroke-width="2" /><line x1="48" y1="30" x2="48" y2="66" stroke="#CDA56A" stroke-width="2" />',
        ports: <Map<String, Object>>[
          <String, Object>{'id': 'connection', 'x': 48, 'y': 12},
        ],
      ),
    ),
    _ToolkitGeneratedAsset(
      fileName: 'Blind.svg',
      builder: () => _buildPrimitiveSvg(
        stableTypeId: 'blind',
        label: 'Blind',
        body:
            '<rect x="24" y="24" width="48" height="48" rx="8" fill="#000000" stroke="#CDA56A" stroke-width="2" /><line x1="28" y1="28" x2="68" y2="68" stroke="#CDA56A" stroke-width="2" /><line x1="68" y1="28" x2="28" y2="68" stroke="#CDA56A" stroke-width="2" />',
        ports: <Map<String, Object>>[
          <String, Object>{'id': 'connection', 'x': 48, 'y': 12},
        ],
      ),
    ),
    _ToolkitGeneratedAsset(
      fileName: 'End Connection.svg',
      builder: () => _buildPrimitiveSvg(
        stableTypeId: 'end_connection',
        label: 'End Connection',
        body:
            '<line x1="20" y1="48" x2="76" y2="48" stroke="#D7D7D7" stroke-width="4" /><circle cx="76" cy="48" r="8" fill="#000000" stroke="#CDA56A" stroke-width="2" />',
        ports: <Map<String, Object>>[
          <String, Object>{'id': 'connection', 'x': 20, 'y': 48},
        ],
      ),
    ),
  ];

  late final List<_ToolkitGeneratedAsset> _fittingsLibraryAssets =
      <_ToolkitGeneratedAsset>[
    _ToolkitGeneratedAsset(
      fileName: 'Equipment Bypass.svg',
      builder: () => _buildToolkitModelSvg(
        _singleFittingModel(
          stableTypeId: 'equipment_bypass',
          internalType: 'bypass',
          label: 'Equipment Bypass',
          width: 30,
          height: 32,
          ports: _portsForItem(
            internalType: 'bypass',
            width: 30,
            height: 32,
            x: 24,
            y: 24,
          ),
        ),
      ),
    ),
    _ToolkitGeneratedAsset(
      fileName: 'Tee.svg',
      builder: () => _ironLibraryAssets[1].builder(),
    ),
    _ToolkitGeneratedAsset(
      fileName: '90 Degree.svg',
      builder: () => _ironLibraryAssets[2].builder(),
    ),
    _ToolkitGeneratedAsset(
      fileName: 'Dead Plug.svg',
      builder: () => _ironLibraryAssets[3].builder(),
    ),
    _ToolkitGeneratedAsset(
      fileName: 'Blind.svg',
      builder: () => _ironLibraryAssets[4].builder(),
    ),
    _ToolkitGeneratedAsset(
      fileName: 'End Connection.svg',
      builder: () => _ironLibraryAssets[5].builder(),
    ),
  ];
}

class _ToolkitEquipmentAsset {
  final String fileName;
  final String label;
  final String stableTypeId;
  final String internalType;
  final double width;
  final double height;
  final Map<String, String> properties;

  const _ToolkitEquipmentAsset(
    this.fileName,
    this.label,
    this.stableTypeId,
    this.internalType,
    this.width,
    this.height,
    this.properties,
  );
}

class _ToolkitGeneratedAsset {
  final String fileName;
  final String Function() builder;

  const _ToolkitGeneratedAsset({
    required this.fileName,
    required this.builder,
  });
}
