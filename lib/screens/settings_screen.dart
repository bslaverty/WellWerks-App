import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_settings_service.dart';
import '../services/app_theme_controller.dart';
import '../services/rate_timer_notification_service.dart';
import '../services/job_profile_defaults_service.dart';
import '../services/operations_sts_reminder_service.dart';
import '../utils/quick_round_reminder_utils.dart';
import '../widgets/app_header.dart';
import '../widgets/lead_time_wheel_picker_sheet.dart';
import 'about_support_screen.dart';
import 'operator_profile_screen.dart';

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
  final _stsReminderService = OperationsStsReminderService();
  final _notificationService = RateTimerNotificationService.instance;
  final _profileDefaults = JobProfileDefaultsService();
  AppSettingsData? _settings;
  List<CompanyProfileSettings> _companyProfiles =
      const <CompanyProfileSettings>[];
  String _appVersion = '--';
  String _appBuild = '--';
  bool _quickRoundReminderEnabled = false;
  int _quickRoundReminderMinute = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final packageInfo = await PackageInfo.fromPlatform();
    await _profileDefaults.ensureCustomProfilesLoaded();
    final settings = await _service.load();
    final prefs = await SharedPreferences.getInstance();
    final quickRoundEnabled = prefs.getBool(
            RateTimerNotificationService.quickRoundReminderEnabledKey) ??
        false;
    final quickRoundMinute = normalizeQuickRoundReminderMinute(
      prefs.getInt(RateTimerNotificationService.quickRoundReminderMinuteKey) ??
          0,
    );
    if (!mounted) return;
    setState(() {
      _appVersion = packageInfo.version;
      _appBuild = packageInfo.buildNumber;
      _settings = settings;
      _companyProfiles = _profileDefaults.customProfiles;
      _quickRoundReminderEnabled = quickRoundEnabled;
      _quickRoundReminderMinute = quickRoundMinute;
      _loading = false;
    });
  }

  Future<void> _saveQuickRoundReminderPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      RateTimerNotificationService.quickRoundReminderEnabledKey,
      _quickRoundReminderEnabled,
    );
    await prefs.setInt(
      RateTimerNotificationService.quickRoundReminderMinuteKey,
      _quickRoundReminderMinute,
    );
  }

  Future<void> _setQuickRoundReminderEnabled(bool enabled) async {
    if (enabled == _quickRoundReminderEnabled) return;

    if (!enabled) {
      await _notificationService.cancelQuickRoundReminder();
      if (!mounted) return;
      setState(() => _quickRoundReminderEnabled = false);
      await _saveQuickRoundReminderPrefs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quick Round reminder turned off.')),
      );
      return;
    }

    final granted = await _notificationService.requestNotificationPermission();
    if (!granted) {
      if (!mounted) return;
      setState(() => _quickRoundReminderEnabled = false);
      await _saveQuickRoundReminderPrefs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications must be enabled for the Quick Round reminder.',
          ),
        ),
      );
      return;
    }

    await _notificationService.scheduleQuickRoundReminder(
      minute: _quickRoundReminderMinute,
    );
    if (!mounted) return;
    setState(() => _quickRoundReminderEnabled = true);
    await _saveQuickRoundReminderPrefs();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Quick Round reminder set for :${formatQuickRoundReminderMinute(_quickRoundReminderMinute)} every hour.',
        ),
      ),
    );
  }

  Future<void> _setQuickRoundReminderMinute(int minute) async {
    final normalized = normalizeQuickRoundReminderMinute(minute);
    if (normalized == _quickRoundReminderMinute) return;

    final previous = _quickRoundReminderMinute;
    if (!mounted) return;
    setState(() => _quickRoundReminderMinute = normalized);
    await _saveQuickRoundReminderPrefs();

    if (!_quickRoundReminderEnabled) return;

    try {
      await _notificationService.scheduleQuickRoundReminder(
        minute: normalized,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Quick Round reminder set for :${formatQuickRoundReminderMinute(normalized)} every hour.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _quickRoundReminderMinute = previous);
      await _saveQuickRoundReminderPrefs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update Quick Round reminder minute.'),
        ),
      );
    }
  }

  String get _appVersionLabel =>
      _appBuild == '--' ? _appVersion : '$_appVersion ($_appBuild)';

  Future<void> _save(AppSettingsData next) async {
    await _service.save(next);
    AppThemeController.instance.setTheme(next.appTheme);
    if (!mounted) return;
    setState(() => _settings = next);
  }

  Future<void> _saveCompanyProfiles(
    List<CompanyProfileSettings> nextProfiles,
  ) async {
    await _profileDefaults.saveCustomProfiles(nextProfiles);
    if (!mounted) return;

    final options = _profileDefaults.companyOptions;
    var nextSettings = _settings;
    if (nextSettings != null) {
      final validJsa = options.where(
        (item) => item != JobProfileDefaultsService.companyNone,
      );
      final jsaFallback = validJsa.isEmpty
          ? JobProfileDefaultsService.companyMach
          : validJsa.first;
      if (!options.contains(nextSettings.jsaCompanyDefault)) {
        nextSettings = nextSettings.copyWith(jsaCompanyDefault: jsaFallback);
      }
      if (!options.contains(nextSettings.activeCompany)) {
        nextSettings = nextSettings.copyWith(
          activeCompany: JobProfileDefaultsService.companyNone,
        );
      }
    }

    setState(() {
      _companyProfiles = _profileDefaults.customProfiles;
      if (nextSettings != null) {
        _settings = nextSettings;
      }
    });

    if (nextSettings != null) {
      await _service.save(nextSettings);
    }
  }

  Future<void> _deleteCompanyProfile(CompanyProfileSettings profile) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Company Profile?'),
            content: Text(
              'Remove ${profile.name} and its custom defaults?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final next = _companyProfiles
        .where((item) => item.name.toLowerCase() != profile.name.toLowerCase())
        .toList(growable: false);
    await _saveCompanyProfiles(next);
  }

  Future<void> _openCompanyProfileEditor({
    CompanyProfileSettings? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    var selectedTemplate = existing?.templateCompany.isNotEmpty == true
        ? existing!.templateCompany
        : JobProfileDefaultsService.companyMach;
    final selectedSections = <String>{
      ...?existing?.defaultActiveSections,
    };

    final saved = await showDialog<CompanyProfileSettings>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: Text(
              existing == null ? 'Add Company Profile' : 'Edit Company Profile',
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Company Name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedTemplate,
                      decoration: const InputDecoration(
                        labelText: 'Field Template',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: JobProfileDefaultsService.companyMach,
                          child: Text('Mach Energy'),
                        ),
                        DropdownMenuItem(
                          value: JobProfileDefaultsService.companyContinental,
                          child: Text('Continental Resources'),
                        ),
                        DropdownMenuItem(
                          value: JobProfileDefaultsService.companyFlywheel,
                          child: Text('Flywheel Energy'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          selectedTemplate = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Default Active Equipment',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    for (final section
                        in JobProfileDefaultsService.optionalEquipmentSections)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: selectedSections.contains(section),
                        title: Text(section),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (enabled) {
                          setDialogState(() {
                            if (enabled ?? false) {
                              selectedSections.add(section);
                            } else {
                              selectedSections.remove(section);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final trimmed = nameController.text.trim();
                  if (trimmed.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Company name is required.')),
                    );
                    return;
                  }

                  final lower = trimmed.toLowerCase();
                  final builtIn = JobProfileDefaultsService
                      .sharedCompanyOptionsAlphabetized
                      .map((item) => item.toLowerCase())
                      .toSet();
                  final takenByOtherCustom = _companyProfiles.any((profile) {
                    final same = profile.name.toLowerCase() == lower;
                    final sameExisting = existing != null &&
                        profile.name.toLowerCase() ==
                            existing.name.toLowerCase();
                    return same && !sameExisting;
                  });

                  if (builtIn.contains(lower) &&
                      (existing == null ||
                          existing.name.toLowerCase() != lower)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'That name is already a built-in profile.',
                        ),
                      ),
                    );
                    return;
                  }

                  if (takenByOtherCustom) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('That company profile already exists.'),
                      ),
                    );
                    return;
                  }

                  Navigator.of(dialogContext).pop(
                    CompanyProfileSettings(
                      name: trimmed,
                      templateCompany: selectedTemplate,
                      defaultActiveSections: selectedSections.toList(),
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    nameController.dispose();

    if (saved == null) return;
    final next = <CompanyProfileSettings>[
      for (final profile in _companyProfiles)
        if (existing == null ||
            profile.name.toLowerCase() != existing.name.toLowerCase())
          profile,
      saved,
    ]..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    await _saveCompanyProfiles(next);
  }

  Future<void> _openSystemNotificationSettings() async {
    final uri = Uri.parse('app-settings:');
    final launched = await launchUrl(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open iPhone settings.')),
      );
    }
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

  String _leadTimeLabel(int minutes) {
    return _stsReminderService.leadTimeLabel(minutes);
  }

  Future<void> _setEstimatedStsReminderLeadTime(AppSettingsData current) async {
    final picked = await showLeadTimeWheelPickerSheet(
      context,
      title: 'Reminder Time',
      actionLabel: 'Set',
      options: OperationsStsReminderService.allowedLeadMinutes,
      initialMinutes: current.estimatedStsReminderLeadMinutes,
    );
    if (picked == null || !mounted) return;
    if (picked == current.estimatedStsReminderLeadMinutes) return;

    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Apply this reminder time to currently scheduled STS reminders?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop('futureOnly'),
            child: const Text('Future Reminders Only'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('updateScheduled'),
            child: const Text('Update Scheduled Reminders'),
          ),
        ],
      ),
    );
    if (!mounted || decision == null || decision == 'cancel') return;

    await _save(current.copyWith(estimatedStsReminderLeadMinutes: picked));
    if (decision == 'updateScheduled') {
      await _stsReminderService.updateUseDefaultScheduledReminders(
        newDefaultLeadMinutes: picked,
      );
    }
  }

  Future<void> _toggleEstimatedStsReminder(
    AppSettingsData current,
    bool enabled,
  ) async {
    if (enabled) {
      await _save(current.copyWith(estimatedStsReminderEnabled: true));
      return;
    }

    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel currently scheduled STS reminders?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop('keep'),
            child: const Text('Keep Reminders'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('cancelReminders'),
            child: const Text('Cancel Reminders'),
          ),
        ],
      ),
    );

    if (!mounted || decision == null || decision == 'cancel') return;
    await _save(current.copyWith(estimatedStsReminderEnabled: false));
    if (decision == 'cancelReminders') {
      await _stsReminderService.cancelAllScheduledFromRegistry();
    }
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
    required ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: TextStyle(color: _text)),
      subtitle: Text(subtitle, style: TextStyle(color: _subtle)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: _accent,
      activeTrackColor: _accent.withValues(alpha: 0.45),
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

    final jsaCompanyOptions = _profileDefaults.companyOptions
        .where((item) => item != JobProfileDefaultsService.companyNone)
        .toList(growable: false);
    final jsaCompanyValue = jsaCompanyOptions.contains(s.jsaCompanyDefault)
        ? s.jsaCompanyDefault
        : (jsaCompanyOptions.isEmpty
            ? JobProfileDefaultsService.companyMach
            : jsaCompanyOptions.first);

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
            title: 'Operator',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.badge_outlined, color: _accent),
                title: Text('Operator Profile', style: TextStyle(color: _text)),
                subtitle: Text(
                  'Name, initials, and local operator ID for logs and reports.',
                  style: TextStyle(color: _subtle),
                ),
                trailing: Icon(Icons.chevron_right, color: _subtle),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const OperatorProfileScreen(),
                    ),
                  );
                },
              ),
            ],
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
              _dropdownTile(
                title: 'Text Update Time Format',
                subtitle:
                    'Controls copied/shared text times (12-hour or 24-hour).',
                value: s.textTimeFormat,
                items: const [
                  DropdownMenuItem(value: '12h', child: Text('12-Hour Clock')),
                  DropdownMenuItem(value: '24h', child: Text('24-Hour Clock')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _save(s.copyWith(textTimeFormat: value));
                },
              ),
            ],
          ),
          _sectionCard(
            title: 'Operations Log',
            children: [
              _switchTile(
                title: 'Automatically Save Rate Calculations',
                subtitle:
                    'Save each successful Rate Calculator result to Operations Log.',
                value: s.autoSaveRateCalculationsToOperationsLog,
                onChanged: (value) => _save(
                  s.copyWith(autoSaveRateCalculationsToOperationsLog: value),
                ),
              ),
            ],
          ),
          _sectionCard(
            title: 'Company Profiles',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Built-in Profiles',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  JobProfileDefaultsService.sharedCompanyOptionsAlphabetized
                      .where((item) =>
                          item != JobProfileDefaultsService.companyNone)
                      .join(', '),
                  style: TextStyle(color: _subtle),
                ),
              ),
              if (_companyProfiles.isEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'No custom company profiles yet.',
                    style: TextStyle(color: _subtle),
                  ),
                )
              else
                for (final profile in _companyProfiles)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(profile.name, style: TextStyle(color: _text)),
                    subtitle: Text(
                      'Template: ${profile.templateCompany} • Default equipment: ${profile.defaultActiveSections.isEmpty ? 'None' : profile.defaultActiveSections.join(', ')}',
                      style: TextStyle(color: _subtle),
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Edit Profile',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () =>
                              _openCompanyProfileEditor(existing: profile),
                        ),
                        IconButton(
                          tooltip: 'Delete Profile',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteCompanyProfile(profile),
                        ),
                      ],
                    ),
                  ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openCompanyProfileEditor(),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add Company Profile'),
                ),
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
                value: jsaCompanyValue,
                items: jsaCompanyOptions
                    .map(
                      (company) => DropdownMenuItem(
                        value: company,
                        child: Text(company),
                      ),
                    )
                    .toList(growable: false),
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
              _switchTile(
                title: 'Hourly Quick Round Reminder',
                subtitle:
                    'Send a reminder every hour at a selected minute during production work.',
                value: _quickRoundReminderEnabled,
                onChanged: _setQuickRoundReminderEnabled,
              ),
              _dropdownTile(
                title: 'Quick Round Reminder Minute',
                subtitle:
                    'Select the minute past each hour for the Quick Round reminder.',
                value: _quickRoundReminderMinute.toString(),
                items: List<DropdownMenuItem<String>>.generate(
                  60,
                  (minute) => DropdownMenuItem<String>(
                    value: minute.toString(),
                    child: Text(':${formatQuickRoundReminderMinute(minute)}'),
                  ),
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value ?? '');
                  if (parsed == null) return;
                  _setQuickRoundReminderMinute(parsed);
                },
              ),
              _switchTile(
                title: 'Enable Rate Timer Notifications',
                subtitle:
                    'Notify while app is backgrounded, locked, or closed.',
                value: s.rateTimerNotificationsEnabled,
                onChanged: (value) =>
                    _save(s.copyWith(rateTimerNotificationsEnabled: value)),
              ),
              _switchTile(
                title: 'Estimated STS Reminder',
                subtitle: 'Notify before an estimated sweep reaches surface.',
                value: s.estimatedStsReminderEnabled,
                onChanged: (value) => _toggleEstimatedStsReminder(s, value),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: s.estimatedStsReminderEnabled,
                title: Text(
                  'Reminder Time',
                  style: TextStyle(color: _text),
                ),
                subtitle: Text(
                  'Choose how long before Estimated STS WellWerks should notify you.',
                  style: TextStyle(color: _subtle),
                ),
                trailing: Text(
                  '${_leadTimeLabel(s.estimatedStsReminderLeadMinutes)} before',
                  style: TextStyle(
                    color: s.estimatedStsReminderEnabled ? _accent : _subtle,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: s.estimatedStsReminderEnabled
                    ? () => _setEstimatedStsReminderLeadTime(s)
                    : null,
              ),
              _switchTile(
                title: '30-Second Warning',
                subtitle: 'Send warning notification 30 seconds before finish.',
                value: s.rateTimerWarningEnabled,
                onChanged: s.rateTimerNotificationsEnabled
                    ? (value) =>
                        _save(s.copyWith(rateTimerWarningEnabled: value))
                    : null,
              ),
              _switchTile(
                title: 'Timer Complete Notification',
                subtitle: 'Notify at exact timer completion.',
                value: s.rateTimerCompleteEnabled,
                onChanged: s.rateTimerNotificationsEnabled
                    ? (value) =>
                        _save(s.copyWith(rateTimerCompleteEnabled: value))
                    : null,
              ),
              _switchTile(
                title: 'Sound',
                subtitle:
                    'Play sound for timer notifications when allowed by iOS.',
                value: s.rateTimerSoundEnabled,
                onChanged: s.rateTimerNotificationsEnabled
                    ? (value) => _save(s.copyWith(rateTimerSoundEnabled: value))
                    : null,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    Icon(Icons.notifications_active_outlined, color: _accent),
                title: Text(
                  'Open iPhone Notification Settings',
                  style: TextStyle(color: _text),
                ),
                subtitle: Text(
                  'Use this if permission was denied and you want to enable alerts.',
                  style: TextStyle(color: _subtle),
                ),
                onTap: _openSystemNotificationSettings,
              ),
              _dropdownTile(
                title: 'Theme',
                subtitle: 'WellWerks visual profile.',
                value: s.appTheme,
                items: const [
                  DropdownMenuItem(
                    value: 'wellwerks_default',
                    child: Text('Classic'),
                  ),
                  DropdownMenuItem(
                    value: 'negative',
                    child: Text('Midnight'),
                  ),
                  DropdownMenuItem(value: 'patriot', child: Text('Patriot')),
                  DropdownMenuItem(
                    value: 'light',
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(value: 'military', child: Text('Military')),
                  DropdownMenuItem(value: 'ou', child: Text('OU')),
                  DropdownMenuItem(value: 'osu', child: Text('OSU')),
                  DropdownMenuItem(value: 'high_vis', child: Text('High Vis')),
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
