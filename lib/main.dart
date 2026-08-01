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
          home: const HomeScreen(),
        );
      },
    );
  }
}
