import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ChokeSelection {
  const ChokeSelection({
    required this.type,
    this.size64,
  });

  final String type;
  final int? size64;

  bool get isNone => type == ChokeTypes.none;
}

class ChokeTypes {
  static const adjustable = 'ADJ';
  static const positive = 'POS';
  static const none = 'NONE';
}

String chokeTypeLabel(String type) {
  switch (type) {
    case ChokeTypes.positive:
      return 'Positive';
    case ChokeTypes.none:
      return 'None / Clear';
    case ChokeTypes.adjustable:
    default:
      return 'Adjustable';
  }
}

String formatChokeDisplay(ChokeSelection selection) {
  if (selection.type == ChokeTypes.none || selection.size64 == null) {
    return 'None / Clear';
  }
  final typeLabel =
      selection.type == ChokeTypes.positive ? 'Positive' : 'Adjustable';
  return '${selection.size64}/64" $typeLabel';
}

Future<ChokeSelection?> showChokeSelectorSheet(
  BuildContext context, {
  required ChokeSelection initial,
  bool allowNone = true,
  List<int>? adjustableSizes,
  List<int>? positiveSizes,
}) async {
  final adjSizes = adjustableSizes ?? List<int>.generate(63, (i) => i + 2);
  final posSizes = positiveSizes ?? List<int>.generate(63, (i) => i + 2);

  return showModalBottomSheet<ChokeSelection>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return _ChokeSelectorSheetBody(
        allowNone: allowNone,
        initialType: initial.type,
        initialSize64: initial.size64,
        adjustableSizes: adjSizes,
        positiveSizes: posSizes,
      );
    },
  );
}

class _ChokeSelectorSheetBody extends StatefulWidget {
  const _ChokeSelectorSheetBody({
    required this.allowNone,
    required this.initialType,
    required this.initialSize64,
    required this.adjustableSizes,
    required this.positiveSizes,
  });

  final bool allowNone;
  final String initialType;
  final int? initialSize64;
  final List<int> adjustableSizes;
  final List<int> positiveSizes;

  @override
  State<_ChokeSelectorSheetBody> createState() =>
      _ChokeSelectorSheetBodyState();
}

class _ChokeSelectorSheetBodyState extends State<_ChokeSelectorSheetBody> {
  late String _type;
  late int _sizeIndex;

  List<int?> get _sizeOptions => [
        if (widget.allowNone) null,
        ...List<int?>.generate(63, (i) => i + 2),
      ];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType == ChokeTypes.positive
        ? ChokeTypes.positive
        : (widget.initialType == ChokeTypes.none
            ? ChokeTypes.none
            : ChokeTypes.adjustable);

    final initialSize = _type == ChokeTypes.none ? null : widget.initialSize64;
    final idx = _sizeOptions.indexOf(initialSize);
    _sizeIndex = idx == -1 ? 0 : idx;
  }

  int? get _selectedSize64 => _sizeOptions[_sizeIndex];

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
                  'Choke Selector',
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
                    final size = _selectedSize64;
                    if (size == null) {
                      Navigator.of(context).pop(
                        const ChokeSelection(
                            type: ChokeTypes.none, size64: null),
                      );
                      return;
                    }
                    Navigator.of(context).pop(
                      ChokeSelection(type: _type, size64: size),
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
                            initialItem: _sizeIndex),
                        onSelectedItemChanged: (index) {
                          setState(() {
                            _sizeIndex = index;
                            if (_selectedSize64 == null) {
                              _type = ChokeTypes.none;
                            } else if (_type == ChokeTypes.none) {
                              _type = ChokeTypes.positive;
                            }
                          });
                        },
                        children: _sizeOptions
                            .map(
                              (size) => Center(
                                child: Text(
                                  size == null ? 'None / Clear' : '$size/64"',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _wheelContainer(
                      child: _selectedSize64 == null
                          ? Center(
                              child: Text(
                                'Type cleared',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Choke Type',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SegmentedButton<String>(
                                    segments: const [
                                      ButtonSegment<String>(
                                        value: ChokeTypes.positive,
                                        label: Text('Positive'),
                                      ),
                                      ButtonSegment<String>(
                                        value: ChokeTypes.adjustable,
                                        label: Text('Adjustable'),
                                      ),
                                    ],
                                    selected: {
                                      _type == ChokeTypes.positive
                                          ? ChokeTypes.positive
                                          : ChokeTypes.adjustable,
                                    },
                                    onSelectionChanged: (selected) {
                                      setState(() {
                                        _type = selected.first;
                                      });
                                    },
                                  ),
                                ],
                              ),
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
}
