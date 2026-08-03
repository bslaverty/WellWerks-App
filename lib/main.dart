import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/app_settings_service.dart';
import 'services/app_theme_controller.dart';
import 'services/job_profile_defaults_service.dart';
import 'services/rate_timer_notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RateTimerNotificationService.instance.ensureInitialized();
  await RateTimerNotificationService.instance.syncQuickRoundReminderFromPrefs();
  await JobProfileDefaultsService().ensureCustomProfilesLoaded();
  final settings = await AppSettingsService().load();
  AppThemeController.instance.setTheme(settings.appTheme);
  runApp(const WellWerksApp());
}

class WellWerksApp extends StatelessWidget {
  const WellWerksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppThemeController.instance.themeId,
      builder: (context, themeId, _) {
        return MaterialApp(
          title: 'WellWerks Toolbox',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(themeId),
          builder: (context, child) {
            return _GlobalChromeBackground(
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const HomeScreen(),
        );
      },
    );
  }
}

class _GlobalChromeBackground extends StatelessWidget {
  const _GlobalChromeBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background =
        Color.lerp(colors.surface, colors.primary, 0.06) ?? colors.surface;
    final accent = colors.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(background, accent, 0.12) ?? background,
            background,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            left: -120,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.08),
                ),
                child: const SizedBox(width: 260, height: 260),
              ),
            ),
          ),
          Positioned(
            right: -90,
            top: 130,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.06),
                ),
                child: const SizedBox(width: 200, height: 200),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
