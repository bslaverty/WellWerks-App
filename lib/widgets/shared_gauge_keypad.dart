import 'package:flutter/material.dart';

class SharedGaugeKeypad extends StatelessWidget {
  const SharedGaugeKeypad({
    super.key,
    required this.activeFieldLabel,
    required this.onInsert,
    required this.onBackspace,
    required this.onClear,
    required this.onDone,
    this.onBack,
    this.onNext,
    this.showPrimaryAction = false,
    this.primaryActionEnabled = false,
    this.primaryActionLabel = 'Calculate Rate',
    this.onPrimaryAction,
  });

  final String activeFieldLabel;
  final ValueChanged<String> onInsert;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onDone;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final bool showPrimaryAction;
  final bool primaryActionEnabled;
  final String primaryActionLabel;
  final VoidCallback? onPrimaryAction;

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
                    'Gauge Keypad • $activeFieldLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(onPressed: onClear, child: const Text('CLR')),
                const SizedBox(width: 6),
                FilledButton(onPressed: onDone, child: const Text('Done')),
              ],
            ),
            const SizedBox(height: 6),
            _keypadRow([
              _fractionButton(context, '1/8'),
              _fractionButton(context, '1/4'),
              _fractionButton(context, '3/8'),
              _fractionButton(context, '1/2'),
              _fractionButton(context, '5/8'),
            ]),
            const SizedBox(height: 6),
            _keypadRow([
              _fractionButton(context, '3/4'),
              _fractionButton(context, '7/8'),
              _fractionButton(context, 'Space'),
              _fractionButton(context, 'Backspace', onPressed: onBackspace),
            ]),
            const SizedBox(height: 8),
            _keypadRow([
              _numberButton(context, '1'),
              _numberButton(context, '2'),
              _numberButton(context, '3'),
            ]),
            const SizedBox(height: 6),
            _keypadRow([
              _numberButton(context, '4'),
              _numberButton(context, '5'),
              _numberButton(context, '6'),
            ]),
            const SizedBox(height: 6),
            _keypadRow([
              _numberButton(context, '7'),
              _numberButton(context, '8'),
              _numberButton(context, '9'),
            ]),
            const SizedBox(height: 6),
            Row(
              children: [
                const Spacer(),
                Expanded(child: _numberButton(context, '0')),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (onBack != null || onNext != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
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
                        ],
                      ),
                      Text(
                        'Gauge Keypad • $activeFieldLabel',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                else
                  const SizedBox.shrink(),
                const Spacer(),
                OutlinedButton.icon(
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
              ],
            ),
            if (showPrimaryAction) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: primaryActionEnabled ? onPrimaryAction : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    disabledBackgroundColor: scheme.surfaceContainerHighest,
                    disabledForegroundColor: scheme.onSurfaceVariant,
                    minimumSize: const Size.fromHeight(50),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  child: Text(
                    primaryActionLabel,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fractionButton(
    BuildContext context,
    String label, {
    VoidCallback? onPressed,
  }) {
    return _keyButton(
      context,
      label,
      compact: true,
      onPressed: onPressed ?? () => onInsert(label),
    );
  }

  Widget _numberButton(BuildContext context, String value) {
    return _keyButton(context, value, onPressed: () => onInsert(value));
  }

  Widget _keyButton(
    BuildContext context,
    String label, {
    required VoidCallback onPressed,
    bool compact = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: compact ? 38 : 42,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: scheme.primary),
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          padding:
              EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 6),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: TextStyle(
            fontSize: compact ? 12 : 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _keypadRow(List<Widget> children) {
    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i != children.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}
