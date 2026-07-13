import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/models/production_shift.dart';
import 'package:wellwerks/screens/shift_report_screen.dart';
import 'package:wellwerks/services/active_company_service.dart';
import 'package:wellwerks/services/job_storage_service.dart';
import 'package:wellwerks/services/production_shift_service.dart';

const _orderedSeriesIds = <String>[
  'tbg',
  'csg',
  'gasRate',
  'waterRate',
  'oilRate',
  'sandRate',
  'choke',
];

const _seriesColorById = <String, Color>{
  'tbg': Colors.yellow,
  'csg': Colors.red,
  'gasRate': Colors.green,
  'waterRate': Colors.blue,
  'oilRate': Colors.black,
  'sandRate': Colors.brown,
  'choke': Colors.orange,
};

Future<JobSetup> _seedActiveJob({
  String company = 'Mach Energy',
  String pad = 'Horse Pad',
  List<String> wells = const ['Horse 16-2H'],
}) async {
  final jobStorage = JobStorageService();
  return jobStorage.saveActiveJob(
    JobSetup(
      company: company,
      padName: pad,
      wells: wells,
      leaseNames: wells,
      wellEntries: [
        for (var i = 0; i < wells.length; i++)
          JobSetupWell(id: 'well_$i', name: wells[i]),
      ],
      shift: 'Day',
    ),
  );
}

Future<void> _seedShiftRows({
  required JobSetup activeJob,
  required List<ProductionReportRow> rows,
  String? shiftJobId,
}) async {
  final service = ProductionShiftService();
  final current = await service.loadActiveShift();
  await service.saveActiveShift(
    current.copyWith(
      activeJobId: shiftJobId ?? activeJob.id,
      header: ProductionShiftHeader(
        company: activeJob.company,
        pad: activeJob.padName,
        wells: activeJob.resolvedWellNames,
      ),
      savedRows: rows,
      inventory: current.inventory.copyWith(productionRows: rows),
    ),
  );
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: ShiftReportScreen()));
  await tester.pumpAndSettle();
}

Future<void> _openChartTab(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('production-report-tabs')),
      matching: find.text('Chart'),
    ),
  );
  await tester.pumpAndSettle();
  if (find
      .byKey(const Key('production-chart-source-note'))
      .evaluate()
      .isEmpty) {
    await tester.drag(find.byType(TabBarView), const Offset(-500, 0));
    await tester.pumpAndSettle();
  }
  expect(find.byKey(const Key('production-report-tab-chart')), findsOneWidget);
}

