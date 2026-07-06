import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WwNumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? helperText;
  final String? hintText;
  final bool allowDecimal;
  final bool allowNegative;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final FocusNode? focusNode;

  const WwNumberField({
    super.key,
    required this.label,
    required this.controller,
    this.helperText,
    this.hintText,
    this.allowDecimal = true,
    this.allowNegative = false,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: onChanged,
        keyboardType: TextInputType.numberWithOptions(
          decimal: allowDecimal,
          signed: allowNegative,
        ),
        textInputAction: textInputAction,
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp(allowNegative ? r'[0-9.\-]' : r'[0-9.]'),
          ),
        ],
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          helperText: helperText,
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear),
                  onPressed: () => controller.clear(),
                ),
        ),
      ),
    );
  }
}

class WwGaugeField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? helperText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final FocusNode? focusNode;

  const WwGaugeField({
    super.key,
    required this.label,
    required this.controller,
    this.helperText,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  State<WwGaugeField> createState() => _WwGaugeFieldState();
}

class _WwGaugeFieldState extends State<WwGaugeField> {
  static const _buttons = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '0',
    'Space',
    '1/8',
    '1/4',
    '3/8',
    '1/2',
    '5/8',
    '3/4',
    '7/8',
    '⌫',
  ];

  void _notifyChanged() {
    widget.onChanged?.call(widget.controller.text);
  }

  void _insert(String value) {
    final insertText = value == 'Space' ? ' ' : value;
    final selection = widget.controller.selection;
    final text = widget.controller.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final next = text.replaceRange(start, end, insertText);
    final cursor = start + insertText.length;

    setState(() {
      widget.controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: cursor),
      );
    });

    _notifyChanged();
  }

  void _backspace() {
    final selection = widget.controller.selection;
    final text = widget.controller.text;

    if (text.isEmpty) return;

    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;

    if (start != end) {
      setState(() {
        widget.controller.value = TextEditingValue(
          text: text.replaceRange(start, end, ''),
          selection: TextSelection.collapsed(offset: start),
        );
      });
    } else if (start > 0) {
      setState(() {
        widget.controller.value = TextEditingValue(
          text: text.replaceRange(start - 1, start, ''),
          selection: TextSelection.collapsed(offset: start - 1),
        );
      });
    }

    _notifyChanged();
  }

  void _clear() {
    setState(widget.controller.clear);
    _notifyChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            readOnly: true,
            showCursor: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: widget.textInputAction,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: 'Example: 12 3/8',
              helperText: widget.helperText,
              suffixIcon: widget.controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.clear),
                      onPressed: _clear,
                    ),
            ),
            onTap: () => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _buttons.map((button) {
              final isBackspace = button == '⌫';

              return SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: isBackspace ? _backspace : () => _insert(button),
                  child: Text(
                    button,
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
