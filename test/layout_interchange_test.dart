import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/models/layout_interchange.dart';
import 'package:wellwerks/services/layout_interchange_codec.dart';

Map<String, dynamic> _designerPayloadFixture() {
  return <String, dynamic>{
    'name': 'Rig Up',
    'company': 'WellWerks',
    'padName': 'Pad A',
    'wellName': 'Well 12',
    'date': '2026-07-16',
    'preparedBy': 'Builder',
    'notes': 'Interchange test',
    'nextId': 9,
    'snapToGrid': true,
    'libraryKeepOpen': true,
    'selectedId': 3,
    'selectedIds': <int>[3],
    'selectedEndpointLeading': false,
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 1,
        'type': 'wellhead',
        'x': 100.0,
        'y': 100.0,
        'width': 30.0,
        'height': 28.0,
        'rotationTurns': 0,
        'locked': false,
        'properties': <String, String>{'displayLabel': 'WH-1'},
      },
      <String, dynamic>{
        'id': 2,
        'type': 'chokeManifold',
        'x': 260.0,
        'y': 90.0,
        'width': 38.0,
        'height': 24.0,
        'rotationTurns': 1,
        'locked': false,
        'properties': <String, String>{'chokeSize': '2'},
      },
      <String, dynamic>{
        'id': 3,
        'type': 'ironHorizontal',
        'x': 130.0,
        'y': 110.0,
        'width': 140.0,
        'height': 24.0,
        'rotationTurns': 0,
        'locked': false,
        'properties': <String, String>{
          'ironSize': '3',
          'freeAngleIron': 'true',
          'freeAngleStartX': '130.0000',
          'freeAngleStartY': '114.0000',
          'freeAngleEndX': '279.0000',
          'freeAngleEndY': '102.0000',
          'anchorStartItemId': '1',
          'anchorStartSide': 'right',
          'anchorEndItemId': '2',
          'anchorEndSide': 'inletTopCenter',
        },
      },
      <String, dynamic>{
        'id': 4,
        'type': 'teeUp',
        'x': 330.0,
        'y': 110.0,
        'width': 21.0,
        'height': 21.0,
        'rotationTurns': 0,
        'locked': false,
        'properties': <String, String>{
          'ironSize': '3',
          'fittingAnchor_runStartItemId': '3',
          'fittingAnchor_runStartSide': 'end',
        },
      },
    ],
    'metadata': <String, dynamic>{
      'version': 1,
      'savedAt': '2026-07-16T00:00:00.000Z',
    },
  };
}

