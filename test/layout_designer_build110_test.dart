import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/screens/equipment_layout_screen.dart';

Future<void> _ensureEquipmentLibraryOpen(WidgetTester tester) async {
  if (find.text('Open Library').evaluate().isNotEmpty) {
    await tester.tap(find.text('Open Library').first);
    await tester.pumpAndSettle();
  }
  if (find.text('Show Equipment Library').evaluate().isNotEmpty) {
    await tester.tap(find.text('Show Equipment Library').first);
    await tester.pumpAndSettle();
  }
}

Future<void> _saveRigUp(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Save').first);
  await tester.pumpAndSettle();
}

Future<Map<String, dynamic>> _savedLayoutPayload() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('wellwerks_layout_designer_v2');
  expect(raw, isNotNull);
  return jsonDecode(raw!) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _itemsFromPayload(Map<String, dynamic> payload) {
  return (payload['items'] as List<dynamic>? ?? <dynamic>[])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
}

Map<String, dynamic> _findByType(
    List<Map<String, dynamic>> items, String type) {
  return items.firstWhere((item) => item['type'] == type);
}

Map<String, dynamic> _findById(List<Map<String, dynamic>> items, int id) {
  return items.firstWhere((item) => item['id'] == id);
}

Map<String, dynamic> _ironItem(
  int id, {
  required double x,
  required double y,
  required double width,
  double height = 24,
  bool vertical = false,
  Map<String, String>? properties,
  bool locked = false,
}) {
  return <String, dynamic>{
    'id': id,
    'type': vertical ? 'ironVertical' : 'ironHorizontal',
    'x': x,
    'y': y,
    'width': vertical ? 28.0 : width,
    'height': vertical ? width : height,
    'properties': <String, String>{'ironSize': '3', ...?properties},
    'rotationTurns': 0,
    'locked': locked,
  };
}

Map<String, dynamic> _equipmentItem(
  int id,
  String type, {
  required double x,
  required double y,
  required double width,
  required double height,
  bool locked = false,
}) {
  return <String, dynamic>{
    'id': id,
    'type': type,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'properties': <String, String>{},
    'rotationTurns': 0,
    'locked': locked,
  };
}

Map<String, dynamic> _bypassItem(
  int id, {
  required double x,
  required double y,
  Map<String, String>? properties,
  bool locked = false,
}) {
  return <String, dynamic>{
    'id': id,
    'type': 'bypass',
    'x': x,
    'y': y,
    'width': 66.0,
    'height': 34.0,
    'properties': <String, String>{'ironSize': '3', ...?properties},
    'rotationTurns': 0,
    'locked': locked,
  };
}

Future<void> _pumpLayout(
  WidgetTester tester, {
  List<Map<String, dynamic>> items = const <Map<String, dynamic>>[],
  int nextId = 10,
  int? selectedId,
  bool? selectedEndpointLeading,
  String? selectedBypassHandle,
}) async {
  final payload = <String, dynamic>{
    'name': 'Test Layout',
    'nextId': nextId,
    'snapToGrid': true,
    'items': items,
    if (selectedId != null) 'selectedId': selectedId,
    if (selectedId != null) 'selectedIds': <int>[selectedId],
    if (selectedEndpointLeading != null)
      'selectedEndpointLeading': selectedEndpointLeading,
    if (selectedBypassHandle != null)
      'selectedBypassHandle': selectedBypassHandle,
    'metadata': <String, dynamic>{'version': 1},
  };
  SharedPreferences.setMockInitialValues(
    <String, Object>{'wellwerks_layout_designer_v2': jsonEncode(payload)},
  );
  await tester.binding.setSurfaceSize(const Size(1280, 1500));
  await tester.pumpWidget(const MaterialApp(home: EquipmentLayoutScreen()));
  await tester.pumpAndSettle();
}

