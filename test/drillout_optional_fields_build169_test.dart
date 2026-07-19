import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/screens/drillout_shift_change_screen.dart';
import 'package:wellwerks/services/active_company_service.dart';
import 'package:wellwerks/services/job_storage_service.dart';

Future<void> _seedActiveJob() async {
  final jobStorage = JobStorageService();
  await jobStorage.saveActiveJob(
    JobSetup(
      company: 'Mach Energy',
      padName: 'Horse Pad',
      wells: const ['Horse 16-2H'],
      leaseNames: const ['Horse 16-2H'],
      wellEntries: const [JobSetupWell(id: 'well_a', name: 'Horse 16-2H')],
      shift: 'Day',
    ),
  );
}

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: DrilloutShiftChangeScreen()),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(
  WidgetTester tester,
  Finder finder, {
  double scrollDelta = 240,
}) async {
  await tester.scrollUntilVisible(
    finder,
    scrollDelta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<String> _openPreviewAndRead(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('drillout-action-preview')),
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('drillout-action-preview')));
  await tester.pumpAndSettle();

  final previewFinder = find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        (widget.data?.contains('Shift Change') ?? false) &&
        (widget.data?.contains('Rate:') ?? false),
  );
  expect(previewFinder, findsOneWidget);
  final preview = tester.widget<Text>(previewFinder).data ?? '';

  await tester.tap(find.widgetWithText(TextButton, 'Close'));
  await tester.pumpAndSettle();
  return preview;
}

Future<String> _scopedSetupKey() async {
  final activeJob = await JobStorageService().loadActiveJob();
  final jobId = (activeJob?.id ?? '').trim();
  if (jobId.isEmpty) return 'wellwerks_drillout_shift_change_v1';
  return 'wellwerks_drillout_shift_change_v1:$jobId';
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ActiveCompanyService.instance.resetForTest();
    await _seedActiveJob();
  });

  testWidgets('Build 169 optional drillout fields default to hidden',
      (WidgetTester tester) async {
    await _pumpScreen(tester);

    expect(find.byKey(const Key('drillout-rate-override-field')), findsNothing);
    expect(
      find.byKey(const Key('drillout-surface-total-fluid-field')),
      findsNothing,
    );
    expect(find.byKey(const Key('drillout-water-hauled-field')), findsNothing);
    expect(find.byKey(const Key('drillout-oil-hauled-field')), findsNothing);
  });

  testWidgets('Build 169 optional field values persist while toggles are off',
      (WidgetTester tester) async {
    await _pumpScreen(tester);

    await _tapVisible(
      tester,
      find.byKey(const Key('drillout-toggle-include-surface-total-fluid')),
      scrollDelta: -240,
    );
    await tester.enterText(
      find.byKey(const Key('drillout-surface-total-fluid-field')),
      '123',
    );
    await tester.pumpAndSettle();

    var preview = await _openPreviewAndRead(tester);
    expect(preview, contains('Surface Total Fluid: 123 bbl'));

    await _tapVisible(
      tester,
      find.byKey(const Key('drillout-toggle-include-surface-total-fluid')),
      scrollDelta: -240,
    );
    expect(
      find.byKey(const Key('drillout-surface-total-fluid-field')),
      findsNothing,
    );

    preview = await _openPreviewAndRead(tester);
    expect(preview.contains('Surface Total Fluid:'), isFalse);

    await _tapVisible(
      tester,
      find.byKey(const Key('drillout-toggle-include-surface-total-fluid')),
      scrollDelta: -240,
    );
    expect(
      find.byKey(const Key('drillout-surface-total-fluid-field')),
      findsOneWidget,
    );
    expect(find.text('123'), findsOneWidget);
  });

  testWidgets(
      'Build 169 status toggle controls status, plug, and coil sections',
      (WidgetTester tester) async {
    await _pumpScreen(tester);

    expect(find.byKey(const Key('drillout-status-dropdown')), findsNothing);
    expect(find.byKey(const Key('drillout-toggle-plug-number')), findsNothing);
    expect(find.byKey(const Key('drillout-toggle-coil-depth')), findsNothing);

    await _tapVisible(tester, find.byKey(const Key('drillout-toggle-status')));

    expect(find.byKey(const Key('drillout-status-dropdown')), findsOneWidget);
    expect(
        find.byKey(const Key('drillout-toggle-plug-number')), findsOneWidget);
    expect(find.byKey(const Key('drillout-toggle-coil-depth')), findsOneWidget);
  });

  testWidgets('Build 169 migration enables saved non-empty optional values',
      (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _scopedSetupKey();
    await prefs.setString(
      key,
      jsonEncode(
        <String, Object>{
          'surfaceTotalFluid': '77',
          'waterHauled': '11',
          'oilHauled': '5',
        },
      ),
    );

    await _pumpScreen(tester);

    expect(
      find.byKey(const Key('drillout-surface-total-fluid-field')),
      findsOneWidget,
    );
    expect(
        find.byKey(const Key('drillout-water-hauled-field')), findsOneWidget);
    expect(find.byKey(const Key('drillout-oil-hauled-field')), findsOneWidget);
  });
}
