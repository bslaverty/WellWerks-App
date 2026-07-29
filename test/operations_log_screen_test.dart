import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/screens/operations_log_screen.dart';
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

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, (methodCall) async {
      if (methodCall.method == 'getAll') {
        return <String, dynamic>{
          'appName': 'WellWerks',
          'packageName': 'wellwerks',
          'version': '1.0.1',
          'buildNumber': '190',
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

  testWidgets('drillout Add Reading button has a non-null callback',
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
      find.widgetWithText(FilledButton, 'Add Reading').first,
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

    await tester.tap(find.widgetWithText(FilledButton, 'Add Reading'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.widgetWithText(FilledButton, 'Add Reading'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.widgetWithText(FilledButton, 'Add Reading'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.widgetWithText(FilledButton, 'Add Reading'));
    await tester.pumpAndSettle();

    expect(find.text('Add Drillout Reading'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('operations-log-form-pump-rate-field')),
      '12.5',
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

    await tester.tap(find.widgetWithText(FilledButton, 'Add Reading'));
    await tester.pumpAndSettle();

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

  testWidgets('cleanout Add Reading opens cleanout reading form',
      (tester) async {
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

    await tester.tap(find.widgetWithText(FilledButton, 'Add Reading'));
    await tester.pumpAndSettle();

    expect(find.text('Add Cleanout Reading'), findsOneWidget);
  });

  testWidgets('empty-state controls do not appear enabled without action',
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

    await tester.scrollUntilVisible(
      find.text('Create Shift Report'),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    final shareButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Share Selected Readings'),
        matching: find.byType(OutlinedButton),
      ),
    );
    final reportButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Create Shift Report'),
        matching: find.byType(FilledButton),
      ),
    );

    expect(shareButton.onPressed, isNull);
    expect(reportButton.onPressed, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Add Reading'));
    await tester.pumpAndSettle();
    expect(find.text('Add Drillout Reading'), findsOneWidget);
  });
}
