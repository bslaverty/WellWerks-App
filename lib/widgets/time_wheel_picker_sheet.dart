import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<TimeOfDay?> showTimeWheelPickerSheet(
  BuildContext context, {
  required TimeOfDay initialTime,
  required bool use24Hour,
}) async {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _TimeWheelPickerBody(
      initialTime: initialTime,
      use24Hour: use24Hour,
    ),
  );
}

class _TimeWheelPickerBody extends StatefulWidget {
  const _TimeWheelPickerBody({
    required this.initialTime,
    required this.use24Hour,
  });

  final TimeOfDay initialTime;
  final bool use24Hour;

  @override
  State<_TimeWheelPickerBody> createState() => _TimeWheelPickerBodyState();
}

class _TimeWheelPickerBodyState extends State<_TimeWheelPickerBody> {
  late int _hourIndex;

  @override
  void initState() {
    super.initState();
    _hourIndex = widget.initialTime.hour;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Select Time',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      TimeOfDay(hour: _hourIndex, minute: 0),
                    );
                  },
                  child: const Text('Confirm'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 220,
              child: _wheelContainer(
                child: CupertinoPicker(
                  itemExtent: 44,
                  scrollController: FixedExtentScrollController(
                    initialItem: _hourIndex,
                  ),
                  onSelectedItemChanged: (index) {
                    setState(() => _hourIndex = index);
                  },
                  children: List.generate(
                    24,
                    (index) {
                      final label = widget.use24Hour
                          ? '${index.toString().padLeft(2, '0')}:00'
                          : _twelveHourLabel(index);
                      return Center(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wheelContainer({required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(14), child: child),
    );
  }

  String _twelveHourLabel(int hour24) {
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:00 $period';
  }
}
