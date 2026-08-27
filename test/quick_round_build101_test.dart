import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/models/production_shift.dart';
import 'package:wellwerks/screens/pressure_entry_screen.dart';
import 'package:wellwerks/screens/shift_report_screen.dart';
import 'package:wellwerks/services/active_company_service.dart';
import 'package:wellwerks/services/job_storage_service.dart';
import 'package:wellwerks/services/production_shift_service.dart';
import 'package:wellwerks/services/round_storage_service.dart';

Finder _labeledTextField(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
    description: 'TextField with label $label',
  );
}

Finder _labeledDropdownField(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == label,
    description: 'DropdownButtonFormField with label $label',
  );
}

Future<void> _seedJobAndShift({
  required List<String> wells,
  Map<String, String> selectedChokes = const {},
  Map<String, String> selectedChokeTypes = const {},
  List<ProductionReportRow> savedRows = const [],
}) async {
  final jobStorage = JobStorageService();
  final service = ProductionShiftService();
  final activeJob = await jobStorage.saveActiveJob(
    JobSetup(
      company: 'Mach Energy',
      padName: 'Horse Pad',
      wells: wells,
      productionGaugeType: 'inches',
      leaseNames: wells,
      shift: 'Day',
      wellEntries: [
        for (var i = 0; i < wells.length; i++)
          JobSetupWell(id: 'w$i', name: wells[i]),
      ],
    ),
  );

  final base = await service.loadActiveShift();
  final checks = [
    ProductionHourlyCheck(
      time: '6 AM',
      well: wells.first,
      wellChecks: {
        for (final well in wells)
          well: ProductionWellCheckData(
            choke: selectedChokes[well] ?? '',
            chokeType: selectedChokeTypes[well] ?? 'ADJ',
          ),
      },
    ),
    ProductionHourlyCheck(
      time: '7 AM',
      well: wells.first,
      wellChecks: {
        for (final well in wells)
          well: ProductionWellCheckData(
            choke: selectedChokes[well] ?? '',
            chokeType: selectedChokeTypes[well] ?? 'ADJ',
          ),
      },
    ),
  ];

  await service.saveActiveShift(
    base.copyWith(
      activeJobId: activeJob.id,
      roundStartTime: '6 AM',
      checkCount: 2,
      header: ProductionShiftHeader(
        company: 'Mach Energy',
        pad: 'Horse Pad',
        wells: wells,
      ),
      inventory: base.inventory.copyWith(
        gaugeEntryType: 'inches',
        waterTanks: const [
          ProductionTank(name: 'Water Tank 1', gauge: '80', bblPerInch: '1.0'),
        ],
        oilTanks: const [
          ProductionTank(name: 'Oil Tank 1', gauge: '45', bblPerInch: '1.0'),
        ],
        startingGasAccum: '7900',
        useStartingReadings: true,
        productionRows: savedRows,
      ),
      hourlyChecks: checks,
      savedRows: savedRows,
      wellSelectedChokes: selectedChokes,
      wellSelectedChokeTypes: selectedChokeTypes,
    ),
  );
}

Future<void> _openQuickRound(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 7000));
  await tester.pumpWidget(const MaterialApp(home: PressureEntryScreen()));
  await tester.pumpAndSettle();
}

Future<void> _saveCurrentHour(WidgetTester tester, String hourLabel,
    {required String gasAccum,
    required String waterGauge,
    required String oilGauge,
    String tbg = '1200',
    String csg = '900'}) async {
  await tester.enterText(_labeledTextField('TBG').first, tbg);
  await tester.enterText(_labeledTextField('CSG').first, csg);
  await tester.enterText(
      _labeledTextField('Current Gas Accum').first, gasAccum);
  await tester.enterText(
      _labeledTextField('Current Gauge (in)').at(0), waterGauge);
  await tester.enterText(
      _labeledTextField('Current Gauge (in)').at(1), oilGauge);
  await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Save $hourLabel Round').first);
  await tester
      .tap(find.widgetWithText(FilledButton, 'Save $hourLabel Round').first);
  await tester.pumpAndSettle();
}

