import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/screens/operations_log_screen.dart';
import 'package:wellwerks/services/drillout_cleanout_field_definitions.dart';
import 'package:wellwerks/services/job_storage_service.dart';
import 'package:wellwerks/services/operations_log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const packageInfoChannel =
      MethodChannel('dev.fluttercommunity.plus/package_info');
  var seededJobCounter = 0;

  Future<String> seedActiveJob({required bool includeStage}) async {
    seededJobCounter += 1;
    final id = 'job-ops-$seededJobCounter';
    final job = JobSetup(
      id: id,
      company: 'Mach Energy',
      padName: 'Horse Pad',
      shift: 'Day',
      workflow: 'drillout',
      wells: const ['Well Alpha', 'Well Bravo'],
      wellEntries: const [
        JobSetupWell(id: 'well-alpha', name: 'Well Alpha'),
        JobSetupWell(id: 'well-bravo', name: 'Well Bravo'),
      ],
      drilloutSetup: includeStage
          ? const <String, dynamic>{'status': 'Stage 12'}
          : const <String, dynamic>{},
    );
    await JobStorageService().saveActiveJob(job);
    return id;
  }

  Future<void> openManualReadingFromAddEntry(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('operations-log-add-entry-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual Reading'));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, (methodCall) async {
      if (methodCall.method == 'getAll') {
        return <String, dynamic>{
          'appName': 'WellWerks',
          'packageName': 'wellwerks',
          'version': '1.0.1',
          'buildNumber': '191',
          'buildSignature': 'signature',
        };
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, null);
  });

  testWidgets('drillout Add Entry button has a non-null callback',
      (tester) async {
    await seedActiveJob(includeStage: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.drillout,
          title: 'Drillout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('operations-log-add-entry-button')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('drillout Add Reading opens form when log is empty',
      (tester) async {
    await seedActiveJob(includeStage: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.drillout,
          title: 'Drillout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openManualReadingFromAddEntry(tester);

    expect(find.text('Add Drillout Reading'), findsOneWidget);
  });

  testWidgets('drillout Add Reading opens form when current stage is blank',
      (tester) async {
    await seedActiveJob(includeStage: false);

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.drillout,
          title: 'Drillout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openManualReadingFromAddEntry(tester);

    final stageField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('operations-log-form-stage-field')),
    );
    expect(stageField.initialValue ?? '', isEmpty);
  });

  testWidgets('drillout form receives current job and selected well defaults',
      (tester) async {
    await seedActiveJob(includeStage: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.drillout,
          title: 'Drillout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openManualReadingFromAddEntry(tester);

    expect(find.text('Current Job'), findsOneWidget);
    expect(find.text('Horse Pad'), findsOneWidget);

    final wellDropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('operations-log-form-well-dropdown')),
    );
    expect(wellDropdown.initialValue, 'well-alpha');
  });

  testWidgets('saving a reading returns to log and adds the entry',
      (tester) async {
    final jobId = await seedActiveJob(includeStage: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.drillout,
          title: 'Drillout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openManualReadingFromAddEntry(tester);

    expect(find.text('Add Drillout Reading'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('operations-log-form-pump-rate-field')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('operations-log-form-pump-rate-field')),
      '12.5',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('operations-log-form-notes-field')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('operations-log-form-notes-field')),
      'Stable conditions',
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('operations-log-form-save-button')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('operations-log-form-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Add Drillout Reading'), findsNothing);

    final persisted = await OperationsLogService().loadEntries(
      workflow: OperationsLogWorkflow.drillout,
      jobId: jobId,
    );
    expect(persisted.length, 1);
    expect(persisted.single.pumpRate, '12.5');
  });

  testWidgets('cancelling a reading form returns without creating entry',
      (tester) async {
    final jobId = await seedActiveJob(includeStage: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.drillout,
          title: 'Drillout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openManualReadingFromAddEntry(tester);

    expect(find.text('Add Drillout Reading'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('operations-log-form-cancel-button')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester
        .tap(find.byKey(const Key('operations-log-form-cancel-button')));
    await tester.pumpAndSettle();

    expect(find.text('Add Drillout Reading'), findsNothing);
    expect(find.textContaining('Rate 12.5'), findsNothing);

    final persisted = await OperationsLogService().loadEntries(
      workflow: OperationsLogWorkflow.drillout,
      jobId: jobId,
    );
    expect(persisted, isEmpty);
  });

  testWidgets('cleanout Add Entry opens cleanout reading form', (tester) async {
    await seedActiveJob(includeStage: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.cleanout,
          title: 'Cleanout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openManualReadingFromAddEntry(tester);

    expect(find.text('Add Cleanout Reading'), findsOneWidget);
  });

  testWidgets('empty-state primary actions provide guidance', (tester) async {
    await seedActiveJob(includeStage: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.drillout,
          title: 'Drillout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('operations-log-action-generate-shift-update')),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.byKey(const Key('operations-log-action-generate-shift-update')),
      findsOneWidget,
    );

    await tester.tap(
        find.byKey(const Key('operations-log-action-generate-shift-update')));
    await tester.pumpAndSettle();
    expect(find.text('Add at least one entry first.'), findsOneWidget);
  });

  testWidgets('operations log gas and sand use text-update dropdown options',
      (tester) async {
    await seedActiveJob(includeStage: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.drillout,
          title: 'Drillout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openManualReadingFromAddEntry(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('operations-log-form-gas-dropdown')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('operations-log-form-gas-dropdown')));
    await tester.pumpAndSettle();
    for (final option in DrilloutCleanoutFieldDefinitions.gasOptions) {
      expect(find.text(option), findsWidgets);
    }
    expect(find.text('Trace'), findsNothing);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('operations-log-form-sand-dropdown')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester
        .tap(find.byKey(const Key('operations-log-form-sand-dropdown')));
    await tester.pumpAndSettle();
    for (final option in DrilloutCleanoutFieldDefinitions.sandOptions) {
      expect(find.text(option), findsWidgets);
    }
  });

  testWidgets('stage dropdown includes Traveling to Bottom from shared source',
      (tester) async {
    await seedActiveJob(includeStage: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.drillout,
          title: 'Drillout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openManualReadingFromAddEntry(tester);

    await tester.tap(find.byKey(const Key('operations-log-form-stage-field')));
    await tester.pumpAndSettle();
    expect(find.text('Traveling to Bottom'), findsWidgets);
  });

  testWidgets('customize fields shows all shared text-update reading fields',
      (tester) async {
    await seedActiveJob(includeStage: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.drillout,
          title: 'Drillout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0;
        i < 10 &&
            find
                .byKey(const Key('operations-log-customize-fields-button'))
                .evaluate()
                .isEmpty;
        i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('operations-log-customize-fields-button')),
        findsOneWidget);
    await tester
        .tap(find.byKey(const Key('operations-log-customize-fields-button')));
    await tester.pumpAndSettle();

    for (final field in DrilloutCleanoutFieldDefinitions.readingFields.where(
      (f) => f.id != DrilloutCleanoutFieldDefinitions.sweepInformationId,
    )) {
      await tester.scrollUntilVisible(
        find.text(field.label).last,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(field.label), findsWidgets);
    }
  });

  testWidgets('build 191 add reading shows pump and returns rate only',
      (tester) async {
    await seedActiveJob(includeStage: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.drillout,
          title: 'Drillout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openManualReadingFromAddEntry(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('operations-log-form-returns-rate-field')),
      180,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byKey(const Key('operations-log-form-pump-rate-field')),
        findsOneWidget);
    expect(find.byKey(const Key('operations-log-form-returns-rate-field')),
        findsOneWidget);
    expect(find.byKey(const Key('operations-log-form-water-rate-field')),
        findsNothing);
    expect(find.byKey(const Key('operations-log-form-flow-rate-field')),
        findsNothing);
  });

  testWidgets(
      'build 191 add reading shows optional estimated STS and STS controls',
      (tester) async {
    await seedActiveJob(includeStage: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.drillout,
          title: 'Drillout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openManualReadingFromAddEntry(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('operations-log-form-estimated-sts-pick')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('operations-log-form-sts-pick')),
      180,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byKey(const Key('operations-log-form-estimated-sts-pick')),
        findsOneWidget);
    expect(
        find.byKey(const Key('operations-log-form-sts-pick')), findsOneWidget);
  });

  testWidgets('disabled field hides from Add Reading and persists by workflow',
      (tester) async {
    await seedActiveJob(includeStage: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.drillout,
          title: 'Drillout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0;
        i < 10 &&
            find
                .byKey(const Key('operations-log-customize-fields-button'))
                .evaluate()
                .isEmpty;
        i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('operations-log-customize-fields-button')),
        findsOneWidget);
    await tester
        .tap(find.byKey(const Key('operations-log-customize-fields-button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(CheckboxListTile, 'Gas'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Gas'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    await openManualReadingFromAddEntry(tester);
    expect(find.byKey(const Key('operations-log-form-gas-dropdown')),
        findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      const MaterialApp(
        home: OperationsLogScreen(
          workflow: OperationsLogWorkflow.drillout,
          title: 'Drillout Log',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openManualReadingFromAddEntry(tester);
    expect(find.byKey(const Key('operations-log-form-gas-dropdown')),
        findsNothing);
  });
}
