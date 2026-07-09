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
    required this.subtleText,
  });

  final String id;
  final String label;
  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color accent;
  final Color text;
  final Color subtleText;
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
    subtleText: Color(0xFFB9B9B9),
  );

  static const negative = AppThemeOption(
    id: 'negative',
    label: 'Negative',
    brightness: Brightness.light,
    background: Color(0xFFF5F4EF),
    surface: Color(0xFFFFFFFF),
    accent: Color(0xFF141414),
    text: Color(0xFF1A1A1A),
    subtleText: Color(0xFF5A5A5A),
  );

  static const osu = AppThemeOption(
    id: 'osu',
    label: 'OSU',
    brightness: Brightness.dark,
    background: Color(0xFF0A0A0A),
    surface: Color(0xFF161616),
    accent: Color(0xFFFF6A13),
    text: Colors.white,
    subtleText: Color(0xFFC3C3C3),
  );

  static const ou = AppThemeOption(
    id: 'ou',
    label: 'OU',
    brightness: Brightness.light,
    background: Color(0xFFF3EEDD),
    surface: Color(0xFFFFF8EA),
    accent: Color(0xFF841617),
    text: Color(0xFF1A1A1A),
    subtleText: Color(0xFF55514A),
  );

  static const military = AppThemeOption(
    id: 'military',
    label: 'Military',
    brightness: Brightness.dark,
    background: Color(0xFF2E3628),
    surface: Color(0xFF3A4331),
    accent: Color(0xFFC19A6B),
    text: Colors.white,
    subtleText: Color(0xFFC4C4C4),
  );

  static const highVisibility = AppThemeOption(
    id: 'high_visibility',
    label: 'High Visibility',
    brightness: Brightness.dark,
    background: Color(0xFF050505),
    surface: Color(0xFF171717),
    accent: Color(0xFFFFE500),
    text: Colors.white,
    subtleText: Color(0xFFD0D0D0),
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
  final onAccent =
      option.brightness == Brightness.dark ? Colors.black : Colors.white;
  const appBarBlack = Color(0xFF000000);
  final scheme = ColorScheme(
    brightness: option.brightness,
    primary: option.accent,
    onPrimary: onAccent,
    secondary: option.accent,
    onSecondary: onAccent,
    tertiary: option.accent,
    onTertiary: onAccent,
    error: Colors.red.shade700,
    onError: Colors.white,
    surface: option.surface,
    onSurface: option.text,
    onSurfaceVariant: option.subtleText,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: option.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: option.background,
    canvasColor: option.background,
    dividerColor: option.accent.withValues(alpha: 0.28),
    iconTheme: IconThemeData(color: option.accent),
    fontFamily: 'Arial',
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: appBarBlack,
      foregroundColor: option.accent,
      elevation: 0,
      iconTheme: IconThemeData(color: option.accent),
      actionsIconTheme: IconThemeData(color: option.accent),
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
    textTheme: base.textTheme.apply(
      bodyColor: option.text,
      displayColor: option.text,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: option.accent,
      selectionColor: option.accent.withValues(alpha: 0.35),
      selectionHandleColor: option.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: TextStyle(color: option.text.withValues(alpha: 0.85)),
      hintStyle: TextStyle(color: option.text.withValues(alpha: 0.6)),
      helperStyle: TextStyle(color: option.subtleText),
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
      iconColor: option.accent,
      prefixIconColor: option.accent,
      suffixIconColor: option.accent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: option.accent,
        foregroundColor: onAccent,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: option.accent,
        foregroundColor: onAccent,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: option.accent.withValues(alpha: 0.7)),
        foregroundColor: option.text,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: option.accent,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return option.accent;
        }
        return option.subtleText;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return option.accent.withValues(alpha: 0.45);
        }
        return option.subtleText.withValues(alpha: 0.35);
      }),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return option.accent;
        return option.surface;
      }),
      checkColor: WidgetStatePropertyAll<Color>(onAccent),
      side: BorderSide(color: option.accent.withValues(alpha: 0.7)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return option.accent;
        return option.subtleText;
      }),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: option.accent,
      circularTrackColor: option.subtleText.withValues(alpha: 0.25),
      linearTrackColor: option.subtleText.withValues(alpha: 0.25),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: option.accent.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: option.accent, width: 1.4),
        ),
      ),
      textStyle: TextStyle(color: option.text),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: option.surface,
      contentTextStyle: TextStyle(color: option.text),
    ),
    dividerTheme: DividerThemeData(
      color: option.accent.withValues(alpha: 0.28),
      thickness: 1,
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: option.accent.withValues(alpha: 0.28),
      checkmarkColor: option.accent,
      side: BorderSide(color: option.accent.withValues(alpha: 0.35)),
      labelStyle: TextStyle(color: option.text),
      secondaryLabelStyle: TextStyle(color: option.text),
      backgroundColor: option.surface,
    ),
  );
}