Future<void> _openChokeSelector(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Select').first);
  await tester.pumpAndSettle();
}

Future<void> _confirmChokeSelection(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
  await tester.pumpAndSettle();
}

Future<void> _chooseClearChoke(WidgetTester tester) async {
  final picker = find.byType(CupertinoPicker).first;
  await tester.drag(picker, const Offset(0, 2000));
  await tester.pumpAndSettle();
  await _confirmChokeSelection(tester);
}

Future<void> _chooseDifferentChoke(WidgetTester tester) async {
  final picker = find.byType(CupertinoPicker).first;
  await tester.drag(picker, const Offset(0, -220));
  await tester.pumpAndSettle();
  await _confirmChokeSelection(tester);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ActiveCompanyService.instance.resetForTest();
  });

  testWidgets('Hours Since Previous Reading is no longer shown',
      (WidgetTester tester) async {
    await _seedJobAndShift(wells: const ['Horse 16-2H']);
    await _openQuickRound(tester);

    expect(find.text('Hours Since Previous Reading'), findsNothing);
    expect(
      find.text('Required after the first saved reading for this well.'),
      findsNothing,
    );

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Quick Round saves without hours since previous reading',
      (WidgetTester tester) async {
    final service = ProductionShiftService();
    await _seedJobAndShift(wells: const ['Horse 16-2H']);
    await _openQuickRound(tester);

    await _saveCurrentHour(
      tester,
      '6 AM',
      gasAccum: '8003',
      waterGauge: '70',
      oilGauge: '40',
    );

    await tester
        .tap(find.widgetWithText(FilledButton, 'Next Hour (7 AM)').first);
    await tester.pumpAndSettle();

    await _saveCurrentHour(
      tester,
      '7 AM',
      gasAccum: '8100',
      waterGauge: '60',
      oilGauge: '35',
    );

    final saved = await service.loadActiveShift();
    expect(saved.savedRows.length, 2);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Choke persists after saving and changing hours',
      (WidgetTester tester) async {
    await _seedJobAndShift(
      wells: const ['Horse 16-2H'],
      selectedChokes: const {'Horse 16-2H': '32/64"'},
      selectedChokeTypes: const {'Horse 16-2H': 'ADJ'},
    );
    await _openQuickRound(tester);

    expect(find.textContaining('32/64"'), findsWidgets);

    await _saveCurrentHour(
      tester,
      '6 AM',
      gasAccum: '8003',
      waterGauge: '70',
      oilGauge: '40',
    );
    await tester
        .tap(find.widgetWithText(FilledButton, 'Next Hour (7 AM)').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('32/64"'), findsWidgets);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Tank gauges carry forward to next hour until changed',
      (WidgetTester tester) async {
    await _seedJobAndShift(wells: const ['Horse 16-2H']);
    await _openQuickRound(tester);

    await _saveCurrentHour(
      tester,
      '6 AM',
      gasAccum: '8003',
      waterGauge: '70',
      oilGauge: '40',
    );

    await tester
        .tap(find.widgetWithText(FilledButton, 'Next Hour (7 AM)').first);
    await tester.pumpAndSettle();

    final waterField =
        tester.widget<TextField>(_labeledTextField('Current Gauge (in)').at(0));
    final oilField =
        tester.widget<TextField>(_labeledTextField('Current Gauge (in)').at(1));

    expect(waterField.controller?.text, '70');
    expect(oilField.controller?.text, '40');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
      'Quick Round carries ICP, wellhead temp, water specific gravity, and sand info to next hour',
      (WidgetTester tester) async {
    await _seedJobAndShift(wells: const ['Horse 16-2H']);
    await _openQuickRound(tester);

    await tester.enterText(_labeledTextField('ICP').first, '1150');
    await tester.enterText(
      _labeledTextField('Water Specific Gravity').first,
      '1.08',
    );
    await tester.enterText(
      _labeledTextField('Wellhead Temperature').first,
      '92',
    );

    await tester.tap(_labeledDropdownField('Sand Amount').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heavy').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      _labeledTextField('Prop / Sand Optional Rate').first,
      '2.5',
    );

    await _saveCurrentHour(
      tester,
      '6 AM',
      gasAccum: '8003',
      waterGauge: '70',
      oilGauge: '40',
    );

    await tester
        .tap(find.widgetWithText(FilledButton, 'Next Hour (7 AM)').first);
    await tester.pumpAndSettle();

    final icpField = tester.widget<TextField>(_labeledTextField('ICP').first);
    final sgField = tester
        .widget<TextField>(_labeledTextField('Water Specific Gravity').first);
    final whtField = tester
        .widget<TextField>(_labeledTextField('Wellhead Temperature').first);
    final sandOptionalField = tester.widget<TextField>(
        _labeledTextField('Prop / Sand Optional Rate').first);
    final sandDropdown = tester.widget<DropdownButtonFormField<String>>(
      _labeledDropdownField('Sand Amount').first,
    );

    expect(icpField.controller?.text, '1150');
    expect(sgField.controller?.text, '1.08');
    expect(whtField.controller?.text, '92');
    expect(sandOptionalField.controller?.text, '2.5');
    expect(sandDropdown.initialValue, '4');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Choke persists after leaving and reopening Quick Round',
      (WidgetTester tester) async {
    await _seedJobAndShift(
      wells: const ['Horse 16-2H'],
      selectedChokes: const {'Horse 16-2H': '32/64"'},
      selectedChokeTypes: const {'Horse 16-2H': 'ADJ'},
    );

    await _openQuickRound(tester);
    expect(find.textContaining('32/64"'), findsWidgets);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    await _openQuickRound(tester);
    expect(find.textContaining('32/64"'), findsWidgets);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Choke persists after app persistence reload',
      (WidgetTester tester) async {
    final service = ProductionShiftService();
    await _seedJobAndShift(
      wells: const ['Horse 16-2H'],
      selectedChokes: const {'Horse 16-2H': '32/64"'},
      selectedChokeTypes: const {'Horse 16-2H': 'ADJ'},
    );

    await _openQuickRound(tester);
    final shift = await service.loadActiveShift();
    expect(shift.wellSelectedChokes['Horse 16-2H'], '32/64"');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Choke persistence is separate per well',
      (WidgetTester tester) async {
    final service = ProductionShiftService();
    await _seedJobAndShift(
      wells: const ['Horse 16-2H', 'Horse 16-3H'],
      selectedChokes: const {
        'Horse 16-2H': '32/64"',
        'Horse 16-3H': '36/64"',
      },
      selectedChokeTypes: const {
        'Horse 16-2H': 'ADJ',
        'Horse 16-3H': 'ADJ',
      },
    );

    await _openQuickRound(tester);
    expect(find.textContaining('32/64"'), findsWidgets);

    final shift = await service.loadActiveShift();
    await service.saveActiveShift(
      shift.copyWith(
        hourlyChecks: shift.hourlyChecks
            .map((check) => check.copyWith(well: 'Horse 16-3H'))
            .toList(growable: false),
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    await _openQuickRound(tester);
    expect(find.textContaining('36/64"'), findsWidgets);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Changing choke updates only the selected well',
      (WidgetTester tester) async {
    final service = ProductionShiftService();
    await _seedJobAndShift(
      wells: const ['Horse 16-2H', 'Horse 16-3H'],
      selectedChokes: const {
        'Horse 16-2H': '32/64"',
        'Horse 16-3H': '36/64"',
      },
      selectedChokeTypes: const {
        'Horse 16-2H': 'ADJ',
        'Horse 16-3H': 'ADJ',
      },
    );

    await _openQuickRound(tester);
    await _openChokeSelector(tester);
    await _chooseDifferentChoke(tester);

    final shift = await service.loadActiveShift();
    expect(shift.wellSelectedChokes['Horse 16-2H'], isNot('32/64"'));
    expect(shift.wellSelectedChokes['Horse 16-3H'], '36/64"');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('None / Clear clears only selected well choke',
      (WidgetTester tester) async {
    final service = ProductionShiftService();
    await _seedJobAndShift(
      wells: const ['Horse 16-2H', 'Horse 16-3H'],
      selectedChokes: const {
        'Horse 16-2H': '32/64"',
        'Horse 16-3H': '36/64"',
      },
      selectedChokeTypes: const {
        'Horse 16-2H': 'ADJ',
        'Horse 16-3H': 'ADJ',
      },
    );

    await _openQuickRound(tester);
    await _openChokeSelector(tester);
    await _chooseClearChoke(tester);

    final shift = await service.loadActiveShift();
    expect(shift.wellSelectedChokes.containsKey('Horse 16-2H'), isFalse);
    expect(shift.wellSelectedChokes['Horse 16-3H'], '36/64"');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Historical saved readings keep original choke values',
      (WidgetTester tester) async {
    final service = ProductionShiftService();
    await _seedJobAndShift(
      wells: const ['Horse 16-2H'],
      selectedChokes: const {'Horse 16-2H': '36/64"'},
      selectedChokeTypes: const {'Horse 16-2H': 'ADJ'},
      savedRows: const [
        ProductionReportRow(
          hourIndex: 0,
          time: '9 AM',
          well: 'Horse 16-2H',
          choke: '32',
          chokeType: 'ADJ',
          tbg: '1200',
          csg: '900',
          waterProduction: 10,
          oilProduction: 10,
          hourlyGas: 10,
          gas24HourRate: 240,
          gasStatic: '100',
          gasDifferential: '20',
          gasTemp: '80',
          sandRate: '.1',
          waterGaugeText: 'W1',
          oilGaugeText: 'O1',
          currentWaterBbl: 100,
          currentOilBbl: 50,
          currentGasAccum: 8000,
          waterHauled: 0,
          oilHauled: 0,
          waterPumped: 0,
          oilPumped: 0,
          notes: '',
        ),
        ProductionReportRow(
          hourIndex: 1,
          time: '10 AM',
          well: 'Horse 16-2H',
          choke: '32',
          chokeType: 'ADJ',
          tbg: '1200',
          csg: '900',
          waterProduction: 10,
          oilProduction: 10,
          hourlyGas: 10,
          gas24HourRate: 240,
          gasStatic: '100',
          gasDifferential: '20',
          gasTemp: '80',
          sandRate: '.1',
          waterGaugeText: 'W1',
          oilGaugeText: 'O1',
          currentWaterBbl: 100,
          currentOilBbl: 50,
          currentGasAccum: 8000,
          waterHauled: 0,
          oilHauled: 0,
          waterPumped: 0,
          oilPumped: 0,
          notes: '',
        ),
      ],
    );

    await _openQuickRound(tester);
    await _openChokeSelector(tester);
    await _chooseClearChoke(tester);

    final shift = await service.loadActiveShift();
    expect(shift.savedRows.length, 2);
    expect(shift.savedRows[0].choke, '32');
    expect(shift.savedRows[1].choke, '32');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Multi-well quick round shows all wells and saves separate rows',
      (WidgetTester tester) async {
    final service = ProductionShiftService();
    final roundStorage = RoundStorageService();
    await _seedJobAndShift(wells: const ['Horse 16-2H', 'Horse 16-3H']);
    await _openQuickRound(tester);

    expect(find.textContaining('Horse 16-2H'), findsWidgets);
    expect(find.textContaining('Horse 16-3H'), findsWidgets);

    await tester.enterText(_labeledTextField('TBG').at(0), '1200');
    await tester.enterText(_labeledTextField('CSG').at(0), '900');
    await tester.enterText(
      _labeledTextField('Current Gas Accum').first,
      '8003',
    );
    await tester.enterText(_labeledTextField('Current Gauge (in)').at(0), '70');
    await tester.enterText(_labeledTextField('Current Gauge (in)').at(1), '40');
    await tester
        .tap(find.widgetWithText(FilledButton, 'Save 6 AM Round').first);
    await tester.pumpAndSettle();

    await tester.enterText(_labeledTextField('TBG').at(1), '1210');
    await tester.enterText(_labeledTextField('CSG').at(1), '910');
    await tester.enterText(
      _labeledTextField('Current Gas Accum').first,
      '8010',
    );
    await tester.enterText(_labeledTextField('Current Gauge (in)').at(0), '69');
    await tester.enterText(_labeledTextField('Current Gauge (in)').at(1), '39');

    await tester
        .tap(find.widgetWithText(FilledButton, 'Save 6 AM Round').first);
    await tester.pumpAndSettle();

    final shift = await service.loadActiveShift();
    final hourRows =
        shift.savedRows.where((row) => row.hourIndex == 0).toList();
    expect(hourRows.length, 2);
    expect(hourRows.map((row) => row.well).toSet(),
        {'Horse 16-2H', 'Horse 16-3H'});

    final savedReadings = await roundStorage.loadReadings();
    final roundReadings =
        savedReadings.where((reading) => reading.roundLabel == '6 AM').toList();
    expect(roundReadings.length, 2);
    expect(roundReadings[0].timestamp, roundReadings[1].timestamp);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Production Report chart choke series remains available',
      (WidgetTester tester) async {
    final service = ProductionShiftService();
    await _seedJobAndShift(
      wells: const ['Horse 16-2H'],
      savedRows: const [
        ProductionReportRow(
          hourIndex: 0,
          time: '9 AM',
          well: 'Horse 16-2H',
          choke: '32',
          chokeType: 'ADJ',
          tbg: '1200',
          csg: '900',
          waterProduction: 10,
          oilProduction: 10,
          hourlyGas: 10,
          gas24HourRate: 240,
          gasStatic: '100',
          gasDifferential: '20',
          gasTemp: '80',
          sandRate: '.1',
          waterGaugeText: 'W1',
          oilGaugeText: 'O1',
          currentWaterBbl: 100,
          currentOilBbl: 50,
          currentGasAccum: 8000,
          waterHauled: 0,
          oilHauled: 0,
          waterPumped: 0,
          oilPumped: 0,
          notes: '',
        ),
        ProductionReportRow(
          hourIndex: 1,
          time: '10 AM',
          well: 'Horse 16-2H',
          choke: '36',
          chokeType: 'ADJ',
          tbg: '1210',
          csg: '910',
          waterProduction: 10,
          oilProduction: 10,
          hourlyGas: 10,
          gas24HourRate: 240,
          gasStatic: '100',
          gasDifferential: '20',
          gasTemp: '80',
          sandRate: '.1',
          waterGaugeText: 'W1',
          oilGaugeText: 'O1',
          currentWaterBbl: 100,
          currentOilBbl: 50,
          currentGasAccum: 8100,
          waterHauled: 0,
          oilHauled: 0,
          waterPumped: 0,
          oilPumped: 0,
          notes: '',
        ),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(900, 7000));
    await tester.pumpWidget(const MaterialApp(home: ShiftReportScreen()));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('production-report-tabs')),
        matching: find.text('Chart'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chart-series-choke')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('chart-series-choke')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chart-series-choke')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('production-line-chart')), findsOneWidget);

    final shift = await service.loadActiveShift();
    expect(shift.savedRows.map((row) => row.choke).toList(), ['32', '36']);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
