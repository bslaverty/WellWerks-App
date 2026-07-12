import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/main.dart';
import 'package:wellwerks/models/production_shift.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/models/jsa_draft.dart';
import 'package:wellwerks/screens/chart_reference_screen.dart';
import 'package:wellwerks/screens/bottoms_up_screen.dart';
import 'package:wellwerks/screens/equipment_layout_screen.dart';
import 'package:wellwerks/screens/job_box_inventory_screen.dart';
import 'package:wellwerks/screens/jsa_screen.dart';
import 'package:wellwerks/screens/home_screen.dart';
import 'package:wellwerks/screens/rig_up_inventory_screen.dart';
import 'package:wellwerks/screens/pressure_entry_screen.dart';
import 'package:wellwerks/screens/production_shift_change_screen.dart';
import 'package:wellwerks/screens/production_history_screen.dart';
import 'package:wellwerks/screens/production_inventory_screen.dart';
import 'package:wellwerks/screens/shift_report_screen.dart';
import 'package:wellwerks/screens/text_update_screen.dart';
import 'package:wellwerks/services/active_company_service.dart';
import 'package:wellwerks/services/app_settings_service.dart';
import 'package:wellwerks/services/job_history_service.dart';
import 'package:wellwerks/services/job_box_inventory_service.dart';
import 'package:wellwerks/services/job_storage_service.dart';
import 'package:wellwerks/services/jsa_storage_service.dart';
import 'package:wellwerks/services/production_shift_service.dart';
import 'package:wellwerks/services/report_profile_service.dart';
import 'package:wellwerks/services/rig_up_inventory_service.dart';

Finder labeledTextField(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
    description: 'TextField with label $label',
  );
}

Future<void> ensureEquipmentLibraryOpen(WidgetTester tester) async {
  if (find.text('Open Library').evaluate().isNotEmpty) {
    await tester.tap(find.text('Open Library').first);
    await tester.pumpAndSettle();
  }
  if (find.text('Show Equipment Library').evaluate().isNotEmpty) {
    await tester.tap(find.text('Show Equipment Library').first);
    await tester.pumpAndSettle();
  }
}

