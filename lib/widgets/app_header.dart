import 'package:flutter/material.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBack;

  const AppHeader({super.key, this.title = 'WellWerks', this.showBack = false});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFF0D0D0F),
      elevation: 0,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            )
          : IconButton(
              icon: const Icon(Icons.home),
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/app-icon.png', width: 34, height: 34, errorBuilder: (_, __, ___) => const SizedBox()),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(color: Color(0xFFCDA56A), fontWeight: FontWeight.w800)),
        ],
      ),
      centerTitle: true,
      actions: const [SizedBox(width: 56)],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
