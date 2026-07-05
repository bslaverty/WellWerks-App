import 'package:flutter/material.dart';

import '../widgets/app_header.dart';

class ConversionCalculatorScreen extends StatefulWidget {
  const ConversionCalculatorScreen({super.key});

  @override
  State<ConversionCalculatorScreen> createState() =>
      _ConversionCalculatorScreenState();
}

class _ConversionCalculatorScreenState
    extends State<ConversionCalculatorScreen> {
  static const Map<String, List<String>> _unitsByCategory = {
    'Length': ['inches', 'feet', 'yards', 'miles', 'meters'],
    'Volume': ['gallons', 'barrels', 'liters', 'cubic feet'],
    'Pressure': ['psi', 'kPa', 'MPa', 'bar'],
    'Temperature': ['Fahrenheit', 'Celsius'],
    'Flow Rate': ['bbl/hr', 'bbl/day', 'gal/min', 'gal/hr'],
    'Gas Rate': ['mcf/d', 'mmcf/d', 'scf/d'],
    'Oilfield Units': [
      'barrels',
      'gallons',
      'feet',
      'inches',
      'decimal feet',
      'barrels (inches × bbl/in)',
    ],
  };

  String _category = 'Length';
  String _from = 'inches';
  String _to = 'feet';

  final TextEditingController _value = TextEditingController();
  final TextEditingController _factor = TextEditingController();

  String _result = '--';
  String? _error;

  @override
  void initState() {
    super.initState();
    _setDefaultUnitsForCategory();
  }

  @override
  void dispose() {
    _value.dispose();
    _factor.dispose();
    super.dispose();
  }

  void _setDefaultUnitsForCategory() {
    final units = _unitsByCategory[_category] ?? const [];
    if (units.length >= 2) {
      _from = units[0];
      _to = units[1];
    }
  }

  double? _factorFor(String category, String unit) {
    switch (category) {
      case 'Length':
        return {
          'inches': 0.0254,
          'feet': 0.3048,
          'yards': 0.9144,
          'miles': 1609.344,
          'meters': 1.0,
        }[unit];
      case 'Volume':
        return {
          'gallons': 3.785411784,
          'barrels': 158.987294928,
          'liters': 1.0,
          'cubic feet': 28.316846592,
        }[unit];
      case 'Pressure':
        return {
          'psi': 6894.757293168,
          'kPa': 1000.0,
          'MPa': 1000000.0,
          'bar': 100000.0,
        }[unit];
      case 'Flow Rate':
        return {
          'bbl/hr': 158.987294928,
          'bbl/day': 158.987294928 / 24,
          'gal/min': 3.785411784 * 60,
          'gal/hr': 3.785411784,
        }[unit];
      case 'Gas Rate':
        return {
          'mcf/d': 1000.0,
          'mmcf/d': 1000000.0,
          'scf/d': 1.0,
        }[unit];
      case 'Oilfield Units':
        return {
          'barrels': 42.0,
          'gallons': 1.0,
          'feet': 12.0,
          'inches': 1.0,
          'decimal feet': 12.0,
        }[unit];
      default:
        return null;
    }
  }

  bool get _requiresOilfieldFactor =>
      _category == 'Oilfield Units' &&
      _from == 'inches' &&
      _to == 'barrels (inches × bbl/in)';

  void _convert() {
    final input = double.tryParse(_value.text.trim());
    if (input == null) {
      setState(() {
        _error = 'Enter a numeric value.';
        _result = '--';
      });
      return;
    }

    if (_category == 'Temperature') {
      final converted = _convertTemperature(input, _from, _to);
      if (converted == null) {
        setState(() {
          _error = 'Select valid temperature units.';
          _result = '--';
        });
        return;
      }
      setState(() {
        _error = null;
        _result = converted.toStringAsFixed(2);
      });
      return;
    }

    if (_requiresOilfieldFactor) {
      final factor = double.tryParse(_factor.text.trim());
      if (factor == null || factor <= 0) {
        setState(() {
          _error = 'Enter BBL per inch factor.';
          _result = '--';
        });
        return;
      }
      setState(() {
        _error = null;
        _result = (input * factor).toStringAsFixed(2);
      });
      return;
    }

    final fromFactor = _factorFor(_category, _from);
    final toFactor = _factorFor(_category, _to);
    if (fromFactor == null || toFactor == null || toFactor == 0) {
      setState(() {
        _error = 'Unsupported unit conversion.';
        _result = '--';
      });
      return;
    }

    final converted = (input * fromFactor) / toFactor;
    setState(() {
      _error = null;
      _result = converted.toStringAsFixed(4);
    });
  }

  double? _convertTemperature(double value, String from, String to) {
    if (from == to) return value;
    if (from == 'Fahrenheit' && to == 'Celsius') {
      return (value - 32) * 5 / 9;
    }
    if (from == 'Celsius' && to == 'Fahrenheit') {
      return (value * 9 / 5) + 32;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final units = _unitsByCategory[_category] ?? const [];

    return Scaffold(
      appBar: const AppHeader(title: 'Conversion Calculator', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Field-ready conversions across common oilfield categories.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final category in _unitsByCategory.keys)
                DropdownMenuItem(value: category, child: Text(category)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _category = value;
                _setDefaultUnitsForCategory();
                _result = '--';
                _error = null;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Value'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _from,
            decoration: const InputDecoration(labelText: 'From'),
            items: [
              for (final unit in units)
                DropdownMenuItem(value: unit, child: Text(unit)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _from = value;
                _result = '--';
                _error = null;
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _to,
            decoration: const InputDecoration(labelText: 'To'),
            items: [
              for (final unit in units)
                DropdownMenuItem(value: unit, child: Text(unit)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _to = value;
                _result = '--';
                _error = null;
              });
            },
          ),
          if (_requiresOilfieldFactor) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _factor,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'BBL per inch'),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _convert,
            child: const Text('Convert'),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Result',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _result,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
