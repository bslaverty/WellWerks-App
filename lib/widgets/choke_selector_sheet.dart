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
  if (selection.type == ChokeTypes.adjustable) {
    return 'Adjustable ${selection.size64}/64"';
  }
  return '${selection.size64}/64"';
}

Future<ChokeSelection?> showChokeSelectorSheet(
  BuildContext context, {
  required ChokeSelection initial,
  bool allowNone = true,
  List<int>? adjustableSizes,
  List<int>? positiveSizes,
}) async {
  final types = <String>[
    ChokeTypes.adjustable,
    ChokeTypes.positive,
    if (allowNone) ChokeTypes.none,
  ];

  final adjSizes = adjustableSizes ?? List<int>.generate(63, (i) => i + 2);
  final posSizes = positiveSizes ?? List<int>.generate(63, (i) => i + 2);

  final initialType =
      types.contains(initial.type) ? initial.type : ChokeTypes.adjustable;

  return showModalBottomSheet<ChokeSelection>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return _ChokeSelectorSheetBody(
        types: types,
        initialType: initialType,
        initialSize64: initial.size64,
        adjustableSizes: adjSizes,
        positiveSizes: posSizes,
      );
    },
  );
}

class _ChokeSelectorSheetBody extends StatefulWidget {
  const _ChokeSelectorSheetBody({
    required this.types,
    required this.initialType,
    required this.initialSize64,
    required this.adjustableSizes,
    required this.positiveSizes,
  });

  final List<String> types;
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
  late int _typeIndex;
  late int _sizeIndex;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _typeIndex = widget.types.indexOf(_type);

    final sizes = _activeSizes;
    final initialSize = widget.initialSize64 ?? sizes.first;
    final idx = sizes.indexOf(initialSize);
    _sizeIndex = idx == -1 ? 0 : idx;
  }

  List<int> get _activeSizes {
    return _type == ChokeTypes.positive
        ? widget.positiveSizes
        : widget.adjustableSizes;
  }

  int get _selectedSize64 {
    final sizes = _activeSizes;
    if (_sizeIndex < 0 || _sizeIndex >= sizes.length) {
      return sizes.first;
    }
    return sizes[_sizeIndex];
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
                    if (_type == ChokeTypes.none) {
                      Navigator.of(context).pop(
                        const ChokeSelection(
                            type: ChokeTypes.none, size64: null),
                      );
                      return;
                    }
                    Navigator.of(context).pop(
                      ChokeSelection(type: _type, size64: _selectedSize64),
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
                            initialItem: _typeIndex),
                        onSelectedItemChanged: (index) {
                          setState(() {
                            _typeIndex = index;
                            _type = widget.types[index];
                            final sizes = _activeSizes;
                            if (_sizeIndex >= sizes.length) {
                              _sizeIndex = sizes.length - 1;
                            }
                          });
                        },
                        children: widget.types
                            .map(
                              (type) => Center(
                                child: Text(
                                  chokeTypeLabel(type),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
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
                      child: _type == ChokeTypes.none
                          ? Center(
                              child: Text(
                                'No size',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : CupertinoPicker(
                              itemExtent: 44,
                              scrollController: FixedExtentScrollController(
                                initialItem: _sizeIndex,
                              ),
                              onSelectedItemChanged: (index) {
                                setState(() {
                                  _sizeIndex = index;
                                });
                              },
                              children: _activeSizes
                                  .map(
                                    (size) => Center(
                                      child: Text(
                                        '$size/64"',
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
