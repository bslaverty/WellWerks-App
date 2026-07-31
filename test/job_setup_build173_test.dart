import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/screens/job_setup_screen.dart';
import 'package:wellwerks/screens/production_dashboard_screen.dart';
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

  testWidgets('Build 220 company is editable when starting a new job',
      (WidgetTester tester) async {
    await ActiveWorkflowModeService.instance
        .setMode(ActiveWorkflowMode.production);
    await _pumpSetup(tester);

    await tester.tap(find.text('Start Job').first);
    await tester.pumpAndSettle();

    final companyField = find.byKey(const Key('job-info-company-field')).first;
    await tester.enterText(companyField, 'Devon');
    await tester.pumpAndSettle();

    expect(find.text('Devon'), findsOneWidget);
  });

  testWidgets('Build 212 Add Well appends rows and preserves names',
      (WidgetTester tester) async {
    await ActiveWorkflowModeService.instance
        .setMode(ActiveWorkflowMode.production);
    await _pumpSetup(tester);

    await tester.tap(find.text('Start Job').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Multi-Well Pad'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Well 1 Name'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Well 2 Name'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Well 1 Name'),
      'Gathers 28-20-17-11-10 #1MH',
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Add Well'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add Well'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Well 2 Name'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Add Well'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add Well'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Well 3 Name'), findsOneWidget);

    expect(find.text('Gathers 28-20-17-11-10 #1MH'), findsOneWidget);
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

  testWidgets(
      'Build 215.1 production dashboard shows concrete flow-path equipment label',
      (WidgetTester tester) async {
    await ActiveWorkflowModeService.instance
        .setMode(ActiveWorkflowMode.production);

    await JobStorageService().saveActiveJob(
      JobSetup(
        company: 'Mach Energy',
        workflow: 'production',
        padName: 'Horse Pad',
        shift: 'Day',
        wells: const ['Horse 16-2H', 'Horse 16-3H'],
        leaseNames: const ['Horse 16-2H', 'Horse 16-3H'],
        wellEntries: const [
          JobSetupWell(id: 'well_1', name: 'Horse 16-2H'),
          JobSetupWell(id: 'well_2', name: 'Horse 16-3H'),
        ],
        activeEquipmentSections: const ['FLARE / ECD', 'VRU'],
        drilloutSetup: const {
          'productionFlowPath': 'ecd',
          'gasRateSource': 'instantSpotRate',
        },
      ),
    );

    await tester
        .pumpWidget(const MaterialApp(home: ProductionDashboardScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Production ready'), findsOneWidget);
    expect(find.text('Open Job Management >'), findsOneWidget);
    expect(find.textContaining('Workflow: Production'), findsNothing);
  });
}
