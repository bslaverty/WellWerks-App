import 'package:flutter/cupertino.dart';
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
    label: 'Classic',
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

  static const light = AppThemeOption(
    id: 'light',
    label: 'Light',
    brightness: Brightness.light,
    background: Color(0xFFF3F2EF),
    surface: Color(0xFFFFFFFF),
    appBarBackground: Color(0xFFF8F6F2),
    accent: Color(0xFFC09A63),
    text: Color(0xFF1A1A1A),
    subtleText: Color(0xFF5A5A5A),
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

  static const ou = AppThemeOption(
    id: 'ou',
    label: 'OU',
    brightness: Brightness.dark,
    background: Color(0xFF2A1010),
    surface: Color(0xFFFDF9D8),
    appBarBackground: Color(0xFF841617),
    accent: Color(0xFF841617),
    text: Color(0xFF2A1A14),
    subtleText: Color(0xFF5F3B2D),
  );

  static const osu = AppThemeOption(
    id: 'osu',
    label: 'OSU',
    brightness: Brightness.dark,
    background: Color(0xFFFF8A00),
    surface: Color(0xFFFFA640),
    appBarBackground: Color(0xFFFF8A00),
    accent: Color(0xFF000000),
    text: Color(0xFF2F2F2F),
    subtleText: Color(0xFF4F4F4F),
  );

  static const highVisibility = AppThemeOption(
    id: 'high_vis',
    label: 'High Vis',
    brightness: Brightness.dark,
    background: Color(0xFF050505),
    surface: Color(0xFF101010),
    appBarBackground: Color(0xFF000000),
    accent: Color(0xFFE9FF2F),
    text: Color(0xFFF5F5F5),
    subtleText: Color(0xFFD6D6D6),
  );

  static const okcThunder = AppThemeOption(
    id: 'okc_thunder',
    label: 'OKC Thunder',
    brightness: Brightness.dark,
    background: Color(0xFF0A1A2F),
    surface: Color(0xFF123057),
    appBarBackground: Color(0xFF0A213D),
    accent: Color(0xFFEF7D00),
    text: Colors.white,
    subtleText: Color(0xFFC8D5E8),
  );

  static const kcChiefs = AppThemeOption(
    id: 'kc_chiefs',
    label: 'KC Chiefs',
    brightness: Brightness.dark,
    background: Color(0xFF1A0005),
    surface: Color(0xFF3A0914),
    appBarBackground: Color(0xFF220008),
    accent: Color(0xFFFFB612),
    text: Colors.white,
    subtleText: Color(0xFFF1CDD6),
  );

  static const options = <AppThemeOption>[
    wellWerksDefault,
    negative,
    patriot,
    light,
    military,
    ou,
    osu,
    highVisibility,
    okcThunder,
    kcChiefs,
  ];

  static AppThemeOption fromId(String id) {
    final normalized = id.trim().toLowerCase();
    final resolved = normalized == 'high_visibility' ? 'light' : normalized;
    for (final option in options) {
      if (option.id == resolved) return option;
    }
    return wellWerksDefault;
  }
}