Future<void> _scrollToChart(WidgetTester tester) async {
  final chartScrollable = find.descendant(
    of: find.byKey(const Key('production-report-tab-chart')),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    find.byKey(const Key('production-line-chart')),
    280,
    scrollable: chartScrollable.first,
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _expectChartText(
  WidgetTester tester,
  String text,
) async {
  final chartScrollable = find.descendant(
    of: find.byKey(const Key('production-report-tab-chart')),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    find.text(text),
    240,
    scrollable: chartScrollable.first,
  );
  await tester.pumpAndSettle();
  expect(find.text(text), findsOneWidget);
}

FilterChip _seriesChip(WidgetTester tester, String id) {
  return tester.widget<FilterChip>(find.byKey(Key('chart-series-$id')));
}

Future<FilterChip> _visibleSeriesChip(WidgetTester tester, String id) async {
  final chartScrollable = find.descendant(
    of: find.byKey(const Key('production-report-tab-chart')),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    find.byKey(Key('chart-series-$id')),
    220,
    scrollable: chartScrollable.first,
  );
  await tester.pumpAndSettle();
  return _seriesChip(tester, id);
}

Future<void> _scrollToChartControls(WidgetTester tester) async {
  final chartScrollable = find.descendant(
    of: find.byKey(const Key('production-report-tab-chart')),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    find.byKey(const Key('chart-select-all')),
    -240,
    scrollable: chartScrollable.first,
  );
  await tester.pumpAndSettle();
}

ProductionReportRow _row({
  required int hourIndex,
  required String time,
  String well = 'Horse 16-2H',
  String tbg = '1200',
  String csg = '900',
  double water = 25,
  double oil = 40,
  double gas = 100,
  String sand = '.2',
  String choke = '28',
}) {
  return ProductionReportRow(
    hourIndex: hourIndex,
    time: time,
    well: well,
    choke: choke,
    chokeType: 'ADJ',
    tbg: tbg,
    csg: csg,
    waterProduction: water,
    oilProduction: oil,
    hourlyGas: gas,
    gas24HourRate: gas * 24,
    gasStatic: '100',
    gasDifferential: '20',
    gasTemp: '85',
    sandRate: sand,
    waterGaugeText: 'Water Tank 1: 50 in',
    oilGaugeText: 'Oil Tank 1: 30 in',
    currentWaterBbl: 100,
    currentOilBbl: 50,
    currentGasAccum: 8000,
    waterHauled: 10,
    oilHauled: 11,
    waterPumped: 12,
    oilPumped: 13,
    notes: 'Row $hourIndex',
  );
}

LineChart _chartWidget(WidgetTester tester) {
  return tester.widget<LineChart>(find.byType(LineChart));
}

Color _legendSeriesColor(WidgetTester tester, String id) {
  final legend = tester.widget<Chip>(find.byKey(Key('chart-legend-$id')));
  final avatar = legend.avatar;
  if (avatar is Container) {
    final decoration = avatar.decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      return decoration.color!;
    }
  }
  throw StateError('Legend avatar color not found for $id');
}

Color _lineDotColor(LineChartBarData bar) {
  final painter = bar.dotData.getDotPainter(const FlSpot(0, 0), 0, bar, 0);
  if (painter is FlDotCirclePainter) {
    return painter.color;
  }
  throw StateError('Unexpected dot painter type: ${painter.runtimeType}');
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ActiveCompanyService.instance.resetForTest();
  });

  testWidgets('Production Report contains Report and Chart tabs',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
      activeJob: job,
      rows: [_row(hourIndex: 0, time: '5 PM')],
    );

    await _pump(tester);

    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Chart'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);

    await _openChartTab(tester);
    await _scrollToChart(tester);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('Existing Production Report remains under Report tab',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
      activeJob: job,
      rows: [_row(hourIndex: 0, time: '5 PM')],
    );

    await _pump(tester);
    expect(find.byType(DataTable), findsOneWidget);
    await _openChartTab(tester);
    expect(find.byType(DataTable), findsNothing);
  });

  testWidgets('Chart reads from existing Production Report entries',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
      activeJob: job,
      rows: [
        _row(hourIndex: 0, time: '5 PM'),
        _row(hourIndex: 1, time: '6 PM'),
        _row(hourIndex: 2, time: '7 PM'),
      ],
    );

    await _pump(tester);
    await _openChartTab(tester);
    await _scrollToChart(tester);

    expect(find.textContaining('Tubing Pressure (3)'), findsOneWidget);
    expect(find.text('5 PM'), findsWidgets);
    expect(find.text('6 PM'), findsWidgets);
    expect(find.text('7 PM'), findsWidgets);
  });

  testWidgets('Hourly entries are ordered chronologically',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
      activeJob: job,
      rows: [
        _row(hourIndex: 2, time: '7 PM'),
        _row(hourIndex: 0, time: '5 PM'),
        _row(hourIndex: 1, time: '6 PM'),
      ],
    );

    await _pump(tester);
    await _openChartTab(tester);
    await _scrollToChart(tester);

    final lineChart = tester.widget<LineChart>(find.byType(LineChart));
    final firstSeries = lineChart.data.lineBarsData.first;
    expect(firstSeries.spots.map((spot) => spot.x).toList(), [0, 1, 2]);
  });

  testWidgets('Valid readings create connected line points',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
      activeJob: job,
      rows: [
        _row(hourIndex: 0, time: '5 PM'),
        _row(hourIndex: 1, time: '6 PM'),
      ],
    );

    await _pump(tester);
    await _openChartTab(tester);
    await _scrollToChart(tester);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.any((series) => series.spots.length >= 2),
        isTrue);
  });

  testWidgets('Blank values are skipped and not converted to zero',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
      activeJob: job,
      rows: [
        _row(hourIndex: 0, time: '5 PM', tbg: ''),
        _row(hourIndex: 1, time: '6 PM', tbg: '1200'),
      ],
    );

    await _pump(tester);
    await _openChartTab(tester);
    await _scrollToChart(tester);

    expect(find.textContaining('Tubing Pressure (1)'), findsOneWidget);
    expect(find.textContaining('Tubing Pressure (2)'), findsNothing);
  });

  testWidgets('Tubing Pressure visibility toggle works',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
        activeJob: job, rows: [_row(hourIndex: 0, time: '5 PM')]);
    await _pump(tester);
    await _openChartTab(tester);

    expect((await _visibleSeriesChip(tester, 'tbg')).selected, isTrue);
    await _tapVisible(tester, find.byKey(const Key('chart-series-tbg')));
    expect((await _visibleSeriesChip(tester, 'tbg')).selected, isFalse);
  });

  testWidgets('Casing Pressure visibility toggle works',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
        activeJob: job, rows: [_row(hourIndex: 0, time: '5 PM')]);
    await _pump(tester);
    await _openChartTab(tester);

    expect((await _visibleSeriesChip(tester, 'csg')).selected, isTrue);
    await _tapVisible(tester, find.byKey(const Key('chart-series-csg')));
    expect((await _visibleSeriesChip(tester, 'csg')).selected, isFalse);
  });

  testWidgets('Gas Rate visibility toggle works', (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
        activeJob: job, rows: [_row(hourIndex: 0, time: '5 PM')]);
    await _pump(tester);
    await _openChartTab(tester);

    expect((await _visibleSeriesChip(tester, 'gasRate')).selected, isTrue);
    await _tapVisible(tester, find.byKey(const Key('chart-series-gasRate')));
    expect((await _visibleSeriesChip(tester, 'gasRate')).selected, isFalse);
  });

  testWidgets('Water Rate visibility toggle works',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
        activeJob: job, rows: [_row(hourIndex: 0, time: '5 PM')]);
    await _pump(tester);
    await _openChartTab(tester);

    expect((await _visibleSeriesChip(tester, 'waterRate')).selected, isTrue);
    await _tapVisible(tester, find.byKey(const Key('chart-series-waterRate')));
    expect((await _visibleSeriesChip(tester, 'waterRate')).selected, isFalse);
  });

  testWidgets('Oil Rate visibility toggle works', (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
        activeJob: job, rows: [_row(hourIndex: 0, time: '5 PM')]);
    await _pump(tester);
    await _openChartTab(tester);

    expect((await _visibleSeriesChip(tester, 'oilRate')).selected, isTrue);
    await _tapVisible(tester, find.byKey(const Key('chart-series-oilRate')));
    expect((await _visibleSeriesChip(tester, 'oilRate')).selected, isFalse);
  });

  testWidgets('Sand Rate visibility toggle works', (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
        activeJob: job, rows: [_row(hourIndex: 0, time: '5 PM')]);
    await _pump(tester);
    await _openChartTab(tester);

    expect((await _visibleSeriesChip(tester, 'sandRate')).selected, isFalse);
    await _tapVisible(tester, find.byKey(const Key('chart-series-sandRate')));
    expect((await _visibleSeriesChip(tester, 'sandRate')).selected, isTrue);
  });

  testWidgets('Choke visibility toggle works', (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
        activeJob: job, rows: [_row(hourIndex: 0, time: '5 PM')]);
    await _pump(tester);
    await _openChartTab(tester);

    expect((await _visibleSeriesChip(tester, 'choke')).selected, isFalse);
    await _tapVisible(tester, find.byKey(const Key('chart-series-choke')));
    expect((await _visibleSeriesChip(tester, 'choke')).selected, isTrue);
  });

  testWidgets('Series visibility persists', (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
        activeJob: job, rows: [_row(hourIndex: 0, time: '5 PM')]);

    await _pump(tester);
    await _openChartTab(tester);
    await _tapVisible(tester, find.byKey(const Key('chart-series-tbg')));
    expect((await _visibleSeriesChip(tester, 'tbg')).selected, isFalse);

    await _pump(tester);
    await _openChartTab(tester);
    expect((await _visibleSeriesChip(tester, 'tbg')).selected, isFalse);
  });

  testWidgets('Chart uses only current report or active job data',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
      activeJob: job,
      shiftJobId: 'different-job-id',
      rows: [_row(hourIndex: 0, time: '5 PM', well: 'Other Well')],
    );

    await _pump(tester);
    await _openChartTab(tester);
    await _expectChartText(tester, 'No production readings available yet.');
  });

  testWidgets('Tooltip detail uses exact stored value and unit',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
      activeJob: job,
      rows: [_row(hourIndex: 0, time: '5 PM', tbg: '1245', gas: 103)],
    );

    await _pump(tester);
    await _openChartTab(tester);
    await _scrollToChart(tester);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineTouchData.enabled, isTrue);
    expect(chart.data.lineTouchData.touchTooltipData, isNotNull);
  });

  testWidgets('Empty state appears with no readings',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(activeJob: job, rows: const []);

    await _pump(tester);
    await _openChartTab(tester);
    await _expectChartText(tester, 'No production readings available yet.');
  });

  testWidgets('Single-reading state works', (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
      activeJob: job,
      rows: [_row(hourIndex: 0, time: '5 PM')],
    );

    await _pump(tester);
    await _openChartTab(tester);
    await _expectChartText(
      tester,
      'Only one reading is available. Add another reading to create a trend line.',
    );
  });

  testWidgets('Fixed series line colors match required mapping',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
      activeJob: job,
      rows: [
        _row(hourIndex: 0, time: '5 PM'),
        _row(hourIndex: 1, time: '6 PM'),
      ],
    );

    await _pump(tester);
    await _openChartTab(tester);
    await _tapVisible(tester, find.byKey(const Key('chart-select-all')));
    await _scrollToChart(tester);

    final chart = _chartWidget(tester);
    expect(chart.data.lineBarsData.length, 7);
    for (var i = 0; i < _orderedSeriesIds.length; i++) {
      final id = _orderedSeriesIds[i];
      expect(chart.data.lineBarsData[i].color, _seriesColorById[id]);
    }
  });

  testWidgets('Markers and legend use the same fixed series colors',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
      activeJob: job,
      rows: [
        _row(hourIndex: 0, time: '5 PM'),
        _row(hourIndex: 1, time: '6 PM'),
      ],
    );

    await _pump(tester);
    await _openChartTab(tester);
    await _tapVisible(tester, find.byKey(const Key('chart-select-all')));
    await _scrollToChart(tester);
    await _scrollToChartControls(tester);

    final chart = _chartWidget(tester);
    for (var i = 0; i < _orderedSeriesIds.length; i++) {
      final id = _orderedSeriesIds[i];
      expect(_lineDotColor(chart.data.lineBarsData[i]), _seriesColorById[id]);
      expect(_legendSeriesColor(tester, id), _seriesColorById[id]);
      expect(_seriesChip(tester, id).checkmarkColor, _seriesColorById[id]);
    }
  });

  testWidgets('Hide/show and selection order keep color assignments stable',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
      activeJob: job,
      rows: [
        _row(hourIndex: 0, time: '5 PM'),
        _row(hourIndex: 1, time: '6 PM'),
      ],
    );

    await _pump(tester);
    await _openChartTab(tester);
    await _tapVisible(tester, find.byKey(const Key('chart-select-all')));
    await _scrollToChart(tester);

    var colors = _chartWidget(tester)
        .data
        .lineBarsData
        .map((bar) => bar.color)
        .toList(growable: false);
    expect(
        colors, _orderedSeriesIds.map((id) => _seriesColorById[id]).toList());

    await _scrollToChartControls(tester);
    await _tapVisible(tester, find.byKey(const Key('chart-series-tbg')));
    await _scrollToChart(tester);
    colors = _chartWidget(tester)
        .data
        .lineBarsData
        .map((bar) => bar.color)
        .toList(growable: false);
    expect(colors, [
      _seriesColorById['csg'],
      _seriesColorById['gasRate'],
      _seriesColorById['waterRate'],
      _seriesColorById['oilRate'],
      _seriesColorById['sandRate'],
      _seriesColorById['choke'],
    ]);

    await _scrollToChartControls(tester);
    await _tapVisible(tester, find.byKey(const Key('chart-series-tbg')));
    await _scrollToChart(tester);
    colors = _chartWidget(tester)
        .data
        .lineBarsData
        .map((bar) => bar.color)
        .toList(growable: false);
    expect(
        colors, _orderedSeriesIds.map((id) => _seriesColorById[id]).toList());

    await _scrollToChartControls(tester);
    await _tapVisible(tester, find.byKey(const Key('chart-clear-all')));
    await _tapVisible(tester, find.byKey(const Key('chart-series-gasRate')));
    await _tapVisible(tester, find.byKey(const Key('chart-series-oilRate')));
    await _tapVisible(tester, find.byKey(const Key('chart-series-tbg')));
    await _tapVisible(tester, find.byKey(const Key('chart-series-choke')));
    await _scrollToChart(tester);
    colors = _chartWidget(tester)
        .data
        .lineBarsData
        .map((bar) => bar.color)
        .toList(growable: false);
    expect(colors, [
      _seriesColorById['tbg'],
      _seriesColorById['gasRate'],
      _seriesColorById['oilRate'],
      _seriesColorById['choke'],
    ]);
  });

  testWidgets('Tubing Pressure remains yellow and not purple',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
      activeJob: job,
      rows: [
        _row(hourIndex: 0, time: '5 PM'),
        _row(hourIndex: 1, time: '6 PM'),
      ],
    );

    await _pump(tester);
    await _openChartTab(tester);
    await _scrollToChart(tester);

    final tubingLineColor = _chartWidget(tester).data.lineBarsData.first.color;
    expect(tubingLineColor, Colors.yellow);
    expect(tubingLineColor, isNot(Colors.purple));
    expect(tubingLineColor, isNot(Colors.deepPurple));
  });

  testWidgets('Clearing report readings updates the chart',
      (WidgetTester tester) async {
    final job = await _seedActiveJob();
    await _seedShiftRows(
      activeJob: job,
      rows: [
        _row(hourIndex: 0, time: '5 PM'),
        _row(hourIndex: 1, time: '6 PM'),
      ],
    );

    await _pump(tester);
    await _openChartTab(tester);
    await _scrollToChart(tester);
    expect(_chartWidget(tester).data.lineBarsData.first.spots.length, 2);

    await _seedShiftRows(
      activeJob: job,
      rows: [_row(hourIndex: 1, time: '6 PM')],
    );
    await _pump(tester);
    await _openChartTab(tester);
    await _scrollToChart(tester);
    expect(_chartWidget(tester).data.lineBarsData.first.spots.length,
        lessThanOrEqualTo(2));
  });
}
