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

  const WwNumberField({
    super.key,
    required this.label,
    required this.controller,
    this.helperText,
    this.hintText,
    this.allowDecimal = true,
    this.allowNegative = false,
    this.textInputAction = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
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

class WwGaugeField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? helperText;
  final TextInputAction textInputAction;

  const WwGaugeField({
    super.key,
    required this.label,
    required this.controller,
    this.helperText,
    this.textInputAction = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: textInputAction,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9./\s]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Example: 12 3/8',
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
