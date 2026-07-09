import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/app_settings_service.dart';
import '../services/app_theme_controller.dart';
import '../widgets/app_header.dart';
import 'about_support_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _bg => Theme.of(context).scaffoldBackgroundColor;
  Color get _card => Theme.of(context).cardColor;
  Color get _text => Theme.of(context).colorScheme.onSurface;
  Color get _subtle => Theme.of(context).colorScheme.onSurfaceVariant;

  final _service = AppSettingsService();
  AppSettingsData? _settings;
  String _appVersion = '--';
  String _appBuild = '--';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final settings = await _service.load();
    if (!mounted) return;
    setState(() {
      _appVersion = packageInfo.version;
      _appBuild = packageInfo.buildNumber;
      _settings = settings;
      _loading = false;
    });
  }

  String get _appVersionLabel =>
      _appBuild == '--' ? _appVersion : '$_appVersion ($_appBuild)';

  Future<void> _save(AppSettingsData next) async {
    await _service.save(next);
    AppThemeController.instance.setTheme(next.appTheme);
    if (!mounted) return;
    setState(() => _settings = next);
  }

  Future<void> _confirmAndRun({
    required String title,
    required String body,
    required Future<void> Function() action,
    required String success,
  }) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await action();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(success)));
  }

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: _accent,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            ..._withDividers(children),
          ],
        ),
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> children) {
    final out = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      out.add(children[i]);
      if (i != children.length - 1) {
        out.add(Divider(color: _accent.withValues(alpha: 0.25), height: 10));
      }
    }
    return out;
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: TextStyle(color: _text)),
      subtitle: Text(subtitle, style: TextStyle(color: _subtle)),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _dropdownTile({
    required String title,
    required String subtitle,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(color: _subtle, fontSize: 12)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          dropdownColor: _card,
          style: TextStyle(color: _text),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    if (_loading || s == null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: const AppHeader(title: 'WellWerks Settings', showBack: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: const AppHeader(title: 'WellWerks Settings', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _accent.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WellWerks Settings',
                  style: TextStyle(
                    color: _accent,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Version: $_appVersionLabel',
                  style: TextStyle(color: _subtle),
                ),
              ],
            ),
          ),
          _sectionCard(
            title: 'Production',
            children: [
              _switchTile(
                title: 'Active Job Defaults',
                subtitle: 'Apply saved production defaults on job tools.',
                value: s.productionActiveJobDefaults,
                onChanged: (value) {
                  _save(s.copyWith(productionActiveJobDefaults: value));
                },
              ),
              _dropdownTile(
                title: 'Production Report',
                subtitle: 'Default report detail level.',
                value: s.productionReportLayout,
                items: const [
                  DropdownMenuItem(value: 'standard', child: Text('Standard')),
                  DropdownMenuItem(value: 'detailed', child: Text('Detailed')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _save(s.copyWith(productionReportLayout: value));
                },
              ),
              _dropdownTile(
                title: 'Text Update Layout',
                subtitle: 'Default text update layout style.',
                value: s.productionTextUpdateLayout,
                items: const [
                  DropdownMenuItem(value: 'standard', child: Text('Standard')),
                  DropdownMenuItem(value: 'compact', child: Text('Compact')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _save(s.copyWith(productionTextUpdateLayout: value));
                },
              ),
            ],
          ),
          _sectionCard(
            title: 'Completions',
            children: [
              _switchTile(
                title: 'Rate Calculator',
                subtitle: 'Keep calculator defaults synced from Settings.',
                value: true,
                onChanged: (_) {},
              ),
              _switchTile(
                title: 'Bottoms Up Calculator',
                subtitle: 'Keep clipboard update behavior enabled.',
                value: true,
                onChanged: (_) {},
              ),
              _dropdownTile(
                title: 'Rate Display Defaults',
                subtitle:
                    'Default display unit for new rate calculator sessions.',
                value: s.completionsRateDisplayDefault,
                items: const [
                  DropdownMenuItem(value: 'bbl_min', child: Text('BBL/min')),
                  DropdownMenuItem(value: 'bbl_hr', child: Text('BBL/hr')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _save(s.copyWith(completionsRateDisplayDefault: value));
                },
              ),
              _dropdownTile(
                title: 'Timer Defaults',
                subtitle: 'Default timer length for timed rate.',
                value: s.completionsTimerDefaultMinutes.toString(),
                items: List<DropdownMenuItem<String>>.generate(
                  60,
                  (index) {
                    final minute = index + 1;
                    return DropdownMenuItem<String>(
                      value: minute.toString(),
                      child: Text(minute == 1 ? '1 minute' : '$minute minutes'),
                    );
                  },
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value ?? '');
                  if (parsed == null) return;
                  _save(s.copyWith(completionsTimerDefaultMinutes: parsed));
                },
              ),
            ],
          ),
          _sectionCard(
            title: 'JSA',
            children: [
              _switchTile(
                title: 'Auto Date',
                subtitle: 'Auto-populate date when creating JSA.',
                value: s.jsaAutoDate,
                onChanged: (value) => _save(s.copyWith(jsaAutoDate: value)),
              ),
              _switchTile(
                title: 'Auto Time',
                subtitle: 'Auto-populate time when creating JSA.',
                value: s.jsaAutoTime,
                onChanged: (value) => _save(s.copyWith(jsaAutoTime: value)),
              ),
              _switchTile(
                title: 'Auto Location',
                subtitle: 'Use GPS location when permissions are granted.',
                value: s.jsaAutoLocation,
                onChanged: (value) => _save(s.copyWith(jsaAutoLocation: value)),
              ),
              _switchTile(
                title: 'Auto Weather',
                subtitle: 'Fetch current weather when location is available.',
                value: s.jsaAutoWeather,
                onChanged: (value) => _save(s.copyWith(jsaAutoWeather: value)),
              ),
              _dropdownTile(
                title: 'Company Defaults',
                subtitle: 'Default company for new JSA forms.',
                value: s.jsaCompanyDefault,
                items: const [
                  DropdownMenuItem(
                      value: 'Mach Energy', child: Text('Mach Energy')),
                  DropdownMenuItem(
                      value: 'Continental', child: Text('Continental')),
                  DropdownMenuItem(value: 'Devon', child: Text('Devon')),
                  DropdownMenuItem(value: 'XTO', child: Text('XTO')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _save(s.copyWith(jsaCompanyDefault: value));
                },
              ),
            ],
          ),
          _sectionCard(
            title: 'Layout Designer',
            children: [
              _dropdownTile(
                title: 'Inventory',
                subtitle: 'Preferred inventory card density.',
                value: s.layoutInventoryMode,
                items: const [
                  DropdownMenuItem(value: 'standard', child: Text('Standard')),
                  DropdownMenuItem(value: 'compact', child: Text('Compact')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _save(s.copyWith(layoutInventoryMode: value));
                },
              ),
              _dropdownTile(
                title: 'Default Equipment',
                subtitle: 'Default equipment profile set.',
                value: s.layoutDefaultEquipment,
                items: const [
                  DropdownMenuItem(value: 'flowback', child: Text('Flowback')),
                  DropdownMenuItem(value: 'full', child: Text('Full Site')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _save(s.copyWith(layoutDefaultEquipment: value));
                },
              ),
            ],
          ),
          _sectionCard(
            title: 'Charts',
            children: [
              _dropdownTile(
                title: 'Chlorides Defaults',
                subtitle: 'Default chlorides result unit.',
                value: s.chartsChloridesDefault,
                items: const [
                  DropdownMenuItem(value: 'ppm', child: Text('PPM')),
                  DropdownMenuItem(value: 'mg_l', child: Text('mg/L')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _save(s.copyWith(chartsChloridesDefault: value));
                },
              ),
              _dropdownTile(
                title: 'Units',
                subtitle: 'Default chart unit system.',
                value: s.chartsUnits,
                items: const [
                  DropdownMenuItem(value: 'field', child: Text('Field')),
                  DropdownMenuItem(value: 'metric', child: Text('Metric')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _save(s.copyWith(chartsUnits: value));
                },
              ),
            ],
          ),
          _sectionCard(
            title: 'History',
            children: [
              _dropdownTile(
                title: 'History Retention',
                subtitle: 'Default retention target for local records.',
                value: s.historyRetentionDays.toString(),
                items: const [
                  DropdownMenuItem(value: '7', child: Text('7 days')),
                  DropdownMenuItem(value: '30', child: Text('30 days')),
                  DropdownMenuItem(value: '90', child: Text('90 days')),
                  DropdownMenuItem(value: '365', child: Text('1 year')),
                ],
                onChanged: (value) {
                  final parsed = int.tryParse(value ?? '');
                  if (parsed == null) return;
                  _save(s.copyWith(historyRetentionDays: parsed));
                },
              ),
              _dropdownTile(
                title: 'Export',
                subtitle: 'Preferred history export format.',
                value: s.historyExportMode,
                items: const [
                  DropdownMenuItem(value: 'csv', child: Text('CSV')),
                  DropdownMenuItem(value: 'json', child: Text('JSON')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _save(s.copyWith(historyExportMode: value));
                },
              ),
            ],
          ),
          _sectionCard(
            title: 'App',
            children: [
              _switchTile(
                title: 'Notifications',
                subtitle: 'Enable app reminder notifications.',
                value: s.appNotifications,
                onChanged: (value) =>
                    _save(s.copyWith(appNotifications: value)),
              ),
              _dropdownTile(
                title: 'Theme',
                subtitle: 'WellWerks visual profile.',
                value: s.appTheme,
                items: const [
                  DropdownMenuItem(
                    value: 'wellwerks_default',
                    child: Text('WellWerks Classic'),
                  ),
                  DropdownMenuItem(
                    value: 'negative',
                    child: Text('Midnight'),
                  ),
                  DropdownMenuItem(value: 'patriot', child: Text('Patriot')),
                  DropdownMenuItem(
                    value: 'high_visibility',
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(value: 'military', child: Text('Military')),
                  DropdownMenuItem(value: 'ou', child: Text('OU')),
                  DropdownMenuItem(value: 'osu', child: Text('OSU')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _save(s.copyWith(appTheme: value));
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline, color: _accent),
                title: Text('About WellWerks', style: TextStyle(color: _text)),
                subtitle: Text(
                  'App info, support, privacy policy, and terms.',
                  style: TextStyle(color: _subtle),
                ),
                trailing: Icon(Icons.chevron_right, color: _subtle),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  );
                },
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmAndRun(
                    title: 'Clear Active Data?',
                    body:
                        'This clears active job, active production shift, and current JSA draft.',
                    action: _service.clearActiveData,
                    success: 'Active local data cleared.',
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear Active Data'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmAndRun(
                    title: 'Clear Archived History?',
                    body: 'This removes all archived local history records.',
                    action: _service.clearHistory,
                    success: 'Archived history cleared.',
                  ),
                  icon: const Icon(Icons.history_toggle_off),
                  label: const Text('Clear Archived History'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
