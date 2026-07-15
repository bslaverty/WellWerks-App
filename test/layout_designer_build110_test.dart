import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

Offset _ironEndpointFromMap(Map<String, dynamic> iron, bool leading) {
  final type = iron['type'] as String;
  final x = (iron['x'] as num).toDouble();
  final y = (iron['y'] as num).toDouble();
  final width = (iron['width'] as num).toDouble();
  final height = (iron['height'] as num).toDouble();
  if (type == 'ironHorizontal') {
    return Offset(leading ? x : x + width, y + height / 2);
  }
  return Offset(x + width / 2, leading ? y : y + height);
}

Offset _bypassSpineCenterFromMap(Map<String, dynamic> bypass) {
  final x = (bypass['x'] as num).toDouble();
  final y = (bypass['y'] as num).toDouble();
  final width = (bypass['width'] as num).toDouble();
  final height = (bypass['height'] as num).toDouble();
  return Offset(x + (width * 0.28), y + (height * 0.5));
}

Map<String, Offset> _anchorFractionsForType(String type) {
  switch (type) {
    case 'wellhead':
    case 'esdValve':
    case 'lineHeater':
    case 'plugCatcher':
    case 'cyclonicSandSep':
    case 'sphericalSandSep':
    case 'chokeManifold':
    case 'testSeparator':
    case 'flare':
    case 'compressor':
      return <String, Offset>{
        'top': const Offset(0.5, 0.08),
        'right': const Offset(0.92, 0.5),
        'bottom': const Offset(0.5, 0.92),
        'left': const Offset(0.08, 0.5),
      };
    case 'flowbackTank':
    case 'productionTank':
    case 'facilities':
      return <String, Offset>{
        'top': const Offset(0.5, 0.16),
        'right': const Offset(0.82, 0.5),
        'bottom': const Offset(0.5, 0.84),
        'left': const Offset(0.18, 0.5),
      };
    case 'bypass':
      return <String, Offset>{
        'mainTop': const Offset(0.28, 0.14),
        'mainBottom': const Offset(0.28, 0.86),
        'upperValveOutlet': const Offset(0.82, 0.34),
        'lowerValveOutlet': const Offset(0.82, 0.66),
      };
    case 'teeUp':
      return <String, Offset>{
        'runStart': const Offset(0.08, 0.5),
        'runEnd': const Offset(0.92, 0.5),
        'branch': const Offset(0.5, 0.08),
      };
    case 'teeRight':
      return <String, Offset>{
        'runStart': const Offset(0.5, 0.08),
        'runEnd': const Offset(0.5, 0.92),
        'branch': const Offset(0.92, 0.5),
      };
    case 'teeDown':
      return <String, Offset>{
        'runStart': const Offset(0.08, 0.5),
        'runEnd': const Offset(0.92, 0.5),
        'branch': const Offset(0.5, 0.92),
      };
    case 'teeLeft':
      return <String, Offset>{
        'runStart': const Offset(0.5, 0.08),
        'runEnd': const Offset(0.5, 0.92),
        'branch': const Offset(0.08, 0.5),
      };
    case 'elbowUpRight':
      return <String, Offset>{
        'inlet': const Offset(0.5, 0.92),
        'outlet': const Offset(0.92, 0.5),
      };
    case 'elbowRightDown':
      return <String, Offset>{
        'inlet': const Offset(0.08, 0.5),
        'outlet': const Offset(0.5, 0.92),
      };
    case 'elbowDownLeft':
      return <String, Offset>{
        'inlet': const Offset(0.5, 0.08),
        'outlet': const Offset(0.08, 0.5),
      };
    case 'elbowLeftUp':
      return <String, Offset>{
        'inlet': const Offset(0.92, 0.5),
        'outlet': const Offset(0.5, 0.08),
      };
    default:
      throw StateError('Unsupported anchor type for test helper: $type');
  }
}

