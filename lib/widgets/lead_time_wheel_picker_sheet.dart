import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<int?> showLeadTimeWheelPickerSheet(
  BuildContext context, {
  required List<int> options,
  required int initialMinutes,
  String title = 'Reminder Time',
  String actionLabel = 'Set',
}) {
  final normalizedOptions = options.isEmpty ? <int>[10] : options;
  final startIndex = normalizedOptions.indexOf(initialMinutes);
  final initialIndex = startIndex < 0 ? 0 : startIndex;

  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _LeadTimeWheelPickerBody(
      title: title,
      actionLabel: actionLabel,
      options: normalizedOptions,
      initialIndex: initialIndex,
    ),
  );
}

class _LeadTimeWheelPickerBody extends StatefulWidget {
  const _LeadTimeWheelPickerBody({
    required this.title,
    required this.actionLabel,
    required this.options,
    required this.initialIndex,
  });

  final String title;
  final String actionLabel;
  final List<int> options;
  final int initialIndex;

  @override
  State<_LeadTimeWheelPickerBody> createState() =>
      _LeadTimeWheelPickerBodyState();
}

class _LeadTimeWheelPickerBodyState extends State<_LeadTimeWheelPickerBody> {
  late int _selectedIndex;
  late final FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _controller = FixedExtentScrollController(initialItem: _selectedIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(widget.options[_selectedIndex]),
                  child: Text(widget.actionLabel),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: CupertinoPicker(
                itemExtent: 46,
                scrollController: _controller,
                onSelectedItemChanged: (index) {
                  setState(() => _selectedIndex = index);
                },
                children: [
                  for (final minutes in widget.options)
                    Center(
                      child: Text(
                        minutes == 60
                            ? '1 hour before'
                            : '$minutes minutes before',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
