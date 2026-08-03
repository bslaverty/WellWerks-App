import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/services/app_settings_service.dart';
import 'package:wellwerks/theme/app_theme.dart';

void main() {
  group('AppThemeCatalog options', () {
    test('includes the expected theme ids and labels', () {
      expect(
        AppThemeCatalog.options.map((theme) => theme.id).toList(),
        <String>[
          'wellwerks_default',
          'negative',
          'patriot',
          'light',
          'military',
          'ou',
          'osu',
          'high_vis',
          'okc_thunder',
          'kc_chiefs',
        ],
      );

      expect(
        AppThemeCatalog.options.map((theme) => theme.label).toList(),
        <String>[
          'Classic',
          'Midnight',
          'Patriot',
          'Light',
          'Military',
          'OU',
          'OSU',
          'High Vis',
          'OKC Thunder',
          'KC Chiefs',
        ],
      );
    });

    test('fromId resolves all known ids and falls back safely', () {
      for (final option in AppThemeCatalog.options) {
        expect(AppThemeCatalog.fromId(option.id).id, option.id);
      }

      expect(AppThemeCatalog.fromId('invalid_theme').id, 'wellwerks_default');
    });
  });

  group('Theme palette intent', () {
    test('OU uses exact Build 88 crimson and cream palette', () {
      const theme = AppThemeCatalog.ou;
      expect(theme.accent, const Color(0xFF841617));
      expect(theme.appBarBackground, const Color(0xFF841617));
      expect(theme.surface, const Color(0xFFFDF9D8));
    });

    test('OSU is orange-first with black control accent', () {
      const theme = AppThemeCatalog.osu;
      expect(theme.background.computeLuminance(), greaterThan(0.35));
      expect(theme.surface.computeLuminance(), greaterThan(0.35));
      expect(theme.accent, Colors.black);
    });

    test('High Vis theme exists and has high-visibility accent', () {
      const theme = AppThemeCatalog.highVisibility;
      expect(theme.id, 'high_vis');
      expect(theme.accent.computeLuminance(), greaterThan(0.7));
      expect(theme.background.computeLuminance(), lessThan(0.02));
    });

    test('team themes exist with expected primary accents', () {
      expect(AppThemeCatalog.okcThunder.accent, const Color(0xFFEF7D00));
      expect(AppThemeCatalog.kcChiefs.accent, const Color(0xFFFFB612));
    });
  });

  group('Theme settings normalization', () {
    test('supports High Vis and Light theme persistence values', () {
      final light = AppSettingsData.fromJson({'appTheme': 'light'});
      final highVis = AppSettingsData.fromJson({'appTheme': 'high_vis'});
      expect(light.appTheme, 'light');
      expect(highVis.appTheme, 'high_vis');
    });

    test('maps legacy high_visibility to light and invalid to classic', () {
      final legacy = AppSettingsData.fromJson({'appTheme': 'high_visibility'});
      final invalid = AppSettingsData.fromJson({'appTheme': 'something_else'});
      expect(legacy.appTheme, 'light');
      expect(invalid.appTheme, AppSettingsDefaults.appTheme);
    });
  });

  group('Active controls derive from theme primary', () {
    test('high vis selected controls use selected theme accent', () {
      const selected = <WidgetState>{WidgetState.selected};

      final highVisTheme = buildAppTheme('high_vis');
      final highVisPrimary = highVisTheme.colorScheme.primary;
      expect(highVisTheme.switchTheme.thumbColor?.resolve(selected),
          highVisPrimary);
      expect(highVisTheme.checkboxTheme.fillColor?.resolve(selected),
          highVisPrimary);
      expect(
          highVisTheme.radioTheme.fillColor?.resolve(selected), highVisPrimary);
    });

    test('OU and OSU selected control colors match Build 89 requirements', () {
      const selected = <WidgetState>{WidgetState.selected};

      final classicTheme = buildAppTheme('wellwerks_default');
      final ouTheme = buildAppTheme('ou');
      final osuTheme = buildAppTheme('osu');

      expect(
        classicTheme.switchTheme.thumbColor?.resolve(selected),
        AppThemeCatalog.wellWerksDefault.accent,
      );
      expect(
        ouTheme.switchTheme.thumbColor?.resolve(selected),
        const Color(0xFF841617),
      );
      expect(
        osuTheme.switchTheme.thumbColor?.resolve(selected),
        const Color(0xFFF2F2F2),
      );
      expect(
        osuTheme.switchTheme.trackColor?.resolve(selected),
        Colors.black,
      );
      expect(
        osuTheme.checkboxTheme.fillColor?.resolve(selected),
        Colors.black,
      );
      expect(
        osuTheme.radioTheme.fillColor?.resolve(selected),
        Colors.black,
      );
    });

    test('OU app bar foreground is cream and cupertino primary follows accent',
        () {
      final osuTheme = buildAppTheme('osu');
      final ouTheme = buildAppTheme('ou');

      expect(
        osuTheme.cupertinoOverrideTheme?.primaryColor,
        AppThemeCatalog.osu.accent,
      );
      expect(
        ouTheme.cupertinoOverrideTheme?.primaryColor,
        AppThemeCatalog.ou.accent,
      );
      expect(ouTheme.appBarTheme.foregroundColor, const Color(0xFFFDF9D8));
    });
  });
}
