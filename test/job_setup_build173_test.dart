import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/screens/job_setup_screen.dart';
import 'package:wellwerks/services/active_company_service.dart';
import 'package:wellwerks/services/active_workflow_mode_service.dart';
import 'package:wellwerks/services/job_storage_service.dart';

Future<void> _pumpSetup(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: JobSetupScreen()));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ActiveCompanyService.instance.resetForTest();
    await ActiveCompanyService.instance.setActiveCompany(
      'Mach Energy',
      syncActiveJob: false,
      syncActiveShift: false,
    );
    await JobStorageService().clearActiveJob();
  });

  testWidgets('Build 173 production setup shows production-only controls',
      (WidgetTester tester) async {
    await ActiveWorkflowModeService.instance
        .setMode(ActiveWorkflowMode.production);
    await _pumpSetup(tester);

    await tester.tap(find.text('Start Job').first);
    await tester.pumpAndSettle();

    expect(find.text('1. Job Information'), findsOneWidget);
    expect(find.text('Multi-Well Pad'), findsOneWidget);
    expect(find.text('Job Type'), findsNothing);
  });

  testWidgets('Build 173 drillout setup hides production-only controls',
      (WidgetTester tester) async {
    await ActiveWorkflowModeService.instance
        .setMode(ActiveWorkflowMode.drillout);
    await _pumpSetup(tester);

    await tester.tap(find.text('Start Job').first);
    await tester.pumpAndSettle();

    expect(find.text('Drillout Job Setup'), findsOneWidget);
    expect(find.text('Chemicals'), findsNothing);
    expect(find.text('Single Well'), findsNothing);
    expect(find.text('Multi-Well / Pad'), findsNothing);
  });

  testWidgets('Build 173 cleanout uses shared drillout/cleanout setup',
      (WidgetTester tester) async {
    await ActiveWorkflowModeService.instance
        .setMode(ActiveWorkflowMode.cleanout);
    await _pumpSetup(tester);

    await tester.tap(find.text('Start Job').first);
    await tester.pumpAndSettle();

    expect(find.text('Cleanout Job Setup'), findsOneWidget);
    expect(find.text('Workflow'), findsOneWidget);
    expect(find.text('Single Well'), findsNothing);
    expect(find.text('Multi-Well / Pad'), findsNothing);
  });
}
