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
  final String? errorText;

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
    this.errorText,
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
          errorText: errorText,
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

class WwGaugeField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? helperText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onTap;
  final bool active;

  const WwGaugeField({
    super.key,
    required this.label,
    required this.controller,
    this.helperText,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.autofocus = false,
    this.focusNode,
    this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        readOnly: true,
        showCursor: active,
        enableInteractiveSelection: false,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: textInputAction,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Example: 12 3/8',
          helperText: helperText,
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    onChanged?.call(controller.text);
                  },
                ),
          border: OutlineInputBorder(
            borderSide: BorderSide(
              color: active ? accent : const Color(0xFF4A4A4A),
              width: active ? 1.8 : 1.0,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: active ? accent : const Color(0xFF4A4A4A),
              width: active ? 1.8 : 1.0,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: accent, width: 2.0),
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
