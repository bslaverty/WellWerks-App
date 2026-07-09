import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBack;
  final bool showHomeAction;
  final List<Widget>? trailingActions;

  const AppHeader({
    super.key,
    this.title = 'WellWerks Toolbox',
    this.showBack = false,
    this.showHomeAction = false,
    this.trailingActions,
  });

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _goHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            )
          : IconButton(
              icon: const Icon(Icons.home),
              onPressed: () => _goHome(context),
            ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/app-icon.png',
              width: 34,
              height: 34,
              errorBuilder: (_, __, ___) => const SizedBox()),
          const SizedBox(width: 10),
          Text(title,
              style: TextStyle(
                  color: colors.primary, fontWeight: FontWeight.w800)),
        ],
      ),
      centerTitle: true,
      actions: trailingActions ??
          [
            if (showBack || showHomeAction)
              IconButton(
                icon: const Icon(Icons.home),
                onPressed: () => _goHome(context),
              )
            else
              const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () => _openSettings(context),
            ),
          ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
