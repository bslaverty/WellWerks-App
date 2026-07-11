import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/choke_selector_sheet.dart';

class MultipleChokeScreen extends StatefulWidget {
  const MultipleChokeScreen({super.key});

  @override
  State<MultipleChokeScreen> createState() => _MultipleChokeScreenState();
}

class _MultipleChokeScreenState extends State<MultipleChokeScreen> {
  final List<TextEditingController> chokes =
      List.generate(5, (_) => TextEditingController());

  final List<int> commonChokes = const [
    12,
    14,
    16,
    18,
    20,
    22,
    24,
    26,
    28,
    30,
    32,
    34,
    36,
    38,
    40,
    42,
    44,
    46,
    48,
    50,
    52,
    54,
    56,
    60,
    64
  ];

  List<double> get values => chokes
      .map((c) => double.tryParse(c.text.trim()))
      .whereType<double>()
      .where((v) => v > 0)
      .toList();

  double? get equivalent64 {
    final v = values;
    if (v.isEmpty) return null;
    final sumSquares = v.fold<double>(0, (sum, item) => sum + (item * item));
    return math.sqrt(sumSquares);
  }

  double? get totalAreaSqIn {
    final v = values;
    if (v.isEmpty) return null;
    return v.fold<double>(0, (sum, choke64) {
      final diameterIn = choke64 / 64.0;
      return sum + (math.pi * math.pow(diameterIn / 2, 2));
    });
  }

  void clearAll() {
    setState(() {
      for (final c in chokes) {
        c.clear();
      }
    });
  }

  void addChoke() {
    setState(() => chokes.add(TextEditingController()));
  }

  void removeChoke(int index) {
    if (chokes.length <= 1) {
      clearAll();
      return;
    }
    setState(() {
      chokes[index].dispose();
      chokes.removeAt(index);
    });
  }

  @override
  void dispose() {
    for (final c in chokes) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final equiv = equivalent64;
    final area = totalAreaSqIn;

    return Scaffold(
      appBar: const AppHeader(title: 'Multiple Choke', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Enter choke sizes in 64ths. Example: 32 = 32/64 choke.',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < chokes.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: chokes[i],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Choke ${i + 1}',
                        suffixText: '/64',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Select choke',
                    icon: const Icon(Icons.tune),
                    onPressed: () async {
                      final current = int.tryParse(chokes[i].text.trim());
                      final picked = await showChokeSelectorSheet(
                        context,
                        initial: ChokeSelection(
                          type: ChokeTypes.positive,
                          size64:
                              (current != null && current >= 2 && current <= 64)
                                  ? current
                                  : commonChokes.first,
                        ),
                        allowNone: false,
                        positiveSizes: commonChokes,
                        adjustableSizes: commonChokes,
                      );
                      if (!mounted || picked == null || picked.size64 == null) {
                        return;
                      }
                      setState(() => chokes[i].text = picked.size64.toString());
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => removeChoke(i),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: addChoke,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Choke'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: clearAll,
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (equiv != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Equivalent Choke',
                        style: TextStyle(
                            color: Color(0xFFCDA56A),
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      '${equiv.toStringAsFixed(1)}/64',
                      style: const TextStyle(
                          fontSize: 34, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    Text('Total flow area: ${area!.toStringAsFixed(4)} sq in',
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(
                        'Chokes entered: ${values.map((v) => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1)}/64').join(', ')}',
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            )
          else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Enter at least one choke size to calculate.',
                    style: TextStyle(color: Colors.white70)),
              ),
            ),
        ],
      ),
    );
  }
}
