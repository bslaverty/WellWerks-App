import 'package:flutter/services.dart';

class GaugeKeypadInput {
  static const fractions = <String>[
    '1/8',
    '1/4',
    '3/8',
    '1/2',
    '5/8',
    '3/4',
    '7/8',
  ];

  static bool isFractionToken(String raw) {
    return RegExp(r'^\d+/\d+').hasMatch(raw) && raw.trim() == raw;
  }

  static TextEditingValue insert(TextEditingValue value, String raw) {
    final text = value.text;
    final start =
        value.selection.start < 0 ? text.length : value.selection.start;
    final end = value.selection.end < 0 ? text.length : value.selection.end;

    final insertText = _insertToken(text, raw);
    final next = _normalizeSpaces(text.replaceRange(start, end, insertText));

    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
          offset: _safeOffset(next, start + insertText.length)),
    );
  }

  static TextEditingValue backspace(TextEditingValue value) {
    final text = value.text;
    if (text.isEmpty) return value;

    final start =
        value.selection.start < 0 ? text.length : value.selection.start;
    final end = value.selection.end < 0 ? text.length : value.selection.end;

    if (start != end) {
      final updated =
          _trimTrailingSpaceOnDelete(text.replaceRange(start, end, ''));
      return TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: _safeOffset(updated, start)),
      );
    }

    if (start == 0) return value;

    final updated =
        _trimTrailingSpaceOnDelete(text.replaceRange(start - 1, start, ''));
    return TextEditingValue(
      text: updated,
      selection:
          TextSelection.collapsed(offset: _safeOffset(updated, start - 1)),
    );
  }

  static String _insertToken(String currentText, String raw) {
    if (raw == 'Space') return ' ';
    if (isFractionToken(raw)) {
      if (currentText.isEmpty) return raw;
      return currentText.endsWith(' ') ? raw : ' $raw';
    }
    return raw;
  }

  static int _safeOffset(String text, int desired) {
    if (desired < 0) return 0;
    if (desired > text.length) return text.length;
    return desired;
  }

  static String _normalizeSpaces(String value) {
    return value.replaceAll(RegExp(r' {2,}'), ' ');
  }

  static String _trimTrailingSpaceOnDelete(String value) {
    return value.trimRight();
  }
}
