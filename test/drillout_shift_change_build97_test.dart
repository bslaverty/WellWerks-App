import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/screens/drillout_shift_change_screen.dart';
import 'package:wellwerks/services/active_company_service.dart';
import 'package:wellwerks/services/job_storage_service.dart';

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: DrilloutShiftChangeScreen()),
  );
  await tester.pumpAndSettle();
}

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

Future<String> _openPreviewAndRead(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('drillout-action-preview')),
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  final previewButton = tester.widget<FilledButton>(
    find.byKey(const Key('drillout-action-preview')),
  );
  previewButton.onPressed!.call();
  await tester.pumpAndSettle();

  final previewFinder = find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        ((widget.data?.contains('Shift Change') ?? false) ||
            (widget.data?.contains('Update') ?? false)) &&
        (widget.data?.contains('Rate:') ?? false),
  );
  expect(previewFinder, findsOneWidget);
  final preview = tester.widget<Text>(previewFinder).data ?? '';

  await tester.tap(find.widgetWithText(TextButton, 'Close'));
  await tester.pumpAndSettle();
  return preview;
}

Future<void> _selectMode(WidgetTester tester, String modeLabel) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('drillout-mode-selector')),
    -240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(modeLabel).last);
  await tester.pumpAndSettle();
}

Future<void> _setStatusAndSand(
  WidgetTester tester, {
  required String status,
  required String sand,
}) async {
  await _tapVisible(tester, find.byKey(const Key('drillout-toggle-status')));
  await _tapVisible(tester, find.byKey(const Key('drillout-status-dropdown')));
  await tester.tap(find.text(status).last);
  await tester.pumpAndSettle();

  await _tapVisible(tester, find.byKey(const Key('drillout-toggle-sand')));
  await _tapVisible(tester, find.byKey(const Key('drillout-sand-dropdown')));
  await tester.tap(find.text(sand).last);
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _expectCopyLabel(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('drillout-action-copy')),
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  expect(find.widgetWithText(OutlinedButton, label), findsOneWidget);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ActiveCompanyService.instance.resetForTest();
    await _seedActiveJob();
  });

  testWidgets('Build 98 mode defaults to Shift Change',
      (WidgetTester tester) async {
    await _pumpScreen(tester);

    await _expectCopyLabel(tester, 'Copy Shift Change');
    final preview = await _openPreviewAndRead(tester);
    expect(preview, contains('5:00 AM Shift Change'));
  });

  testWidgets('Build 98 Shift Change selection persists',
      (WidgetTester tester) async {
    await _pumpScreen(tester);

    await _selectMode(tester, 'Shift Change');
    await _pumpScreen(tester);

    await _expectCopyLabel(tester, 'Copy Shift Change');
    final preview = await _openPreviewAndRead(tester);
    expect(preview, contains('5:00 AM Shift Change'));
  });

  testWidgets('Build 98 Update selection persists',
      (WidgetTester tester) async {
    await _pumpScreen(tester);

    await _selectMode(tester, 'Update');
    await _pumpScreen(tester);

    await _expectCopyLabel(tester, 'Copy Update');
    final preview = await _openPreviewAndRead(tester);
    expect(preview, contains('5:00 AM Update'));
    expect(preview.contains('Shift Update'), isFalse);
  });

  testWidgets('Build 98 toggles hide and show each optional field',
      (WidgetTester tester) async {
    await _pumpScreen(tester);

    expect(find.byKey(const Key('drillout-status-dropdown')), findsNothing);
    expect(find.byKey(const Key('drillout-plug-number-field')), findsNothing);
    expect(find.byKey(const Key('drillout-coil-depth-field')), findsNothing);
    expect(find.byKey(const Key('drillout-gas-spot-rate-field')), findsNothing);
    expect(find.byKey(const Key('drillout-sand-dropdown')), findsNothing);

    await _tapVisible(tester, find.byKey(const Key('drillout-toggle-status')));
    expect(find.byKey(const Key('drillout-status-dropdown')), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(const Key('drillout-toggle-plug-number')),
    );
    expect(
      find.byKey(const Key('drillout-plug-number-field')),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(const Key('drillout-toggle-coil-depth')),
    );
    expect(find.byKey(const Key('drillout-coil-depth-field')), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(const Key('drillout-toggle-gas-spot-rate')),
    );
    expect(
      find.byKey(const Key('drillout-gas-spot-rate-field')),
      findsOneWidget,
    );

    await _tapVisible(tester, find.byKey(const Key('drillout-toggle-sand')));
    expect(find.byKey(const Key('drillout-sand-dropdown')), findsOneWidget);
  });

  testWidgets(
      'Build 98 toggles control output, field order is exact, and preview matches copy in Shift Change',
      (WidgetTester tester) async {
    String copiedText = '';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments;
          if (args is Map) {
            copiedText = (args['text'] as String?) ?? '';
          }
          return null;
        }
        if (methodCall.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': copiedText};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await _pumpScreen(tester);

    await _tapVisible(tester, find.byKey(const Key('drillout-toggle-status')));
    await _tapVisible(
        tester, find.byKey(const Key('drillout-status-dropdown')));
    await tester.tap(find.text('Drilling Plugs').last);
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const Key('drillout-toggle-plug-number')),
    );
    await tester.enterText(
      find.byKey(const Key('drillout-plug-number-field')),
      '12',
    );

    await _tapVisible(
      tester,
      find.byKey(const Key('drillout-toggle-coil-depth')),
    );
    await tester.enterText(
      find.byKey(const Key('drillout-coil-depth-field')),
      '12450',
    );

    await _tapVisible(
      tester,
      find.byKey(const Key('drillout-toggle-gas-spot-rate')),
    );
    await tester.enterText(
      find.byKey(const Key('drillout-gas-spot-rate-field')),
      '425',
    );

    await _tapVisible(tester, find.byKey(const Key('drillout-toggle-sand')));
    await _tapVisible(tester, find.byKey(const Key('drillout-sand-dropdown')));
    await tester.tap(find.text('Light').last);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('drillout-notes-field')), 'Test note');
    await tester.pumpAndSettle();

    final preview = await _openPreviewAndRead(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('drillout-action-copy')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final copyButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('drillout-action-copy')),
    );
    copyButton.onPressed!.call();
    await tester.pumpAndSettle();

    expect(copiedText, preview);

    expect(preview, contains('Status: Drilling Plugs'));
    expect(preview, contains('Plug #: 12'));
    expect(preview, contains('Coil Depth: 12450 ft'));
    expect(preview, contains('Gas: 425 MCFD'));
    expect(preview, contains('Sand: Light'));

    final order = <String>[
      'Shift Change',
      'Mach Energy',
      'Horse Pad',
      'Horse 16-2H',
      'Status: Drilling Plugs',
      'Plug #: 12',
      'Coil Depth: 12450 ft',
      'Gas: 425 MCFD',
      'Sand: Light',
      'Rate:',
      'Notes: Test note',
    ];
    for (var i = 0; i < order.length - 1; i++) {
      expect(preview.indexOf(order[i]) < preview.indexOf(order[i + 1]), isTrue);
    }
  });

  testWidgets('Build 98 status and sand selections persist with drillout setup',
      (WidgetTester tester) async {
    await _pumpScreen(tester);

    await _tapVisible(tester, find.byKey(const Key('drillout-toggle-status')));
    await _tapVisible(
        tester, find.byKey(const Key('drillout-status-dropdown')));
    await tester.tap(find.text('Circulating').last);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const Key('drillout-toggle-sand')));
    await _tapVisible(tester, find.byKey(const Key('drillout-sand-dropdown')));
    await tester.tap(find.text('Medium').last);
    await tester.pumpAndSettle();

    await _pumpScreen(tester);

    final persistedPreview = await _openPreviewAndRead(tester);
    expect(persistedPreview, contains('Status: Circulating'));
    expect(persistedPreview, contains('Sand: Medium'));
  });

  testWidgets(
      'Build 98 switching modes keeps entered values and updates copy label',
      (WidgetTester tester) async {
    await _pumpScreen(tester);

    await _setStatusAndSand(
      tester,
      status: 'Drilling Plugs',
      sand: 'Light',
    );
    await _tapVisible(
      tester,
      find.byKey(const Key('drillout-toggle-plug-number')),
    );
    await tester.enterText(
      find.byKey(const Key('drillout-plug-number-field')),
      '12',
    );
    await tester.pumpAndSettle();

    await _selectMode(tester, 'Update');
    await _expectCopyLabel(tester, 'Copy Update');
    var preview = await _openPreviewAndRead(tester);
    expect(preview, contains('5:00 AM Update'));
    expect(preview, contains('Status: Drilling Plugs'));
    expect(preview, contains('Plug #: 12'));
    expect(preview, contains('Sand: Light'));

    await _selectMode(tester, 'Shift Change');
    await _expectCopyLabel(tester, 'Copy Shift Change');
    preview = await _openPreviewAndRead(tester);
    expect(preview, contains('5:00 AM Shift Change'));
    expect(preview, contains('Status: Drilling Plugs'));
    expect(preview, contains('Plug #: 12'));
    expect(preview, contains('Sand: Light'));
  });

  testWidgets('Build 98 preview equals copy in both modes',
      (WidgetTester tester) async {
    String copiedText = '';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments;
          if (args is Map) {
            copiedText = (args['text'] as String?) ?? '';
          }
          return null;
        }
        if (methodCall.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': copiedText};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await _pumpScreen(tester);

    for (final mode in const ['Shift Change', 'Update']) {
      await _selectMode(tester, mode);
      final preview = await _openPreviewAndRead(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('drillout-action-copy')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final copyButton = tester.widget<OutlinedButton>(
        find.byKey(const Key('drillout-action-copy')),
      );
      copyButton.onPressed!.call();
      await tester.pumpAndSettle();
      expect(copiedText, preview);
      expect(
        copiedText,
        contains(mode == 'Update' ? '5:00 AM Update' : '5:00 AM Shift Change'),
      );
    }
  });

  testWidgets(
      'Build 98 clear current shift values keeps toggles, clears values, and keeps selected mode',
      (WidgetTester tester) async {
    await _pumpScreen(tester);

    await _selectMode(tester, 'Update');

    await _tapVisible(tester, find.byKey(const Key('drillout-toggle-status')));
    await _tapVisible(
        tester, find.byKey(const Key('drillout-status-dropdown')));
    await tester.tap(find.text('Equipment Issues').last);
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const Key('drillout-toggle-plug-number')),
    );
    await tester.enterText(
      find.byKey(const Key('drillout-plug-number-field')),
      '8',
    );

    await _tapVisible(
      tester,
      find.byKey(const Key('drillout-toggle-coil-depth')),
    );
    await tester.enterText(
      find.byKey(const Key('drillout-coil-depth-field')),
      '10000',
    );

    await _tapVisible(
      tester,
      find.byKey(const Key('drillout-toggle-gas-spot-rate')),
    );
    await tester.enterText(
      find.byKey(const Key('drillout-gas-spot-rate-field')),
      '333',
    );

    await _tapVisible(tester, find.byKey(const Key('drillout-toggle-sand')));
    await _tapVisible(tester, find.byKey(const Key('drillout-sand-dropdown')));
    await tester.tap(find.text('Heavy').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('drillout-action-clear-current')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final clearCurrentButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('drillout-action-clear-current')),
    );
    clearCurrentButton.onPressed!.call();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear Current Values'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('drillout-toggle-status')),
      -240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('drillout-status-dropdown')), findsOneWidget);
    expect(find.byKey(const Key('drillout-plug-number-field')), findsOneWidget);
    expect(find.byKey(const Key('drillout-coil-depth-field')), findsOneWidget);
    expect(
      find.byKey(const Key('drillout-gas-spot-rate-field')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('drillout-sand-dropdown')), findsOneWidget);

    final preview = await _openPreviewAndRead(tester);
    await _expectCopyLabel(tester, 'Copy Update');
    expect(preview, contains('5:00 AM Update'));
    expect(preview, contains('Status: -'));
    expect(preview, contains('Plug #: -'));
    expect(preview, contains('Coil Depth: - ft'));
    expect(preview, contains('Gas: - MCFD'));
    expect(preview, contains('Sand: -'));
  });

  testWidgets(
      'Build 98 clear drillout setup clears toggles and values and resets mode to Shift Change',
      (WidgetTester tester) async {
    await _pumpScreen(tester);

    await _selectMode(tester, 'Update');

    await _tapVisible(tester, find.byKey(const Key('drillout-toggle-status')));
    await _tapVisible(
        tester, find.byKey(const Key('drillout-status-dropdown')));
    await tester.tap(find.text('POOH').last);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const Key('drillout-toggle-sand')));
    await _tapVisible(tester, find.byKey(const Key('drillout-sand-dropdown')));
    await tester.tap(find.text('Trace').last);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('drillout-notes-field')), 'Will clear');
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('drillout-action-clear-setup')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final clearSetupButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('drillout-action-clear-setup')),
    );
    clearSetupButton.onPressed!.call();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear Drillout Setup'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('drillout-status-dropdown')), findsNothing);
    expect(find.byKey(const Key('drillout-plug-number-field')), findsNothing);
    expect(find.byKey(const Key('drillout-coil-depth-field')), findsNothing);
    expect(find.byKey(const Key('drillout-gas-spot-rate-field')), findsNothing);
    expect(find.byKey(const Key('drillout-sand-dropdown')), findsNothing);

    final preview = await _openPreviewAndRead(tester);
    await _expectCopyLabel(tester, 'Copy Shift Change');
    expect(preview, contains('5:00 AM Shift Change'));
    expect(preview.contains('Status:'), isFalse);
    expect(preview.contains('Sand:'), isFalse);
    expect(preview, contains('Notes: -'));
  });
}
