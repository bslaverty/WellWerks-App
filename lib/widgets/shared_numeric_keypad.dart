import 'package:flutter/material.dart';

/// Themed on-screen numeric keypad used in place of the OS keyboard for
/// plain decimal entry fields (pressures, temps, rates, etc.). Styled to
/// match [SharedGaugeKeypad] so every custom keypad in the app looks the
/// same regardless of which field type it is driving.
class SharedNumericKeypad extends StatelessWidget {
  const SharedNumericKeypad({
    super.key,
    required this.activeFieldLabel,
    required this.onInsert,
    required this.onBackspace,
    required this.onClear,
    required this.onDone,
    this.onBack,
    this.onNext,
  });

  final String activeFieldLabel;
  final ValueChanged<String> onInsert;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onDone;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Keypad • $activeFieldLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton(onPressed: onDone, child: const Text('Done')),
              ],
            ),
            const SizedBox(height: 8),
            _keypadRow(context, ['7', '8', '9']),
            const SizedBox(height: 6),
            _keypadRow(context, ['4', '5', '6']),
            const SizedBox(height: 6),
            _keypadRow(context, ['1', '2', '3']),
            const SizedBox(height: 6),
            _keypadRow(context, ['±', '0', '.']),
            const SizedBox(height: 8),
            Row(
              children: [
                if (onBack != null || onNext != null) ...[
                  IconButton(
                    tooltip: 'Previous field',
                    onPressed: onBack,
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: scheme.primary,
                    disabledColor: scheme.onSurfaceVariant.withValues(
                      alpha: 0.35,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: 'Next field',
                    onPressed: onNext,
                    icon: const Icon(Icons.chevron_right_rounded),
                    color: scheme.primary,
                    disabledColor: scheme.onSurfaceVariant.withValues(
                      alpha: 0.35,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onBackspace,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: scheme.primary),
                      foregroundColor: scheme.onSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.backspace_outlined, size: 18),
                    label: const Text('Backspace'),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(onPressed: onClear, child: const Text('CLR')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _keypadRow(BuildContext context, List<String> values) {
    return Row(
      children: [
        for (var i = 0; i < values.length; i++) ...[
          Expanded(child: _keyButton(context, values[i])),
          if (i != values.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _keyButton(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: () => onInsert(label),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: scheme.primary),
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
