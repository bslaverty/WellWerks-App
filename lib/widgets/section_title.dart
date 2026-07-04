import 'package:flutter/material.dart';

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Text(text.toUpperCase(), style: const TextStyle(color: Color(0xFFCDA56A), fontWeight: FontWeight.w900, letterSpacing: .8)),
    );
  }
}
