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
  late int _minuteIndex;
  late int _periodIndex;

  @override
  void initState() {
    super.initState();
    final h = widget.initialTime.hour;
    _minuteIndex = widget.initialTime.minute;

    if (widget.use24Hour) {
      _hourIndex = h;
      _periodIndex = 0;
    } else {
      _periodIndex = h >= 12 ? 1 : 0;
      final hour12 = h % 12 == 0 ? 12 : h % 12;
      _hourIndex = hour12 - 1;
    }
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
                    int hour;
                    if (widget.use24Hour) {
                      hour = _hourIndex;
                    } else {
                      final hour12 = _hourIndex + 1;
                      if (_periodIndex == 0) {
                        hour = hour12 == 12 ? 0 : hour12;
                      } else {
                        hour = hour12 == 12 ? 12 : hour12 + 12;
                      }
                    }
                    Navigator.of(context).pop(
                      TimeOfDay(hour: hour, minute: _minuteIndex),
                    );
                  },
                  child: const Text('Confirm'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 220,
              child: Row(
                children: [
                  Expanded(
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
                          widget.use24Hour ? 24 : 12,
                          (index) {
                            final label = widget.use24Hour
                                ? index.toString().padLeft(2, '0')
                                : (index + 1).toString();
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: _wheelContainer(
                      child: CupertinoPicker(
                        itemExtent: 44,
                        scrollController: FixedExtentScrollController(
                          initialItem: _minuteIndex,
                        ),
                        onSelectedItemChanged: (index) {
                          setState(() => _minuteIndex = index);
                        },
                        children: List.generate(
                          60,
                          (index) => Center(
                            child: Text(
                              index.toString().padLeft(2, '0'),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!widget.use24Hour) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _wheelContainer(
                        child: CupertinoPicker(
                          itemExtent: 44,
                          scrollController: FixedExtentScrollController(
                            initialItem: _periodIndex,
                          ),
                          onSelectedItemChanged: (index) {
                            setState(() => _periodIndex = index);
                          },
                          children: const [
                            Center(
                              child: Text(
                                'AM',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Center(
                              child: Text(
                                'PM',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
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
}
