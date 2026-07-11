import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/services/app_settings_service.dart';
import 'package:wellwerks/theme/app_theme.dart';

void main() {
  group('AppThemeCatalog options', () {
    test('includes the expected eight themes and labels', () {
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
    test('OU uses crimson accent and cream-leaning surfaces', () {
      const theme = AppThemeCatalog.ou;
      final hue = HSLColor.fromColor(theme.accent).hue;
      expect(hue, greaterThan(340));
      expect(theme.surface.computeLuminance(),
          greaterThan(theme.background.computeLuminance()));
    });

    test('OSU uses orange accent and dark surfaces', () {
      const theme = AppThemeCatalog.osu;
      final hue = HSLColor.fromColor(theme.accent).hue;
      expect(hue, inInclusiveRange(15, 40));
      expect(theme.surface.computeLuminance(), lessThan(0.12));
    });

    test('High Vis theme exists and has high-visibility accent', () {
      const theme = AppThemeCatalog.highVisibility;
      expect(theme.id, 'high_vis');
      expect(theme.accent.computeLuminance(), greaterThan(0.7));
      expect(theme.background.computeLuminance(), lessThan(0.02));
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
    test(
        'switch, checkbox, and radio selected colors use selected theme accent',
        () {
      const selected = <WidgetState>{WidgetState.selected};

      final osuTheme = buildAppTheme('osu');
      final osuPrimary = osuTheme.colorScheme.primary;
      expect(osuTheme.switchTheme.thumbColor?.resolve(selected), osuPrimary);
      expect(osuTheme.checkboxTheme.fillColor?.resolve(selected), osuPrimary);
      expect(osuTheme.radioTheme.fillColor?.resolve(selected), osuPrimary);

      final highVisTheme = buildAppTheme('high_vis');
      final highVisPrimary = highVisTheme.colorScheme.primary;
      expect(highVisTheme.switchTheme.thumbColor?.resolve(selected),
          highVisPrimary);
      expect(highVisTheme.checkboxTheme.fillColor?.resolve(selected),
          highVisPrimary);
      expect(
          highVisTheme.radioTheme.fillColor?.resolve(selected), highVisPrimary);
    });

    test('classic, OU, and OSU switch selected thumb uses each theme accent',
        () {
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
        AppThemeCatalog.ou.accent,
      );
      expect(
        osuTheme.switchTheme.thumbColor?.resolve(selected),
        AppThemeCatalog.osu.accent,
      );
    });

    test('cupertino override primary color follows selected theme accent', () {
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
    });
  });
}
