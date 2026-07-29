import 'package:flutter/material.dart';

import '../models/job_setup.dart';
import '../models/operations_log_entry.dart';
import '../services/app_settings_service.dart';
import '../services/drillout_cleanout_field_definitions.dart';
import '../services/operations_sts_reminder_service.dart';
import '../services/operations_log_service.dart';
import '../services/rate_timer_notification_service.dart';
import '../widgets/lead_time_wheel_picker_sheet.dart';
import '../widgets/choke_selector_sheet.dart';
import '../widgets/sts_date_time_selector_sheet.dart';

class OperationsLogEntryFormScreen extends StatefulWidget {
  const OperationsLogEntryFormScreen({
    super.key,
    required this.workflow,
    required this.title,
    required this.activeJob,
    required this.defaultWells,
    required this.initialSelectedWellId,
    required this.initialSelectedWellName,
    required this.initialStage,
    required this.initialReadingTimestamp,
    required this.stageOptions,
    required this.enabledFieldIds,
    required this.logService,
    this.existingEntries = const <OperationsLogEntry>[],
  });

  final OperationsLogWorkflow workflow;
  final String title;
  final JobSetup activeJob;
  final List<JobSetupWell> defaultWells;
  final String initialSelectedWellId;
  final String initialSelectedWellName;
  final String initialStage;
  final DateTime initialReadingTimestamp;
  final List<String> stageOptions;
  final Set<String> enabledFieldIds;
  final OperationsLogService logService;
  final List<OperationsLogEntry> existingEntries;

  @override
  State<OperationsLogEntryFormScreen> createState() =>
      _OperationsLogEntryFormScreenState();
}

