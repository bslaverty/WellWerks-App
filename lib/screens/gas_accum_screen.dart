import 'package:flutter/material.dart';
import '../widgets/app_header.dart';

class GasAccumScreen extends StatefulWidget {
  const GasAccumScreen({super.key});

  @override
  State<GasAccumScreen> createState() => _GasAccumScreenState();
}

class _GasAccumScreenState extends State<GasAccumScreen> {
  static const int readingCount = 13;
  String unit = 'MCF';
  final readings = List.generate(readingCount, (_) => TextEditingController());

  double? valueAt(int index) => double.tryParse(readings[index].text.trim());

  double? rateForHour(int hour) {
    final previous = valueAt(hour - 1);
    final current = valueAt(hour);
    if (previous == null || current == null) return null;
    final diff = current - previous;
    if (diff < 0) return null;
    return diff * 24;
  }

  String _format(double value) {
    if (value.abs() >= 100) return value.toStringAsFixed(0);
    if (value.abs() >= 10) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  void clearAll() {
    setState(() {
      for (final controller in readings) {
        controller.clear();
      }
    });
  }

  @override
  void dispose() {
    for (final controller in readings) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _rateCard(int hour, double rate) {
    return Card(
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Hour $hour Gas Rate',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${_format(rate)} $unit/D',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Gas Accum Calculator', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Enter the starting totalizer reading, then each hourly reading. Each hourly gas rate calculates automatically as next reading minus previous reading, multiplied by 24.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: unit,
            decoration: const InputDecoration(labelText: 'Reading Unit'),
            items: const [
              DropdownMenuItem(value: 'MCF', child: Text('MCF')),
              DropdownMenuItem(value: 'MMCF', child: Text('MMCF')),
            ],
            onChanged: (value) => setState(() => unit = value ?? 'MCF'),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < readings.length; i++) ...[
            TextField(
              controller: readings[i],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: i == readings.length - 1
                  ? TextInputAction.done
                  : TextInputAction.next,
              decoration: InputDecoration(
                labelText: i == 0 ? 'Starting Reading' : 'Hour $i Reading',
                suffixIcon: readings[i].text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => readings[i].clear()),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (i > 0 && rateForHour(i) != null)
              _rateCard(i, rateForHour(i)!)
            else
              const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: clearAll,
            icon: const Icon(Icons.clear),
            label: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
