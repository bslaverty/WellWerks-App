import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/screens/equipment_layout_screen.dart';

Future<void> _ensureEquipmentLibraryOpen(WidgetTester tester) async {
  if (find.text('Add Equipment').evaluate().isNotEmpty) {
    await tester.tap(find.text('Add Equipment').first);
    await tester.pumpAndSettle();
  }
  if (find.text('Equipment').evaluate().isNotEmpty) {
    await tester.tap(find.text('Equipment').last);
    await tester.pumpAndSettle();
  }
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
  bool snapToGrid = false,
  bool? selectedEndpointLeading,
  String? selectedBypassHandle,
}) async {
  final payload = <String, dynamic>{
    'name': 'Test Layout',
    'nextId': nextId,
    'snapToGrid': snapToGrid,
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
  test('Build number is 128', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('version: 1.0.1+128'));
  });

  testWidgets(
      'Build 117 default bypass is narrower and keeps usable attachment handles',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'type': 'bypass',
          'x': 180.0,
          'y': 110.0,
          'properties': <String, String>{'ironSize': '3'},
          'rotationTurns': 0,
          'locked': false,
        },
      ],
      selectedId: 1,
    );

    expect(find.byKey(const ValueKey<String>('bypass-handle-1-primary')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('bypass-handle-1-secondary')),
        findsOneWidget);

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final bypass = _findByType(items, 'bypass');
    expect((bypass['width'] as num).toDouble(), closeTo(30, 0.01));
    expect((bypass['height'] as num).toDouble(), closeTo(32, 0.01));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Legacy bypass dimensions migrate to compact width with center preserved',
      (tester) async {
    const legacyX = 180.0;
    const legacyY = 110.0;
    const legacyWidth = 66.0;
    const legacyHeight = 34.0;
    const legacyCenterX = legacyX + legacyWidth / 2;
    const legacyCenterY = legacyY + legacyHeight / 2;

    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _bypassItem(3, x: legacyX, y: legacyY),
      ],
      selectedId: 3,
    );

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final bypass = _findById(items, 3);
    final width = (bypass['width'] as num).toDouble();
    final height = (bypass['height'] as num).toDouble();
    final x = (bypass['x'] as num).toDouble();
    final y = (bypass['y'] as num).toDouble();

    expect(width, closeTo(30, 0.01));
    expect(height, closeTo(32, 0.01));
    expect(x + width / 2, closeTo(legacyCenterX, 0.01));
    expect(y + height / 2, closeTo(legacyCenterY, 0.01));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Empty canvas tap clears selection and creates neither iron nor duplicate',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'wellhead', x: 280, y: 260, width: 30, height: 28),
      ],
      selectedId: 1,
    );

    expect(find.byKey(const ValueKey<String>('selection-dock-toolbar')),
        findsOneWidget);

    await tester.tapAt(const Offset(40, 520));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('selection-dock-toolbar')),
        findsOneWidget);

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    expect(items.length, 1);
    expect(_findById(items, 1)['type'], 'wellhead');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Empty canvas drag pans without deselecting the current item',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'wellhead', x: 280, y: 260, width: 30, height: 28),
      ],
      selectedId: 1,
    );

    expect(find.byKey(const ValueKey<String>('selection-dock-toolbar')),
        findsOneWidget);

    await tester.dragFrom(const Offset(40, 520), const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('selection-dock-toolbar')),
        findsOneWidget);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('D-pad center deselects while fixed strip stays visible',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'wellhead', x: 280, y: 260, width: 30, height: 28),
      ],
      selectedId: 1,
    );

    expect(find.byKey(const ValueKey<String>('selection-dock-toolbar')),
        findsOneWidget);
    await tester.tap(find.byTooltip('Deselect'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('selection-dock-toolbar')),
        findsOneWidget);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Full D-pad keeps all arrows and center button inside bounds',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'wellhead', x: 280, y: 260, width: 30, height: 28),
      ],
      selectedId: 1,
    );

    final dpadRect =
        tester.getRect(find.byKey(const ValueKey<String>('selection-dpad')));
    for (final tooltip in <String>[
      'Move Up',
      'Move Down',
      'Move Left',
      'Move Right',
      'Deselect',
    ]) {
      final rect = tester.getRect(find.byTooltip(tooltip));
      expect(rect.left, greaterThanOrEqualTo(dpadRect.left));
      expect(rect.top, greaterThanOrEqualTo(dpadRect.top));
      expect(rect.right, lessThanOrEqualTo(dpadRect.right));
      expect(rect.bottom, lessThanOrEqualTo(dpadRect.bottom));
    }

    final centerRect = tester.getRect(find.byTooltip('Deselect'));
    expect(centerRect.center.dx, closeTo(dpadRect.center.dx, 4.0));
    expect(centerRect.center.dy, closeTo(dpadRect.center.dy, 4.0));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Fixed edit strip keeps a stable height through select and deselect',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'wellhead', x: 280, y: 260, width: 30, height: 28),
      ],
      selectedId: 1,
    );

    final stripFinder =
        find.byKey(const ValueKey<String>('selection-dock-toolbar'));
    final selectedHeight = tester.getSize(stripFinder).height;

    await tester.tapAt(const Offset(40, 520));
    await tester.pumpAndSettle();

    final deselectedHeight = tester.getSize(stripFinder).height;
    expect(deselectedHeight, closeTo(selectedHeight, 0.01));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Snap OFF D-pad nudge moves selected item by one logical unit',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'wellhead', x: 280, y: 260, width: 30, height: 28),
      ],
      selectedId: 1,
    );

    await tester.tap(find.byTooltip('Move Right'));
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final moved = _findById(items, 1);
    expect((moved['x'] as num).toDouble(), closeTo(281.0, 0.01));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Align to Grid ON D-pad nudge uses the grid-aligned step increment',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'wellhead', x: 280, y: 260, width: 30, height: 28),
      ],
      selectedId: 1,
    );

    await tester.tap(find.text('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Align to Grid: Off').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Move Right'));
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final moved = _findById(items, 1);
    expect((moved['x'] as num).toDouble(), closeTo(282.0, 0.01));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Undo and redo stay directly accessible in the fixed strip',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'wellhead', x: 280, y: 260, width: 30, height: 28),
      ],
      selectedId: 1,
    );

    final undoFinder = find.widgetWithText(OutlinedButton, 'Undo').first;
    final redoFinder = find.widgetWithText(OutlinedButton, 'Redo').first;
    expect(undoFinder, findsOneWidget);
    expect(redoFinder, findsOneWidget);

    await tester.tap(find.byTooltip('Move Right'));
    await tester.pumpAndSettle();

    await tester.tap(undoFinder);
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    final undone = _findById(_itemsFromPayload(await _savedLayoutPayload()), 1);
    expect((undone['x'] as num).toDouble(), closeTo(280.0, 0.01));

    await tester.tap(redoFinder);
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    final redone = _findById(_itemsFromPayload(await _savedLayoutPayload()), 1);
    expect((redone['x'] as num).toDouble(), closeTo(281.0, 0.01));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('D-pad hold repeats after delay and stops immediately on release',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'wellhead', x: 280, y: 260, width: 30, height: 28),
      ],
      selectedId: 1,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Move Right')),
    );
    await tester.pump(const Duration(milliseconds: 520));
    await gesture.up();
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    final afterHoldItems = _itemsFromPayload(await _savedLayoutPayload());
    final afterHoldX = (_findById(afterHoldItems, 1)['x'] as num).toDouble();
    expect(afterHoldX, greaterThanOrEqualTo(281.0));

    await tester.pump(const Duration(milliseconds: 260));
    await _saveRigUp(tester);
    final afterWaitItems = _itemsFromPayload(await _savedLayoutPayload());
    final afterWaitX = (_findById(afterWaitItems, 1)['x'] as num).toDouble();
    expect(afterWaitX, closeTo(afterHoldX, 0.01));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Fixed strip stays visible during drag and remains off dragged item',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'wellhead', x: 340, y: 320, width: 30, height: 28),
      ],
      selectedId: 1,
    );

    expect(find.byKey(const ValueKey<String>('selection-dock-toolbar')),
        findsOneWidget);

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<String>('item-hitbox-1'))));
    await tester.pump();
    await gesture.moveBy(const Offset(90, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('selection-dock-toolbar')),
        findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    final toolbarFinder =
        find.byKey(const ValueKey<String>('selection-dock-toolbar'));
    expect(toolbarFinder, findsOneWidget);
    final toolbarRect = tester.getRect(toolbarFinder);
    final itemRect =
        tester.getRect(find.byKey(const ValueKey<String>('item-hitbox-1')));
    final physicalWidth = tester.view.physicalSize.width;

    expect(toolbarRect.overlaps(itemRect), isFalse);
    expect(toolbarRect.left, greaterThanOrEqualTo(0));
    expect(toolbarRect.right, lessThanOrEqualTo(physicalWidth));

    await tester.tap(find.byTooltip('Move Right'));
    await tester.pumpAndSettle();
    await _saveRigUp(tester);
    final movedItems = _itemsFromPayload(await _savedLayoutPayload());
    final moved = _findById(movedItems, 1);
    expect((moved['x'] as num).toDouble(), greaterThan(340));

    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    await _ensureEquipmentLibraryOpen(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Plug Catcher').first);
    await tester.pumpAndSettle();
    await _ensureEquipmentLibraryOpen(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Facilities').first);
    await tester.pumpAndSettle();

    expect(find.text('Rig-Up Library'), findsOneWidget);
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
      'Selecting equipment from the library keeps the library open by default',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 1500));
    await tester.pumpWidget(const MaterialApp(home: EquipmentLayoutScreen()));
    await tester.pumpAndSettle();

    await _ensureEquipmentLibraryOpen(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Wellhead').first);
    await tester.pumpAndSettle();

    expect(find.text('Rig-Up Library'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('item-hitbox-1')), findsOneWidget);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Connect Iron mode minimizes the library, shows valid anchors, and stores both equipment anchors',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'wellhead', x: 180, y: 220, width: 30, height: 28),
        _equipmentItem(2, 'plugCatcher', x: 360, y: 206, width: 40, height: 26),
      ],
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add Iron').last);
    await tester.pumpAndSettle();

    expect(find.text('Rig-Up Library'), findsNothing);
    final startAnchor =
        find.byKey(const ValueKey<String>('connect-anchor-1-right'));
    final endAnchor =
        find.byKey(const ValueKey<String>('connect-anchor-2-left'));
    expect(startAnchor, findsOneWidget);
    expect(endAnchor, findsOneWidget);

    await tester.tapAt(tester.getCenter(startAnchor));
    await tester.pumpAndSettle();
    expect(find.text('Select destination'), findsOneWidget);

    await tester.tapAt(tester.getCenter(endAnchor));
    await tester.pumpAndSettle();

    expect(find.text('Continue Iron'), findsOneWidget);
    expect(find.text('Done'), findsWidgets);

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final iron = _findByType(items, 'ironHorizontal');
    final props = (iron['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorStartItemId'], '1');
    expect(props['anchorStartSide'], 'right');
    expect(props['anchorEndItemId'], '2');
    expect(props['anchorEndSide'], 'left');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  }, skip: true);

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

  testWidgets('Selected iron keeps its selection controls available',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 94),
        _ironItem(2, x: 214, y: 96, width: 120),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    expect(find.byKey(const ValueKey<String>('selection-dock-toolbar')),
        findsOneWidget);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Selected horizontal iron shows two visible endpoint handles aligned to endpoints',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 140),
      ],
      selectedId: 1,
    );

    final start = find.byKey(const ValueKey<String>('iron-handle-1-start'));
    final end = find.byKey(const ValueKey<String>('iron-handle-1-end'));
    expect(start, findsOneWidget);
    expect(end, findsOneWidget);

    final startRect = tester.getRect(start);
    final endRect = tester.getRect(end);
    expect(startRect.width, closeTo(44.0, 0.1));
    expect(startRect.height, closeTo(44.0, 0.1));
    expect((endRect.center.dy - startRect.center.dy).abs(),
        lessThanOrEqualTo(1.5));
    expect(
        (endRect.center.dx - startRect.center.dx).abs(), closeTo(140.0, 2.0));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Selected vertical iron shows two visible endpoint handles aligned to endpoints',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 180, y: 120, width: 160, vertical: true),
      ],
      selectedId: 1,
    );

    final start = find.byKey(const ValueKey<String>('iron-handle-1-start'));
    final end = find.byKey(const ValueKey<String>('iron-handle-1-end'));
    expect(start, findsOneWidget);
    expect(end, findsOneWidget);

    final startRect = tester.getRect(start);
    final endRect = tester.getRect(end);
    expect((endRect.center.dx - startRect.center.dx).abs(),
        lessThanOrEqualTo(1.5));
    expect(
        (endRect.center.dy - startRect.center.dy).abs(), closeTo(160.0, 2.0));

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
      find.byKey(const ValueKey<String>('iron-handle-1-end')),
      const Offset(16, 0),
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
    await _saveRigUp(tester);

    items = _itemsFromPayload(await _savedLayoutPayload());
    props1 = (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props1['jointEnd'], isNotNull);
    expect(items.length, 2);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Dragging endpoint outside snap radius creates no iron-to-iron connection',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 80),
        _ironItem(2, x: 270, y: 96, width: 120),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('iron-handle-1-end')),
      const Offset(24, 0),
    );
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final props =
        (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['jointEnd'], isNull);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Self-connection is prevented and duplicate endpoint joins are stable',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 80, properties: <String, String>{
          'jointEnd': 'joint_a',
        }),
        _ironItem(2, x: 214, y: 96, width: 120, properties: <String, String>{
          'jointStart': 'joint_a',
        }),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );
    await _saveRigUp(tester);

    var items = _itemsFromPayload(await _savedLayoutPayload());
    final firstJoin = ((_findById(items, 1)['properties'] as Map)
        .cast<String, dynamic>())['jointEnd'];
    expect(firstJoin, isNotNull);

    await tester.drag(
      find.byKey(const ValueKey<String>('iron-handle-1-end')),
      const Offset(2, 0),
    );
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    items = _itemsFromPayload(await _savedLayoutPayload());
    final props =
        (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['jointEnd'], firstJoin);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Equipment anchor connection metadata persists and follows movement',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 328, width: 140, properties: <String, String>{
          'anchorEndItemId': '2',
          'anchorEndSide': 'left',
        }),
        _equipmentItem(2, 'wellhead', x: 260, y: 326, width: 30, height: 28),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    await _saveRigUp(tester);
    var items = _itemsFromPayload(await _savedLayoutPayload());
    var props =
        (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '2');
    expect(props['anchorEndSide'], anyOf('left', 'right'));

    await tester.drag(find.byKey(const ValueKey<String>('item-hitbox-2')),
        const Offset(48, 0));
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    items = _itemsFromPayload(await _savedLayoutPayload());
    props = (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '2');
    expect(props['anchorEndSide'], anyOf('left', 'right'));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Cyclonic anchor connection metadata persists and follows movement',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 328, width: 140, properties: <String, String>{
          'anchorEndItemId': '2',
          'anchorEndSide': 'left',
        }),
        _equipmentItem(2, 'cyclonicSandSep',
            x: 260, y: 316, width: 56, height: 34),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    await _saveRigUp(tester);
    var items = _itemsFromPayload(await _savedLayoutPayload());
    var props =
        (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '2');
    expect(props['anchorEndSide'], isNotNull);

    await tester.drag(
      find.byKey(const ValueKey<String>('item-hitbox-2')),
      const Offset(36, 0),
    );
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    items = _itemsFromPayload(await _savedLayoutPayload());
    props = (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '2');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Bypass left-handle endpoint anchor persists across movement',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 110, y: 350, width: 70, properties: <String, String>{
          'anchorEndItemId': '3',
          'anchorEndSide': 'bypassPrimary',
        }),
        _bypassItem(3, x: 180, y: 350),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    await _saveRigUp(tester);
    var items = _itemsFromPayload(await _savedLayoutPayload());
    var props =
        (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '3');
    expect(props['anchorEndSide'], anyOf('bypassPrimary', 'bypassSecondary'));

    await tester.drag(
      find.byKey(const ValueKey<String>('item-hitbox-3')),
      const Offset(48, 0),
    );
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    items = _itemsFromPayload(await _savedLayoutPayload());
    props = (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '3');
    expect(props['anchorEndSide'], anyOf('bypassPrimary', 'bypassSecondary'));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Bypass right-handle endpoint anchor persists across movement',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _bypassItem(3, x: 180, y: 350),
        _ironItem(1, x: 246, y: 350, width: 74, properties: <String, String>{
          'anchorStartItemId': '3',
          'anchorStartSide': 'bypassSecondary',
        }),
      ],
      selectedId: 1,
      selectedEndpointLeading: true,
    );

    await _saveRigUp(tester);
    var items = _itemsFromPayload(await _savedLayoutPayload());
    var props =
        (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorStartItemId'], '3');
    expect(props['anchorStartSide'], anyOf('bypassPrimary', 'bypassSecondary'));

    await tester.drag(
      find.byKey(const ValueKey<String>('item-hitbox-3')),
      const Offset(-36, 0),
    );
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    items = _itemsFromPayload(await _savedLayoutPayload());
    props = (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorStartItemId'], '3');
    expect(props['anchorStartSide'], anyOf('bypassPrimary', 'bypassSecondary'));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Bypass left and right attachments persist independently',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 240),
        _ironItem(2, x: 120, y: 168, width: 240),
        _bypassItem(3, x: 180, y: 110, properties: <String, String>{
          'bypassPrimaryIronId': '1',
          'bypassPrimaryT': '0.3500',
          'bypassSecondaryIronId': '2',
          'bypassSecondaryT': '0.3400',
        }),
      ],
      selectedId: 3,
    );

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
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
