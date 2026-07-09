import 'package:flutter/material.dart';

class AppThemeOption {
  const AppThemeOption({
    required this.id,
    required this.label,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.appBarBackground,
    required this.accent,
    required this.text,
    required this.subtleText,
  });

  final String id;
  final String label;
  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color appBarBackground;
  final Color accent;
  final Color text;
  final Color subtleText;
}

class AppThemeCatalog {
  static const wellWerksDefault = AppThemeOption(
    id: 'wellwerks_default',
    label: 'WellWerks Classic',
    brightness: Brightness.dark,
    background: Color(0xFF0B0B0C),
    surface: Color(0xFF171513),
    appBarBackground: Color(0xFF0A0908),
    accent: Color(0xFFCDA56A),
    text: Colors.white,
    subtleText: Color(0xFFC1B9AE),
  );

  static const negative = AppThemeOption(
    id: 'negative',
    label: 'Midnight',
    brightness: Brightness.dark,
    background: Color(0xFF0D131A),
    surface: Color(0xFF1A232D),
    appBarBackground: Color(0xFF0B1118),
    accent: Color(0xFF7897B6),
    text: Colors.white,
    subtleText: Color(0xFFB2C0CE),
  );

  static const patriot = AppThemeOption(
    id: 'patriot',
    label: 'Patriot',
    brightness: Brightness.dark,
    background: Color(0xFF0C1626),
    surface: Color(0xFF18273C),
    appBarBackground: Color(0xFF0A1526),
    accent: Color(0xFFB15D5D),
    text: Colors.white,
    subtleText: Color(0xFFC4CEDC),
  );

  static const osu = AppThemeOption(
    id: 'osu',
    label: 'OSU',
    brightness: Brightness.dark,
    background: Color(0xFF120E0C),
    surface: Color(0xFF231913),
    appBarBackground: Color(0xFF110D0B),
    accent: Color(0xFFDC7A28),
    text: Colors.white,
    subtleText: Color(0xFFC2B6AE),
  );

  static const ou = AppThemeOption(
    id: 'ou',
    label: 'OU',
    brightness: Brightness.dark,
    background: Color(0xFF160E10),
    surface: Color(0xFF28191E),
    appBarBackground: Color(0xFF140D0F),
    accent: Color(0xFFB04A54),
    text: Colors.white,
    subtleText: Color(0xFFE3D7CA),
  );

  static const military = AppThemeOption(
    id: 'military',
    label: 'Military',
    brightness: Brightness.dark,
    background: Color(0xFF10150F),
    surface: Color(0xFF1C251A),
    appBarBackground: Color(0xFF0F150E),
    accent: Color(0xFFC1A06E),
    text: Colors.white,
    subtleText: Color(0xFFBAC3B2),
  );

  static const highVisibility = AppThemeOption(
    id: 'high_visibility',
    label: 'Light',
    brightness: Brightness.light,
    background: Color(0xFFF3F2EF),
    surface: Color(0xFFFFFFFF),
    appBarBackground: Color(0xFFF8F6F2),
    accent: Color(0xFFC09A63),
    text: Color(0xFF1A1A1A),
    subtleText: Color(0xFF5A5A5A),
  );

  static const options = <AppThemeOption>[
    wellWerksDefault,
    negative,
    patriot,
    highVisibility,
    military,
    ou,
    osu,
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
      option.accent.computeLuminance() > 0.5 ? Colors.black : Colors.white;
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
      backgroundColor: option.appBarBackground,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    popupMenuTheme: PopupMenuThemeData(
      color: option.surface,
      textStyle: TextStyle(color: option.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: option.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: TextStyle(
        color: option.text,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: TextStyle(color: option.text),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: option.surface,
      modalBackgroundColor: option.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: option.surface,
      indicatorColor: option.accent.withValues(alpha: 0.2),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: option.accent);
        }
        return IconThemeData(color: option.subtleText);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          color: states.contains(WidgetState.selected)
              ? option.accent
              : option.subtleText,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
        );
      }),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: option.surface,
      selectedItemColor: option.accent,
      unselectedItemColor: option.subtleText,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: option.accent,
      textColor: option.text,
      tileColor: option.surface,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: option.accent,
      foregroundColor: onAccent,
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
