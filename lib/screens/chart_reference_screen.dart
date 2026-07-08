import 'package:flutter/material.dart';

import '../data/tank_charts.dart';
import '../widgets/app_header.dart';

class ChartReferenceScreen extends StatefulWidget {
  const ChartReferenceScreen({
    super.key,
    required this.title,
    required this.description,
    this.sections = const [],
    this.showDataPlaceholder = false,
    this.enableSearch = false,
    this.showBrixTool = false,
    this.showChloridesCalculator = false,
  });

  factory ChartReferenceScreen.tankChart({
    Key? key,
    required String title,
    required TankChart chart,
    String? description,
  }) {
    return ChartReferenceScreen(
      key: key,
      title: title,
      description: description ??
          '${chart.name} reference values. Gauge in inches, volume in barrels.',
      enableSearch: true,
      sections: [
        ChartSection(
          title: chart.name,
          columns: const ['Gauge (in)', 'Volume (BBL)'],
          rows: chart.points
              .map((point) => [
                    point.inches.toStringAsFixed(0),
                    point.barrels.toStringAsFixed(1),
                  ])
              .toList(),
        ),
      ],
    );
  }

  const ChartReferenceScreen.productionTankReference({super.key})
      : title = 'Production Tank Chart',
        description =
            'Default production tank reference using 1.67 BBL/in. Use your site-specific factor when available.',
        sections = const [
          ChartSection(
            title: 'Production Tank Reference',
            columns: ['Gauge (in)', 'Volume (BBL)'],
            rows: [
              ['0', '0.0'],
              ['10', '16.7'],
              ['20', '33.4'],
              ['30', '50.1'],
              ['40', '66.8'],
              ['50', '83.5'],
              ['60', '100.2'],
              ['70', '116.9'],
              ['80', '133.6'],
              ['90', '150.3'],
              ['100', '167.0'],
              ['110', '183.7'],
              ['120', '200.4'],
            ],
          ),
        ],
        showDataPlaceholder = false,
        enableSearch = true,
        showBrixTool = false,
        showChloridesCalculator = false;

  factory ChartReferenceScreen.placeholder({
    Key? key,
    required String title,
    required String description,
  }) {
    return ChartReferenceScreen(
      key: key,
      title: title,
      description: description,
      showDataPlaceholder: true,
    );
  }

  final String title;
  final String description;
  final List<ChartSection> sections;
  final bool showDataPlaceholder;
  final bool enableSearch;
  final bool showBrixTool;
  final bool showChloridesCalculator;

  @override
  State<ChartReferenceScreen> createState() => _ChartReferenceScreenState();
}