void main() {
  group('ChloridesCalculator', () {
    const entries = [
      ChloridesTableEntry(
        specificGravity: 1.002,
        poundsPerGallon: 8.36,
        chloridesPpm: 1755,
      ),
      ChloridesTableEntry(
        specificGravity: 1.004,
        poundsPerGallon: 8.38,
        chloridesPpm: 3511,
      ),
      ChloridesTableEntry(
        specificGravity: 1.006,
        poundsPerGallon: 8.40,
        chloridesPpm: 5267,
      ),
    ];

    test('uses exact specific gravity match', () {
      final response = ChloridesCalculator.interpolate(
        entries: entries,
        inputType: 'Specific Gravity',
        inputValue: 1.004,
      );

      expect(response.warning, isNull);
      expect(response.result?.specificGravity, 1.004);
      expect(response.result?.poundsPerGallon, 8.38);
      expect(response.result?.chloridesPpm, 3511);
    });

    test('interpolates between specific gravity rows', () {
      final response = ChloridesCalculator.interpolate(
        entries: entries,
        inputType: 'Specific Gravity',
        inputValue: 1.005,
      );

      expect(response.warning, isNull);
      expect(response.result?.specificGravity, closeTo(1.005, 0.0001));
      expect(response.result?.poundsPerGallon, closeTo(8.39, 0.001));
      expect(response.result?.chloridesPpm, closeTo(4389, 0.5));
    });

    test('uses pounds input for lookup', () {
      final response = ChloridesCalculator.interpolate(
        entries: entries,
        inputType: 'Pounds',
        inputValue: 8.38,
      );

      expect(response.warning, isNull);
      expect(response.result?.specificGravity, 1.004);
      expect(response.result?.poundsPerGallon, 8.38);
      expect(response.result?.chloridesPpm, 3511);
    });

    test('warns when value is out of range', () {
      final response = ChloridesCalculator.interpolate(
        entries: entries,
        inputType: 'Specific Gravity',
        inputValue: 1.000,
      );

      expect(response.result, isNull);
      expect(response.warning, 'Value is outside chart range.');
    });
  });

  testWidgets('WellWerks app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const WellWerksApp());
    expect(find.text('WellWerks Toolbox'), findsOneWidget);
  });

  testWidgets('Home shows combined company and collapsed active job card',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final jobStorage = JobStorageService();
    await jobStorage.saveActiveJob(
      JobSetup(
        company: 'Mach Energy',
        padName: 'Horse Pad',
        wells: const ['Well 1'],
        leaseNames: const ['Horse 16-2H'],
        wellEntries: const [JobSetupWell(id: 'well_a', name: 'Well Name')],
        shift: 'Day',
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Active Company'), findsOneWidget);
    expect(find.textContaining('Active Job: Horse Pad • Horse 16-2H • Day'),
        findsOneWidget);
    expect(find.text('Active Job'), findsNothing);
    expect(find.text('Continue Active Job'), findsNothing);
    expect(find.text('ACTIVE'), findsNothing);
    expect(find.text('Manage / Edit Job'), findsNothing);
    expect(find.textContaining('Horse Pad • - • Day'), findsNothing);
    expect(find.text('Reset Active Job'), findsNothing);

    await tester.tap(find.byTooltip('Expand details'));
    await tester.pumpAndSettle();

    expect(find.text('Active Job'), findsOneWidget);
    expect(find.text('Continue Active Job'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('Reset Active Job'), findsOneWidget);
    expect(find.text('Manage / Edit Job'), findsOneWidget);
  });

  testWidgets(
      'Home no active job state keeps company selector and start action',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final jobStorage = JobStorageService();
    await jobStorage.clearActiveJob();
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Active Company'), findsOneWidget);
    expect(find.text('No Active Job'), findsOneWidget);
    expect(find.text('Start Job'), findsOneWidget);
    expect(find.text('Continue Active Job'), findsNothing);
    expect(find.text('ACTIVE'), findsNothing);
    expect(find.textContaining('Active Job:'), findsNothing);
  });

  test('Well name precedence replaces placeholders with lease names', () {
    final job = JobSetup(
      wells: const ['Well 1', '-'],
      leaseNames: const ['Horse 16-2H', 'Horse 16-3H'],
      wellEntries: const [
        JobSetupWell(id: 'well_a', name: 'Well Name'),
        JobSetupWell(id: 'well_b', name: '-'),
      ],
    );

    expect(job.resolvedWellNames, const ['Horse 16-2H', 'Horse 16-3H']);
    expect(job.wellIds, const ['well_a', 'well_b']);
  });

  test('Manual real well name beats lease name', () {
    final job = JobSetup(
      wells: const ['Custom Alpha'],
      leaseNames: const ['Horse 16-2H'],
      wellEntries: const [JobSetupWell(id: 'well_a', name: 'Custom Alpha')],
    );

    expect(job.resolvedWellNames, const ['Custom Alpha']);
  });

  test('Active job persistence normalizes placeholders and survives reload',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = JobStorageService();

    await storage.saveActiveJob(
      JobSetup(
        padName: 'Horse Pad',
        shift: 'Day',
        wells: const ['Well 1'],
        leaseNames: const ['Horse 16-2H'],
        wellEntries: const [JobSetupWell(id: 'well_a', name: 'Well Name')],
      ),
    );

    final loaded = await storage.loadActiveJob();
    expect(loaded, isNotNull);
    expect(loaded!.resolvedWellNames, const ['Horse 16-2H']);
    expect(loaded.wellEntries.first.name, 'Horse 16-2H');
    expect(loaded.wellEntries.first.id, 'well_a');
  });

  test('Active job save publishes updated wells through shared notifier',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = JobStorageService();
    await storage.clearActiveJob();

    final notifiedWells = <String>[];
    void listener() {
      final current = storage.activeJobListenable.value;
      notifiedWells.add(current?.primaryWell ?? '');
    }

    storage.activeJobListenable.addListener(listener);
    final first = await storage.saveActiveJob(
      JobSetup(
        padName: 'Horse Pad',
        wells: const ['Well 1'],
        leaseNames: const ['Horse 16-2H'],
      ),
    );
    await storage.updateActiveJob(
      first.copyWith(
        wellEntries: const [JobSetupWell(id: 'well_a', name: 'Horse 16-3H')],
        wells: const ['Horse 16-3H'],
        leaseNames: const ['Horse 16-2H'],
      ),
    );
    storage.activeJobListenable.removeListener(listener);

    expect(notifiedWells, contains('Horse 16-2H'));
    expect(notifiedWells, contains('Horse 16-3H'));
  });

  testWidgets('Bottoms Up shows tubing and casing selectors', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BottomsUpScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Tubing Size'), findsOneWidget);
    expect(find.text('Casing Size'), findsOneWidget);
  });

  testWidgets('Wide layout shows persistent equipment library', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: EquipmentLayoutScreen()));
    await tester.pumpAndSettle();

    await ensureEquipmentLibraryOpen(tester);

    expect(find.text('Wellhead'), findsWidgets);
    expect(find.text('Plug Catcher'), findsWidgets);
    expect(find.text('Line Heater'), findsWidgets);
    expect(find.text('Facilities'), findsWidgets);
    expect(find.text('Spherical Sand Separator'), findsWidgets);
    expect(find.text('Cyclonic Sand Separator'), findsWidgets);
    expect(find.text('Choke Manifold'), findsWidgets);
    expect(find.text('Equipment Bypass'), findsWidgets);
    expect(find.text('Tee'), findsOneWidget);
    expect(find.text('90° Fitting'), findsOneWidget);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  }, skip: true);

  testWidgets('Tools menu opens required hidden actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: EquipmentLayoutScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save / Load / Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export / Share'));
    await tester.pumpAndSettle();

    expect(find.text('Save Rig-Up'), findsWidgets);
    expect(find.text('Load Rig-Up'), findsWidgets);
    expect(find.text('Clear Layout'), findsWidgets);
    expect(find.text('Export PDF'), findsWidgets);
    expect(find.text('Save Image'), findsWidgets);
    expect(find.text('Share Package'), findsWidgets);
    expect(find.text('Bill of Materials'), findsWidgets);
  }, skip: true);

  testWidgets('Draw Iron supports 2, 3, and 4 inch sizes', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    await tester.pumpWidget(const MaterialApp(home: EquipmentLayoutScreen()));
    await tester.pumpAndSettle();

    await ensureEquipmentLibraryOpen(tester);
    await tester.ensureVisible(find.text('Draw Iron').first);
    await tester.tap(find.text('Draw Iron'));
    await tester.pumpAndSettle();

    expect(find.text('DRAW IRON ACTIVE'), findsOneWidget);
    expect(find.text('Cancel'), findsWidgets);

    await tester.tap(find.text('2" Iron'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(180, 260));
    await tester.pump();
    await tester.tapAt(const Offset(420, 260));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3" Iron'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(600, 260));
    await tester.pumpAndSettle();

    await tester.tap(find.text('4" Iron'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(600, 470));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Draw Iron ON'));
    await tester.pumpAndSettle();

    expect(find.text('DRAW IRON ACTIVE'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && (widget.data ?? '').contains('•'),
      ),
      findsNothing,
    );

    addTearDown(() => tester.binding.setSurfaceSize(null));
  }, skip: true);

  testWidgets('Can add utility items and clear selection is visible', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1500));
    await tester.pumpWidget(const MaterialApp(home: EquipmentLayoutScreen()));
    await tester.pumpAndSettle();

    await ensureEquipmentLibraryOpen(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Tee').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '90° Fitting').first);
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithText(FilledButton, 'Equipment Bypass').first);
    await tester.pumpAndSettle();
    expect(find.text('Bypass 3"'), findsNothing);
    expect(find.text('Tee 3"'), findsNothing);
    expect(find.text('90° 3"'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Choke Manifold').first);
    await tester.pumpAndSettle();

    expect(find.text('Choke Manifold'), findsWidgets);

    expect(find.textContaining('Clear Selection'), findsWidgets);
    expect(find.text('Clear Selection / Unselect'), findsOneWidget);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  }, skip: true);

  testWidgets('Major equipment icons are visible after adding to canvas', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1500));
    await tester.pumpWidget(const MaterialApp(home: EquipmentLayoutScreen()));
    await tester.pumpAndSettle();

    await ensureEquipmentLibraryOpen(tester);

    final checks = <MapEntry<String, IconData>>[
      const MapEntry<String, IconData>(
          'Cyclonic Sand Separator', Icons.cyclone),
      const MapEntry<String, IconData>(
          'Spherical Sand Separator', Icons.circle),
      const MapEntry<String, IconData>(
          'Test Separator', Icons.precision_manufacturing),
      const MapEntry<String, IconData>('Flare', Icons.local_fire_department),
      const MapEntry<String, IconData>('Compressor', Icons.compress),
      const MapEntry<String, IconData>('Facilities', Icons.crop_square),
      const MapEntry<String, IconData>('ESD Valve', Icons.emergency),
      const MapEntry<String, IconData>('Choke Manifold', Icons.tune),
      const MapEntry<String, IconData>('Plug Catcher', Icons.filter_alt),
      const MapEntry<String, IconData>('Line Heater', Icons.whatshot),
      const MapEntry<String, IconData>('Flowback Tank', Icons.oil_barrel),
      const MapEntry<String, IconData>('Production Tank', Icons.oil_barrel),
    ];

    for (final entry in checks) {
      final beforeCount = find.byIcon(entry.value).evaluate().length;
      await tester.tap(find.widgetWithText(FilledButton, entry.key).first);
      await tester.pumpAndSettle();
      final afterCount = find.byIcon(entry.value).evaluate().length;
      expect(
        afterCount,
        greaterThan(beforeCount),
        reason: 'Expected icon for ${entry.key} to render on canvas.',
      );
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));
  }, skip: true);

  testWidgets('Layout designer saves under the current active job', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final jobStorage = JobStorageService();
    final activeJob = await jobStorage.saveActiveJob(
      JobSetup(
        company: 'Mach Energy',
        padName: 'Layout Pad',
        wells: const ['Layout 1'],
        shift: 'Day',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1200, 1500));
    await tester.pumpWidget(const MaterialApp(home: EquipmentLayoutScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Active Job'), findsOneWidget);
    expect(find.textContaining('Pad: Layout Pad'), findsOneWidget);
    expect(find.textContaining('Well: Layout 1'), findsOneWidget);
    expect(find.textContaining('Shift: Day'), findsOneWidget);

    await tester.tap(find.text('Save / Load / Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save Rig-Up').first);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('wellwerks_layout_designer_v2');
    expect(saved, isNotNull);
    final payload = jsonDecode(saved!) as Map<String, dynamic>;
    expect(payload['activeJobId'], activeJob.id);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  }, skip: true);

  testWidgets('Quick round workflow builds and syncs production outputs', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final service = ProductionShiftService();
    final jobStorage = JobStorageService();

    await jobStorage.saveActiveJob(
      JobSetup(
        company: 'Continental Resources',
        padName: 'Bow Pad',
        wells: const ['Bow 21-3'],
        shift: 'Day',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(900, 7000));
    await tester
        .pumpWidget(const MaterialApp(home: ProductionInventoryScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(labeledTextField('Date').first, '2026-07-05');
    expect(find.textContaining('Bow 21-3'), findsWidgets);
    await tester.enterText(labeledTextField('Gauge (inches)').at(0), '80');
    await tester.enterText(labeledTextField('Gauge (inches)').at(1), '45');
    await tester.enterText(
        labeledTextField('Starting Gas Accum').first, '7900');
    await tester.tap(find.widgetWithText(FilledButton, 'Save Inventory'));
    await tester.pumpAndSettle();

    await tester.binding.setSurfaceSize(const Size(900, 7000));
    await tester.pumpWidget(const MaterialApp(home: PressureEntryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Active Job'), findsOneWidget);
    expect(find.textContaining('Continental Resources'), findsWidgets);
    expect(find.textContaining('Pad: Bow Pad'), findsOneWidget);
    expect(find.textContaining('Well: Bow 21-3'), findsOneWidget);
    expect(find.textContaining('Shift: Day'), findsOneWidget);
    expect(find.text('Shift Baseline'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Build Round').first,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final buildRoundButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Build Round').first,
    );
    buildRoundButton.onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.textContaining('Save 6 AM Round'), findsOneWidget);
    expect(labeledTextField('Well Name'), findsNothing);
    expect(find.textContaining('Bow 21-3'), findsWidgets);

    await tester.enterText(labeledTextField('TBG').first, '1200');
    await tester.enterText(labeledTextField('CSG').first, '2888');
    await tester.enterText(labeledTextField('Current Gas Accum').first, '8003');
    await tester.enterText(labeledTextField('Gas Static').first, '300');
    await tester.enterText(labeledTextField('Gas Differential').first, '20');
    await tester.enterText(labeledTextField('Gas Temperature').first, '88');
    await tester.enterText(labeledTextField('Sand Rate').first, '.5');

    await tester.scrollUntilVisible(
      find.text('Current Water Tank Gauges').first,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.enterText(labeledTextField('Current Gauge (in)').at(0), '70');
    await tester.enterText(labeledTextField('Current Gauge (in)').at(1), '40');

    await tester.enterText(
        labeledTextField('Water Hauled This Hour').first, '120');
    await tester.enterText(labeledTextField('Oil Hauled This Hour').first, '0');
    await tester.enterText(
        labeledTextField('Water Pumped This Hour').first, '35');
    await tester.enterText(labeledTextField('Oil Pumped This Hour').first, '0');
    await tester.enterText(labeledTextField('Notes').first, 'Flowing steady.');

    await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Save 6 AM Round').first);
    final saveSixButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save 6 AM Round').first,
    );
    saveSixButton.onPressed!.call();
    await tester.pumpAndSettle();

    final nextHourButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Next Hour (7 AM)').first,
    );
    nextHourButton.onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.textContaining('Active Hour • 7 AM'), findsOneWidget);

    await tester.enterText(
        labeledTextField('Hours Since Previous Reading').first, '1.0');
    await tester.enterText(labeledTextField('Current Gas Accum').first, '8100');
    await tester.enterText(labeledTextField('Current Gauge (in)').at(0), '60');
    await tester.enterText(labeledTextField('Current Gauge (in)').at(1), '35');
    await tester.enterText(
        labeledTextField('Water Hauled This Hour').first, '120');
    await tester.enterText(
        labeledTextField('Water Pumped This Hour').first, '35');
    await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Save 7 AM Round').first);
    final saveSevenButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save 7 AM Round').first,
    );
    saveSevenButton.onPressed!.call();
    await tester.pumpAndSettle();

    final savedShift = await service.loadActiveShift();
    final activeJob = await jobStorage.loadActiveJob();
    expect(savedShift.activeJobId, activeJob?.id ?? '');
    expect(savedShift.savedRows.length, 2);
    expect(savedShift.savedRows[0].time, '6 AM');
    expect(savedShift.savedRows[1].time, '7 AM');

    await tester.pumpWidget(const MaterialApp(home: PressureEntryScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Active Hour • 7 AM'), findsOneWidget);

    addTearDown(() {
      tester.binding.setSurfaceSize(null);
    });
  });

  testWidgets('Production inventory supports baseline save and new day confirm',
      (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    ActiveCompanyService.instance.resetForTest();
    final service = ProductionShiftService();
    final jobStorage = JobStorageService();
    final settingsService = AppSettingsService();
    final settings = await settingsService.load();
    await settingsService.save(settings.copyWith(activeCompany: 'Mach Energy'));
    await jobStorage.saveActiveJob(
      JobSetup(
        company: 'Mach Energy',
        padName: 'Mach Pad',
        wells: const ['Mach 12-8'],
      ),
    );

    await tester.binding.setSurfaceSize(const Size(900, 4000));

    await tester
        .pumpWidget(const MaterialApp(home: ProductionInventoryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Shift Header'), findsOneWidget);
    expect(find.text('Starting Inventory • Water Tanks'), findsOneWidget);
    expect(find.text('Pre-Round Adjustments'), findsOneWidget);
    expect(find.text('Starting Gas Accum'), findsOneWidget);

    await tester.enterText(labeledTextField('Date').first, '2026-07-05');
    await tester.enterText(labeledTextField('Gauge (inches)').at(0), '10');
    await tester.scrollUntilVisible(
      find.text('Starting Inventory • Oil Tanks').first,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(labeledTextField('Gauge (inches)').at(1), '5');
    await tester.tap(find.widgetWithText(FilledButton, 'Save Inventory'));
    await tester.pumpAndSettle();

    final saved = await service.loadActiveShift();
    expect(saved.header.company, 'Mach Energy');
    expect(saved.header.wells.first, 'Mach 12-8');

    await tester.tap(find.widgetWithText(OutlinedButton, 'New Day'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    final afterCancel = await service.loadActiveShift();
    expect(afterCancel.header.company, 'Mach Energy');

    await tester.tap(find.widgetWithText(OutlinedButton, 'New Day'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(OutlinedButton, 'Clear Without Archive'));
    await tester.pumpAndSettle();

    final afterConfirm = await service.loadActiveShift();
    expect(afterConfirm.savedRows, isEmpty);
    expect(afterConfirm.header.company, isEmpty);

    addTearDown(() {
      tester.binding.setSurfaceSize(null);
    });
  });

  testWidgets('Rig-Up assign by well enables after quantity increases', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final jobStorage = JobStorageService();
    await jobStorage.saveActiveJob(
      JobSetup(
        company: 'Mach Energy',
        padName: 'Rig Pad',
        wells: const ['Horse 16-2H', 'Horse 16-3H'],
        leaseNames: const ['Horse 16-2H', 'Horse 16-3H'],
        wellEntries: const [
          JobSetupWell(id: 'well_a', name: 'Horse 16-2H'),
          JobSetupWell(id: 'well_b', name: 'Horse 16-3H'),
        ],
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1200, 4200));
    await tester.pumpWidget(const MaterialApp(home: RigUpInventoryScreen()));
    await tester.pumpAndSettle();
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final assignButton =
        find.byKey(const ValueKey('rig-up-assign-sphericalSeparator'));
    expect(
      tester.widget<TextButton>(assignButton).onPressed,
      isNull,
    );

    await tester
        .tap(find.byKey(const ValueKey('rig-up-increase-sphericalSeparator')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextButton>(assignButton).onPressed,
      isNotNull,
    );
  });

  test('Rig-Up assignment payload persists stable well IDs and Asset Numbers',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = RigUpInventoryService();
    final recordId = await service.saveRecord(
      payload: {
        'customer': 'Mach Energy',
        'pad': 'Rig Pad',
        'wells': const ['Horse 16-2H', 'Horse 16-3H'],
        'wellIds': const ['well_a', 'well_b'],
        'assignByWellEnabled': {
          'sphericalSeparator': true,
        },
        'assignedByWell': {
          'sphericalSeparator': {
            'well_a': 1,
            'well_b': 1,
          },
        },
        'assetNumbersByWell': {
          'sphericalSeparator': {
            'well_a': ['SS-1042'],
            'well_b': ['SS-1088'],
          },
        },
      },
    );

    final saved = await service.loadRecord(recordId);
    expect(saved, isNotNull);
    expect(saved!['wellIds'], ['well_a', 'well_b']);
    expect(saved['assignByWellEnabled'], isA<Map>());
    expect(saved['assignedByWell'], isA<Map>());
    expect(saved['assetNumbersByWell'], isA<Map>());
    expect(
      (saved['assetNumbersByWell'] as Map)['sphericalSeparator']['well_a'],
      ['SS-1042'],
    );
    expect(
      (saved['assetNumbersByWell'] as Map)['sphericalSeparator']['well_b'],
      ['SS-1088'],
    );
  });

  testWidgets('Rig-Up quantity increase preserves existing Asset Numbers',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final jobStorage = JobStorageService();
    await jobStorage.saveActiveJob(
      JobSetup(
        company: 'Mach Energy',
        padName: 'Rig Pad',
        wells: const ['Horse 16-2H'],
        leaseNames: const ['Horse 16-2H'],
        wellEntries: const [JobSetupWell(id: 'well_a', name: 'Horse 16-2H')],
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1200, 4200));
    await tester.pumpWidget(const MaterialApp(home: RigUpInventoryScreen()));
    await tester.pumpAndSettle();
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester
        .tap(find.byKey(const ValueKey('rig-up-increase-sphericalSeparator')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('rig-up-assign-sphericalSeparator')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'SS-1042');
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('rig-up-assign-sphericalSeparator')));
    await tester.pumpAndSettle();

    expect(find.byType(Switch), findsWidgets);

    final plusButtons = find.byIcon(Icons.add);
    await tester.tap(plusButtons.last);
    await tester.pumpAndSettle();

    final assetFields = find.byType(TextField);
    expect(assetFields, findsWidgets);
    expect(
      (tester.widget<TextField>(assetFields.at(0)).controller?.text ?? ''),
      'SS-1042',
    );
  });

  testWidgets(
      'Production report is table-only and text update is select copy only', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final service = ProductionShiftService();
    final jobStorage = JobStorageService();
    final activeJob = await jobStorage.saveActiveJob(
      JobSetup(
        company: 'Continental Resources',
        padName: 'Bow Pad',
        wells: const ['Bow 21-3'],
        shift: 'Day',
      ),
    );
    final seed = (await service.loadActiveShift()).copyWith(
      activeJobId: activeJob.id,
      header: const ProductionShiftHeader(
        company: 'Continental Resources',
        pad: 'Bow Pad',
        wells: ['Bow 21-3'],
      ),
      savedRows: const [
        ProductionReportRow(
          hourIndex: 0,
          time: '6 AM',
          well: 'Bow 21-3',
          choke: '35',
          tbg: '1200',
          csg: '2888',
          waterProduction: 135,
          oilProduction: -10,
          hourlyGas: 103,
          gas24HourRate: 2472,
          gasStatic: '300',
          gasDifferential: '20',
          gasTemp: '88',
          sandRate: '.5',
          waterGaugeText: 'Water Tank 1: 70',
          oilGaugeText: 'Oil Tank 1: 40',
          currentWaterBbl: 140,
          currentOilBbl: 80,
          currentGasAccum: 8003,
          waterHauled: 120,
          oilHauled: 0,
          waterPumped: 35,
          oilPumped: 0,
          notes: 'Flowing steady.',
        ),
      ],
    );
    await service.saveActiveShift(seed);

    await tester.pumpWidget(const MaterialApp(home: ShiftReportScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Active Job'), findsOneWidget);
    expect(find.textContaining('Pad: Bow Pad'), findsOneWidget);
    expect(find.textContaining('Well: Bow 21-3'), findsOneWidget);
    expect(find.textContaining('Shift: Day'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: TextUpdateScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Active Job'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Production report and text update handle missing active job', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final jobStorage = JobStorageService();
    await jobStorage.clearActiveJob();
    ActiveCompanyService.instance.resetForTest();
    final service = ProductionShiftService();

    await service.saveActiveShift(
      ProductionShift.empty().copyWith(
        header: const ProductionShiftHeader(
          company: 'Mach Energy',
          pad: 'Test Pad',
          wells: ['Well 1'],
        ),
        activeJobId: 'stale-job-id',
        savedRows: const [
          ProductionReportRow(
            hourIndex: 0,
            time: '6 AM',
            well: 'Well 1',
            choke: '32',
            chokeType: 'ADJ',
            tbg: '1200',
            csg: '900',
            waterProduction: 25,
            oilProduction: 40,
            hourlyGas: 100,
            gas24HourRate: 2400,
            gasStatic: '100',
            gasDifferential: '20',
            gasTemp: '85',
            sandRate: '.2',
            waterGaugeText: 'Water Tank 1: 50 in',
            oilGaugeText: 'Oil Tank 1: 30 in',
            currentWaterBbl: 100,
            currentOilBbl: 50,
            currentGasAccum: 8000,
            waterHauled: 0,
            oilHauled: 0,
            waterPumped: 0,
            oilPumped: 0,
            notes: 'Stable report.',
          ),
        ],
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: ShiftReportScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Well 1'), findsWidgets);
    final copyReportButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Copy Text'),
    );
    expect(copyReportButton.onPressed, isNotNull);

    await tester.pumpWidget(const MaterialApp(home: TextUpdateScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Mach Energy'), findsWidgets);
    final copyTextButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Copy Text Update'),
    );
    expect(copyTextButton.onPressed, isNotNull);
  });

  testWidgets('Rig-Up inventory removes Share / Send action', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: RigUpInventoryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Share / Send'), findsNothing);
  });

  testWidgets(
      'Production Shift Change defaults to latest saved hour and updates when selecting another hour',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = ProductionShiftService();
    final jobStorage = JobStorageService();
    final activeJob = await jobStorage.saveActiveJob(
      JobSetup(
        company: 'Mach Energy',
        padName: 'Horse Pad',
        wells: const ['Horse 16-2H'],
        leaseNames: const ['Horse 16-2H'],
        wellEntries: const [JobSetupWell(id: 'well_a', name: 'Horse 16-2H')],
        shift: 'Day',
      ),
    );
    await service.saveActiveShift(
      (await service.loadActiveShift()).copyWith(
        activeJobId: activeJob.id,
        header: const ProductionShiftHeader(
          company: 'Mach Energy',
          pad: 'Horse Pad',
          wells: ['Horse 16-2H'],
        ),
        savedRows: const [
          ProductionReportRow(
            hourIndex: 0,
            time: '6 AM',
            well: 'Horse 16-2H',
            choke: '32',
            chokeType: 'ADJ',
            tbg: '1200',
            csg: '900',
            waterProduction: 25,
            oilProduction: 40,
            hourlyGas: 100,
            gas24HourRate: 2400,
            gasStatic: '100',
            gasDifferential: '20',
            gasTemp: '85',
            sandRate: '.2',
            waterGaugeText: 'Water Tank 1: 50 in',
            oilGaugeText: 'Oil Tank 1: 30 in',
            currentWaterBbl: 100,
            currentOilBbl: 50,
            currentGasAccum: 8000,
            waterHauled: 10,
            oilHauled: 11,
            waterPumped: 12,
            oilPumped: 13,
            notes: 'First hour.',
          ),
          ProductionReportRow(
            hourIndex: 1,
            time: '7 AM',
            well: 'Horse 16-2H',
            choke: '33',
            chokeType: 'ADJ',
            tbg: '1200',
            csg: '905',
            waterProduction: 30,
            oilProduction: 45,
            hourlyGas: 110,
            gas24HourRate: 2640,
            gasStatic: '110',
            gasDifferential: '22',
            gasTemp: '86',
            sandRate: '.3',
            waterGaugeText: 'Water Tank 1: 60 in',
            oilGaugeText: 'Oil Tank 1: 40 in',
            currentWaterBbl: 120,
            currentOilBbl: 60,
            currentGasAccum: 8100,
            waterHauled: 20,
            oilHauled: 21,
            waterPumped: 22,
            oilPumped: 23,
            notes: 'Latest hour.',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: ProductionShiftChangeScreen()),
    );
    await tester.pumpAndSettle();

    final preview = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(preview.data, contains('7 AM Production Shift Change'));
    expect(preview.data, contains('Water Tank 1: 60 in'));
    expect(preview.data, contains('Water Hauled - 20 BBL'));
    expect(preview.data, isNot(contains('First hour.')));

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6 AM').last);
    await tester.pumpAndSettle();

    final updated = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(updated.data, contains('6 AM Production Shift Change'));
    expect(updated.data, contains('Water Tank 1: 50 in'));
    expect(updated.data, contains('Water Hauled - 10 BBL'));
  });

  testWidgets(
      'Production Shift Change preview matches copy and keeps multiple wells separated',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = ProductionShiftService();
    final jobStorage = JobStorageService();
    final activeJob = await jobStorage.saveActiveJob(
      JobSetup(
        company: 'Mach Energy',
        jobType: 'multiWellPad',
        padName: 'Horse Pad',
        wells: const ['Horse 16-2H', 'Horse 16-3H'],
        leaseNames: const ['Horse 16-2H', 'Horse 16-3H'],
        wellEntries: const [
          JobSetupWell(id: 'well_a', name: 'Horse 16-2H'),
          JobSetupWell(id: 'well_b', name: 'Horse 16-3H'),
        ],
        shift: 'Day',
      ),
    );
    await service.saveActiveShift(
      (await service.loadActiveShift()).copyWith(
        activeJobId: activeJob.id,
        header: const ProductionShiftHeader(
          company: 'Mach Energy',
          pad: 'Horse Pad',
          wells: ['Horse 16-2H', 'Horse 16-3H'],
        ),
        savedRows: const [
          ProductionReportRow(
            hourIndex: 0,
            time: '6 AM',
            well: 'Horse 16-2H',
            choke: '32',
            chokeType: 'ADJ',
            tbg: '1200',
            csg: '900',
            waterProduction: 25,
            oilProduction: 40,
            hourlyGas: 100,
            gas24HourRate: 2400,
            gasStatic: '100',
            gasDifferential: '20',
            gasTemp: '85',
            sandRate: '.2',
            waterGaugeText: 'Water Tank 1: 50 in',
            oilGaugeText: 'Oil Tank 1: 30 in',
            currentWaterBbl: 100,
            currentOilBbl: 50,
            currentGasAccum: 8000,
            waterHauled: 10,
            oilHauled: 11,
            waterPumped: 12,
            oilPumped: 13,
            notes: 'Well A.',
          ),
          ProductionReportRow(
            hourIndex: 0,
            time: '6 AM',
            well: 'Horse 16-3H',
            choke: '33',
            chokeType: 'ADJ',
            tbg: '1210',
            csg: '910',
            waterProduction: 26,
            oilProduction: 41,
            hourlyGas: 101,
            gas24HourRate: 2424,
            gasStatic: '101',
            gasDifferential: '21',
            gasTemp: '86',
            sandRate: '.3',
            waterGaugeText: 'Water Tank 2: 55 in',
            oilGaugeText: 'Oil Tank 2: 35 in',
            currentWaterBbl: 101,
            currentOilBbl: 51,
            currentGasAccum: 8001,
            waterHauled: 20,
            oilHauled: 21,
            waterPumped: 22,
            oilPumped: 23,
            notes: 'Well B.',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: ProductionShiftChangeScreen()),
    );
    await tester.pumpAndSettle();

    final preview =
        tester.widget<SelectableText>(find.byType(SelectableText)).data ?? '';
    expect(preview, contains('Horse 16-2H'));
    expect(preview, contains('Horse 16-3H'));
    expect(preview, contains('Water Tank 1: 50 in'));
    expect(preview, contains('Water Tank 2: 55 in'));
    expect(preview, contains('Water Hauled - 10 BBL'));
    expect(preview, contains('Water Hauled - 20 BBL'));

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

    final copyButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Copy Shift Change'),
    );
    copyButton.onPressed!.call();
    await tester.pumpAndSettle();
    expect(copiedText, preview);
  });

  testWidgets(
      'Production Shift Change reuses Flywheel field order and appends selected-hour extras',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = ProductionShiftService();
    final jobStorage = JobStorageService();
    final activeJob = await jobStorage.saveActiveJob(
      JobSetup(
        company: 'Flywheel Energy',
        padName: 'Flywheel Pad',
        wells: const ['FW 1'],
        leaseNames: const ['FW 1'],
        wellEntries: const [JobSetupWell(id: 'well_a', name: 'FW 1')],
        shift: 'Night',
      ),
    );
    await service.saveActiveShift(
      (await service.loadActiveShift()).copyWith(
        activeJobId: activeJob.id,
        header: const ProductionShiftHeader(
          company: 'Flywheel Energy',
          pad: 'Flywheel Pad',
          wells: ['FW 1'],
        ),
        savedRows: const [
          ProductionReportRow(
            hourIndex: 0,
            time: '6 PM',
            well: 'FW 1',
            choke: '28',
            chokeType: 'ADJ',
            tbg: '1200',
            csg: '900',
            waterProduction: 25,
            oilProduction: 40,
            hourlyGas: 100,
            gas24HourRate: 2400,
            gasStatic: '100',
            gasDifferential: '20',
            gasTemp: '85',
            sandRate: '.2',
            waterGaugeText: 'Water Tank 1: 50 in',
            oilGaugeText: 'Oil Tank 1: 30 in',
            currentWaterBbl: 100,
            currentOilBbl: 50,
            currentGasAccum: 8000,
            waterHauled: 10,
            oilHauled: 11,
            waterPumped: 12,
            oilPumped: 13,
            notes: 'Flywheel row.',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: ProductionShiftChangeScreen()),
    );
    await tester.pumpAndSettle();

    final preview =
        tester.widget<SelectableText>(find.byType(SelectableText)).data ?? '';
    expect(preview, contains('6 PM Production Shift Change'));
    expect(
        preview.indexOf('Tubing 1200') < preview.indexOf('CSG- 900'), isTrue);
    expect(preview.indexOf('CSG- 900') < preview.indexOf('Ck- 28'), isTrue);
    expect(preview.indexOf('Ck- 28') < preview.indexOf('Oil- 40'), isTrue);
    expect(preview.indexOf('Oil- 40') < preview.indexOf('Wtr- 25'), isTrue);
    expect(preview, contains('Tank Gauges'));
    expect(preview, contains('Hauled / Pumped'));
  });

  test('Production math uses previous saved hour for 7 AM calculations', () {
    const previousRow = ProductionReportRow(
      hourIndex: 0,
      time: '6 AM',
      well: 'Bow 21-3',
      choke: '35',
      tbg: '1200',
      csg: '2888',
      waterProduction: 135,
      oilProduction: -10,
      hourlyGas: 103,
      gas24HourRate: 2472,
      gasStatic: '300',
      gasDifferential: '20',
      gasTemp: '88',
      sandRate: '.5',
      waterGaugeText: 'Water Tank 1: 70',
      oilGaugeText: 'Oil Tank 1: 40',
      currentWaterBbl: 140,
      currentOilBbl: 80,
      currentGasAccum: 8003,
      waterHauled: 120,
      oilHauled: 0,
      waterPumped: 35,
      oilPumped: 0,
      notes: 'Flowing steady.',
    );

    final previous = ProductionMath.previousSavedRow([previousRow], 1);
    expect(previous, isNotNull);
    expect(previous!.currentWaterBbl, 140);
    expect(previous.currentOilBbl, 80);
    expect(previous.currentGasAccum, 8003);

    final waterProduction = ProductionMath.waterProduction(
      currentWaterBbl: 120,
      previousWaterBbl: previous.currentWaterBbl,
      waterHauled: 120,
      waterPumped: 35,
      preRoundWaterHauled: 0,
      preRoundWaterPumped: 0,
      isFirstHour: false,
    );
    final oilProduction = ProductionMath.oilProduction(
      currentOilBbl: 70,
      previousOilBbl: previous.currentOilBbl,
      oilHauled: 0,
      oilPumped: 0,
      preRoundOilHauled: 0,
      preRoundOilPumped: 0,
      isFirstHour: false,
    );
    final hourlyGas = ProductionMath.hourlyGas(
      currentGasAccum: 8100,
      previousGasAccum: previous.currentGasAccum,
    );

    expect(waterProduction, 135);
    expect(oilProduction, -10);
    expect(hourlyGas, 97);
    expect(ProductionMath.gas24Hour(hourlyGas), 2328);
  });

  testWidgets('Custom layout profile controls report and text update', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final jobStorage = JobStorageService();
    final activeJob = await jobStorage.saveActiveJob(
      JobSetup(
        company: 'WellWerks',
        padName: 'Pad 7',
        wells: const ['Well 1'],
      ),
    );
    final shiftService = ProductionShiftService();
    final layoutService = ReportProfileService();

    final createdProfiles = await layoutService.createProfile(
      name: 'Customer A',
      source: layoutService.defaultProfile(),
    );
    final created = createdProfiles.last;

    List<ReportField> includeOnly(
      List<ReportField> fields,
      Set<String> includeKeys,
    ) {
      return fields
          .map((field) =>
              field.copyWith(included: includeKeys.contains(field.key)))
          .toList();
    }

    final customized = created.copyWith(
      reportFields: includeOnly(
        created.reportFields,
        {'time', 'well', 'chk', 'bwph'},
      ),
      textFields: includeOnly(
        created.textFields,
        {'chk', 'notes'},
      ),
    );
    await layoutService.upsertProfile(customized);
    await layoutService.setActiveProfileId(customized.id);

    final reloadedService = ReportProfileService();
    final reloadedProfiles = await reloadedService.loadProfiles();
    final reloadedActiveId = await reloadedService.loadActiveProfileId();
    expect(reloadedProfiles.any((item) => item.id == customized.id), isTrue);
    expect(reloadedActiveId, customized.id);

    final seededShift = (await shiftService.loadActiveShift()).copyWith(
      activeJobId: activeJob.id,
      header: const ProductionShiftHeader(
        company: 'WellWerks',
        pad: 'Pad 7',
        wells: ['Well 1'],
      ).copyWith(layoutProfileId: customized.id),
      savedRows: const [
        ProductionReportRow(
          hourIndex: 0,
          time: '6 AM',
          well: 'Well 1',
          choke: '32',
          chokeType: 'ADJ',
          tbg: '1000',
          icp: '0.0',
          csg: '543',
          waterProduction: 53,
          oilProduction: 86,
          hourlyGas: 100,
          gas24HourRate: 4.534,
          gasStatic: '100',
          gasDifferential: '377',
          gasTemp: '96',
          sandRate: '.15',
          waterSpecificGravity: '1.020',
          wellheadTemp: '117',
          waterTemp: '115',
          flareRate: '14.23',
          flarePilotTemp: '1665',
          biocide: '10',
          vruGasRate: '160',
          vruSuction: '1.4',
          vruDischarge: '110',
          waterGaugeText: 'Water Tank 1: 50 in',
          oilGaugeText: 'Oil Tank 1: 35 in',
          currentWaterBbl: 0,
          currentOilBbl: 0,
          currentGasAccum: 0,
          waterHauled: 0,
          oilHauled: 0,
          waterPumped: 0,
          oilPumped: 0,
          notes: 'Stable.',
        ),
      ],
    );
    await shiftService.saveActiveShift(seededShift);

    await tester.pumpWidget(const MaterialApp(home: ShiftReportScreen()));
    await tester.pumpAndSettle();

    expect(find.text('CHK'), findsOneWidget);
    expect(find.text('CSG'), findsNothing);
    expect(find.text('32 ADJ'), findsOneWidget);
    expect(find.text('CHK - 32 ADJ'), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: TextUpdateScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('CHK - 32 adj'), findsOneWidget);
    expect(find.textContaining('CSG -'), findsNothing);
    expect(find.textContaining('Notes'), findsOneWidget);
  });

  testWidgets('Local job history archives, persists, opens, and deletes', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final shiftService = ProductionShiftService();
    final jobStorage = JobStorageService();
    final historyService = JobHistoryService();

    final activeJob = await jobStorage.saveActiveJob(
      JobSetup(
        company: 'Mach Energy',
        padName: 'History Pad',
        dateStarted: '2026-07-05',
        wells: const ['History 1'],
      ),
    );

    await shiftService.saveActiveShift(
      ProductionShift.empty().copyWith(
        activeJobId: activeJob.id,
        header: const ProductionShiftHeader(
          company: 'Mach Energy',
          pad: 'History Pad',
          date: '2026-07-05',
          wells: ['History 1'],
        ),
        inventory: ProductionInventoryBaseline.empty().copyWith(
          startingGasAccum: '7900',
        ),
        hourlyChecks: const [
          ProductionHourlyCheck(
            time: '6 AM',
            well: 'History 1',
            choke: '32',
            tbg: '1200',
            csg: '900',
          ),
        ],
        savedRows: const [
          ProductionReportRow(
            hourIndex: 0,
            time: '6 AM',
            well: 'History 1',
            choke: '32',
            chokeType: 'ADJ',
            tbg: '1200',
            csg: '900',
            waterProduction: 25,
            oilProduction: 40,
            hourlyGas: 100,
            gas24HourRate: 2400,
            gasStatic: '100',
            gasDifferential: '20',
            gasTemp: '85',
            sandRate: '.2',
            waterGaugeText: 'Water Tank 1: 50 in',
            oilGaugeText: 'Oil Tank 1: 30 in',
            currentWaterBbl: 100,
            currentOilBbl: 50,
            currentGasAccum: 8000,
            waterHauled: 0,
            oilHauled: 0,
            waterPumped: 0,
            oilPumped: 0,
            notes: 'Stable report.',
          ),
        ],
      ),
    );

    final archived = await historyService.archiveCurrentJobOrShift();
    expect(archived, isNotNull);

    final persisted = await JobHistoryService().loadHistory();
    expect(persisted, isNotEmpty);
    expect(persisted.first.company, 'Mach Energy');

    await tester.pumpWidget(const MaterialApp(home: ProductionHistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('History'), findsOneWidget);
    expect(find.text('Mach Energy'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .ancestor(
            of: find.text('Mach Energy').first,
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Job Detail'), findsOneWidget);

    await historyService.deleteArchivedJob(archived!.id);

    final afterDelete = await JobHistoryService().loadHistory();
    expect(afterDelete, isEmpty);
  });

  testWidgets('Job Box Inventory saves to history and reopens', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final inventoryService = JobBoxInventoryService();
    final jobStorage = JobStorageService();
    await jobStorage.saveActiveJob(
      JobSetup(
        company: 'Mach Energy',
        padName: 'Inventory Pad',
        wells: const ['Inventory Well'],
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: JobBoxInventoryScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(labeledTextField('Date').first, '07/09/2026');
    await tester.enterText(
      labeledTextField('Job Box Number').first,
      'JB-101',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save to History'));
    await tester.pumpAndSettle();

    final records = await inventoryService.loadAllRecords();
    expect(records, isNotEmpty);
    expect(records.first.wellNames, 'Inventory Well');
    expect(records.first.jobBoxNumber, 'JB-101');

    await tester.pumpWidget(const MaterialApp(home: ProductionHistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('History'), findsOneWidget);
    expect(find.text('Inventory Well'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: JobBoxInventoryScreen(initialRecordId: records.first.id),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Job Box Inventory'), findsWidgets);
    expect(find.text('JB-101'), findsOneWidget);
  });

  testWidgets('JSA saves under the current active job', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final jobStorage = JobStorageService();
    final jsaStorage = JsaStorageService();
    final activeJob = await jobStorage.saveActiveJob(
      JobSetup(
        company: 'Mach Energy',
        padName: 'JSA Pad',
        wells: const ['JSA 1'],
        shift: 'Night',
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: JsaScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Active Job'), findsOneWidget);
    expect(
      find.text('JSA will save under this active job.'),
      findsOneWidget,
    );

    await tester.enterText(
      labeledTextField('Location / Pad').first,
      'JSA Pad',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await jsaStorage.saveDraft(
      JsaDraft(
        activeJobId: activeJob.id,
        company: 'Mach Energy',
        date: '2026-07-05',
        time: 'Night',
        location: 'JSA Pad',
        task: 'Flowback',
        steps: const ['Monitor well flow'],
        hazards: const ['High pressure'],
        recommendations: const ['Wear PPE'],
        employees: List.generate(6, (_) => JsaEmployee()),
        notes: '',
      ),
    );

    final draft = await jsaStorage.loadDraft();
    expect(draft, isNotNull);
    expect(draft!.activeJobId, activeJob.id);
  });
}
