import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

class BottomsUpScreen extends StatefulWidget {
  const BottomsUpScreen({super.key});

  @override
  State<BottomsUpScreen> createState() => _BottomsUpScreenState();
}

class _PipeOption {
  final String label;
  final double capacity;
  final bool custom;

  const _PipeOption(this.label, this.capacity, {this.custom = false});
}

class _SizeOption {
  final String label;

  const _SizeOption(this.label);
}

class _BottomsUpScreenState extends State<BottomsUpScreen> {
  static const _gold = Color(0xFFCDA56A);

  static const _tubingSizes = <_PipeOption>[
    _PipeOption('2-3/8" EUE', 0.00387),
    _PipeOption('2-7/8" EUE', 0.00579),
    _PipeOption('3-1/2"', 0.00870),
    _PipeOption('4-1/2"', 0.01422),
    _PipeOption('5"', 0.01730),
    _PipeOption('5-1/2"', 0.02000),
    _PipeOption('7"', 0.03640),
    _PipeOption('9-5/8"', 0.07400),
    _PipeOption('Custom Capacity', 0, custom: true),
  ];

  static const _casingSizes = <_SizeOption>[
    _SizeOption('4-1/2" Casing'),
    _SizeOption('5" Casing'),
    _SizeOption('5-1/2" Casing'),
    _SizeOption('7" Casing'),
    _SizeOption('9-5/8" Casing'),
  ];

  _PipeOption selectedTubing = _tubingSizes[1];
  _SizeOption selectedCasing = _casingSizes[2];

  final capacity = TextEditingController(
    text: _tubingSizes[1].capacity.toStringAsFixed(5),
  );
  final length = TextEditingController();
  final pumpRate = TextEditingController();
  final lagFactor = TextEditingController(text: '1.00');

  double get _capacity => double.tryParse(capacity.text.trim()) ?? 0;
  double get _length => double.tryParse(length.text.trim()) ?? 0;
  double get _pumpRate => double.tryParse(pumpRate.text.trim()) ?? 0;
  double get _lag => double.tryParse(lagFactor.text.trim()) ?? 1.0;

  double? get pipeVolume {
    if (_capacity <= 0 || _length <= 0) return null;
    return _capacity * _length * (_lag <= 0 ? 1.0 : _lag);
  }

  double? get bottomsUpMinutes {
    final volume = pipeVolume;
    if (volume == null || _pumpRate <= 0) return null;
    return volume / _pumpRate;
  }

  String get arrivalTime {
    final mins = bottomsUpMinutes;
    if (mins == null) return '--';
    final eta = DateTime.now().add(Duration(seconds: (mins * 60).round()));
    return DateFormat('h:mm a').format(eta);
  }

  String get hourMinuteText {
    final mins = bottomsUpMinutes;
    if (mins == null) return '--';
    final totalMinutes = mins.round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return hours > 0 ? '$hours hr $minutes min' : '$minutes min';
  }

  @override
  void initState() {
    super.initState();
    for (final controller in [capacity, length, pumpRate, lagFactor]) {
      controller.addListener(() => setState(() {}));
    }
  }

  void _selectTubing(_PipeOption pipe) {
    setState(() {
      selectedTubing = pipe;
      if (!pipe.custom) {
        capacity.text = pipe.capacity.toStringAsFixed(5);
      } else {
        capacity.clear();
      }
    });
  }

  void _selectCasing(_SizeOption casing) {
    setState(() => selectedCasing = casing);
  }

  void clearAll() {
    setState(() {
      selectedTubing = _tubingSizes[1];
      selectedCasing = _casingSizes[2];
      capacity.text = _tubingSizes[1].capacity.toStringAsFixed(5);
      length.clear();
      pumpRate.clear();
      lagFactor.text = '1.00';
    });
  }