void main() {
  test('designer payload converts to interchange and back preserving state',
      () {
    final payload = _designerPayloadFixture();

    final model = LayoutInterchangeCodec.fromDesignerPayload(
      payload,
      canvasWidth: 1200,
      canvasHeight: 800,
      showGrid: true,
    );

    expect(model.layoutName, 'Rig Up');
    expect(model.canvas.width, 1200);
    expect(model.canvas.height, 800);
    expect(model.equipment.length, 2);
    expect(model.iron.length, 1);
    expect(model.fittings.length, 1);
    expect(model.equipment.last.rotationTurns, 1);
    expect(model.equipment.last.stableTypeId, 'choke_manifold_2');
    expect(model.iron.single.startEquipmentId, 1);
    expect(model.iron.single.startPortId, 'right');
    expect(model.iron.single.endEquipmentId, 2);
    expect(model.iron.single.endPortId, 'inletTopCenter');

    final rebuilt = LayoutInterchangeCodec.toDesignerPayload(model);
    final rebuiltItems = (rebuilt['items'] as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    final rebuiltChoke =
        rebuiltItems.firstWhere((item) => item['type'] == 'chokeManifold');
    final rebuiltIron =
        rebuiltItems.firstWhere((item) => item['type'] == 'ironHorizontal');

    expect(rebuilt['name'], payload['name']);
    expect(rebuilt['selectedId'], payload['selectedId']);
    expect(rebuiltChoke['rotationTurns'], 1);
    expect((rebuiltIron['properties'] as Map)['anchorStartSide'], 'right');
    expect(
        (rebuiltIron['properties'] as Map)['anchorEndSide'], 'inletTopCenter');
    expect((rebuiltIron['properties'] as Map)['freeAngleStartX'], '130.0000');
    expect((rebuiltIron['properties'] as Map)['freeAngleEndY'], '102.0000');
  });

  test('wellwerks json round trip preserves rotation position and connections',
      () {
    final model = LayoutInterchangeCodec.fromDesignerPayload(
      _designerPayloadFixture(),
      canvasWidth: 1200,
      canvasHeight: 800,
      showGrid: true,
    );

    final encoded = LayoutInterchangeCodec.encodeWellWerksJson(model);
    final decoded = LayoutInterchangeCodec.decodeWellWerksJson(encoded);

    expect(decoded.equipment.last.rotationTurns,
        model.equipment.last.rotationTurns);
    expect(decoded.equipment.first.x, model.equipment.first.x);
    expect(decoded.iron.single.startEquipmentId,
        model.iron.single.startEquipmentId);
    expect(decoded.iron.single.endPortId, model.iron.single.endPortId);
  });

  test('invalid json is rejected safely', () {
    expect(
      () => LayoutInterchangeCodec.decodeWellWerksJson('{not-json}'),
      throwsA(isA<LayoutInterchangeException>()),
    );
  });

  test('unsupported version is rejected safely', () {
    final raw = _designerPayloadFixture();
    final model = LayoutInterchangeCodec.fromDesignerPayload(
      raw,
      canvasWidth: 1200,
      canvasHeight: 800,
      showGrid: true,
    );
    final json = model.toJson()..['version'] = 99;

    expect(
      () => LayoutInterchangeCodec.decodeWellWerksJson(
          const JsonEncoder.withIndent('  ').convert(json)),
      throwsA(isA<LayoutInterchangeException>()),
    );
  });

  test('duplicate ids are rejected safely', () {
    final model = LayoutInterchangeCodec.fromDesignerPayload(
      _designerPayloadFixture(),
      canvasWidth: 1200,
      canvasHeight: 800,
      showGrid: true,
    );
    final duplicated = WellWerksLayoutInterchange(
      format: model.format,
      version: model.version,
      layoutName: model.layoutName,
      canvas: model.canvas,
      nextId: model.nextId,
      snapToGrid: model.snapToGrid,
      libraryKeepOpen: model.libraryKeepOpen,
      company: model.company,
      padName: model.padName,
      wellName: model.wellName,
      date: model.date,
      preparedBy: model.preparedBy,
      notes: model.notes,
      selectedId: model.selectedId,
      selectedIds: model.selectedIds,
      selectedEndpointLeading: model.selectedEndpointLeading,
      selectedBypassHandle: model.selectedBypassHandle,
      equipment: <InterchangeEquipmentItem>[
        model.equipment.first,
        model.equipment.last,
      ],
      iron: <InterchangeIronSegment>[
        InterchangeIronSegment(
          id: model.equipment.first.id,
          stableTypeId: model.iron.single.stableTypeId,
          internalType: model.iron.single.internalType,
          ironSize: model.iron.single.ironSize,
          start: model.iron.single.start,
          end: model.iron.single.end,
          locked: model.iron.single.locked,
          properties: model.iron.single.properties,
          startEquipmentId: model.iron.single.startEquipmentId,
          startPortId: model.iron.single.startPortId,
          endEquipmentId: model.iron.single.endEquipmentId,
          endPortId: model.iron.single.endPortId,
          startJointId: model.iron.single.startJointId,
          endJointId: model.iron.single.endJointId,
        ),
      ],
      fittings: model.fittings,
      metadata: model.metadata,
    );

    expect(
      () => LayoutInterchangeCodec.validate(duplicated),
      throwsA(isA<LayoutInterchangeException>()),
    );
  });

  test('svg export contains WellWerks metadata for groups ports and iron', () {
    final model = LayoutInterchangeCodec.fromDesignerPayload(
      _designerPayloadFixture(),
      canvasWidth: 1200,
      canvasHeight: 800,
      showGrid: true,
    );

    final svg = LayoutInterchangeCodec.encodeVisioSvg(model);

    expect(svg, contains('data-wellwerks-format="wellwerks-layout-svg"'));
    expect(svg, contains('wellwerks-layout-interchange'));
    expect(svg, contains('data-wellwerks-type="wellhead"'));
    expect(svg, contains('data-wellwerks-id="1"'));
    expect(svg, contains('data-wellwerks-port-id="right"'));
    expect(svg, contains('data-wellwerks-iron-size="3"'));
  });

  test('non-wellwerks svg is rejected with the expected message', () {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>';

    expect(
      () => LayoutInterchangeCodec.decodeVisioSvg(svg),
      throwsA(
        predicate((error) =>
            error is LayoutInterchangeException &&
            error.message ==
                'This SVG does not contain editable WellWerks layout data.'),
      ),
    );
  });

  test('esd equipment uses stable esd identifier', () {
    final payload = <String, dynamic>{
      'name': 'Rig Up',
      'nextId': 2,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'type': 'esdValve',
          'x': 20.0,
          'y': 30.0,
          'width': 30.0,
          'height': 24.0,
          'rotationTurns': 0,
          'locked': false,
          'properties': <String, String>{},
        },
      ],
      'metadata': <String, dynamic>{'version': 1},
    };

    final model = LayoutInterchangeCodec.fromDesignerPayload(
      payload,
      canvasWidth: 1200,
      canvasHeight: 800,
      showGrid: false,
    );

    expect(model.equipment.single.stableTypeId, 'esd');
  });

  test('svg export and import round trip rebuilds editable layout state', () {
    final original = LayoutInterchangeCodec.fromDesignerPayload(
      _designerPayloadFixture(),
      canvasWidth: 1200,
      canvasHeight: 800,
      showGrid: true,
    );
    final svg = LayoutInterchangeCodec.encodeVisioSvg(original);
    final restored = LayoutInterchangeCodec.decodeVisioSvg(svg);
    final payload = LayoutInterchangeCodec.toDesignerPayload(restored);
    final items = (payload['items'] as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    final iron = items.firstWhere((item) => item['type'] == 'ironHorizontal');

    expect(restored.layoutName, original.layoutName);
    expect(restored.equipment.length, original.equipment.length);
    expect(restored.fittings.length, original.fittings.length);
    expect((iron['properties'] as Map)['anchorEndSide'], 'inletTopCenter');
    expect((iron['properties'] as Map)['freeAngleEndX'], '279.0000');
  });
}
