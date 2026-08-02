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
  static const Map<String, double> _cookingVolumeToMl = {
    'teaspoons (tsp)': 4.92892159375,
    'tablespoons (tbsp)': 14.78676478125,
    'fluid ounces (fl oz)': 29.5735295625,
    'cups': 236.5882365,
    'pints': 473.176473,
    'quarts': 946.352946,
    'gallons': 3785.411784,
    'milliliters (mL)': 1.0,
    'liters (L)': 1000.0,
  };

  static const Map<String, double> _cookingWeightToGrams = {
    'ounces (oz)': 28.349523125,
    'pounds (lb)': 453.59237,
    'grams (g)': 1.0,
    'kilograms (kg)': 1000.0,
  };

  static const Map<String, List<String>> _unitsByCategory = {
    'Length': ['inches', 'feet', 'yards', 'miles', 'meters'],
    'Volume': ['gallons', 'barrels', 'liters'],
    'Pressure': ['psi', 'kPa', 'MPa', 'bar'],
    'Temperature': ['Fahrenheit', 'Celsius'],
    'Fluid Rate': [
      'bbl/min',
      'bbl/hr',
      'bbl/day',
      'gal/min',
      'gal/hr',
      'gal/day',
    ],
    'Gas Rate': ['mcf/d', 'mmcf/d', 'scf/d'],
    'Cooking Conversions': [
      'teaspoons (tsp)',
      'tablespoons (tbsp)',
      'fluid ounces (fl oz)',
      'cups',
      'pints',
      'quarts',
      'gallons',
      'milliliters (mL)',
      'liters (L)',
      'ounces (oz)',
      'pounds (lb)',
      'grams (g)',
      'kilograms (kg)',
      'Fahrenheit',
      'Celsius',
    ],
    'Oilfield Units': [
      'barrels',
      'gallons',
      'inches',
      'decimal feet',
      'fractional feet',
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
        }[unit];
      case 'Pressure':
        return {
          'psi': 6894.757293168,
          'kPa': 1000.0,
          'MPa': 1000000.0,
          'bar': 100000.0,
        }[unit];
      case 'Fluid Rate':
        return {
          'bbl/min': 158.987294928 * 60,
          'bbl/hr': 158.987294928,
          'bbl/day': 158.987294928 / 24,
          'gal/min': 3.785411784 * 60,
          'gal/hr': 3.785411784,
          'gal/day': 3.785411784 / 24,
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
          'inches': 1.0,
          'decimal feet': 12.0,
          'fractional feet': 12.0,
        }[unit];
      default:
        return null;
    }
  }

  bool get _usesFractionalFeetInput =>
      _category == 'Oilfield Units' && _from == 'fractional feet';

  double? _parseFractionalFeet(String raw) {
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty) return null;

    final asDecimal = double.tryParse(trimmed);
    if (asDecimal != null) return asDecimal;

    final apostrophePattern = RegExp(
      r'''^(-?\d+)\s*['-]\s*(\d+(?:\.\d+)?)\s*(?:"|in)?$''',
    );
    final ftInPattern = RegExp(
      r'^(-?\d+)\s*ft\s*(\d+(?:\.\d+)?)?\s*(?:in)?$',
    );
    final spacePattern = RegExp(r'^(-?\d+)\s+(\d+(?:\.\d+)?)$');

    RegExpMatch? match = apostrophePattern.firstMatch(trimmed);
    match ??= ftInPattern.firstMatch(trimmed);
    match ??= spacePattern.firstMatch(trimmed);
    if (match == null) return null;

    final feetPart = int.tryParse(match.group(1) ?? '');
    final inchesPart = double.tryParse(match.group(2) ?? '0') ?? 0;
    if (feetPart == null) return null;

    final sign = feetPart < 0 ? -1.0 : 1.0;
    return feetPart.toDouble() + (sign * (inchesPart / 12.0));
  }

  String _formatFeetAndInches(double decimalFeet) {
    final sign = decimalFeet < 0 ? '-' : '';
    final absFeet = decimalFeet.abs();
    final feetWhole = absFeet.floor();
    final inches = (absFeet - feetWhole) * 12.0;
    return '$sign$feetWhole\' ${inches.toStringAsFixed(2)}"';
  }

  bool _isCookingVolumeUnit(String unit) =>
      _cookingVolumeToMl.containsKey(unit);

  bool _isCookingWeightUnit(String unit) =>
      _cookingWeightToGrams.containsKey(unit);

  bool _isCookingTemperatureUnit(String unit) =>
      unit == 'Fahrenheit' || unit == 'Celsius';

  double? _convertCooking(double value, String from, String to) {
    if (from == to) return value;

    if (_isCookingTemperatureUnit(from) && _isCookingTemperatureUnit(to)) {
      return _convertTemperature(value, from, to);
    }

    if (_isCookingVolumeUnit(from) && _isCookingVolumeUnit(to)) {
      final fromMl = _cookingVolumeToMl[from]!;
      final toMl = _cookingVolumeToMl[to]!;
      return (value * fromMl) / toMl;
    }

    if (_isCookingWeightUnit(from) && _isCookingWeightUnit(to)) {
      final fromG = _cookingWeightToGrams[from]!;
      final toG = _cookingWeightToGrams[to]!;
      return (value * fromG) / toG;
    }

    return null;
  }

  bool get _requiresOilfieldFactor =>
      _category == 'Oilfield Units' &&
      _from == 'inches' &&
      _to == 'barrels (inches × bbl/in)';

  void _convert() {
    final rawInput = _value.text.trim();
    final input = _usesFractionalFeetInput
        ? _parseFractionalFeet(rawInput)
        : double.tryParse(rawInput);
    if (input == null) {
      setState(() {
        _error = _usesFractionalFeetInput
            ? 'Enter decimal feet or fractional feet (example: 10\' 6").'
            : 'Enter a numeric value.';
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

    if (_category == 'Cooking Conversions') {
      final converted = _convertCooking(input, _from, _to);
      if (converted == null) {
        setState(() {
          _error =
              'Use volume-to-volume, weight-to-weight, or Fahrenheit to Celsius.';
          _result = '--';
        });
        return;
      }
      setState(() {
        _error = null;
        _result = _isCookingTemperatureUnit(_to)
            ? converted.toStringAsFixed(2)
            : converted.toStringAsFixed(4);
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
      _result = _category == 'Oilfield Units' && _to == 'fractional feet'
          ? _formatFeetAndInches(converted)
          : converted.toStringAsFixed(4);
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
            keyboardType: _usesFractionalFeetInput
                ? TextInputType.text
                : const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Value',
              hintText:
                  _usesFractionalFeetInput ? 'Examples: 10.5 or 10\' 6"' : null,
            ),
          ),
          if (_category == 'Oilfield Units') ...[
            const SizedBox(height: 8),
            const Text(
              'Oilfield Units converts between barrels, gallons, inches, decimal feet, and fractional feet.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          if (_category == 'Cooking Conversions') ...[
            const SizedBox(height: 8),
            const Text(
              'Cooking Conversions supports kitchen volume, kitchen weight, and oven temperature conversions.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
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
