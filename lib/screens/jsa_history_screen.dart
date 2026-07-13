import 'package:flutter/material.dart';

import '../widgets/app_header.dart';
import '../widgets/jsa_history_pane.dart';

class JsaHistoryScreen extends StatelessWidget {
  const JsaHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: AppHeader(title: 'JSA History', showBack: true),
      body: JsaHistoryPane(),
    );
  }
}