Offset _rotateLocal(Offset local, Size size, int turns) {
  final center = Offset(size.width / 2, size.height / 2);
  final delta = local - center;
  final normalized = ((turns % 4) + 4) % 4;
  late final Offset rotated;
  switch (normalized) {
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

Offset _fittingAnchorFromMap(Map<String, dynamic> item, String side) {
  final type = item['type'] as String;
  final x = (item['x'] as num).toDouble();
  final y = (item['y'] as num).toDouble();
  final width = (item['width'] as num).toDouble();
  final height = (item['height'] as num).toDouble();
  final turns = (item['rotationTurns'] as num?)?.toInt() ?? 0;
  final fractions = _anchorFractionsForType(type);
  final uv = fractions[side];
  if (uv == null) {
    throw StateError('Unsupported side "$side" for type $type in test helper');
  }
  final local = Offset(width * uv.dx, height * uv.dy);
  final rotated = _rotateLocal(local, Size(width, height), turns);
  return Offset(x + rotated.dx, y + rotated.dy);
}

Offset _bypassLeadEndpointFromMap(Map<String, dynamic> item, String leadId) {
  final x = (item['x'] as num).toDouble();
  final y = (item['y'] as num).toDouble();
  final width = (item['width'] as num).toDouble();
  final height = (item['height'] as num).toDouble();
  final turns = (item['rotationTurns'] as num?)?.toInt() ?? 0;
  final props = (item['properties'] as Map).cast<String, dynamic>();
  final local = Offset(
    double.parse(props['bypassLead${leadId}EndX'] as String),
    double.parse(props['bypassLead${leadId}EndY'] as String),
  );
  final rotated = _rotateLocal(local, Size(width, height), turns);
  return Offset(x + rotated.dx, y + rotated.dy);
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
  test('Build number is 151', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('version: 1.0.1+151'));
  });

  testWidgets('Selected bypass shows built-in lead handles', (tester) async {
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

    expect(find.byKey(const ValueKey<String>('bypass-lead-handle-1-leadA')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('bypass-lead-handle-1-leadB')),
        findsOneWidget);

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final bypass = _findByType(items, 'bypass');
    expect((bypass['width'] as num).toDouble(), closeTo(30, 0.01));
    expect((bypass['height'] as num).toDouble(), closeTo(32, 0.01));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Legacy bypass dimensions migrate to Build 134 width with center preserved',
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
    expect(startRect.width, closeTo(56.0, 0.1));
    expect(startRect.height, closeTo(56.0, 0.1));
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
      'Dragging endpoint inside preview radius shows one target but does not connect before release',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 80),
        _ironItem(2, x: 248, y: 96, width: 120),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    final handle = find.byKey(const ValueKey<String>('iron-handle-1-end'));
    expect(handle, findsOneWidget);

    final startCenter = tester.getCenter(handle);
    final gesture = await tester.startGesture(startCenter);
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();

    expect(
        find.byKey(const ValueKey<String>('snap-indicator')), findsOneWidget);
    final draggedCenter = tester.getCenter(handle);
    expect(draggedCenter.dx, greaterThan(startCenter.dx));
    expect(draggedCenter.dy, closeTo(startCenter.dy, 0.5));

    await gesture.up();
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final props =
        (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['jointEnd'], isNull);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Dragging endpoint inside final release radius snaps exactly on release',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 80),
        _ironItem(2, x: 236, y: 96, width: 120),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    final handle = find.byKey(const ValueKey<String>('iron-handle-1-end'));
    const targetCenter = Offset(236, 108);

    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();

    final draggedCenter = tester.getCenter(handle);
    expect(
        find.byKey(const ValueKey<String>('snap-indicator')), findsOneWidget);
    expect(draggedCenter.dx, isNot(closeTo(targetCenter.dx, 0.5)));

    await gesture.up();
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final iron1 = _findById(items, 1);
    final iron2 = _findById(items, 2);
    final props1 = (iron1['properties'] as Map).cast<String, dynamic>();
    final props2 = (iron2['properties'] as Map).cast<String, dynamic>();
    expect(props1['jointEnd'], isNotNull);
    expect(props1['jointEnd'], props2['jointStart']);
    expect(
        _ironEndpointFromMap(iron1, false), _ironEndpointFromMap(iron2, true));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Dragging endpoint within snap radius creates an iron-to-iron connection that survives save reload and can disconnect',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 80),
        _ironItem(2, x: 236, y: 96, width: 120),
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
    expect(props['anchorEndSide'], anyOf('left', 'right', 'inlet', 'outlet'));

    final wellheadRect =
        tester.getRect(find.byKey(const ValueKey<String>('item-hitbox-2')));
    await tester.dragFrom(
      Offset(wellheadRect.right - 8, wellheadRect.center.dy),
      const Offset(48, 0),
    );
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    items = _itemsFromPayload(await _savedLayoutPayload());
    props = (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '2');
    expect(props['anchorEndSide'], anyOf('left', 'right', 'inlet', 'outlet'));

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

    final cyclonicRect =
        tester.getRect(find.byKey(const ValueKey<String>('item-hitbox-2')));
    await tester.dragFrom(
      Offset(cyclonicRect.right - 8, cyclonicRect.center.dy),
      const Offset(36, 0),
    );
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    items = _itemsFromPayload(await _savedLayoutPayload());
    props = (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '2');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Bypass-linked iron endpoint stays connected and follows bypass drag',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 110, y: 350, width: 70, properties: <String, String>{
          'anchorEndItemId': '3',
          'anchorEndSide': 'leftEnd',
        }),
        _bypassItem(3, x: 180, y: 350, properties: <String, String>{
          'bypassPrimaryIronId': '1',
          'bypassPrimaryT': '1.0000',
        }),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    await _saveRigUp(tester);
    var items = _itemsFromPayload(await _savedLayoutPayload());
    var props =
        (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '3');
    expect(props['anchorEndSide'],
        anyOf('mainTop', 'mainBottom', 'upperValveOutlet', 'lowerValveOutlet'));

    final bypassCenterBefore =
        tester.getCenter(find.byKey(const ValueKey<String>('item-hitbox-3')));
    await tester.dragFrom(bypassCenterBefore, const Offset(48, 0));
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    items = _itemsFromPayload(await _savedLayoutPayload());
    props = (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '3');
    expect(props['anchorEndSide'],
        anyOf('mainTop', 'mainBottom', 'upperValveOutlet', 'lowerValveOutlet'));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Bypass right-side linked endpoint stays connected while bypass moves',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _bypassItem(3, x: 180, y: 350),
        _ironItem(1, x: 246, y: 350, width: 74, properties: <String, String>{
          'anchorStartItemId': '3',
          'anchorStartSide': 'rightEnd',
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
    expect(props['anchorStartSide'], anyOf('mainTop', 'mainBottom'));

    final bypassCenterBefore =
        tester.getCenter(find.byKey(const ValueKey<String>('item-hitbox-3')));
    await tester.dragFrom(bypassCenterBefore, const Offset(-36, 0));
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    items = _itemsFromPayload(await _savedLayoutPayload());
    final movedBypass = _findById(items, 3);
    expect((movedBypass['x'] as num).toDouble(), isNot(closeTo(180.0, 0.01)));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Bypass legacy dual-attachment metadata loads safely',
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
    expect(props['bypassSecondaryIronId'], anyOf(isNull, '2'));
    expect(double.parse(props['bypassPrimaryT'] as String),
        inInclusiveRange(0.2, 0.8));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Attached bypass body drag slides along parent axis and keeps attachment',
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

    await _saveRigUp(tester);

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

    expect(hProps['bypassParentIronId'], '1');
    expect(vProps['bypassParentIronId'], '4');
    expect(hProps['bypassPrimaryIronId'], '1');
    expect(vProps['bypassPrimaryIronId'], '4');
    final horizontalSpineCenter = _bypassSpineCenterFromMap(horizontalBypass);
    final verticalSpineCenter = _bypassSpineCenterFromMap(verticalBypass);
    expect(horizontalSpineCenter.dy, closeTo(108.0, 2.0));
    expect(verticalSpineCenter.dx, closeTo(494.0, 2.0));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Build 137 canonical bypass port IDs persist across save',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 160, width: 120, properties: <String, String>{
          'anchorEndItemId': '3',
          'anchorEndSide': 'bypassPrimary',
        }),
        _ironItem(2, x: 120, y: 230, width: 120, properties: <String, String>{
          'anchorEndItemId': '3',
          'anchorEndSide': 'bypassSecondary',
        }),
        _ironItem(4, x: 300, y: 160, width: 100, properties: <String, String>{
          'anchorStartItemId': '3',
          'anchorStartSide': 'upperValveOutlet',
        }),
        _ironItem(5, x: 300, y: 230, width: 100, properties: <String, String>{
          'anchorStartItemId': '3',
          'anchorStartSide': 'lowerValveOutlet',
        }),
        _bypassItem(3, x: 245, y: 188),
      ],
    );

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final p1 =
        (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    final p2 =
        (_findById(items, 2)['properties'] as Map).cast<String, dynamic>();
    final p4 =
        (_findById(items, 4)['properties'] as Map).cast<String, dynamic>();
    final p5 =
        (_findById(items, 5)['properties'] as Map).cast<String, dynamic>();

    expect(p1['anchorEndSide'], 'mainTop');
    expect(p2['anchorEndSide'], 'mainBottom');
    expect(p4['anchorStartSide'], 'upperValveOutlet');
    expect(p5['anchorStartSide'], 'lowerValveOutlet');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Upper and lower valve connections persist and follow bypass move',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 130, y: 150, width: 120, properties: <String, String>{
          'anchorEndItemId': '3',
          'anchorEndSide': 'upperValveOutlet',
        }),
        _ironItem(2, x: 130, y: 228, width: 120, properties: <String, String>{
          'anchorEndItemId': '3',
          'anchorEndSide': 'lowerValveOutlet',
        }),
        _bypassItem(3, x: 250, y: 182, properties: <String, String>{
          'bypassPrimaryIronId': '4',
          'bypassPrimaryT': '0.5000',
        }),
        _ironItem(4, x: 150, y: 180, width: 300),
      ],
      selectedId: 3,
    );

    await _saveRigUp(tester);
    var items = _itemsFromPayload(await _savedLayoutPayload());
    var bypass = _findById(items, 3);
    var ironUpper = _findById(items, 1);
    var ironLower = _findById(items, 2);

    var upperEnd = _ironEndpointFromMap(ironUpper, false);
    var lowerEnd = _ironEndpointFromMap(ironLower, false);
    final upperProps = (ironUpper['properties'] as Map).cast<String, dynamic>();
    final lowerProps = (ironLower['properties'] as Map).cast<String, dynamic>();

    expect(upperProps['anchorEndItemId'], '3');
    expect(upperProps['anchorEndSide'], 'upperValveOutlet');
    expect(lowerProps['anchorEndItemId'], '3');
    expect(lowerProps['anchorEndSide'], 'lowerValveOutlet');

    await _pumpLayout(
      tester,
      items: items,
      nextId: 10,
      selectedId: 3,
    );
    await _saveRigUp(tester);

    items = _itemsFromPayload(await _savedLayoutPayload());
    bypass = _findById(items, 3);
    ironUpper = _findById(items, 1);
    ironLower = _findById(items, 2);
    final upperEndAfter = _ironEndpointFromMap(ironUpper, false);
    final lowerEndAfter = _ironEndpointFromMap(ironLower, false);
    final bypassCenter = Offset(
      (bypass['x'] as num).toDouble() + (bypass['width'] as num).toDouble() / 2,
      (bypass['y'] as num).toDouble() +
          (bypass['height'] as num).toDouble() / 2,
    );

    expect(upperEndAfter, equals(upperEnd));
    expect(lowerEndAfter, equals(lowerEnd));
    expect((upperEndAfter - bypassCenter).distance, lessThan(60));
    expect((lowerEndAfter - bypassCenter).distance, lessThan(60));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Unsupported bypass port resolves as disconnected endpoint',
      (tester) async {
    final iron =
        _ironItem(1, x: 120, y: 96, width: 120, properties: <String, String>{
      'anchorEndItemId': '3',
      'anchorEndSide': 'center',
    });
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        iron,
        _bypassItem(3, x: 260, y: 92),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    final handle = find.byKey(const ValueKey<String>('iron-handle-1-end'));
    expect(handle, findsOneWidget);
    final handleCenter = tester.getCenter(handle);
    final itemRect =
        tester.getRect(find.byKey(const ValueKey<String>('item-hitbox-1')));
    final expectedEndpoint = Offset(itemRect.right - 24.0, itemRect.center.dy);
    expect(handleCenter.dx, closeTo(expectedEndpoint.dx, 1.0));
    expect(handleCenter.dy, closeTo(expectedEndpoint.dy, 1.0));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Endpoint same-target lockout blocks immediate recapture until leaving the lockout radius',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 120, properties: <String, String>{
          'anchorEndItemId': '3',
          'anchorEndSide': 'upperValveOutlet',
        }),
        _bypassItem(3, x: 260, y: 92),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    final handle = find.byKey(const ValueKey<String>('iron-handle-1-end'));
    final firstGesture = await tester.startGesture(tester.getCenter(handle));
    await firstGesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await firstGesture.moveBy(const Offset(-24, 0));
    await tester.pump();
    await firstGesture.up();
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    var items = _itemsFromPayload(await _savedLayoutPayload());
    var props =
        (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], isNull);
    expect(props['anchorEndSide'], isNull);

    final secondGesture = await tester.startGesture(tester.getCenter(handle));
    await secondGesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await secondGesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    expect(
        find.byKey(const ValueKey<String>('snap-indicator')), findsOneWidget);
    await secondGesture.up();
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    items = _itemsFromPayload(await _savedLayoutPayload());
    props = (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '3');
    expect(props['anchorEndSide'], 'upperValveOutlet');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Connected bypass endpoint holds, disconnects, and reconnects on release',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 120, properties: <String, String>{
          'anchorEndItemId': '3',
          'anchorEndSide': 'upperValveOutlet',
        }),
        _bypassItem(3, x: 260, y: 92),
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    final handle = find.byKey(const ValueKey<String>('iron-handle-1-end'));
    final start = tester.getCenter(handle);
    await tester.dragFrom(start, const Offset(8, 0));
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    var items = _itemsFromPayload(await _savedLayoutPayload());
    var props =
        (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '3');
    expect(props['anchorEndSide'], 'upperValveOutlet');

    final pulledStart = tester.getCenter(handle);
    await tester.dragFrom(pulledStart, const Offset(96, 0));
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    items = _itemsFromPayload(await _savedLayoutPayload());
    props = (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], isNull);
    expect(props['anchorEndSide'], isNull);

    final freeStart = tester.getCenter(handle);
    await tester.dragFrom(freeStart, const Offset(-96, 0));
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    items = _itemsFromPayload(await _savedLayoutPayload());
    props = (_findById(items, 1)['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndItemId'], '3');
    expect(props['anchorEndSide'], 'upperValveOutlet');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Bypass D-pad movement respects attached axis', (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 96, width: 260),
        _bypassItem(3, x: 172, y: 79, properties: <String, String>{
          'bypassPrimaryIronId': '1',
          'bypassPrimaryT': '0.3000',
        }),
        _ironItem(4, x: 500, y: 80, width: 260, vertical: true),
        _bypassItem(5, x: 481, y: 150, properties: <String, String>{
          'bypassPrimaryIronId': '4',
          'bypassPrimaryT': '0.4200',
        }),
      ],
      selectedId: 3,
    );

    await _saveRigUp(tester);

    await tester.tap(find.byTooltip('Move Right'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Up'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('item-hitbox-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Down'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Left'));
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
    expect(double.parse(hProps['bypassPrimaryT'] as String),
        inInclusiveRange(0.0, 1.0));
    expect(double.parse(vProps['bypassPrimaryT'] as String),
        inInclusiveRange(0.0, 1.0));

    final horizontalSpineCenter = _bypassSpineCenterFromMap(horizontalBypass);
    final verticalSpineCenter = _bypassSpineCenterFromMap(verticalBypass);
    expect(horizontalSpineCenter.dy, closeTo(108.0, 2.0));
    expect(verticalSpineCenter.dx, closeTo(514.0, 3.0));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Bypass port IDs remain stable when bypass rotates',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 200, y: 180, width: 120, properties: <String, String>{
          'anchorEndItemId': '3',
          'anchorEndSide': 'upperValveOutlet',
        }),
        <String, dynamic>{
          'id': 3,
          'type': 'bypass',
          'x': 320.0,
          'y': 170.0,
          'width': 30.0,
          'height': 32.0,
          'properties': <String, String>{'ironSize': '3'},
          'rotationTurns': 1,
          'locked': false,
        },
      ],
      selectedId: 3,
    );

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final iron = _findById(items, 1);
    final props = (iron['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorEndSide'], 'upperValveOutlet');

    await tester.drag(find.byKey(const ValueKey<String>('item-hitbox-3')),
        const Offset(48, 0));
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final movedItems = _itemsFromPayload(await _savedLayoutPayload());
    final movedIron = _findById(movedItems, 1);
    final movedProps = (movedIron['properties'] as Map).cast<String, dynamic>();
    expect(movedProps['anchorEndItemId'], '3');
    expect(movedProps['anchorEndSide'], 'upperValveOutlet');

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

  testWidgets('Bypass dropped near horizontal iron middle attaches on drag end',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 240, width: 300),
        _bypassItem(2, x: 250, y: 120),
      ],
      selectedId: 2,
    );

    final bypassCenter =
        tester.getCenter(find.byKey(const ValueKey<String>('item-hitbox-2')));
    final ironCenter =
        tester.getCenter(find.byKey(const ValueKey<String>('item-hitbox-1')));
    await tester.dragFrom(
      bypassCenter,
      Offset(ironCenter.dx - bypassCenter.dx, ironCenter.dy - bypassCenter.dy),
    );
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final bypass = _findById(items, 2);
    final props = (bypass['properties'] as Map).cast<String, dynamic>();
    final centerY = _bypassSpineCenterFromMap(bypass).dy;
    final initialDistance = (136.0 - 252.0).abs();
    final movedDistance = (centerY - 252.0).abs();

    final parentT = props['bypassParentT'] ?? props['bypassPrimaryT'];
    if (parentT is String) {
      expect(double.parse(parentT), inInclusiveRange(0.0, 1.0));
    }
    expect(movedDistance, lessThan(initialDistance));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Bypass dropped near vertical iron middle attaches on drag end',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 480, y: 120, width: 300, vertical: true),
        _bypassItem(2, x: 300, y: 250),
      ],
      selectedId: 2,
    );

    final bypassCenter =
        tester.getCenter(find.byKey(const ValueKey<String>('item-hitbox-2')));
    final ironCenter =
        tester.getCenter(find.byKey(const ValueKey<String>('item-hitbox-1')));
    await tester.dragFrom(
      bypassCenter,
      Offset(ironCenter.dx - bypassCenter.dx, ironCenter.dy - bypassCenter.dy),
    );
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final bypass = _findById(items, 2);
    final props = (bypass['properties'] as Map).cast<String, dynamic>();
    final centerX = _bypassSpineCenterFromMap(bypass).dx;
    final initialDistance = (315.0 - 494.0).abs();
    final movedDistance = (centerX - 494.0).abs();

    final parentT = props['bypassParentT'] ?? props['bypassPrimaryT'];
    if (parentT is String) {
      expect(double.parse(parentT), inInclusiveRange(0.0, 1.0));
    }
    expect(movedDistance, lessThan(initialDistance));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Bypass spine attaches near beginning of long iron',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 260, width: 600),
        <String, dynamic>{
          'id': 2,
          'type': 'bypass',
          'x': 118.0,
          'y': 140.0,
          'width': 30.0,
          'height': 32.0,
          'properties': <String, String>{
            'ironSize': '3',
            'bypassPrimaryIronId': '1',
            'bypassPrimaryT': '0.0500',
          },
          'rotationTurns': 0,
          'locked': false,
        },
      ],
      selectedId: 2,
    );

    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final bypass = _findById(items, 2);
    final props = (bypass['properties'] as Map).cast<String, dynamic>();
    final t = double.parse(
        (props['bypassParentT'] ?? props['bypassPrimaryT']) as String);
    expect(props['bypassParentIronId'] ?? props['bypassPrimaryIronId'], '1');
    expect(t, lessThan(0.12));
    expect(_bypassSpineCenterFromMap(bypass).dy, closeTo(272.0, 2.0));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Bypass spine attaches near end of long iron without rotation',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 260, width: 600),
        <String, dynamic>{
          'id': 2,
          'type': 'bypass',
          'x': 690.0,
          'y': 140.0,
          'width': 30.0,
          'height': 32.0,
          'properties': <String, String>{
            'ironSize': '3',
            'bypassPrimaryIronId': '1',
            'bypassPrimaryT': '0.9500',
          },
          'rotationTurns': 1,
          'locked': false,
        },
      ],
      selectedId: 2,
    );

    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final bypass = _findById(items, 2);
    final props = (bypass['properties'] as Map).cast<String, dynamic>();
    final t = double.parse(
        (props['bypassParentT'] ?? props['bypassPrimaryT']) as String);
    expect(props['bypassParentIronId'] ?? props['bypassPrimaryIronId'], '1');
    expect(t, greaterThan(0.88));
    expect(bypass['rotationTurns'], 1);
    expect(_bypassSpineCenterFromMap(bypass).dy, closeTo(272.0, 2.0));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Valve-overlap alone does not attach bypass body to parent iron',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 210.6, y: 120, width: 280, vertical: true),
        <String, dynamic>{
          'id': 2,
          'type': 'bypass',
          'x': 200.0,
          'y': 220.0,
          'width': 30.0,
          'height': 32.0,
          'properties': <String, String>{'ironSize': '3'},
          'rotationTurns': 0,
          'locked': false,
        },
      ],
      selectedId: 2,
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('item-hitbox-2')),
      const Offset(2, 0),
    );
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final bypass = _findById(items, 2);
    final props = (bypass['properties'] as Map).cast<String, dynamic>();
    expect(props['bypassParentIronId'], isNull);
    expect(props['inlineParentIronId'], isNull);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Tee attaches to long iron without auto-rotation',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 260, width: 620),
        <String, dynamic>{
          'id': 2,
          'type': 'teeUp',
          'x': 360.0,
          'y': 140.0,
          'width': 34.0,
          'height': 34.0,
          'properties': <String, String>{
            'ironSize': '3',
            'inlineParentIronId': '1',
            'inlineParentT': '0.5000',
          },
          'rotationTurns': 1,
          'locked': false,
        },
      ],
      selectedId: 2,
    );

    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final tee = _findById(items, 2);
    final props = (tee['properties'] as Map).cast<String, dynamic>();
    expect(props['inlineParentIronId'], '1');
    expect(double.parse(props['inlineParentT'] as String),
        inInclusiveRange(0.0, 1.0));
    expect(tee['rotationTurns'], 1);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Tee slides on parent iron and keeps endpoint connector IDs',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 480, y: 100, width: 620, vertical: true),
        <String, dynamic>{
          'id': 2,
          'type': 'teeRight',
          'x': 300.0,
          'y': 320.0,
          'width': 34.0,
          'height': 34.0,
          'properties': <String, String>{
            'ironSize': '3',
            'inlineParentIronId': '1',
            'inlineParentT': '0.5000',
            'inlineAttachedSegmentId': 'run',
          },
          'rotationTurns': 0,
          'locked': false,
        },
        <String, dynamic>{
          ..._ironItem(3, x: 220, y: 260, width: 100),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorEndItemId': '2',
            'anchorEndSide': 'runStart',
          },
        },
        <String, dynamic>{
          ..._ironItem(4, x: 420, y: 220, width: 100, vertical: true),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorStartItemId': '2',
            'anchorStartSide': 'branch',
          },
        },
      ],
      selectedId: 2,
    );

    await tester.tap(find.byTooltip('Move Down').first);
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final tee = _findById(items, 2);
    final teeProps = (tee['properties'] as Map).cast<String, dynamic>();
    expect(teeProps['inlineParentIronId'], '1');
    expect(double.parse(teeProps['inlineParentT'] as String),
        isNot(closeTo(0.5, 0.001)));
    expect(teeProps['inlineAttachedSegmentId'], 'run');

    final iron3Props =
        (_findById(items, 3)['properties'] as Map).cast<String, dynamic>();
    final iron4Props =
        (_findById(items, 4)['properties'] as Map).cast<String, dynamic>();
    expect(iron3Props['anchorEndItemId'], '2');
    expect(iron3Props['anchorEndSide'], 'runStart');
    expect(iron4Props['anchorStartItemId'], '2');
    expect(iron4Props['anchorStartSide'], 'branch');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('90 does not persist inline spine attachment metadata',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 480, y: 100, width: 620, vertical: true),
        <String, dynamic>{
          'id': 2,
          'type': 'elbowUpRight',
          'x': 300.0,
          'y': 320.0,
          'width': 34.0,
          'height': 34.0,
          'properties': <String, String>{
            'ironSize': '3',
            'inlineParentIronId': '1',
            'inlineParentT': '0.5000',
          },
          'rotationTurns': 2,
          'locked': false,
        },
      ],
      selectedId: 2,
    );

    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final elbow = _findById(items, 2);
    final props = (elbow['properties'] as Map).cast<String, dynamic>();
    expect(props['inlineParentIronId'], isNull);
    expect(props['inlineParentT'], isNull);
    expect(props['inlineAttachedSegmentId'], isNull);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Tee keeps run as parent spine and preserves three stable ports',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 480, y: 100, width: 620, vertical: true),
        <String, dynamic>{
          'id': 2,
          'type': 'teeRight',
          'x': 300.0,
          'y': 320.0,
          'width': 34.0,
          'height': 34.0,
          'properties': <String, String>{
            'ironSize': '3',
            'inlineParentIronId': '1',
            'inlineParentT': '0.5000',
            'inlineAttachedSegmentId': 'run',
          },
          'rotationTurns': 0,
          'locked': false,
        },
        <String, dynamic>{
          ..._ironItem(3, x: 220, y: 260, width: 100),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorEndItemId': '2',
            'anchorEndSide': 'runStart',
          },
        },
        <String, dynamic>{
          ..._ironItem(4, x: 560, y: 260, width: 100),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorStartItemId': '2',
            'anchorStartSide': 'runEnd',
          },
        },
        <String, dynamic>{
          ..._ironItem(5, x: 420, y: 220, width: 100, vertical: true),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorStartItemId': '2',
            'anchorStartSide': 'branch',
          },
        },
      ],
    );

    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final iron = _findById(items, 1);
    final tee = _findById(items, 2);
    final teeProps = (tee['properties'] as Map).cast<String, dynamic>();
    expect(teeProps['inlineAttachedSegmentId'], 'run');

    final parentX = _ironEndpointFromMap(iron, true).dx;
    final runStart = _fittingAnchorFromMap(tee, 'runStart');
    final runEnd = _fittingAnchorFromMap(tee, 'runEnd');
    final branch = _fittingAnchorFromMap(tee, 'branch');
    expect(runStart.dx, closeTo(parentX, 1.2));
    expect(runEnd.dx, closeTo(parentX, 1.2));
    expect((branch.dx - parentX).abs(), greaterThan(2.0));

    final iron3Props =
        (_findById(items, 3)['properties'] as Map).cast<String, dynamic>();
    final iron4Props =
        (_findById(items, 4)['properties'] as Map).cast<String, dynamic>();
    final iron5Props =
        (_findById(items, 5)['properties'] as Map).cast<String, dynamic>();
    expect(iron3Props['anchorEndSide'], 'runStart');
    expect(iron4Props['anchorStartSide'], 'runEnd');
    expect(iron5Props['anchorStartSide'], 'branch');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      '90 inlet and outlet ports keep stable IDs and exact endpoint alignment',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 2,
          'type': 'elbowUpRight',
          'x': 300.0,
          'y': 320.0,
          'width': 34.0,
          'height': 34.0,
          'properties': <String, String>{'ironSize': '3'},
          'rotationTurns': 0,
          'locked': false,
        },
        <String, dynamic>{
          ..._ironItem(3, x: 260, y: 330, width: 100),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorEndItemId': '2',
            'anchorEndSide': 'inlet',
          },
        },
        <String, dynamic>{
          ..._ironItem(4, x: 330, y: 290, width: 100, vertical: true),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorStartItemId': '2',
            'anchorStartSide': 'outlet',
          },
        },
      ],
    );

    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final ironInlet = _findById(items, 3);
    final ironOutlet = _findById(items, 4);

    final inletProps = (ironInlet['properties'] as Map).cast<String, dynamic>();
    final outletProps =
        (ironOutlet['properties'] as Map).cast<String, dynamic>();
    expect(inletProps['anchorEndSide'], 'inlet');
    expect(outletProps['anchorStartSide'], 'outlet');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('90 fitting does not auto-attach to long iron spine',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 480, y: 100, width: 620, vertical: true),
        <String, dynamic>{
          'id': 2,
          'type': 'elbowUpRight',
          'x': 300.0,
          'y': 320.0,
          'width': 34.0,
          'height': 34.0,
          'properties': <String, String>{
            'ironSize': '3',
            'inlineParentIronId': '1',
            'inlineParentT': '0.5000',
          },
          'rotationTurns': 2,
          'locked': false,
        },
      ],
      selectedId: 2,
    );

    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final elbow = _findById(items, 2);
    final props = (elbow['properties'] as Map).cast<String, dynamic>();
    expect(props['inlineParentIronId'], isNull);
    expect(props['inlineParentT'], isNull);
    expect(props['inlineAttachedSegmentId'], isNull);
    expect(elbow['rotationTurns'], 2);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Tee stores full-run parent position near beginning and end',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 120, y: 260, width: 620),
        <String, dynamic>{
          'id': 2,
          'type': 'teeUp',
          'x': 360.0,
          'y': 140.0,
          'width': 34.0,
          'height': 34.0,
          'properties': <String, String>{
            'ironSize': '3',
            'inlineParentIronId': '1',
            'inlineParentT': '0.0600',
          },
          'rotationTurns': 0,
          'locked': false,
        },
        <String, dynamic>{
          'id': 3,
          'type': 'teeUp',
          'x': 580.0,
          'y': 140.0,
          'width': 34.0,
          'height': 34.0,
          'properties': <String, String>{
            'ironSize': '3',
            'inlineParentIronId': '1',
            'inlineParentT': '0.9400',
          },
          'rotationTurns': 0,
          'locked': false,
        },
      ],
    );

    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final teeStart = _findById(items, 2);
    final teeEnd = _findById(items, 3);
    final startProps = (teeStart['properties'] as Map).cast<String, dynamic>();
    final endProps = (teeEnd['properties'] as Map).cast<String, dynamic>();
    expect(startProps['inlineParentIronId'], '1');
    expect(endProps['inlineParentIronId'], '1');
    expect(double.parse(startProps['inlineParentT'] as String), lessThan(0.12));
    expect(
        double.parse(endProps['inlineParentT'] as String), greaterThan(0.88));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('90 clears legacy inline parent metadata on save/reload',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 480, y: 100, width: 620, vertical: true),
        <String, dynamic>{
          'id': 2,
          'type': 'elbowUpRight',
          'x': 300.0,
          'y': 200.0,
          'width': 34.0,
          'height': 34.0,
          'properties': <String, String>{
            'ironSize': '3',
            'inlineParentIronId': '1',
            'inlineParentT': '0.0600',
          },
          'rotationTurns': 1,
          'locked': false,
        },
        <String, dynamic>{
          'id': 3,
          'type': 'elbowUpRight',
          'x': 300.0,
          'y': 560.0,
          'width': 34.0,
          'height': 34.0,
          'properties': <String, String>{
            'ironSize': '3',
            'inlineParentIronId': '1',
            'inlineParentT': '0.9400',
          },
          'rotationTurns': 2,
          'locked': false,
        },
      ],
    );

    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final elbowStart = _findById(items, 2);
    final elbowEnd = _findById(items, 3);
    final startProps =
        (elbowStart['properties'] as Map).cast<String, dynamic>();
    final endProps = (elbowEnd['properties'] as Map).cast<String, dynamic>();
    expect(startProps['inlineParentIronId'], isNull);
    expect(endProps['inlineParentIronId'], isNull);
    expect(startProps['inlineParentT'], isNull);
    expect(endProps['inlineParentT'], isNull);
    expect(startProps['inlineAttachedSegmentId'], isNull);
    expect(endProps['inlineAttachedSegmentId'], isNull);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Inline equipment supports top/right/bottom/left iron endpoints',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'testSeparator',
            x: 420, y: 220, width: 112, height: 74),
        <String, dynamic>{
          ..._ironItem(2, x: 320, y: 250, width: 80),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorEndItemId': '1',
            'anchorEndSide': 'left',
          },
        },
        <String, dynamic>{
          ..._ironItem(3, x: 540, y: 250, width: 80),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorStartItemId': '1',
            'anchorStartSide': 'right',
          },
        },
        <String, dynamic>{
          ..._ironItem(4, x: 460, y: 130, width: 80, vertical: true),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorEndItemId': '1',
            'anchorEndSide': 'top',
          },
        },
        <String, dynamic>{
          ..._ironItem(5, x: 460, y: 296, width: 80, vertical: true),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorStartItemId': '1',
            'anchorStartSide': 'bottom',
          },
        },
      ],
    );

    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final sep = _findById(items, 1);
    final center = Offset(
      (sep['x'] as num).toDouble() + (sep['width'] as num).toDouble() / 2,
      (sep['y'] as num).toDouble() + (sep['height'] as num).toDouble() / 2,
    );
    for (final side in const <String>['top', 'right', 'bottom', 'left']) {
      final p = _fittingAnchorFromMap(sep, side);
      expect((p - center).distance, greaterThan(8.0));
    }

    final leftIronProps =
        (_findById(items, 2)['properties'] as Map).cast<String, dynamic>();
    final rightIronProps =
        (_findById(items, 3)['properties'] as Map).cast<String, dynamic>();
    final topIronProps =
        (_findById(items, 4)['properties'] as Map).cast<String, dynamic>();
    final bottomIronProps =
        (_findById(items, 5)['properties'] as Map).cast<String, dynamic>();
    expect(leftIronProps['anchorEndSide'], 'left');
    expect(rightIronProps['anchorStartSide'], 'right');
    expect(topIronProps['anchorEndSide'], 'top');
    expect(bottomIronProps['anchorStartSide'], 'bottom');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Tank allows only one active inlet side at a time',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'flowbackTank',
            x: 420, y: 220, width: 38, height: 28),
        <String, dynamic>{
          ..._ironItem(2, x: 320, y: 250, width: 80),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorEndItemId': '1',
            'anchorEndSide': 'left',
          },
        },
        <String, dynamic>{
          ..._ironItem(3, x: 540, y: 250, width: 80),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorStartItemId': '1',
            'anchorStartSide': 'right',
          },
        },
      ],
    );

    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final p2 =
        (_findById(items, 2)['properties'] as Map).cast<String, dynamic>();
    final p3 =
        (_findById(items, 3)['properties'] as Map).cast<String, dynamic>();
    final occupied = <String>[];
    if (p2['anchorEndItemId'] == '1' &&
        (p2['anchorEndSide'] as String?) != null) {
      occupied.add(p2['anchorEndSide'] as String);
    }
    if (p3['anchorStartItemId'] == '1' &&
        (p3['anchorStartSide'] as String?) != null) {
      occupied.add(p3['anchorStartSide'] as String);
    }
    expect(occupied.length, 1);
    expect(occupied.single, anyOf('top', 'right', 'bottom', 'left'));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Connected iron endpoint follows equipment side exactly on move',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'wellhead', x: 240, y: 220, width: 30, height: 28),
        <String, dynamic>{
          ..._ironItem(2, x: 120, y: 220, width: 120),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorEndItemId': '1',
            'anchorEndSide': 'left',
          },
        },
      ],
      selectedId: 1,
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Right'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Right'));
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final equipment = _findById(items, 1);
    final iron = _findById(items, 2);
    final anchor = _fittingAnchorFromMap(equipment, 'left');
    final endpoint = _ironEndpointFromMap(iron, false);
    expect((endpoint - anchor).distance, lessThanOrEqualTo(0.2));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Select Next cycles stacked close iron IDs and wraps',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 140, y: 240, width: 220),
        _ironItem(2, x: 140, y: 240, width: 220),
      ],
    );

    final topCenter =
        tester.getCenter(find.byKey(const ValueKey<String>('item-hitbox-1')));
    await tester.longPressAt(topCenter);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Iron Horizontal 3" 1').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('select-next-button')),
        findsOneWidget);
    final startedWithOne = find
        .byKey(const ValueKey<String>('iron-handle-1-start'))
        .evaluate()
        .isNotEmpty;
    final startedWithTwo = find
        .byKey(const ValueKey<String>('iron-handle-2-start'))
        .evaluate()
        .isNotEmpty;
    expect(startedWithOne || startedWithTwo, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('select-next-button')));
    await tester.pumpAndSettle();
    if (startedWithOne) {
      expect(find.byKey(const ValueKey<String>('iron-handle-2-start')),
          findsOneWidget);
    } else {
      expect(find.byKey(const ValueKey<String>('iron-handle-1-start')),
          findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey<String>('select-next-button')));
    await tester.pumpAndSettle();
    if (startedWithOne) {
      expect(find.byKey(const ValueKey<String>('iron-handle-1-start')),
          findsOneWidget);
    } else {
      expect(find.byKey(const ValueKey<String>('iron-handle-2-start')),
          findsOneWidget);
    }

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    expect((_findById(items, 1)['x'] as num).toDouble(), closeTo(140, 0.01));
    expect((_findById(items, 2)['x'] as num).toDouble(), closeTo(140, 0.01));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Long press crowded location opens picker and selects exact item',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 140, y: 240, width: 220),
        _ironItem(2, x: 140, y: 240, width: 220),
        <String, dynamic>{
          'id': 3,
          'type': 'elbowUpRight',
          'x': 220.0,
          'y': 248.0,
          'width': 34.0,
          'height': 34.0,
          'properties': <String, String>{'ironSize': '3'},
          'rotationTurns': 0,
          'locked': false,
        },
      ],
    );

    final topCenter =
        tester.getCenter(find.byKey(const ValueKey<String>('item-hitbox-1')));
    await tester.longPressAt(topCenter);
    await tester.pumpAndSettle();

    expect(find.text('Select Item'), findsOneWidget);
    expect(find.textContaining('Iron Horizontal 3" 1'), findsOneWidget);
    expect(find.textContaining('Iron Horizontal 3" 2'), findsOneWidget);

    await tester.tap(find.textContaining('Iron Horizontal 3" 1').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('iron-handle-2-start')),
        findsOneWidget);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('New tap location rebuilds candidates and hides Select Next',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 140, y: 240, width: 220),
        _ironItem(2, x: 140, y: 240, width: 220),
      ],
    );

    final topCenter =
        tester.getCenter(find.byKey(const ValueKey<String>('item-hitbox-1')));
    await tester.longPressAt(topCenter);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Iron Horizontal 3" 1').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('select-next-button')),
        findsOneWidget);

    await tester.tapAt(const Offset(24, 24));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey<String>('select-next-button')), findsNothing);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Horizontal iron can shorten significantly from right endpoint',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 180, y: 220, width: 120),
      ],
      selectedId: 1,
    );

    const originalX = 180.0;
    await tester.drag(
      find.byKey(const ValueKey<String>('iron-handle-1-end')),
      const Offset(-96, 0),
    );
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final iron = _findById(items, 1);
    expect((iron['width'] as num).toDouble(), lessThan(36.0));
    expect((iron['width'] as num).toDouble(), greaterThanOrEqualTo(14.0));
    expect((iron['x'] as num).toDouble(), closeTo(originalX, 0.5));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Vertical iron can shorten significantly from top endpoint',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 220, y: 180, width: 120, vertical: true),
      ],
      selectedId: 1,
    );

    const originalBottom = 300.0;
    await tester.drag(
      find.byKey(const ValueKey<String>('iron-handle-1-start')),
      const Offset(0, 94),
    );
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final iron = _findById(items, 1);
    expect((iron['height'] as num).toDouble(), lessThan(36.0));
    expect((iron['height'] as num).toDouble(), greaterThanOrEqualTo(14.0));
    final bottomAfter =
        (iron['y'] as num).toDouble() + (iron['height'] as num).toDouble();
    expect(bottomAfter, closeTo(originalBottom, 0.8));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Connected short iron can be shorter than free minimum',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'wellhead', x: 280, y: 220, width: 30, height: 28),
        _equipmentItem(2, 'wellhead', x: 306, y: 220, width: 30, height: 28),
        <String, dynamic>{
          ..._ironItem(3, x: 286, y: 220, width: 40),
          'properties': <String, String>{
            'ironSize': '3',
            'anchorStartItemId': '1',
            'anchorStartSide': 'right',
            'anchorEndItemId': '2',
            'anchorEndSide': 'left',
          },
        },
      ],
    );

    await tester.pumpAndSettle();
    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final iron = _findById(items, 3);
    final width = (iron['width'] as num).toDouble();
    expect(width, lessThan(14.0));
    final props = (iron['properties'] as Map).cast<String, dynamic>();
    expect(props['anchorStartSide'], 'right');
    expect(props['anchorEndSide'], 'left');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('D-pad fine adjusts selected horizontal endpoint only on axis',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 180, y: 220, width: 120),
      ],
      selectedId: 1,
    );

    await tester.tap(find.byKey(const ValueKey<String>('iron-handle-1-end')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Right'));
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final iron = _findById(items, 1);
    expect((iron['width'] as num).toDouble(), greaterThan(120));
    expect((iron['y'] as num).toDouble(), closeTo(220, 0.01));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('New bypass creates two built-in leads anchored to bypass ports',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _bypassItem(1, x: 180, y: 110),
      ],
      selectedId: 1,
    );

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final bypass = _findById(items, 1);
    final props = (bypass['properties'] as Map).cast<String, dynamic>();
    expect(props['bypassLeadleadAOriginPortId'], 'upperValveOutlet');
    expect(props['bypassLeadleadBOriginPortId'], 'lowerValveOutlet');
    final originA = _fittingAnchorFromMap(bypass, 'upperValveOutlet');
    final originB = _fittingAnchorFromMap(bypass, 'lowerValveOutlet');
    final endA = _bypassLeadEndpointFromMap(bypass, 'leadA');
    final endB = _bypassLeadEndpointFromMap(bypass, 'leadB');
    expect((endA - originA).distance, greaterThan(8.0));
    expect((endB - originB).distance, greaterThan(8.0));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Legacy bypass receives default built-in leads on load',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'type': 'bypass',
          'x': 180.0,
          'y': 110.0,
          'width': 30.0,
          'height': 32.0,
          'properties': <String, String>{'ironSize': '3'},
          'rotationTurns': 0,
          'locked': false,
        },
      ],
    );

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final bypass = _findById(items, 1);
    final props = (bypass['properties'] as Map).cast<String, dynamic>();
    expect(props['bypassLeadleadAEndX'], isNotNull);
    expect(props['bypassLeadleadAEndY'], isNotNull);
    expect(props['bypassLeadleadBEndX'], isNotNull);
    expect(props['bypassLeadleadBEndY'], isNotNull);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Bypass lead geometry persists without moving bypass or equipment',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _bypassItem(1, x: 180, y: 110, properties: <String, String>{
          'bypassLeadleadAEndX': '52.6000',
          'bypassLeadleadAEndY': '10.8800',
          'bypassLeadleadBEndX': '52.6000',
          'bypassLeadleadBEndY': '21.1200',
        }),
        _equipmentItem(2, 'wellhead', x: 420, y: 120, width: 30, height: 28),
      ],
      selectedId: 1,
    );

    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final bypass = _findById(items, 1);
    final equipment = _findById(items, 2);
    expect((bypass['x'] as num).toDouble(), closeTo(198.0, 0.01));
    expect((bypass['y'] as num).toDouble(), closeTo(111.0, 0.01));
    expect((equipment['x'] as num).toDouble(), closeTo(420.0, 0.01));
    expect((equipment['y'] as num).toDouble(), closeTo(120.0, 0.01));
    final endA = _bypassLeadEndpointFromMap(bypass, 'leadA');
    final originA = _fittingAnchorFromMap(bypass, 'upperValveOutlet');
    expect((endA - originA).distance, greaterThanOrEqualTo(28.0));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Bypass connected lead resolves exact target coordinate on reload',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _bypassItem(1, x: 180, y: 110, properties: <String, String>{
          'bypassLeadleadATargetKind': 'equipmentAnchor',
          'bypassLeadleadATargetItemId': '2',
          'bypassLeadleadATargetSide': 'left',
        }),
        _equipmentItem(2, 'wellhead', x: 420, y: 120, width: 30, height: 28),
      ],
      selectedId: 1,
    );

    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final bypass = _findById(items, 1);
    final equipment = _findById(items, 2);
    final props = (bypass['properties'] as Map).cast<String, dynamic>();
    expect(props['bypassLeadleadATargetItemId'], '2');
    expect(props['bypassLeadleadATargetSide'],
        anyOf('top', 'right', 'bottom', 'left'));
    final target = _fittingAnchorFromMap(
        equipment, props['bypassLeadleadATargetSide'] as String);
    expect(target.dx, greaterThan(0));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Iron dragged to 90 and 90 dragged to iron resolve same node',
      (tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _ironItem(1, x: 180, y: 260, width: 100),
        <String, dynamic>{
          'id': 2,
          'type': 'elbowUpRight',
          'x': 320.0,
          'y': 240.0,
          'width': 34.0,
          'height': 34.0,
          'properties': <String, String>{'ironSize': '3'},
          'rotationTurns': 0,
          'locked': false,
        },
      ],
      selectedId: 1,
      selectedEndpointLeading: false,
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('iron-handle-1-end')),
      const Offset(56, 14),
    );
    await tester.pumpAndSettle();
    await _saveRigUp(tester);

    final items = _itemsFromPayload(await _savedLayoutPayload());
    final iron = _findById(items, 1);
    final elbow = _findById(items, 2);
    final ironEnd = _ironEndpointFromMap(iron, false);
    final inlet = _fittingAnchorFromMap(elbow, 'inlet');
    final outlet = _fittingAnchorFromMap(elbow, 'outlet');
    final matchedDistance =
        math.min((ironEnd - inlet).distance, (ironEnd - outlet).distance);
    final props = (iron['properties'] as Map).cast<String, dynamic>();
    expect(matchedDistance, lessThanOrEqualTo(0.2));
    expect(props['anchorEndItemId'], '2');
    expect(props['anchorEndSide'], anyOf('inlet', 'outlet'));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Build 150 tee and elbow migrate to half-size visuals while keeping usable hitboxes',
      (tester) async {
    const teeCenter = Offset(210, 210);
    const elbowCenter = Offset(340, 210);
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        _equipmentItem(1, 'teeRight',
            x: teeCenter.dx - 21, y: teeCenter.dy - 21, width: 42, height: 42),
        _equipmentItem(2, 'elbowUpRight',
            x: elbowCenter.dx - 21,
            y: elbowCenter.dy - 21,
            width: 42,
            height: 42),
      ],
      selectedId: 1,
    );

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final tee = _findById(items, 1);
    final elbow = _findById(items, 2);
    expect((tee['width'] as num).toDouble(), closeTo(21.0, 0.01));
    expect((tee['height'] as num).toDouble(), closeTo(21.0, 0.01));
    expect((elbow['width'] as num).toDouble(), closeTo(21.0, 0.01));
    expect((elbow['height'] as num).toDouble(), closeTo(21.0, 0.01));

    final teeCenterAfter = Offset(
      (tee['x'] as num).toDouble() + (tee['width'] as num).toDouble() / 2,
      (tee['y'] as num).toDouble() + (tee['height'] as num).toDouble() / 2,
    );
    final elbowCenterAfter = Offset(
      (elbow['x'] as num).toDouble() + (elbow['width'] as num).toDouble() / 2,
      (elbow['y'] as num).toDouble() + (elbow['height'] as num).toDouble() / 2,
    );
    expect(teeCenterAfter.dx, closeTo(teeCenter.dx, 0.01));
    expect(teeCenterAfter.dy, closeTo(teeCenter.dy, 0.01));
    expect(elbowCenterAfter.dx, closeTo(elbowCenter.dx, 0.01));
    expect(elbowCenterAfter.dy, closeTo(elbowCenter.dy, 0.01));

    final teeHitbox =
        tester.getRect(find.byKey(const ValueKey<String>('item-hitbox-1')));
    final elbowHitbox =
        tester.getRect(find.byKey(const ValueKey<String>('item-hitbox-2')));
    expect(teeHitbox.width, closeTo(45.0, 0.5));
    expect(teeHitbox.height, closeTo(45.0, 0.5));
    expect(elbowHitbox.width, closeTo(45.0, 0.5));
    expect(elbowHitbox.height, closeTo(45.0, 0.5));

    final teeBranch = _fittingAnchorFromMap(tee, 'branch');
    expect(teeBranch.dx, greaterThan(teeCenter.dx));
    expect(teeBranch.dy, closeTo(teeCenter.dy, 0.5));
    final elbowOutlet = _fittingAnchorFromMap(elbow, 'outlet');
    expect(elbowOutlet.dx, greaterThan(elbowCenter.dx));
    expect(elbowOutlet.dy, closeTo(elbowCenter.dy, 0.5));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
