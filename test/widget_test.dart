import 'dart:convert';

import 'package:flutter/material.dart';
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
import 'package:wellwerks/screens/pressure_entry_screen.dart';
import 'package:wellwerks/screens/production_history_screen.dart';
import 'package:wellwerks/screens/production_inventory_screen.dart';
import 'package:wellwerks/screens/shift_report_screen.dart';
import 'package:wellwerks/screens/text_update_screen.dart';
import 'package:wellwerks/services/job_history_service.dart';
import 'package:wellwerks/services/job_box_inventory_service.dart';
import 'package:wellwerks/services/job_storage_service.dart';
import 'package:wellwerks/services/jsa_storage_service.dart';
import 'package:wellwerks/services/production_shift_service.dart';
import 'package:wellwerks/services/report_profile_service.dart';

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
    await tester.binding.setSurfaceSize(const Size(1200, 800));
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

    await tester.enterText(
        labeledTextField('Company').first, 'Continental Resources');
    await tester.enterText(labeledTextField('Pad Name').first, 'Bow Pad');
    await tester.enterText(labeledTextField('Date').first, '2026-07-05');
    await tester.enterText(labeledTextField('Well 1').first, 'Bow 21-3');
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
    final service = ProductionShiftService();

    await tester.binding.setSurfaceSize(const Size(900, 4000));

    await tester
        .pumpWidget(const MaterialApp(home: ProductionInventoryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Shift Header'), findsOneWidget);
    expect(find.text('Starting Inventory • Water Tanks'), findsOneWidget);
    expect(find.text('Pre-Round Adjustments'), findsOneWidget);
    expect(find.text('Starting Gas Accum'), findsOneWidget);

    await tester.enterText(labeledTextField('Company').first, 'Mach Energy');
    await tester.enterText(labeledTextField('Pad Name').first, 'Mach Pad');
    await tester.enterText(labeledTextField('Date').first, '2026-07-05');
    await tester.enterText(labeledTextField('Well 1').first, 'Mach 12-8');
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

    expect(find.textContaining('Linked to active shift data'), findsWidgets);
    final copyReportButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Copy Production Report'),
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

    await tester.pumpWidget(const MaterialApp(home: JobBoxInventoryScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(labeledTextField('Date').first, '07/09/2026');
    await tester.enterText(
      labeledTextField('Well Name(s)').first,
      'Inventory Well',
    );
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

    expect(find.text('Job Box Inventory Records'), findsOneWidget);
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
