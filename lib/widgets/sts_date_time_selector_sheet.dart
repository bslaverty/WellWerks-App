import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class StsDateTimeSelection {
  const StsDateTimeSelection({
    required this.value,
    required this.cleared,
  });

  final DateTime? value;
  final bool cleared;
}

Future<StsDateTimeSelection?> showStsDateTimeSelectorSheet(
  BuildContext context, {
  required String title,
  required String helperText,
  required DateTime readingTimestamp,
  DateTime? initialValue,
}) {
  return showModalBottomSheet<StsDateTimeSelection>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _StsDateTimeSelectorBody(
      title: title,
      helperText: helperText,
      readingTimestamp: readingTimestamp,
      initialValue: initialValue,
    ),
  );
}

class _StsDateTimeSelectorBody extends StatefulWidget {
  const _StsDateTimeSelectorBody({
    required this.title,
    required this.helperText,
    required this.readingTimestamp,
    required this.initialValue,
  });

  final String title;
  final String helperText;
  final DateTime readingTimestamp;
  final DateTime? initialValue;

  @override
  State<_StsDateTimeSelectorBody> createState() =>
      _StsDateTimeSelectorBodyState();
}

class _StsDateTimeSelectorBodyState extends State<_StsDateTimeSelectorBody> {
  late DateTime _selectedDate;
  late int _hourIndex;
  late int _minuteIndex;
  late int _periodIndex;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late FixedExtentScrollController _periodController;

  DateTime get _readingDate => DateTime(
        widget.readingTimestamp.year,
        widget.readingTimestamp.month,
        widget.readingTimestamp.day,
      );

  DateTime get _tomorrowDate => _readingDate.add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    final base = widget.initialValue ?? widget.readingTimestamp;
    _selectedDate = DateTime(base.year, base.month, base.day);
    _hourIndex = _displayHour(base.hour);
    _minuteIndex = base.minute;
    _periodIndex = base.hour >= 12 ? 1 : 0;
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.helperText,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      StsDateTimeSelection(
                        value: _selectedDateTime(),
                        cleared: false,
                      ),
                    );
                  },
                  child: const Text('Set Time'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Today'),
                  selected: _isSameDate(_selectedDate, _readingDate),
                  onSelected: (_) {
                    setState(() => _selectedDate = _readingDate);
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Tomorrow'),
                  selected: _isSameDate(_selectedDate, _tomorrowDate),
                  onSelected: (_) {
                    setState(() => _selectedDate = _tomorrowDate);
                  },
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickCustomDate,
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Choose Date'),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      const StsDateTimeSelection(value: null, cleared: true),
                    );
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _selectedDateLabel(),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
                          12,
                          (index) {
                            final label = (index + 1).toString();
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
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) return;
    setState(
        () => _selectedDate = DateTime(picked.year, picked.month, picked.day));
  }

  DateTime _selectedDateTime() {
    final hour12 = _hourIndex + 1;
    final hour24 = _periodIndex == 1 ? (hour12 % 12) + 12 : (hour12 % 12);
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      hour24,
      _minuteIndex,
    );
  }

  int _displayHour(int hour24) {
    final hour12 = hour24 % 12;
    return hour12 == 0 ? 12 : hour12 - 1;
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _selectedDateLabel() {
    final localizations = MaterialLocalizations.of(context);
    if (_isSameDate(_selectedDate, _readingDate)) {
      return 'Date: Today';
    }
    if (_isSameDate(_selectedDate, _tomorrowDate)) {
      return 'Date: Tomorrow';
    }
    return 'Date: ${localizations.formatCompactDate(_selectedDate)}';
  }
}