void main() {
  test('Build number is 113', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('version: 1.0.1+113'));
  });

  testWidgets(
      'Build 111 compact equipment sizing remains unchanged while Facilities stays unchanged',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 1500));
    await tester.pumpWidget(const MaterialApp(home: EquipmentLayoutScreen()));
    await tester.pumpAndSettle();

    await _ensureEquipmentLibraryOpen(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Wellhead').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Plug Catcher').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Facilities').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('library-symbol-wellhead-button')),
        findsWidgets);
    expect(find.byIcon(Icons.account_tree), findsNothing);

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final wellhead = _findByType(items, 'wellhead');
    final plug = _findByType(items, 'plugCatcher');
    final facilities = _findByType(items, 'facilities');

    expect((wellhead['width'] as num).toDouble(), closeTo(30, 0.01));
    expect((wellhead['height'] as num).toDouble(), closeTo(28, 0.01));
    expect((plug['width'] as num).toDouble(), closeTo(40, 0.01));
    expect((plug['height'] as num).toDouble(), closeTo(26, 0.01));
    expect((facilities['width'] as num).toDouble(), closeTo(220, 0.01));
    expect((facilities['height'] as num).toDouble(), closeTo(112, 0.01));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Iron uses a larger invisible hit area while visible iron thickness remains unchanged',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 180),
      ],
    );

    final hitbox =
        tester.getSize(find.byKey(const ValueKey<String>('item-hitbox-1')));
    expect(hitbox.height, greaterThan(40));

    await _saveRigUp(tester);
    final saved = _findById(_itemsFromPayload(await _savedLayoutPayload()), 1);
    expect((saved['height'] as num).toDouble(), closeTo(24, 0.01));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Endpoint handles appear for selected iron and disconnect action is available',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 94, properties: <String, String>{
          'jointEnd': 'joint_a',
        }),
        _ironItem(2, x: 214, y: 96, width: 120, properties: <String, String>{
          'jointStart': 'joint_a',
        }),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    expect(find.byKey(const ValueKey<String>('iron-handle-1-start')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('iron-handle-1-end')),
        findsOneWidget);
    expect(find.byTooltip('Disconnect'), findsOneWidget);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Dragging endpoint within snap radius creates an iron-to-iron connection that survives save reload and can disconnect',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 80),
        _ironItem(2, x: 214, y: 96, width: 120),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('item-hitbox-1')),
      const Offset(24, 0),
    );
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    var items = _itemsFromPayload(await _savedLayoutPayload());
    var iron1 = _findById(items, 1);
    var iron2 = _findById(items, 2);
    var props1 = (iron1['properties'] as Map).cast<String, dynamic>();
    var props2 = (iron2['properties'] as Map).cast<String, dynamic>();
    expect(props1['jointEnd'], isNotNull);
    expect(props1['jointEnd'], props2['jointStart']);

    await _pumpLayout(
      tester,
      items: items,
      nextId: 10,
      selectedId: 1,
    );
    await tester.tap(find.byTooltip('Disconnect'));
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    items = _itemsFromPayload(await _savedLayoutPayload());
    props1 = (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props1.containsKey('jointEnd'), isFalse);
    expect(items.length, 2);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Dragging endpoint to equipment anchor creates and preserves a real connection',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 88, width: 140),
        _equipmentItem(2, 'wellhead', x: 260, y: 86, width: 30, height: 28),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('item-hitbox-1')),
      const Offset(24, 0),
    );
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    var items = _itemsFromPayload(await _savedLayoutPayload());
    var props =
        (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '2');
    expect(props['anchorEndSide'], 'left');

    await tester.drag(find.byKey(const ValueKey<String>('item-hitbox-2')),
        const Offset(48, 0));
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    items = _itemsFromPayload(await _savedLayoutPayload());
    props = (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '2');
    expect(props['anchorEndSide'], 'left');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Bypass first and second side attachments persist independently',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 240),
        _ironItem(2, x: 120, y: 168, width: 240),
        _bypassItem(3, x: 180, y: 110),
      ],
      selectedId: 3,
      selectedBypassHandle: 'Primary',
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('item-hitbox-3')),
      const Offset(0, -24),
    );
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    var items = _itemsFromPayload(await _savedLayoutPayload());

    await _pumpLayout(
      tester,
      items: items,
      nextId: 10,
      selectedId: 3,
      selectedBypassHandle: 'Secondary',
    );
    await tester.drag(
      find.byKey(const ValueKey<String>('item-hitbox-3')),
      const Offset(0, 34),
    );
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    items = _itemsFromPayload(await _savedLayoutPayload());
    final props =
        (_findById(items, 3)['properties'] as Map).cast<String, dynamic>();
    expect(props['bypassPrimaryIronId'], '1');
    expect(props['bypassSecondaryIronId'], '2');
    expect(double.parse(props['bypassPrimaryT'] as String),
        inInclusiveRange(0.2, 0.8));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Bypass slides horizontally and vertically without drifting off axis',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 240),
        _bypassItem(3, x: 170, y: 79, properties: <String, String>{
          'bypassPrimaryIronId': '1',
          'bypassPrimaryT': '0.3500',
        }),
        _ironItem(4, x: 480, y: 80, width: 220, vertical: true),
        _bypassItem(5, x: 461, y: 140, properties: <String, String>{
          'bypassPrimaryIronId': '4',
          'bypassPrimaryT': '0.4000',
        }),
      ],
    );

    await tester.drag(find.byKey(const ValueKey<String>('item-hitbox-3')),
        const Offset(96, 10));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const ValueKey<String>('item-hitbox-5')),
        const Offset(14, 80));
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final horizontalBypass = _findById(items, 3);
    final verticalBypass = _findById(items, 5);
    final hProps =
        (horizontalBypass['properties'] as Map).cast<String, dynamic>();
    final vProps =
        (verticalBypass['properties'] as Map).cast<String, dynamic>();

    expect(hProps['bypassPrimaryIronId'], '1');
    expect(vProps['bypassPrimaryIronId'], '4');
    expect(
        (horizontalBypass['y'] as num).toDouble() +
            (horizontalBypass['height'] as num).toDouble() / 2,
        closeTo(108, 0.1));
    expect(
        (verticalBypass['x'] as num).toDouble() +
            (verticalBypass['width'] as num).toDouble() / 2,
        closeTo(494, 0.1));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Moving main iron carries attached bypass and locked iron stays fixed',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 240),
        _bypassItem(2, x: 170, y: 79, properties: <String, String>{
          'bypassPrimaryIronId': '1',
          'bypassPrimaryT': '0.3500',
        }),
        _ironItem(3, x: 420, y: 96, width: 180, locked: true),
      ],
    );

    await tester.drag(find.byKey(const ValueKey<String>('item-hitbox-1')),
        const Offset(48, 0));
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final bypass = _findById(items, 2);
    final lockedIron = _findById(items, 3);
    expect((bypass['x'] as num).toDouble(), greaterThan(170));
    expect((lockedIron['width'] as num).toDouble(), closeTo(180, 0.01));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Old layouts without new connection metadata still load safely',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 180),
        _bypassItem(2, x: 180, y: 110),
        _equipmentItem(3, 'facilities',
            x: 500, y: 260, width: 220, height: 112),
      ],
    );

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    expect(_findById(items, 1)['type'], 'ironHorizontal');
    expect(_findById(items, 2)['type'], 'bypass');
    expect(_findById(items, 3)['type'], 'facilities');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