class _ChartReferenceScreenState extends State<ChartReferenceScreen> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _brix = TextEditingController();
  final TextEditingController _chloridesBrixInput = TextEditingController();
  final TextEditingController _chloridesSpecificGravityInput =
      TextEditingController();
  final TextEditingController _chloridesSalinityInput = TextEditingController();
  String _sgResult = '--';
  String _chloridesInputType = 'Specific Gravity';
  ChloridesCalculationResult? _chloridesResult;
  String? _chloridesWarning;

  @override
  void dispose() {
    _search.dispose();
    _brix.dispose();
    _chloridesBrixInput.dispose();
    _chloridesSpecificGravityInput.dispose();
    _chloridesSalinityInput.dispose();
    super.dispose();
  }

  List<ChloridesTableEntry> get _chloridesEntries {
    for (final section in widget.sections) {
      final columns =
          section.columns.map((item) => item.toLowerCase()).toList();
      final hasSpecificGravity = columns.contains('sp.gr.');
      final hasPounds = columns.contains('#/g');
      if (!hasSpecificGravity || !hasPounds) {
        continue;
      }

      return section.rows
          .map(ChloridesTableEntry.fromRow)
          .whereType<ChloridesTableEntry>()
          .toList();
    }
    return const [];
  }

  List<List<String>> _filteredRows(List<List<String>> rows) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return rows;
    return rows
        .where((row) => row.any((cell) => cell.toLowerCase().contains(query)))
        .toList();
  }

  void _convertBrix() {
    final brix = double.tryParse(_brix.text.trim()) ?? 0;
    final sg = 1 + (brix / (258.6 - ((brix / 258.2) * 227.1)));
    setState(() => _sgResult = sg.toStringAsFixed(4));
  }

  void _calculateChlorides() {
    double? input;
    const String inputType = 'Specific Gravity';

    if (_chloridesInputType == 'Brix') {
      final brix = double.tryParse(_chloridesBrixInput.text.trim());
      if (brix != null) {
        input = 1 + (brix / (258.6 - ((brix / 258.2) * 227.1)));
      }
    } else if (_chloridesInputType == 'Salinity / PPT') {
      final salinity = double.tryParse(_chloridesSalinityInput.text.trim());
      if (salinity != null) {
        input = ChloridesCalculator.specificGravityFromSalinityPpt(salinity);
      }
    } else {
      input = double.tryParse(_chloridesSpecificGravityInput.text.trim());
    }

    if (input == null) {
      setState(() {
        _chloridesResult = null;
        _chloridesWarning = 'Enter a numeric value.';
      });
      return;
    }

    final result = ChloridesCalculator.interpolate(
      entries: _chloridesEntries,
      inputType: inputType,
      inputValue: input,
    );

    setState(() {
      _chloridesResult = result.result;
      _chloridesWarning = result.warning;
    });
  }

  String _formatOutput(double? value, {int decimals = 3}) {
    if (value == null) return 'N/A';
    return value.toStringAsFixed(decimals);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(title: widget.title, showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.description,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
          ),
          if (widget.showBrixTool)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Brix to Specific Gravity',
                      style: TextStyle(
                        color: Color(0xFFCDA56A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _brix,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Brix'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _convertBrix,
                      child: const Text('Convert'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Specific Gravity: $_sgResult',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (widget.showChloridesCalculator)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chlorides Calculator',
                      style: TextStyle(
                        color: Color(0xFFCDA56A),
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _chloridesInputType,
                      decoration:
                          const InputDecoration(labelText: 'Input Type'),
                      items: const [
                        DropdownMenuItem(
                          value: 'Brix',
                          child: Text('Brix'),
                        ),
                        DropdownMenuItem(
                          value: 'Specific Gravity',
                          child: Text('Specific Gravity'),
                        ),
                        DropdownMenuItem(
                          value: 'Salinity / PPT',
                          child: Text('Salinity / PPT'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _chloridesInputType = value;
                          _chloridesResult = null;
                          _chloridesWarning = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_chloridesInputType == 'Brix')
                      TextField(
                        controller: _chloridesBrixInput,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Brix',
                        ),
                        onChanged: (_) {
                          setState(() {
                            _chloridesResult = null;
                            _chloridesWarning = null;
                          });
                        },
                      )
                    else if (_chloridesInputType == 'Specific Gravity')
                      TextField(
                        controller: _chloridesSpecificGravityInput,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Specific Gravity',
                        ),
                        onChanged: (_) {
                          setState(() {
                            _chloridesResult = null;
                            _chloridesWarning = null;
                          });
                        },
                      )
                    else
                      TextField(
                        controller: _chloridesSalinityInput,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Salinity / PPT',
                        ),
                        onChanged: (_) {
                          setState(() {
                            _chloridesResult = null;
                            _chloridesWarning = null;
                          });
                        },
                      ),
                    if (_chloridesInputType == 'Salinity / PPT') ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Salinity / PPT uses the right-side refractometer scale.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _calculateChlorides,
                      child: const Text('Calculate'),
                    ),
                    if (_chloridesWarning != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _chloridesWarning!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _ResultLine(
                      label: 'Specific Gravity',
                      value: _formatOutput(_chloridesResult?.specificGravity,
                          decimals: 4),
                    ),
                    _ResultLine(
                      label: 'Pounds',
                      value: _formatOutput(_chloridesResult?.poundsPerGallon,
                          decimals: 2),
                    ),
                    _ResultLine(
                      label: 'Chlorides / ppm',
                      value: _formatOutput(_chloridesResult?.chloridesPpm,
                          decimals: 0),
                    ),
                  ],
                ),
              ),
            ),
          if (widget.enableSearch)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search Chart',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
            ),
          if (widget.showDataPlaceholder)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Chart data needs to be added.',
                  style: TextStyle(
                    color: Color(0xFFCDA56A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          for (final section in widget.sections) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (section.title.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          section.title,
                          style: const TextStyle(
                            color: Color(0xFFCDA56A),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: [
                          for (final col in section.columns)
                            DataColumn(label: Text(col)),
                        ],
                        rows: [
                          for (final row in _filteredRows(section.rows))
                            DataRow(
                              cells: [
                                for (final cell in row) DataCell(Text(cell)),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ChartRow {
  const ChartRow({required this.left, required this.right});

  final String left;
  final String right;
}

class ChartSection {
  const ChartSection({
    required this.title,
    required this.columns,
    required this.rows,
  });

  final String title;
  final List<String> columns;
  final List<List<String>> rows;
}

class ChloridesTableEntry {
  const ChloridesTableEntry({
    required this.specificGravity,
    required this.poundsPerGallon,
    required this.chloridesPpm,
  });

  factory ChloridesTableEntry.fromRow(List<String> row) {
    double? parseAt(int index) {
      if (index >= row.length) return null;
      return double.tryParse(row[index].trim());
    }

    return ChloridesTableEntry(
      specificGravity: parseAt(0),
      poundsPerGallon: parseAt(1),
      chloridesPpm: parseAt(2),
    );
  }

  final double? specificGravity;
  final double? poundsPerGallon;
  final double? chloridesPpm;
}

class ChloridesCalculationResult {
  const ChloridesCalculationResult({
    this.specificGravity,
    this.poundsPerGallon,
    this.chloridesPpm,
  });

  final double? specificGravity;
  final double? poundsPerGallon;
  final double? chloridesPpm;
}

class ChloridesInterpolationResponse {
  const ChloridesInterpolationResponse({this.result, this.warning});

  final ChloridesCalculationResult? result;
  final String? warning;
}

class ChloridesCalculator {
  static double specificGravityFromSalinityPpt(double salinityPpt) {
    final s = salinityPpt < 0 ? 0 : salinityPpt;
    // Practical field approximation for brine/seawater refractometer salinity.
    return 1 + (0.00078 * s) + (0.0000003 * s * s);
  }

  static ChloridesInterpolationResponse interpolate({
    required List<ChloridesTableEntry> entries,
    required String inputType,
    required double inputValue,
  }) {
    if (entries.isEmpty) {
      return const ChloridesInterpolationResponse(
        warning: 'N/A',
      );
    }

    final sorted = List<ChloridesTableEntry>.from(entries)
      ..sort((a, b) {
        final aValue = inputType == 'Pounds'
            ? (a.poundsPerGallon ?? double.infinity)
            : (a.specificGravity ?? double.infinity);
        final bValue = inputType == 'Pounds'
            ? (b.poundsPerGallon ?? double.infinity)
            : (b.specificGravity ?? double.infinity);
        return aValue.compareTo(bValue);
      });

    double? xOf(ChloridesTableEntry item) =>
        inputType == 'Pounds' ? item.poundsPerGallon : item.specificGravity;

    final candidates = sorted.where((item) => xOf(item) != null).toList();
    if (candidates.isEmpty) {
      return const ChloridesInterpolationResponse(warning: 'N/A');
    }

    final min = xOf(candidates.first)!;
    final max = xOf(candidates.last)!;
    if (inputValue < min || inputValue > max) {
      return const ChloridesInterpolationResponse(
        warning: 'Value is outside chart range.',
      );
    }

    for (final item in candidates) {
      final x = xOf(item)!;
      if ((x - inputValue).abs() < 0.0000001) {
        return ChloridesInterpolationResponse(
          result: ChloridesCalculationResult(
            specificGravity: item.specificGravity,
            poundsPerGallon: item.poundsPerGallon,
            chloridesPpm: item.chloridesPpm,
          ),
        );
      }
    }

    for (int i = 0; i < candidates.length - 1; i++) {
      final lower = candidates[i];
      final upper = candidates[i + 1];
      final lowerX = xOf(lower)!;
      final upperX = xOf(upper)!;
      if (inputValue <= upperX) {
        final t = (inputValue - lowerX) / (upperX - lowerX);
        double? lerp(double? a, double? b) {
          if (a == null || b == null) return null;
          return a + ((b - a) * t);
        }

        return ChloridesInterpolationResponse(
          result: ChloridesCalculationResult(
            specificGravity: inputType == 'Specific Gravity'
                ? inputValue
                : lerp(lower.specificGravity, upper.specificGravity),
            poundsPerGallon: inputType == 'Pounds'
                ? inputValue
                : lerp(lower.poundsPerGallon, upper.poundsPerGallon),
            chloridesPpm: lerp(lower.chloridesPpm, upper.chloridesPpm),
          ),
        );
      }
    }

    return const ChloridesInterpolationResponse(
      warning: 'Value is outside chart range.',
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}
