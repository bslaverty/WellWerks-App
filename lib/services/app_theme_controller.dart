import 'package:flutter/foundation.dart';

import 'app_settings_service.dart';

class AppThemeController {
  AppThemeController._();

  static final AppThemeController instance = AppThemeController._();

  final ValueNotifier<String> themeId =
      ValueNotifier<String>(AppSettingsDefaults.appTheme);

  void setTheme(String nextTheme) {
    final normalized = nextTheme.trim().toLowerCase();
    if (themeId.value == normalized) return;
    themeId.value = normalized;
  }
}
