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
  List<Map<String, dynamic>> items,
  String type,
) {
  return items.firstWhere((item) => item['type'] == type);
}

void main() {
  test('Build number is 111', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('version: 1.0.1+111'));
  });

  testWidgets('Compact defaults are applied while Facilities stays unchanged',
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
    expect(find.text('Wellhead'), findsWidgets);

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

    // Build 111 restores icon container dimensions smaller than Build 110.
    expect((wellhead['width'] as num).toDouble(), lessThan(74));
    expect((wellhead['height'] as num).toDouble(), lessThan(58));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Compact symbol uses minimal shell padding for normal equipment',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.binding.setSurfaceSize(const Size(1280, 1500));
    await tester.pumpWidget(const MaterialApp(home: EquipmentLayoutScreen()));
    await tester.pumpAndSettle();

    await _ensureEquipmentLibraryOpen(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Wellhead').first);
    await tester.pumpAndSettle();

    final shell =
        tester.getSize(find.byKey(const ValueKey<String>('equipment-shell-1')));
    final symbol = tester
        .getSize(find.byKey(const ValueKey<String>('equipment-symbol-1')));

    final horizontalPadding = (shell.width - symbol.width) / 2;
    final verticalPadding = (shell.height - symbol.height) / 2;

    expect(symbol.width, lessThan(26));
    expect(symbol.height, lessThan(26));
    expect(horizontalPadding, inInclusiveRange(2, 5));
    expect(verticalPadding, inInclusiveRange(2, 5));
    expect(symbol.width, lessThan(shell.width - 2));
    expect(symbol.height, lessThan(shell.height - 2));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Duplicate, rotate, lock/unlock, and drag continue working',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.binding.setSurfaceSize(const Size(1280, 1500));
    await tester.pumpWidget(const MaterialApp(home: EquipmentLayoutScreen()));
    await tester.pumpAndSettle();

    await _ensureEquipmentLibraryOpen(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Wellhead').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('equipment-shell-1')));
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    final firstItems = _itemsFromPayload(await _savedLayoutPayload());
    final initialWellhead = _findByType(firstItems, 'wellhead');
    final initialX = (initialWellhead['x'] as num).toDouble();
    final initialY = (initialWellhead['y'] as num).toDouble();

    await tester.tap(find.byTooltip('Rotate 90°').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Lock').first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock), findsWidgets);
    await tester.tap(find.byTooltip('Unlock').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Duplicate').first);
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey<String>('equipment-shell-1')),
      const Offset(120, 40),
    );
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    final secondItems = _itemsFromPayload(await _savedLayoutPayload());
    final wellheads =
        secondItems.where((item) => item['type'] == 'wellhead').toList();

    expect(wellheads.length, 2);
    expect(wellheads.any((item) => (item['rotationTurns'] as int? ?? 0) > 0),
        isTrue);
    expect(wellheads.every((item) => item['locked'] == false), isTrue);

    final movedWellhead = wellheads.first;
    final movedX = (movedWellhead['x'] as num).toDouble();
    final movedY = (movedWellhead['y'] as num).toDouble();
    expect(movedX != initialX || movedY != initialY, isTrue);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Legacy saved layouts migrate compactly and preserve connections',
      (tester) async {
    final legacyPayload = <String, dynamic>{
      'name': 'Legacy Rig-Up',
      'nextId': 5,
      'snapToGrid': true,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'type': 'ironHorizontal',
          'x': 100.0,
          'y': 100.0,
          'width': 150.0,
          'height': 24.0,
          'properties': <String, String>{'ironSize': '3'},
          'rotationTurns': 0,
          'locked': false,
        },
        <String, dynamic>{
          'id': 2,
          'type': 'bypass',
          'x': 120.0,
          'y': 40.0,
          'width': 66.0,
          'height': 34.0,
          'properties': <String, String>{
            'ironSize': '3',
            'snapIronId': '1',
            'snapAxis': 'horizontal',
          },
          'rotationTurns': 0,
          'locked': false,
        },
        <String, dynamic>{
          'id': 3,
          'type': 'wellhead',
          'x': 300.0,
          'y': 300.0,
          'width': 98.0,
          'height': 64.0,
          'properties': <String, String>{},
          'rotationTurns': 0,
          'locked': false,
        },
        <String, dynamic>{
          'id': 4,
          'type': 'facilities',
          'x': 500.0,
          'y': 260.0,
          'width': 220.0,
          'height': 112.0,
          'properties': <String, String>{},
          'rotationTurns': 0,
          'locked': false,
        },
      ],
      'metadata': <String, dynamic>{'version': 1},
    };

    SharedPreferences.setMockInitialValues(
      <String, Object>{
        'wellwerks_layout_designer_v2': jsonEncode(legacyPayload),
      },
    );

    await tester.binding.setSurfaceSize(const Size(1280, 1500));
    await tester.pumpWidget(const MaterialApp(home: EquipmentLayoutScreen()));
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());

    final iron = _findByType(items, 'ironHorizontal');
    final bypass = _findByType(items, 'bypass');
    final wellhead = _findByType(items, 'wellhead');
    final facilities = _findByType(items, 'facilities');

    expect((wellhead['width'] as num).toDouble(), closeTo(30, 0.01));
    expect((wellhead['height'] as num).toDouble(), closeTo(28, 0.01));

    const oldCenterX = 300 + 98 / 2;
    const oldCenterY = 300 + 64 / 2;
    final newCenterX = (wellhead['x'] as num).toDouble() +
        (wellhead['width'] as num).toDouble() / 2;
    final newCenterY = (wellhead['y'] as num).toDouble() +
        (wellhead['height'] as num).toDouble() / 2;
    expect(newCenterX, closeTo(oldCenterX, 0.1));
    expect(newCenterY, closeTo(oldCenterY, 0.1));

    expect((facilities['width'] as num).toDouble(), closeTo(220, 0.01));
    expect((facilities['height'] as num).toDouble(), closeTo(112, 0.01));

    final bypassProps = (bypass['properties'] as Map).cast<String, dynamic>();
    expect(bypassProps['snapIronId'], '1');

    final ironCenterY =
        (iron['y'] as num).toDouble() + (iron['height'] as num).toDouble() / 2;
    final bypassCenterY = (bypass['y'] as num).toDouble() +
        (bypass['height'] as num).toDouble() / 2;
    expect(bypassCenterY, closeTo(ironCenterY, 0.1));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Build 110 saved dimensions migrate to Build 111 compact sizes',
      (tester) async {
    final build110Payload = <String, dynamic>{
      'name': 'Build 110 Layout',
      'nextId': 3,
      'snapToGrid': true,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'type': 'wellhead',
          'x': 200.0,
          'y': 180.0,
          'width': 74.0,
          'height': 58.0,
          'properties': <String, String>{},
          'rotationTurns': 0,
          'locked': false,
        },
        <String, dynamic>{
          'id': 2,
          'type': 'facilities',
          'x': 420.0,
          'y': 260.0,
          'width': 220.0,
          'height': 112.0,
          'properties': <String, String>{},
          'rotationTurns': 0,
          'locked': false,
        },
      ],
      'metadata': <String, dynamic>{'version': 1},
    };

    SharedPreferences.setMockInitialValues(
      <String, Object>{
        'wellwerks_layout_designer_v2': jsonEncode(build110Payload),
      },
    );

    await tester.binding.setSurfaceSize(const Size(1280, 1500));
    await tester.pumpWidget(const MaterialApp(home: EquipmentLayoutScreen()));
    await tester.pumpAndSettle();

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final wellhead = _findByType(items, 'wellhead');
    final facilities = _findByType(items, 'facilities');

    expect((wellhead['width'] as num).toDouble(), closeTo(30, 0.01));
    expect((wellhead['height'] as num).toDouble(), closeTo(28, 0.01));
    expect((facilities['width'] as num).toDouble(), closeTo(220, 0.01));
    expect((facilities['height'] as num).toDouble(), closeTo(112, 0.01));

    const build110CenterX = 200 + 74 / 2;
    const build110CenterY = 180 + 58 / 2;
    final migratedCenterX = (wellhead['x'] as num).toDouble() +
        (wellhead['width'] as num).toDouble() / 2;
    final migratedCenterY = (wellhead['y'] as num).toDouble() +
        (wellhead['height'] as num).toDouble() / 2;
    expect(migratedCenterX, closeTo(build110CenterX, 0.1));
    expect(migratedCenterY, closeTo(build110CenterY, 0.1));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