ThemeData buildAppTheme(String themeId) {
  final option = AppThemeCatalog.fromId(themeId);
  const ouCream = Color(0xFFFDF9D8);
  final isOu = option.id == 'ou';
  final isOsu = option.id == 'osu';
  final onAccent =
      option.accent.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  final appBarForeground =
      isOu ? ouCream : (isOsu ? Colors.black : option.accent);

  final scheme = ColorScheme.fromSeed(
    seedColor: option.accent,
    brightness: option.brightness,
  ).copyWith(
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
    outline: option.accent.withValues(alpha: 0.55),
    outlineVariant: option.accent.withValues(alpha: 0.3),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: option.brightness,
    colorScheme: scheme,
    cupertinoOverrideTheme: CupertinoThemeData(
      primaryColor: option.accent,
      scaffoldBackgroundColor: option.background,
      barBackgroundColor: option.surface,
      textTheme: CupertinoTextThemeData(
        primaryColor: option.accent,
        textStyle: TextStyle(color: option.text),
      ),
    ),
    scaffoldBackgroundColor: option.background,
    canvasColor: option.background,
    dividerColor: option.accent.withValues(alpha: 0.28),
    iconTheme: IconThemeData(color: option.accent),
    fontFamily: 'Arial',
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: option.appBarBackground,
      foregroundColor: appBarForeground,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: appBarForeground),
      actionsIconTheme: IconThemeData(color: appBarForeground),
      titleTextStyle: TextStyle(
        color: appBarForeground,
        fontWeight: FontWeight.w800,
        fontSize: 20,
      ),
    ),
    cardTheme: CardThemeData(
      color: option.surface,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: option.accent.withValues(alpha: 0.22)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      iconColor: option.accent,
      tileColor: option.surface.withValues(alpha: 0.45),
      textColor: option.text,
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
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 1.8),
      ),
      iconColor: option.accent,
      prefixIconColor: option.accent,
      suffixIconColor: option.accent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: option.accent,
        foregroundColor: onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: option.accent,
        foregroundColor: onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: option.accent.withValues(alpha: 0.8)),
        foregroundColor: option.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: option.accent,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: option.accent,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return option.subtleText.withValues(alpha: 0.45);
        }
        if (states.contains(WidgetState.selected)) {
          if (isOsu) return const Color(0xFFF2F2F2);
          return option.accent;
        }
        return option.subtleText;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return option.subtleText.withValues(alpha: 0.2);
        }
        if (states.contains(WidgetState.selected)) {
          if (isOsu) return Colors.black;
          return option.accent.withValues(alpha: 0.45);
        }
        if (isOsu) return const Color(0xFF4A4A4A);
        return option.subtleText.withValues(alpha: 0.35);
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return isOsu ? Colors.black : option.accent;
        }
        return scheme.outlineVariant;
      }),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return option.subtleText.withValues(alpha: 0.2);
        }
        if (states.contains(WidgetState.selected)) {
          return isOsu ? Colors.black : option.accent;
        }
        return option.surface;
      }),
      checkColor: WidgetStatePropertyAll<Color>(onAccent),
      side: BorderSide(color: scheme.outline),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return option.subtleText.withValues(alpha: 0.35);
        }
        if (states.contains(WidgetState.selected)) {
          return isOsu ? Colors.black : option.accent;
        }
        return option.subtleText;
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return option.accent.withValues(alpha: 0.2);
          }
          return option.surface;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return option.accent;
          }
          return option.text;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return BorderSide(color: option.accent, width: 1.4);
          }
          return BorderSide(color: scheme.outlineVariant);
        }),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: option.accent,
      inactiveTrackColor: option.subtleText.withValues(alpha: 0.35),
      thumbColor: option.accent,
      overlayColor: option.accent.withValues(alpha: 0.18),
      valueIndicatorColor: option.accent,
      valueIndicatorTextStyle: TextStyle(color: onAccent),
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
          borderSide: BorderSide(color: option.accent, width: 1.8),
        ),
      ),
      textStyle: TextStyle(color: option.text),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: option.surface,
      contentTextStyle: TextStyle(color: option.text),
      actionTextColor: option.accent,
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
      dragHandleColor: option.accent.withValues(alpha: 0.75),
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
      checkmarkColor: onAccent,
      side: BorderSide(color: option.accent.withValues(alpha: 0.35)),
      labelStyle: TextStyle(color: option.text),
      secondaryLabelStyle: TextStyle(color: option.text),
      backgroundColor: option.surface,
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: option.surface,
      hourMinuteColor: option.accent.withValues(alpha: 0.18),
      hourMinuteTextColor: option.text,
      dayPeriodColor: option.surface,
      dayPeriodTextColor: option.text,
      dialBackgroundColor: option.surface,
      dialHandColor: option.accent,
      dialTextColor: option.text,
      entryModeIconColor: option.accent,
      helpTextStyle:
          TextStyle(color: option.accent, fontWeight: FontWeight.w700),
      confirmButtonStyle: TextButton.styleFrom(foregroundColor: option.accent),
      cancelButtonStyle:
          TextButton.styleFrom(foregroundColor: option.subtleText),
    ),
  );
}