class _OperationsLogEntryFormScreenState
    extends State<OperationsLogEntryFormScreen> {
  late final TextEditingController _pumpRateController;
  late final TextEditingController _casingPressureController;
  late final TextEditingController _tubingPressureController;
  late final TextEditingController _pumpPressureController;
  late final TextEditingController _returnsRateController;
  late final TextEditingController _tankLevelController;
  late final TextEditingController _equipmentStatusController;
  late final TextEditingController _downtimeController;
  late final TextEditingController _notesController;

  late DateTime _readingTimestamp;
  DateTime? _estimatedSts;
  DateTime? _sts;
  String _reminderChoice = StsReminderChoice.useDefault;
  int _defaultReminderLeadMinutes =
      AppSettingsDefaults.estimatedStsReminderLeadMinutes;
  String _linkedSweepId = '';
  late String _selectedWellId;
  String _selectedStage = '';
  String _selectedGas = '';
  String _selectedSand = '';
  ChokeSelection _choke = const ChokeSelection(type: ChokeTypes.none);
  bool _saving = false;
  final _settingsService = AppSettingsService();
  final _stsReminderService = OperationsStsReminderService();
  final _notificationService = RateTimerNotificationService.instance;

  @override
  void initState() {
    super.initState();
    _pumpRateController = TextEditingController();
    _casingPressureController = TextEditingController();
    _tubingPressureController = TextEditingController();
    _pumpPressureController = TextEditingController();
    _returnsRateController = TextEditingController();
    _tankLevelController = TextEditingController();
    _equipmentStatusController = TextEditingController();
    _downtimeController = TextEditingController();
    _notesController = TextEditingController();
    _readingTimestamp = widget.initialReadingTimestamp;
    final trimmedInitialStage = widget.initialStage.trim();
    _selectedStage = widget.stageOptions.contains(trimmedInitialStage)
        ? trimmedInitialStage
        : '';
    final setup = widget.activeJob.drilloutSetup;
    final initialGas =
        (setup['gas'] as String? ?? setup['gasSpotRate'] as String? ?? '')
            .trim();
    if (DrilloutCleanoutFieldDefinitions.gasOptions.contains(initialGas)) {
      _selectedGas = initialGas;
    }
    final initialSand = (setup['sand'] as String? ?? '').trim();
    if (DrilloutCleanoutFieldDefinitions.sandOptions.contains(initialSand)) {
      _selectedSand = initialSand;
    }

    final availableWellIds = widget.defaultWells.map((item) => item.id).toSet();
    final requestedId = widget.initialSelectedWellId.trim();
    if (requestedId.isNotEmpty && availableWellIds.contains(requestedId)) {
      _selectedWellId = requestedId;
    } else if (widget.defaultWells.isNotEmpty) {
      _selectedWellId = widget.defaultWells.first.id;
    } else {
      _selectedWellId = '';
    }

    _loadReminderDefaults();
  }

  @override
  void dispose() {
    _pumpRateController.dispose();
    _casingPressureController.dispose();
    _tubingPressureController.dispose();
    _pumpPressureController.dispose();
    _returnsRateController.dispose();
    _tankLevelController.dispose();
    _equipmentStatusController.dispose();
    _downtimeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool _isEnabled(String fieldId) => widget.enabledFieldIds.contains(fieldId);

  Future<void> _loadReminderDefaults() async {
    final settings = await _settingsService.load();
    if (!mounted) return;
    setState(() {
      _defaultReminderLeadMinutes = settings.estimatedStsReminderLeadMinutes;
      _reminderChoice = _stsReminderService.normalizeChoice(
        _reminderChoice,
        defaultLeadMinutes: _defaultReminderLeadMinutes,
      );
    });
  }

  String _labelFor(String fieldId, {String fallback = ''}) {
    final field = DrilloutCleanoutFieldDefinitions.byId(fieldId);
    if (field == null) return fallback;
    if (field.unitLabel?.trim().isNotEmpty ?? false) {
      return '${field.label} (${field.unitLabel})';
    }
    return field.label;
  }

  Future<void> _pickChoke() async {
    final selected = await showChokeSelectorSheet(
      context,
      initial: _choke,
      allowNone: true,
    );
    if (!mounted || selected == null) return;
    setState(() => _choke = selected);
  }

  String get _formTitle {
    final workflowLabel = widget.workflow == OperationsLogWorkflow.drillout
        ? 'Drillout'
        : 'Cleanout';
    return 'Add $workflowLabel Reading';
  }

  String get _selectedWellName {
    for (final item in widget.defaultWells) {
      if (item.id == _selectedWellId) return item.name;
    }
    return widget.initialSelectedWellName.trim();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _readingTimestamp,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (selected == null) return;
    setState(() {
      _readingTimestamp = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _readingTimestamp.hour,
        _readingTimestamp.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_readingTimestamp),
    );
    if (selected == null) return;
    setState(() {
      _readingTimestamp = DateTime(
        _readingTimestamp.year,
        _readingTimestamp.month,
        _readingTimestamp.day,
        selected.hour,
        selected.minute,
      );
    });
  }

  String _formatOptionalDateTime(DateTime? value) {
    if (value == null) return 'Not set';
    final local = value.toLocal();
    final readingDate = DateTime(
      _readingTimestamp.year,
      _readingTimestamp.month,
      _readingTimestamp.day,
    );
    final selectedDate = DateTime(local.year, local.month, local.day);
    final timeLabel = TimeOfDay.fromDateTime(local).format(context);
    if (selectedDate == readingDate) {
      return timeLabel;
    }
    if (selectedDate == readingDate.add(const Duration(days: 1))) {
      return 'Tomorrow $timeLabel';
    }
    final dateLabel =
        MaterialLocalizations.of(context).formatCompactDate(local);
    return '$dateLabel $timeLabel';
  }

  Future<void> _pickStsDateTime({
    required String fieldId,
    required DateTime? currentValue,
    required ValueChanged<DateTime?> onChanged,
  }) async {
    final field = DrilloutCleanoutFieldDefinitions.byId(fieldId);
    final helper = fieldId == DrilloutCleanoutFieldDefinitions.estimatedStsId
        ? 'Estimated sweep-to-surface time'
        : 'Actual sweep-to-surface time';
    final selection = await showStsDateTimeSelectorSheet(
      context,
      title: field?.label ?? fieldId,
      helperText: helper,
      readingTimestamp: _readingTimestamp,
      initialValue: currentValue,
    );
    if (!mounted || selection == null) return;
    if (selection.cleared) {
      onChanged(null);
      return;
    }
    onChanged(selection.value);
  }

  Widget _buildOptionalDateTimeField({
    required String fieldId,
    required DateTime? value,
    required String pickerKeyPrefix,
    required ValueChanged<DateTime> onSelected,
    required VoidCallback onCleared,
  }) {
    return Column(
      children: [
        ListTile(
          key: Key('$pickerKeyPrefix-tile'),
          contentPadding: EdgeInsets.zero,
          title: Text(_labelFor(fieldId, fallback: fieldId)),
          subtitle: Text(_formatOptionalDateTime(value)),
          trailing: Wrap(
            spacing: 8,
            children: [
              if (value != null)
                OutlinedButton(
                  key: Key('$pickerKeyPrefix-clear'),
                  onPressed: onCleared,
                  child: const Text('Clear'),
                ),
              FilledButton(
                key: Key('$pickerKeyPrefix-pick'),
                onPressed: () => _pickStsDateTime(
                  fieldId: fieldId,
                  currentValue: value,
                  onChanged: (next) {
                    if (next == null) return;
                    onSelected(next);
                  },
                ),
                child: Text(value == null ? 'Set' : 'Change'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _pickReminderChoice() async {
    final options = _stsReminderService.options(
      defaultLeadMinutes: _defaultReminderLeadMinutes,
    );
    final minuteOptions = options
        .where((item) => item.minutes != null)
        .map((item) => item.minutes!)
        .toList(growable: false);

    final current = _stsReminderService.resolveLeadMinutes(
      _reminderChoice,
      defaultLeadMinutes: _defaultReminderLeadMinutes,
    );

    final selectedMinutes = await showLeadTimeWheelPickerSheet(
      context,
      title: 'Notify me',
      actionLabel: 'Set',
      options: minuteOptions,
      initialMinutes: current ?? _defaultReminderLeadMinutes,
    );
    if (!mounted || selectedMinutes == null) return;
    setState(() {
      _reminderChoice = StsReminderChoice.explicit(selectedMinutes);
    });
  }

  String _reminderChoiceLabel() {
    final normalized = _stsReminderService.normalizeChoice(
      _reminderChoice,
      defaultLeadMinutes: _defaultReminderLeadMinutes,
    );
    if (normalized == StsReminderChoice.none) {
      return 'No reminder';
    }
    if (normalized == StsReminderChoice.useDefault) {
      return 'Use default - ${_stsReminderService.leadTimeLabel(_defaultReminderLeadMinutes)} before';
    }
    return _stsReminderService.optionLabel(
      normalized,
      defaultLeadMinutes: _defaultReminderLeadMinutes,
    );
  }

  List<DropdownMenuItem<String>> _estimatedSweepLinkOptions() {
    final selectedWell = _selectedWellName.trim();
    final open = widget.existingEntries
        .where((entry) =>
            entry.wellName.trim() == selectedWell &&
            entry.sweepId.trim().isNotEmpty &&
            entry.estimatedSts != null &&
            entry.sts == null)
        .toList(growable: false)
      ..sort((a, b) => a.estimatedSts!.compareTo(b.estimatedSts!));

    return <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: '',
        child: Text('No link'),
      ),
      for (final item in open)
        DropdownMenuItem<String>(
          value: item.sweepId,
          child:
              Text('Estimated ${_formatOptionalDateTime(item.estimatedSts)}'),
        ),
    ];
  }

  Future<bool> _ensureEstimatedStsPermission() async {
    final prompted =
        await _notificationService.hasPromptedEstimatedStsPermission();
    if (prompted) {
      return await _notificationService.requestNotificationPermission();
    }

    if (!mounted) return false;
    final allow = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Estimated STS Reminder'),
            content: const Text(
              'WellWerks can notify you before the estimated sweep reaches surface.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not Now'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Allow Notifications'),
              ),
            ],
          ),
        ) ??
        false;
    await _notificationService.markEstimatedStsPermissionPrompted();
    if (!allow) return false;
    return await _notificationService.requestNotificationPermission();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final job = widget.activeJob;
      var entry = await widget.logService.createLocalEntry(
        workflow: widget.workflow,
        jobId: job.id,
        wellId: _selectedWellId,
        wellName: _selectedWellName,
        readingTimestamp: _readingTimestamp,
        operationStage:
            _isEnabled('operationStage') ? _selectedStage.trim() : '',
        choke: _isEnabled('choke') ? formatChokeDisplay(_choke) : '',
        pumpRate: _pumpRateController.text.trim(),
        casingPressure: _casingPressureController.text.trim(),
        tubingPressure: _isEnabled('tubingPressure')
            ? _tubingPressureController.text.trim()
            : '',
        pumpPressure: _isEnabled('pumpPressure')
            ? _pumpPressureController.text.trim()
            : '',
        gas: _isEnabled('gas') ? _selectedGas.trim() : '',
        returnsRate:
            _isEnabled('returnsRate') ? _returnsRateController.text.trim() : '',
        estimatedSts: _isEnabled('estimatedSts') ? _estimatedSts : null,
        sts: _isEnabled('sts') ? _sts : null,
        tankLevel:
            _isEnabled('tankLevel') ? _tankLevelController.text.trim() : '',
        sandOrSolids: _isEnabled('sandOrSolids') ? _selectedSand.trim() : '',
        equipmentStatus: _isEnabled('equipmentStatus')
            ? _equipmentStatusController.text.trim()
            : '',
        downtime: _isEnabled('downtime') ? _downtimeController.text.trim() : '',
        notes: _notesController.text.trim(),
      );

      final sweepId = (_estimatedSts != null || _sts != null)
          ? (_linkedSweepId.trim().isNotEmpty
              ? _linkedSweepId.trim()
              : 'sweep_${entry.entryId}')
          : '';
      entry = entry.copyWith(
        sweepId: sweepId,
        linkedSweepId: _linkedSweepId.trim(),
        estimatedStsReminderChoice: _reminderChoice,
      );

      final settings = await _settingsService.load();
      final needsReminder = entry.estimatedSts != null &&
          _stsReminderService.resolveLeadMinutes(
                _reminderChoice,
                defaultLeadMinutes: settings.estimatedStsReminderLeadMinutes,
              ) !=
              null &&
          settings.estimatedStsReminderEnabled;

      StsReminderSyncResult sync = StsReminderSyncResult(entry: entry);
      try {
        var permissionGranted = true;
        if (needsReminder) {
          permissionGranted = await _ensureEstimatedStsPermission();
        }

        sync = await _stsReminderService.syncForSavedEntry(
          entry: entry,
          remindersEnabled: settings.estimatedStsReminderEnabled,
          defaultLeadMinutes: settings.estimatedStsReminderLeadMinutes,
          permissionGranted: permissionGranted,
        );

        entry = sync.entry;
        if (sync.needsLateDecision && sync.recommendedLeadMinutes != null) {
          if (!mounted) return;
          final decision = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              content:
                  const Text('The selected reminder time has already passed.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('No Reminder'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Notify Now'),
                ),
              ],
            ),
          );
          entry = await _stsReminderService.applyLateDecision(
            entry: entry,
            notifyNow: decision == true,
            leadMinutes: sync.recommendedLeadMinutes!,
          );
        }

        if (_sts != null && _linkedSweepId.trim().isNotEmpty) {
          await _stsReminderService.cancelBySweepId(_linkedSweepId.trim());
          entry = entry.copyWith(
            estimatedStsNotificationStatus: 'actualStsRecorded',
            estimatedStsCancellationReason: 'actualStsRecorded',
          );
        }
      } catch (notificationError, notificationStackTrace) {
        debugPrint(
          '[OperationsLog] Reminder sync skipped: $notificationError\n$notificationStackTrace',
        );
      }

      await widget.logService.upsertEntry(
        workflow: widget.workflow,
        jobId: job.id,
        entry: entry,
      );
      if (sync.userMessage != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(sync.userMessage!)));
      }
      if (!mounted) return;
      Navigator.of(context).pop(entry);
    } catch (error, stackTrace) {
      debugPrint(
        '[OperationsLog] Failed to save reading form for ${widget.workflow.name}: $error\n$stackTrace',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save this reading.')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = MaterialLocalizations.of(context).formatCompactDate(
      _readingTimestamp,
    );
    final timeLabel = TimeOfDay.fromDateTime(_readingTimestamp).format(context);

    return Scaffold(
      appBar: AppBar(title: Text(_formTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Job',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.activeJob.padName.trim().isEmpty
                        ? widget.activeJob.company
                        : widget.activeJob.padName,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('operations-log-form-well-dropdown'),
            initialValue: _selectedWellId.isEmpty ? null : _selectedWellId,
            decoration: const InputDecoration(labelText: 'Well'),
            items: [
              for (final item in widget.defaultWells)
                DropdownMenuItem<String>(
                  value: item.id,
                  child: Text(item.name),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedWellId = value);
            },
          ),
          const SizedBox(height: 12),
          if (_isEnabled('operationStage')) ...[
            DropdownButtonFormField<String>(
              key: const Key('operations-log-form-stage-field'),
              initialValue: _selectedStage,
              decoration: const InputDecoration(labelText: 'Stage'),
              items: [
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('Select status'),
                ),
                for (final stage in widget.stageOptions)
                  DropdownMenuItem<String>(
                    value: stage,
                    child: Text(stage),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _selectedStage = (value ?? '').trim()),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('operations-log-form-date-button'),
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text('Date: $dateLabel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('operations-log-form-time-button'),
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time),
                  label: Text('Time: $timeLabel'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isEnabled('pumpRate')) ...[
            TextFormField(
              key: const Key('operations-log-form-pump-rate-field'),
              controller: _pumpRateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _labelFor('pumpRate', fallback: 'Pump Rate'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('casingPressure')) ...[
            TextFormField(
              key: const Key('operations-log-form-csg-field'),
              controller: _casingPressureController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _labelFor('casingPressure', fallback: 'Casing PSI'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('pumpPressure')) ...[
            TextFormField(
              key: const Key('operations-log-form-pump-pressure-field'),
              controller: _pumpPressureController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _labelFor('pumpPressure', fallback: 'Pump PSI'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('tubingPressure')) ...[
            TextFormField(
              key: const Key('operations-log-form-tbg-field'),
              controller: _tubingPressureController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText:
                    _labelFor('tubingPressure', fallback: 'Manifold PSI'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('gas')) ...[
            DropdownButtonFormField<String>(
              key: const Key('operations-log-form-gas-dropdown'),
              initialValue: _selectedGas,
              decoration: InputDecoration(
                labelText: _labelFor('gas', fallback: 'Gas'),
              ),
              items: [
                const DropdownMenuItem<String>(
                    value: '', child: Text('Select gas')),
                for (final option
                    in DrilloutCleanoutFieldDefinitions.gasOptions)
                  DropdownMenuItem<String>(
                    value: option,
                    child: Text(option),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _selectedGas = (value ?? '').trim()),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('returnsRate')) ...[
            TextFormField(
              key: const Key('operations-log-form-returns-rate-field'),
              controller: _returnsRateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _labelFor('returnsRate', fallback: 'Returns Rate'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('tankLevel')) ...[
            TextFormField(
              key: const Key('operations-log-form-tank-level-field'),
              controller: _tankLevelController,
              decoration: const InputDecoration(labelText: 'Tank Level'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('choke')) ...[
            ListTile(
              key: const Key('operations-log-form-choke-selector'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune),
              title: Text(_labelFor('choke', fallback: 'Choke Selector')),
              subtitle: Text(formatChokeDisplay(_choke)),
              trailing: FilledButton(
                onPressed: _pickChoke,
                child: const Text('Select'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('estimatedSts'))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOptionalDateTimeField(
                  fieldId: 'estimatedSts',
                  value: _estimatedSts,
                  pickerKeyPrefix: 'operations-log-form-estimated-sts',
                  onSelected: (value) => setState(() => _estimatedSts = value),
                  onCleared: () => setState(() => _estimatedSts = null),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Estimated sweep-to-surface time',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                ListTile(
                  key: const Key('operations-log-form-reminder-choice-tile'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Notify me'),
                  subtitle: Text(_reminderChoiceLabel()),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => setState(
                          () => _reminderChoice = StsReminderChoice.useDefault,
                        ),
                        child: const Text('Use Default'),
                      ),
                      OutlinedButton(
                        onPressed: () => setState(
                            () => _reminderChoice = StsReminderChoice.none),
                        child: const Text('No Reminder'),
                      ),
                      FilledButton(
                        onPressed: _pickReminderChoice,
                        child: const Text('Choose'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          if (_isEnabled('sts'))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOptionalDateTimeField(
                  fieldId: 'sts',
                  value: _sts,
                  pickerKeyPrefix: 'operations-log-form-sts',
                  onSelected: (value) => setState(() => _sts = value),
                  onCleared: () => setState(() => _sts = null),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Actual sweep-to-surface time',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                if (_sts != null)
                  DropdownButtonFormField<String>(
                    key: const Key('operations-log-form-link-estimated-sweep'),
                    initialValue: _linkedSweepId,
                    decoration: const InputDecoration(
                      labelText: 'Link to Estimated Sweep',
                    ),
                    items: _estimatedSweepLinkOptions(),
                    onChanged: (value) {
                      setState(() => _linkedSweepId = (value ?? '').trim());
                    },
                  ),
                if (_sts != null) const SizedBox(height: 12),
              ],
            ),
          if (_isEnabled('sandOrSolids')) ...[
            DropdownButtonFormField<String>(
              key: const Key('operations-log-form-sand-dropdown'),
              initialValue: _selectedSand,
              decoration: InputDecoration(
                labelText: _labelFor('sandOrSolids', fallback: 'Sand / Solids'),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('Select sand / solids'),
                ),
                for (final option
                    in DrilloutCleanoutFieldDefinitions.sandOptions)
                  DropdownMenuItem<String>(
                    value: option,
                    child: Text(option),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _selectedSand = (value ?? '').trim()),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('equipmentStatus')) ...[
            TextFormField(
              key: const Key('operations-log-form-equipment-field'),
              controller: _equipmentStatusController,
              decoration: const InputDecoration(labelText: 'Equipment Issues'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('downtime')) ...[
            TextFormField(
              key: const Key('operations-log-form-downtime-field'),
              controller: _downtimeController,
              decoration: const InputDecoration(labelText: 'Downtime'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('notes')) ...[
            TextFormField(
              key: const Key('operations-log-form-notes-field'),
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('operations-log-form-cancel-button'),
                  onPressed:
                      _saving ? null : () => Navigator.of(context).maybePop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('operations-log-form-save-button'),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Reading'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
