import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';

class ModuleMenuScreen extends StatelessWidget {
  final String title;
  final List<ModuleTool> tools;

  const ModuleMenuScreen({
    super.key,
    required this.title,
    required this.tools,
  });

  void _open(BuildContext context, Widget? screen, String title) {
    if (screen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title is on the build list.')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(title: title, showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: tools
            .map(
              (tool) => ToolCard(
                icon: tool.icon,
                title: tool.title,
                subtitle: tool.subtitle,
                onTap: () => _open(context, tool.screen, tool.title),
              ),
            )
            .toList(),
      ),
    );
  }
}

class ModuleTool {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? screen;

  const ModuleTool({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.screen,
  });
}