  Future<void> copyResults() async {
    final volume = pipeVolume;
    final mins = bottomsUpMinutes;
    if (volume == null || mins == null) return;

    final text = '''Bottoms Up
Tubing: ${selectedTubing.label}
Casing: ${selectedCasing.label}
Capacity: ${_capacity.toStringAsFixed(5)} BBL/ft
Length: ${_length.toStringAsFixed(0)} ft
Pump Rate: ${_pumpRate.toStringAsFixed(2)} BBL/min
Lag Factor: ${_lag.toStringAsFixed(2)}
Pipe Volume: ${volume.toStringAsFixed(2)} BBL
Bottoms Up: ${mins.toStringAsFixed(2)} min ($hourMinuteText)
Estimated Arrival: $arrivalTime''';

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Bottoms Up copied')));
  }

  @override
  void dispose() {
    capacity.dispose();
    length.dispose();
    pumpRate.dispose();
    lagFactor.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFF111317),
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3A3A3A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _gold, width: 1.4),
      ),
    );
  }

  Widget _dropdownField<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      dropdownColor: const Color(0xFF1A1D21),
      iconEnabledColor: _gold,
      style: const TextStyle(color: Colors.white),
      decoration: _fieldDecoration(label),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Card(
      color: const Color(0xFF14171A),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final volume = pipeVolume;
    final mins = bottomsUpMinutes;

    return Scaffold(
      appBar: const AppHeader(title: 'Bottoms Up', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Completions tool for pipe volume, bottoms-up time, and estimated returns.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            child: Column(
              children: [
                _dropdownField<_PipeOption>(
                  label: 'Tubing Size',
                  value: selectedTubing,
                  items: _tubingSizes
                      .map(
                        (pipe) => DropdownMenuItem<_PipeOption>(
                          value: pipe,
                          child: Text(pipe.label),
                        ),
                      )
                      .toList(),
                  onChanged: (pipe) {
                    if (pipe != null) _selectTubing(pipe);
                  },
                ),
                const SizedBox(height: 12),
                _dropdownField<_SizeOption>(
                  label: 'Casing Size',
                  value: selectedCasing,
                  items: _casingSizes
                      .map(
                        (casing) => DropdownMenuItem<_SizeOption>(
                          value: casing,
                          child: Text(casing.label),
                        ),
                      )
                      .toList(),
                  onChanged: (casing) {
                    if (casing != null) _selectCasing(casing);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          WwNumberField(
            label: 'Pipe Capacity (BBL/ft)',
            controller: capacity,
            allowDecimal: true,
          ),
          WwNumberField(
            label: 'Depth (ft)',
            controller: length,
            allowDecimal: true,
          ),
          WwNumberField(
            label: 'Pump Rate (BBL/min)',
            controller: pumpRate,
            allowDecimal: true,
            textInputAction: TextInputAction.done,
          ),
          WwNumberField(
            label: 'Lag Factor',
            controller: lagFactor,
            allowDecimal: true,
            helperText:
                'Default 1.00. Increase if you want a field safety factor.',
          ),
          const SizedBox(height: 8),
          if (volume == null || mins == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Enter depth and pump rate in BBL/min to calculate bottoms up.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            )
          else ...[
            _ResultCard(
              label: 'Pipe Volume',
              value: volume.toStringAsFixed(2),
              unit: 'BBL',
            ),
            _ResultCard(
              label: 'Bottoms Up',
              value: mins.toStringAsFixed(2),
              unit: 'min',
            ),
            _ResultCard(label: 'Bottoms Up', value: hourMinuteText, unit: ''),
            _ResultCard(
                label: 'Estimated Arrival', value: arrivalTime, unit: ''),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: volume == null || mins == null ? null : copyResults,
            icon: const Icon(Icons.copy),
            label: const Text('Copy Results'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: clearAll,
            icon: const Icon(Icons.clear),
            label: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _ResultCard({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              unit.isEmpty ? value : '$value $unit',
              style: const TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
