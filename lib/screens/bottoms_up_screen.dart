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

class _BottomsUpScreenState extends State<BottomsUpScreen> {
  static const _pipes = <_PipeOption>[
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

  _PipeOption selectedPipe = _pipes[1];
  final capacity = TextEditingController(text: _pipes[1].capacity.toStringAsFixed(5));
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
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return h > 0 ? '$h hr $m min' : '$m min';
  }

  @override
  void initState() {
    super.initState();
    for (final c in [capacity, length, pumpRate, lagFactor]) {
      c.addListener(() => setState(() {}));
    }
  }

  void _selectPipe(_PipeOption pipe) {
    setState(() {
      selectedPipe = pipe;
      if (!pipe.custom) {
        capacity.text = pipe.capacity.toStringAsFixed(5);
      } else {
        capacity.clear();
      }
    });
  }

  void clearAll() {
    setState(() {
      selectedPipe = _pipes[1];
      capacity.text = _pipes[1].capacity.toStringAsFixed(5);
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
Pipe: ${selectedPipe.label}
Capacity: ${_capacity.toStringAsFixed(5)} BBL/ft
Length: ${_length.toStringAsFixed(0)} ft
Pump Rate: ${_pumpRate.toStringAsFixed(2)} BBL/min
Lag Factor: ${_lag.toStringAsFixed(2)}
Pipe Volume: ${volume.toStringAsFixed(2)} BBL
Bottoms Up: ${mins.toStringAsFixed(2)} min ($hourMinuteText)
Estimated Arrival: $arrivalTime''';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bottoms Up copied')));
  }

  @override
  void dispose() {
    capacity.dispose();
    length.dispose();
    pumpRate.dispose();
    lagFactor.dispose();
    super.dispose();
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
          DropdownButtonFormField<_PipeOption>(
            value: selectedPipe,
            decoration: const InputDecoration(labelText: 'Pipe Size'),
            items: _pipes
                .map((p) => DropdownMenuItem<_PipeOption>(
                      value: p,
                      child: Text(p.label),
                    ))
                .toList(),
            onChanged: (p) {
              if (p != null) _selectPipe(p);
            },
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
            helperText: 'Default 1.00. Increase if you want a field safety factor.',
          ),
          const SizedBox(height: 8),
          if (volume == null || mins == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Enter depth and pump rate in BBL/min to calculate bottoms up.', style: TextStyle(color: Colors.white70)),
              ),
            )
          else ...[
            _ResultCard(label: 'Pipe Volume', value: volume.toStringAsFixed(2), unit: 'BBL'),
            _ResultCard(label: 'Bottoms Up', value: mins.toStringAsFixed(2), unit: 'min'),
            _ResultCard(label: 'Bottoms Up', value: hourMinuteText, unit: ''),
            _ResultCard(label: 'Estimated Arrival', value: arrivalTime, unit: ''),
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

  const _ResultCard({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              unit.isEmpty ? value : '$value $unit',
              style: const TextStyle(color: Color(0xFFCDA56A), fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
