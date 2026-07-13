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
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  late final FixedExtentScrollController _periodController;

  @override
  void initState() {
    super.initState();
    _hourIndex = widget.use24Hour
        ? widget.initialTime.hour
        : _displayHour(widget.initialTime.hour);
    _minuteIndex = widget.initialTime.minute;
    _periodIndex = widget.initialTime.hour >= 12 ? 1 : 0;
    _hourController = FixedExtentScrollController(initialItem: _hourIndex);
    _minuteController = FixedExtentScrollController(initialItem: _minuteIndex);
    _periodController = FixedExtentScrollController(initialItem: _periodIndex);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    super.dispose();
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
                    Navigator.of(context).pop(_selectedTime());
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 260,
              child: Row(
                children: [
                  Expanded(
                    child: _wheelWithLabel(
                      label: 'Hour',
                      child: CupertinoPicker(
                        itemExtent: 44,
                        scrollController: _hourController,
                        onSelectedItemChanged: (index) {
                          setState(() => _hourIndex = index);
                        },
                        children: List.generate(
                          widget.use24Hour ? 24 : 12,
                          (index) {
                            final label = widget.use24Hour
                                ? index.toString().padLeft(2, '0')
                                : _twelveHourLabel(index + 1);
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
                  Expanded(
                    child: _wheelWithLabel(
                      label: 'Minute',
                      child: CupertinoPicker(
                        itemExtent: 44,
                        scrollController: _minuteController,
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
                  if (!widget.use24Hour)
                    Expanded(
                      child: _wheelWithLabel(
                        label: 'AM/PM',
                        child: CupertinoPicker(
                          itemExtent: 44,
                          scrollController: _periodController,
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

  Widget _wheelWithLabel({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(child: _wheelContainer(child: child)),
        ],
      ),
    );
  }

  TimeOfDay _selectedTime() {
    if (widget.use24Hour) {
      return TimeOfDay(hour: _hourIndex, minute: _minuteIndex);
    }
    final hour12 = _hourIndex + 1;
    final hour24 = _periodIndex == 1 ? (hour12 % 12) + 12 : (hour12 % 12);
    return TimeOfDay(hour: hour24, minute: _minuteIndex);
  }

  int _displayHour(int hour24) {
    final hour12 = hour24 % 12;
    return hour12 == 0 ? 12 : hour12 - 1;
  }

  String _twelveHourLabel(int hour12) {
    final period = hour12 == 12 ? 'PM' : 'AM';
    return '$hour12:00 $period';
  }
}
