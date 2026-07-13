double? parseChokePlotValue(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final lower = trimmed.toLowerCase();
  if (lower.contains('none') || lower.contains('clear')) {
    return null;
  }

  final cleaned = trimmed.replaceAll(RegExp(r'[^0-9./]'), '');
  if (cleaned.isEmpty) return null;

  final fraction =
      RegExp(r'^(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)$').firstMatch(cleaned);
  if (fraction != null) {
    final numerator = double.tryParse(fraction.group(1) ?? '');
    final denominator = double.tryParse(fraction.group(2) ?? '');
    if (numerator == null || denominator == null || denominator == 0) {
      return null;
    }
    final as64ths = (numerator / denominator) * 64;
    if (!as64ths.isFinite || as64ths <= 0 || as64ths > 64) {
      return null;
    }
    return as64ths;
  }

  final scalar = double.tryParse(cleaned);
  if (scalar == null || !scalar.isFinite || scalar <= 0) {
    return null;
  }

  // Values <= 1 are treated as simplified whole fractions (for example 1 -> 64).
  final as64ths = scalar <= 1 ? scalar * 64 : scalar;
  if (as64ths > 64) return null;
  return as64ths;
}

int? parseChokeSize64(String raw) {
  final value = parseChokePlotValue(raw);
  if (value == null) return null;
  final rounded = value.round();
  if ((value - rounded).abs() > 0.01) return null;
  if (rounded < 2 || rounded > 64) return null;
  return rounded;
}
