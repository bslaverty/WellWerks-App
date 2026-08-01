import 'package:flutter/material.dart';

import '../data/tank_charts.dart';
import '../models/drillout_tank_configuration.dart';
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
    this.existingEntry,
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
  final OperationsLogEntry? existingEntry;

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
  late final TextEditingController _waterHauledController;
  late final TextEditingController _oilHauledController;
  late final TextEditingController _sweepInformationController;
  late final TextEditingController _equipmentStatusController;
  late final TextEditingController _downtimeController;
  late final TextEditingController _notesController;
  final Map<String, TextEditingController> _tankGaugeControllers =
      <String, TextEditingController>{};
  late DrilloutTankConfiguration _tankConfig;

  late DateTime _readingTimestamp;
  DateTime? _estimatedSts;
  DateTime? _sts;
  String _reminderChoice = StsReminderChoice.useDefault;
  int _defaultReminderLeadMinutes =
      AppSettingsDefaults.estimatedStsReminderLeadMinutes;
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
    _waterHauledController = TextEditingController();
    _oilHauledController = TextEditingController();
    _sweepInformationController = TextEditingController();
    _equipmentStatusController = TextEditingController();
    _downtimeController = TextEditingController();
    _notesController = TextEditingController();
    _tankConfig = DrilloutTankConfiguration.fromDrilloutSetup(
      Map<String, dynamic>.from(widget.activeJob.drilloutSetup),
    );
    _initializeTankGaugeControllers();
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

    if (widget.existingEntry != null) {
      _seedFromExistingEntry(widget.existingEntry!);
    } else {
      _applyCarryForwardDefaultsForWell();
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
    _waterHauledController.dispose();
    _oilHauledController.dispose();
    _sweepInformationController.dispose();
    _equipmentStatusController.dispose();
    _downtimeController.dispose();
    _notesController.dispose();
    for (final controller in _tankGaugeControllers.values) {
      controller.dispose();
    }
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
    if (widget.existingEntry != null) {
      final workflowLabel = widget.workflow == OperationsLogWorkflow.drillout
          ? 'Drillout'
          : 'Cleanout';
      return 'Edit $workflowLabel Reading';
    }
    final workflowLabel = widget.workflow == OperationsLogWorkflow.drillout
        ? 'Drillout'
        : 'Cleanout';
    return 'Add $workflowLabel Reading';
  }

  void _seedFromExistingEntry(OperationsLogEntry entry) {
    _readingTimestamp = entry.entryTime;
    final stage = entry.operationStage.trim();
    _selectedStage = widget.stageOptions.contains(stage) ? stage : '';
    _choke = _parseChokeSelection(entry.choke) ?? _choke;
    _pumpRateController.text = entry.pumpRate;
    _returnsRateController.text = entry.returnsRate;
    _casingPressureController.text = entry.casingPressure;
    _tubingPressureController.text = entry.tubingPressure;
    _pumpPressureController.text = entry.pumpPressure;
    _waterHauledController.text = entry.waterHauled;
    _oilHauledController.text = entry.oilHauled;
    _sweepInformationController.text = entry.sweepInformation;
    _tankLevelController.text = entry.tankLevel;
    _equipmentStatusController.text = entry.equipmentStatus;
    _downtimeController.text = entry.downtime;
    _notesController.text = entry.notes;
    _estimatedSts = entry.estimatedSts;
    _sts = entry.sts;
    _seedTankInventoryFromEntry(entry);

    final wellId = entry.persistentWellId.trim();
    if (wellId.isNotEmpty &&
        widget.defaultWells.any((item) => item.id == wellId)) {
      _selectedWellId = wellId;
    } else {
      final byName = widget.defaultWells.where(
        (item) => item.name.trim() == entry.wellName.trim(),
      );
      if (byName.isNotEmpty) {
        _selectedWellId = byName.first.id;
      }
    }

    final gas = entry.gas.trim();
    if (DrilloutCleanoutFieldDefinitions.gasOptions.contains(gas)) {
      _selectedGas = gas;
    }
    final sand = entry.sandOrSolids.trim();
    if (DrilloutCleanoutFieldDefinitions.sandOptions.contains(sand)) {
      _selectedSand = sand;
    }
  }

  String get _selectedWellName {
    for (final item in widget.defaultWells) {
      if (item.id == _selectedWellId) return item.name;
    }
    return widget.initialSelectedWellName.trim();
  }

  Future<void> _pickEntryTime() async {
    final selection = await showStsDateTimeSelectorSheet(
      context,
      title: 'Entry Time',
      helperText: 'Select the operational time for this reading.',
      readingTimestamp: _readingTimestamp,
      initialValue: _readingTimestamp,
    );
    if (!mounted || selection == null || selection.cleared) return;
    if (selection.value == null) return;
    setState(() => _readingTimestamp = selection.value!);
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

  String _latestKnownValue(String Function(OperationsLogEntry entry) selector) {
    final selectedWell = _selectedWellName.trim();
    final ordered = List<OperationsLogEntry>.from(widget.existingEntries)
      ..sort((a, b) => b.entryTime.compareTo(a.entryTime));
    for (final entry in ordered) {
      if (entry.wellName.trim() != selectedWell) continue;
      final value = selector(entry).trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _oldestOpenEstimatedSweepId() {
    final selectedWell = _selectedWellName.trim();
    final open = widget.existingEntries
        .where((entry) =>
            entry.wellName.trim() == selectedWell &&
            entry.sweepId.trim().isNotEmpty &&
            entry.estimatedSts != null &&
            entry.sts == null)
        .toList(growable: false)
      ..sort((a, b) {
        final byEstimated = a.estimatedSts!.compareTo(b.estimatedSts!);
        if (byEstimated != 0) return byEstimated;
        return a.entryTime.compareTo(b.entryTime);
      });
    if (open.isEmpty) return '';
    return open.first.sweepId.trim();
  }

  ChokeSelection? _parseChokeSelection(String rawValue) {
    final normalized = rawValue.trim();
    if (normalized.isEmpty) return null;
    final lower = normalized.toLowerCase();
    if (lower.contains('none') || lower.contains('clear')) {
      return const ChokeSelection(type: ChokeTypes.none);
    }
    final sizeMatch = RegExp(r'(\d+)\s*/\s*64').firstMatch(normalized);
    final size =
        sizeMatch == null ? null : int.tryParse(sizeMatch.group(1) ?? '');
    if (size == null) return null;
    final type = lower.contains('positive')
        ? ChokeTypes.positive
        : ChokeTypes.adjustable;
    return ChokeSelection(type: type, size64: size);
  }

  void _applyCarryForwardDefaultsForWell() {
    String latest(String Function(OperationsLogEntry entry) selector) {
      return _latestKnownValue(selector);
    }

    if (_pumpRateController.text.trim().isEmpty) {
      _pumpRateController.text = latest((entry) => entry.pumpRate);
    }
    if (_casingPressureController.text.trim().isEmpty) {
      _casingPressureController.text = latest((entry) => entry.casingPressure);
    }
    if (_tubingPressureController.text.trim().isEmpty) {
      _tubingPressureController.text = latest((entry) => entry.tubingPressure);
    }
    if (_pumpPressureController.text.trim().isEmpty) {
      _pumpPressureController.text = latest((entry) => entry.pumpPressure);
    }
    if (_returnsRateController.text.trim().isEmpty) {
      _returnsRateController.text = latest((entry) => entry.returnsRate);
    }
    if (_waterHauledController.text.trim().isEmpty) {
      _waterHauledController.text = latest((entry) => entry.waterHauled);
    }
    if (_oilHauledController.text.trim().isEmpty) {
      _oilHauledController.text = latest((entry) => entry.oilHauled);
    }
    if (_sweepInformationController.text.trim().isEmpty) {
      _sweepInformationController.text =
          latest((entry) => entry.sweepInformation);
    }
    if (_tankLevelController.text.trim().isEmpty) {
      _tankLevelController.text = latest((entry) => entry.tankLevel);
    }
    _applyCarryForwardTankInventoryForWell();
    if (_choke.isNone) {
      final carryChoke = latest((entry) => entry.choke);
      if (carryChoke.isNotEmpty) {
        final parsed = _parseChokeSelection(carryChoke);
        if (parsed != null) {
          _choke = parsed;
        }
      }
    }
    if (_selectedGas.trim().isEmpty) {
      final carryGas = latest((entry) => entry.gas);
      if (DrilloutCleanoutFieldDefinitions.gasOptions.contains(carryGas)) {
        _selectedGas = carryGas;
      }
    }
    if (_selectedSand.trim().isEmpty) {
      final carrySand = latest((entry) => entry.sandOrSolids);
      if (DrilloutCleanoutFieldDefinitions.sandOptions.contains(carrySand)) {
        _selectedSand = carrySand;
      }
    }
  }

  void _initializeTankGaugeControllers() {
    for (final selection in _tankConfig.activeSelections) {
      final roleId = selection.roleId.trim();
      if (roleId.isEmpty) continue;
      _tankGaugeControllers.putIfAbsent(
        roleId,
        () => TextEditingController(text: selection.gauge.trim()),
      );
    }
  }

  List<DrilloutTankSelection> _activeTankSelections() {
    final seeded = <String, String>{
      ..._tankConfig.gaugesByRole,
      for (final entry in _tankGaugeControllers.entries)
        entry.key: entry.value.text.trim(),
    };
    return _tankConfig.copyWith(gaugesByRole: seeded).activeSelections;
  }

  TankChart _chartForType(String typeId) {
    final normalized = DrilloutTankCatalog.normalizeLegacyType(typeId);
    switch (normalized) {
      case DrilloutTankCatalog.typeFs3:
        return fs3Chart;
      case DrilloutTankCatalog.typeFlowbackVBottom:
        return flowback500Chart;
      case DrilloutTankCatalog.typeFlowbackRoundBottom:
        return flowbackRoundBottomChart;
      case DrilloutTankCatalog.typeSandX:
      default:
        return sandXChart;
    }
  }

  String _fmtTrim(double value) {
    if (value.isNaN || value.isInfinite) return '0';
    final fixed = value.toStringAsFixed(2);
    return fixed
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  double? _parseGaugeOrNull(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
    return parsed;
  }

  List<Map<String, dynamic>> _tankInventoryRows() {
    final rows = <Map<String, dynamic>>[];
    for (final selection in _activeTankSelections()) {
      final role = DrilloutTankCatalog.roleById(selection.roleId);
      final chart = _chartForType(selection.typeId);
      final gauge = _parseGaugeOrNull(selection.gauge);
      final barrels = gauge == null || !chart.supportsGauge(gauge)
          ? null
          : chart.barrelsAt(gauge).round();
      rows.add(<String, dynamic>{
        'roleId': selection.roleId,
        'typeId': selection.typeId,
        'label': role.label,
        'gauge': selection.gauge.trim(),
        'barrels': barrels,
      });
    }
    return rows;
  }

  String _tankInventoryBlockTextFromRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '';
    final lines = <String>['Tank Inventory', ''];
    var total = 0;
    for (final row in rows) {
      final label = (row['label'] as String? ?? '').trim();
      final gauge = (row['gauge'] as String? ?? '').trim();
      final barrels = row['barrels'] as int?;
      final gaugeText = gauge.isEmpty ? '-' : '${gauge}"';
      final bblText = barrels == null ? '-' : '$barrels bbl';
      lines.add('${label.isEmpty ? 'Tank' : label}: $gaugeText - $bblText');
      if (barrels != null) {
        total += barrels;
      }
    }
    lines.add('');
    lines.add('Total On Location: $total bbl');
    return lines.join('\n').trim();
  }

  String _tankLevelSummaryFromRows(List<Map<String, dynamic>> rows) {
    final parts = <String>[];
    for (final row in rows) {
      final label = (row['label'] as String? ?? '').trim();
      final gauge = (row['gauge'] as String? ?? '').trim();
      if (label.isEmpty || gauge.isEmpty) continue;
      parts.add('$label $gauge"');
    }
    return parts.join(' | ');
  }

  Map<String, dynamic> _applyTankInventoryStructuredData(
    Map<String, dynamic> existing,
    List<Map<String, dynamic>> rows,
  ) {
    final next = Map<String, dynamic>.from(existing);
    next['tankInventoryV1'] = rows;
    next['tankInventoryBlock'] = _tankInventoryBlockTextFromRows(rows);
    return next;
  }

  void _seedTankInventoryFromEntry(OperationsLogEntry entry) {
    final rawRows = entry.structuredData['tankInventoryV1'];
    if (rawRows is! List) return;
    for (final item in rawRows) {
      if (item is! Map) continue;
      final roleId = (item['roleId'] as String? ?? '').trim();
      if (roleId.isEmpty) continue;
      final gauge = (item['gauge'] as String? ?? '').trim();
      _tankGaugeControllers.putIfAbsent(roleId, () => TextEditingController());
      _tankGaugeControllers[roleId]!.text = gauge;
    }
  }

  void _applyCarryForwardTankInventoryForWell() {
    final selectedWell = _selectedWellName.trim();
    final ordered = List<OperationsLogEntry>.from(widget.existingEntries)
      ..sort((a, b) => b.entryTime.compareTo(a.entryTime));
    for (final entry in ordered) {
      if (entry.wellName.trim() != selectedWell) continue;
      final rows = entry.structuredData['tankInventoryV1'];
      if (rows is! List) continue;
      for (final item in rows) {
        if (item is! Map) continue;
        final roleId = (item['roleId'] as String? ?? '').trim();
        if (roleId.isEmpty) continue;
        final gauge = (item['gauge'] as String? ?? '').trim();
        _tankGaugeControllers.putIfAbsent(
          roleId,
          () => TextEditingController(),
        );
        if (_tankGaugeControllers[roleId]!.text.trim().isEmpty) {
          _tankGaugeControllers[roleId]!.text = gauge;
        }
      }
      break;
    }
  }

  Widget _drilloutTankInventorySection() {
    final selections = _activeTankSelections();
    if (selections.isEmpty) {
      return const SizedBox.shrink();
    }

    final rows = _tankInventoryRows();
    final block = _tankInventoryBlockTextFromRows(rows);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tank Inventory',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter tank gauges in inches to calculate barrels for text updates.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 10),
            for (final selection in selections) ...[
              _tankGaugeInputTile(selection),
              const SizedBox(height: 10),
            ],
            if (block.trim().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                  color: Colors.black.withValues(alpha: 0.18),
                ),
                child: Text(
                  block,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tankGaugeInputTile(DrilloutTankSelection selection) {
    final role = DrilloutTankCatalog.roleById(selection.roleId);
    final type = DrilloutTankCatalog.typeById(selection.typeId);
    final chart = _chartForType(selection.typeId);
    final controller = _tankGaugeControllers.putIfAbsent(
      selection.roleId,
      () => TextEditingController(text: selection.gauge.trim()),
    );
    final gauge = _parseGaugeOrNull(controller.text);
    final barrels = gauge == null || !chart.supportsGauge(gauge)
        ? null
        : chart.barrelsAt(gauge).round();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            role.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            type.label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: Key('operations-log-form-tank-gauge-${selection.roleId}'),
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Gauge (in)',
              hintText: '30.25',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Text(
            barrels == null
                ? 'Barrels: -'
                : 'Barrels: ${barrels.toString()} bbl',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
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
      final existing = widget.existingEntry;
      final usesGaugeTankInventory =
          widget.workflow == OperationsLogWorkflow.drillout ||
              widget.workflow == OperationsLogWorkflow.cleanout;
      final tankRows = _tankInventoryRows();
      final tankLevelValue = _isEnabled('tankLevel')
          ? (usesGaugeTankInventory
              ? _tankLevelSummaryFromRows(tankRows)
              : _tankLevelController.text.trim())
          : '';
      final structuredData = _applyTankInventoryStructuredData(
        existing?.structuredData ?? const <String, dynamic>{},
        tankRows,
      );
      var entry = existing != null
          ? existing.copyWith(
              persistentWellId: _selectedWellId,
              wellName: _selectedWellName,
              readingTimestamp: _readingTimestamp,
              structuredData: structuredData,
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
              returnsRate: _isEnabled('returnsRate')
                  ? _returnsRateController.text.trim()
                  : '',
              estimatedSts: _isEnabled('estimatedSts') ? _estimatedSts : null,
              sts: _isEnabled('sts') ? _sts : null,
              tankLevel: tankLevelValue,
              waterHauled: _isEnabled('waterHauled')
                  ? _waterHauledController.text.trim()
                  : '',
              oilHauled: _isEnabled('oilHauled')
                  ? _oilHauledController.text.trim()
                  : '',
              sweepInformation: _isEnabled('sweepInformation')
                  ? _sweepInformationController.text.trim()
                  : '',
              sandOrSolids:
                  _isEnabled('sandOrSolids') ? _selectedSand.trim() : '',
              equipmentStatus: _isEnabled('equipmentStatus')
                  ? _equipmentStatusController.text.trim()
                  : '',
              downtime:
                  _isEnabled('downtime') ? _downtimeController.text.trim() : '',
              notes: _notesController.text.trim(),
            )
          : await widget.logService.createLocalEntry(
              workflow: widget.workflow,
              jobId: job.id,
              wellId: _selectedWellId,
              wellName: _selectedWellName,
              readingTimestamp: _readingTimestamp,
              structuredData: structuredData,
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
              returnsRate: _isEnabled('returnsRate')
                  ? _returnsRateController.text.trim()
                  : '',
              estimatedSts: _isEnabled('estimatedSts') ? _estimatedSts : null,
              sts: _isEnabled('sts') ? _sts : null,
              tankLevel: tankLevelValue,
              waterHauled: _isEnabled('waterHauled')
                  ? _waterHauledController.text.trim()
                  : '',
              oilHauled: _isEnabled('oilHauled')
                  ? _oilHauledController.text.trim()
                  : '',
              sweepInformation: _isEnabled('sweepInformation')
                  ? _sweepInformationController.text.trim()
                  : '',
              sandOrSolids:
                  _isEnabled('sandOrSolids') ? _selectedSand.trim() : '',
              equipmentStatus: _isEnabled('equipmentStatus')
                  ? _equipmentStatusController.text.trim()
                  : '',
              downtime:
                  _isEnabled('downtime') ? _downtimeController.text.trim() : '',
              notes: _notesController.text.trim(),
            );

      final resolvedLinkedSweepId = _sts != null
          ? ((existing?.linkedSweepId.trim().isNotEmpty ?? false)
              ? existing!.linkedSweepId.trim()
              : _oldestOpenEstimatedSweepId())
          : '';
      final existingSweepId = existing?.sweepId.trim() ?? '';
      final sweepId = (_estimatedSts != null || _sts != null)
          ? (resolvedLinkedSweepId.isNotEmpty
              ? resolvedLinkedSweepId
              : (existingSweepId.isNotEmpty
                  ? existingSweepId
                  : 'sweep_${entry.entryId}'))
          : '';
      entry = entry.copyWith(
        sweepId: sweepId,
        linkedSweepId: resolvedLinkedSweepId,
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

        if (_sts != null && resolvedLinkedSweepId.isNotEmpty) {
          await _stsReminderService.cancelBySweepId(resolvedLinkedSweepId);
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

  String _returnsDisplay(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return '';
    if (widget.workflow == OperationsLogWorkflow.drillout) {
      return '$trimmed bbl/min';
    }
    return trimmed;
  }

  List<String> _previewLines() {
    final lines = <String>[
      'Entry Time: ${MaterialLocalizations.of(context).formatCompactDate(_readingTimestamp)} ${TimeOfDay.fromDateTime(_readingTimestamp).format(context)}',
      'Entry Type: Manual Reading',
      'Well: ${_selectedWellName.trim().isEmpty ? '-' : _selectedWellName.trim()}',
    ];

    if (_isEnabled('operationStage') && _selectedStage.trim().isNotEmpty) {
      lines.add('Stage: ${_selectedStage.trim()}');
    }
    if (_isEnabled('pumpRate') && _pumpRateController.text.trim().isNotEmpty) {
      lines.add('Pump Rate: ${_pumpRateController.text.trim()}');
    }
    if (_isEnabled('returnsRate') &&
        _returnsRateController.text.trim().isNotEmpty) {
      lines.add('Returns: ${_returnsDisplay(_returnsRateController.text)}');
    }
    if (_isEnabled('choke') && !_choke.isNone) {
      lines.add('Choke: ${formatChokeDisplay(_choke)}');
    }
    if (_isEnabled('pumpPressure') &&
        _pumpPressureController.text.trim().isNotEmpty) {
      lines.add('Pump PSI: ${_pumpPressureController.text.trim()}');
    }
    if (_isEnabled('tubingPressure') &&
        _tubingPressureController.text.trim().isNotEmpty) {
      lines.add('Manifold PSI: ${_tubingPressureController.text.trim()}');
    }
    if (_isEnabled('waterHauled') &&
        _waterHauledController.text.trim().isNotEmpty) {
      lines.add('Water Hauled: ${_waterHauledController.text.trim()}');
    }
    if (_isEnabled('oilHauled') &&
        _oilHauledController.text.trim().isNotEmpty) {
      lines.add('Oil Hauled: ${_oilHauledController.text.trim()}');
    }
    if (_isEnabled('sweepInformation') &&
        _sweepInformationController.text.trim().isNotEmpty) {
      lines.add('Coil Depth: ${_sweepInformationController.text.trim()}');
    }
    if (_isEnabled('estimatedSts') && _estimatedSts != null) {
      lines.add('Estimated STS: ${_formatOptionalDateTime(_estimatedSts)}');
    }
    if (_isEnabled('sts') && _sts != null) {
      lines.add('STS: ${_formatOptionalDateTime(_sts)}');
    }
    if (_isEnabled('tankLevel') &&
        (widget.workflow == OperationsLogWorkflow.drillout ||
            widget.workflow == OperationsLogWorkflow.cleanout)) {
      final block = _tankInventoryBlockTextFromRows(_tankInventoryRows());
      if (block.trim().isNotEmpty) {
        lines.addAll(['', ...block.split('\n')]);
      }
    } else if (_isEnabled('tankLevel') &&
        _tankLevelController.text.trim().isNotEmpty) {
      lines.add('Tank Readings: ${_tankLevelController.text.trim()}');
    }
    if (_isEnabled('notes') && _notesController.text.trim().isNotEmpty) {
      lines.add('Notes: ${_notesController.text.trim()}');
    }
    return lines;
  }

  Future<void> _previewBeforeSave() async {
    final lines = _previewLines();
    if (!mounted) return;
    final shouldSave = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Preview Reading'),
            content: SingleChildScrollView(
              child: SelectableText(lines.join('\n')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Edit'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Save Reading'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldSave) return;
    await _save();
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
              setState(() {
                _selectedWellId = value;
                _applyCarryForwardDefaultsForWell();
              });
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
          ListTile(
            key: const Key('operations-log-form-entry-time-tile'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('Entry Time'),
            subtitle: Text('$dateLabel $timeLabel'),
            trailing: FilledButton(
              key: const Key('operations-log-form-entry-time-button'),
              onPressed: _pickEntryTime,
              child: const Text('Select'),
            ),
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
          if (_isEnabled('returnsRate')) ...[
            TextFormField(
              key: const Key('operations-log-form-returns-rate-field'),
              controller: _returnsRateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _labelFor('returnsRate', fallback: 'Returns'),
              ),
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
              ],
            ),
          if (_isEnabled('tankLevel')) ...[
            if (widget.workflow == OperationsLogWorkflow.drillout ||
                widget.workflow == OperationsLogWorkflow.cleanout)
              _drilloutTankInventorySection()
            else
              TextFormField(
                key: const Key('operations-log-form-tank-level-field'),
                controller: _tankLevelController,
                decoration: const InputDecoration(labelText: 'Tank Level'),
              ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('waterHauled')) ...[
            TextFormField(
              key: const Key('operations-log-form-water-hauled-field'),
              controller: _waterHauledController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _labelFor('waterHauled', fallback: 'Water Hauled'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('oilHauled')) ...[
            TextFormField(
              key: const Key('operations-log-form-oil-hauled-field'),
              controller: _oilHauledController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _labelFor('oilHauled', fallback: 'Oil Hauled'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('sweepInformation')) ...[
            TextFormField(
              key: const Key('operations-log-form-coil-depth-field'),
              controller: _sweepInformationController,
              decoration: InputDecoration(
                labelText:
                    _labelFor('sweepInformation', fallback: 'Coil Depth'),
              ),
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
          if (_isEnabled('gas') || _isEnabled('sandOrSolids')) ...[
            const SizedBox(height: 4),
            const Text(
              'Conditions',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isEnabled('gas'))
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const Key('operations-log-form-gas-dropdown'),
                      initialValue: _selectedGas,
                      decoration: InputDecoration(
                        labelText: _labelFor('gas', fallback: 'Gas'),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('Select gas'),
                        ),
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
                  ),
                if (_isEnabled('gas') && _isEnabled('sandOrSolids'))
                  const SizedBox(width: 12),
                if (_isEnabled('sandOrSolids'))
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const Key('operations-log-form-sand-dropdown'),
                      initialValue: _selectedSand,
                      decoration: InputDecoration(
                        labelText: _labelFor('sandOrSolids',
                            fallback: 'Sand / Solids'),
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
                  ),
              ],
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
                child: OutlinedButton(
                  key: const Key('operations-log-form-preview-button'),
                  onPressed: _saving ? null : _previewBeforeSave,
                  child: const Text('Preview'),
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
