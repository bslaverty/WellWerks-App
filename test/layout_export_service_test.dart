import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/models/layout_interchange.dart';
import 'package:wellwerks/services/layout_export_service.dart';

WellWerksLayoutInterchange _modelFixture() {
  return const WellWerksLayoutInterchange(
    format: WellWerksLayoutInterchange.formatName,
    version: WellWerksLayoutInterchange.currentVersion,
    layoutName: 'My Rig Up',
    canvas: InterchangeCanvas(
      width: 1200,
      height: 800,
      gridSize: 24,
      showGrid: false,
    ),
    nextId: 5,
    snapToGrid: false,
    libraryKeepOpen: true,
    company: 'WellWerks',
    padName: 'Pad A',
    wellName: 'Well 1',
    date: '2026-07-16',
    preparedBy: 'Builder',
    notes: 'Testing',
    selectedId: 1,
    selectedIds: <int>[1],
    selectedEndpointLeading: null,
    selectedBypassHandle: null,
    equipment: <InterchangeEquipmentItem>[
      InterchangeEquipmentItem(
        id: 1,
        stableTypeId: 'wellhead',
        internalType: 'wellhead',
        x: 100,
        y: 100,
        width: 30,
        height: 28,
        rotationTurns: 0,
        label: 'WH-1',
        locked: false,
        properties: <String, String>{'displayLabel': 'WH-1'},
        ports: <InterchangePort>[
          InterchangePort(id: 'right', x: 127.6, y: 114.0),
        ],
      ),
    ],
    iron: <InterchangeIronSegment>[
      InterchangeIronSegment(
        id: 2,
        stableTypeId: 'straight_iron',
        internalType: 'ironHorizontal',
        ironSize: '3',
        start: InterchangePoint(x: 127.6, y: 114.0),
        end: InterchangePoint(x: 280.0, y: 114.0),
        locked: false,
        properties: <String, String>{'ironSize': '3'},
        startEquipmentId: 1,
        startPortId: 'right',
      ),
    ],
    fittings: <InterchangeFittingItem>[],
    metadata: <String, dynamic>{'version': 1},
  );
}

void main() {
  const service = LayoutExportService();

  test('filename sanitization preserves spaces and replaces invalid characters',
      () {
    expect(service.sanitizeFileName(' My / Rig:Up? '), 'My _ Rig_Up_');
  });

  test('blank filename falls back to WellWerks Layout', () {
    expect(
        service.sanitizeFileName('   '), LayoutExportService.fallbackFileName);
  });

  test('svg extension is appended only once without case sensitivity', () {
    expect(service.fileNameWithExtension('Rig Up', 'svg'), 'Rig Up.svg');
    expect(service.fileNameWithExtension('Rig Up.svg', 'svg'), 'Rig Up.svg');
    expect(service.fileNameWithExtension('Rig Up.SVG', 'svg'), 'Rig Up.SVG');
  });

  test('wwlayout extension is appended only once without case sensitivity', () {
    expect(
        service.fileNameWithExtension('Rig Up', 'wwlayout'), 'Rig Up.wwlayout');
    expect(service.fileNameWithExtension('Rig Up.wwlayout', 'wwlayout'),
        'Rig Up.wwlayout');
    expect(service.fileNameWithExtension('Rig Up.WWLAYOUT', 'wwlayout'),
        'Rig Up.WWLAYOUT');
  });

  test('svg artifact is non-empty and contains svg metadata', () {
    final artifact = service.buildSvgArtifact(
      _modelFixture(),
      requestedFileName: 'My Rig Up',
    );

    expect(artifact.fileName, 'My Rig Up.svg');
    expect(artifact.mimeType, 'image/svg+xml');
    expect(artifact.contents, isNotEmpty);
    expect(artifact.contents, contains('<svg'));
    expect(artifact.contents, contains('wellwerks-layout-interchange'));
    expect(artifact.contents, contains('data-wellwerks-type'));
  });

  test('editable artifact is valid json with format and version', () {
    final artifact = service.buildEditableArtifact(
      _modelFixture(),
      requestedFileName: 'My Rig Up',
    );

    expect(artifact.fileName, 'My Rig Up.wwlayout');
    expect(artifact.mimeType, 'application/octet-stream');
    expect(artifact.contents, isNotEmpty);
    final decoded = jsonDecode(artifact.contents) as Map<String, dynamic>;
    expect(decoded['format'], WellWerksLayoutInterchange.formatName);
    expect(decoded['version'], WellWerksLayoutInterchange.currentVersion);
  });

  test('temporary export file is written and non-empty', () async {
    final artifact = service.buildEditableArtifact(
      _modelFixture(),
      requestedFileName: 'My Rig Up',
    );
    final directory =
        await Directory.systemTemp.createTemp('wellwerks_export_test');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final file =
        await service.writeTemporaryFile(artifact, directory: directory);

    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(0));
  });
}
