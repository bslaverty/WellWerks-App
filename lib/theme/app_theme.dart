import 'package:flutter/material.dart';

class AppThemeOption {
  const AppThemeOption({
    required this.id,
    required this.label,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.accent,
    required this.text,
    required this.appBar,
  });

  final String id;
  final String label;
  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color accent;
  final Color text;
  final Color appBar;
}

class AppThemeCatalog {
  static const wellWerksDefault = AppThemeOption(
    id: 'wellwerks_default',
    label: 'WellWerks Default',
    brightness: Brightness.dark,
    background: Color(0xFF0C0C0D),
    surface: Color(0xFF17191D),
    accent: Color(0xFFCDA56A),
    text: Colors.white,
    appBar: Color(0xFF0D0D0F),
  );

  static const negative = AppThemeOption(
    id: 'negative',
    label: 'Negative',
    brightness: Brightness.light,
    background: Color(0xFFF5F4EF),
    surface: Color(0xFFFFFFFF),
    accent: Color(0xFFCDA56A),
    text: Color(0xFF1A1A1A),
    appBar: Color(0xFFE8E6DF),
  );

  static const osu = AppThemeOption(
    id: 'osu',
    label: 'OSU',
    brightness: Brightness.dark,
    background: Color(0xFF0A0A0A),
    surface: Color(0xFF161616),
    accent: Color(0xFFFF6A13),
    text: Colors.white,
    appBar: Color(0xFF0F0F0F),
  );

  static const ou = AppThemeOption(
    id: 'ou',
    label: 'OU',
    brightness: Brightness.light,
    background: Color(0xFFF3EEDD),
    surface: Color(0xFFFFF8EA),
    accent: Color(0xFF841617),
    text: Color(0xFF1A1A1A),
    appBar: Color(0xFFF8F3E4),
  );

  static const military = AppThemeOption(
    id: 'military',
    label: 'Military',
    brightness: Brightness.dark,
    background: Color(0xFF2E3628),
    surface: Color(0xFF3A4331),
    accent: Color(0xFFC19A6B),
    text: Colors.white,
    appBar: Color(0xFF303828),
  );

  static const highVisibility = AppThemeOption(
    id: 'high_visibility',
    label: 'High Visibility',
    brightness: Brightness.dark,
    background: Color(0xFF050505),
    surface: Color(0xFF171717),
    accent: Color(0xFFFFE500),
    text: Colors.white,
    appBar: Color(0xFF080808),
  );

  static const options = <AppThemeOption>[
    wellWerksDefault,
    negative,
    osu,
    ou,
    military,
    highVisibility,
  ];

  static AppThemeOption fromId(String id) {
    final normalized = id.trim().toLowerCase();
    for (final option in options) {
      if (option.id == normalized) return option;
    }
    return wellWerksDefault;
  }
}

ThemeData buildAppTheme(String themeId) {
  final option = AppThemeCatalog.fromId(themeId);
  final scheme = ColorScheme(
    brightness: option.brightness,
    primary: option.accent,
    onPrimary:
        option.brightness == Brightness.dark ? Colors.black : Colors.white,
    secondary: option.accent,
    onSecondary:
        option.brightness == Brightness.dark ? Colors.black : Colors.white,
    error: Colors.red.shade700,
    onError: Colors.white,
    surface: option.surface,
    onSurface: option.text,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: option.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: option.background,
    fontFamily: 'Arial',
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: option.appBar,
      foregroundColor: option.text,
      elevation: 0,
      iconTheme: IconThemeData(color: option.text),
      titleTextStyle: TextStyle(
        color: option.accent,
        fontWeight: FontWeight.w800,
        fontSize: 20,
      ),
    ),
    cardTheme: CardThemeData(
      color: option.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerColor: option.accent.withValues(alpha: 0.28),
    textTheme: base.textTheme.apply(
      bodyColor: option.text,
      displayColor: option.text,
    ),
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: TextStyle(color: option.text.withValues(alpha: 0.85)),
      hintStyle: TextStyle(color: option.text.withValues(alpha: 0.6)),
      filled: true,
      fillColor: option.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: option.accent.withValues(alpha: 0.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: option.accent, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: option.accent,
        foregroundColor:
            option.brightness == Brightness.dark ? Colors.black : Colors.white,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: option.accent.withValues(alpha: 0.7)),
        foregroundColor: option.text,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: option.surface,
      contentTextStyle: TextStyle(color: option.text),
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: option.accent.withValues(alpha: 0.28),
      checkmarkColor: option.accent,
      side: BorderSide(color: option.accent.withValues(alpha: 0.35)),
      labelStyle: TextStyle(color: option.text),
      secondaryLabelStyle: TextStyle(color: option.text),
    ),
  );
}
