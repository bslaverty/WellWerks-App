import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/screens/equipment_layout_screen.dart';

Future<void> _ensureEquipmentLibraryOpen(WidgetTester tester) async {
  if (find.text('Add Equipment').evaluate().isNotEmpty) {
    await tester.tap(find.text('Add Equipment').first);
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

Future<void> _pumpLayout(
  WidgetTester tester, {
  List<Map<String, dynamic>> items = const <Map<String, dynamic>>[],
  int? selectedId,
}) async {
  final payload = <String, dynamic>{
    'name': 'Build 174 Test Layout',
    'nextId': 1,
    'items': items,
    if (selectedId != null) 'selectedId': selectedId,
    'metadata': <String, dynamic>{'version': 1},
  };
  SharedPreferences.setMockInitialValues(
    <String, Object>{'wellwerks_layout_designer_v2': jsonEncode(payload)},
  );
  await tester.binding.setSurfaceSize(const Size(1280, 1500));
  await tester.pumpWidget(const MaterialApp(home: EquipmentLayoutScreen()));
  await tester.pumpAndSettle();
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

void main() {
  testWidgets('Build 174 completions library shows all 11 items',
      (WidgetTester tester) async {
    await _pumpLayout(tester);
    await _ensureEquipmentLibraryOpen(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('library-tab-completions')),
    );
    await tester
        .tap(find.byKey(const ValueKey<String>('library-tab-completions')));
    await tester.pumpAndSettle();

    for (final label in const <String>[
      'Coil Tubing Unit',
      'Mixing Plant',
      'Pump',
      'Crane',
      'Light Plant',
      'Wireline',
      'Date Van',
      'Fuel Trailer',
      'Chemical Trailer',
      'Nitrogen',
      'Generator',
    ]) {
      expect(find.widgetWithText(FilledButton, label), findsOneWidget);
    }
  });

  testWidgets('Build 174 completions rotation degrees persist in layout save',
      (WidgetTester tester) async {
    await _pumpLayout(
      tester,
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'type': 'coilTubingUnit',
          'x': 180.0,
          'y': 110.0,
          'width': 98.0,
          'height': 54.0,
          'properties': <String, String>{},
          'rotationTurns': 0,
          'rotationDegrees': 37.5,
          'locked': false,
        },
      ],
      selectedId: 1,
    );

    await _saveRigUp(tester);
    final items = _itemsFromPayload(await _savedLayoutPayload());
    final coilTubing = items.firstWhere(
      (item) => item['type'] == 'coilTubingUnit',
    );

    expect(
        (coilTubing['rotationDegrees'] as num).toDouble(), closeTo(37.5, 0.01));
    expect((coilTubing['rotationTurns'] as num).toInt(), 0);
  });
}
