import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import '../services/app_settings_service.dart';
import '../services/job_storage_service.dart';
import '../services/rate_timer_notification_service.dart';
import '../services/rate_timer_service.dart';
import '../data/tank_charts.dart';
import '../utils/gauge_keypad_input.dart';
import '../utils/gauge_parser.dart';
import '../widgets/app_header.dart';
import '../widgets/shared_gauge_keypad.dart';
import '../widgets/ww_number_field.dart';

enum _KeypadTarget { start, end }

enum _RateDisplayUnit { bblPerMin, bblPerHr }

class _RateLogEntry {
  const _RateLogEntry({
    required this.timestamp,
    required this.rateValue,
    required this.rateUnit,
    this.selected = true,
  });

  final DateTime timestamp;
  final double rateValue;
  final String rateUnit;
  final bool selected;

  _RateLogEntry copyWith({
    DateTime? timestamp,
    double? rateValue,
    String? rateUnit,
    bool? selected,
  }) {
    return _RateLogEntry(
      timestamp: timestamp ?? this.timestamp,
      rateValue: rateValue ?? this.rateValue,
      rateUnit: rateUnit ?? this.rateUnit,
      selected: selected ?? this.selected,
    );
  }
}

class RateCalculatorConfig {
  final String title;
  final String? chartId;
  final double? defaultFactor;

  const RateCalculatorConfig.chart(this.title, this.chartId)
      : defaultFactor = null;
  const RateCalculatorConfig.linear(this.title, {required this.defaultFactor})
      : chartId = null;

  bool get usesChart => chartId != null;

  static RateCalculatorConfig? fromStorageId(String storageId) {
    switch (storageId) {
      case 'fs3':
        return const RateCalculatorConfig.chart('FS3 Tank', 'fs3');
      case 'sandx':
        return const RateCalculatorConfig.chart('SandX G3', 'sandx');
      case 'flowback500':
        return const RateCalculatorConfig.chart(
            '500 BBL Flowback Tank', 'flowback500');
      case 'flowback_round_bottom':
        return const RateCalculatorConfig.chart(
            'Flowback Tank - Round Bottom', 'flowback_round_bottom');
      case 'production_tank':
        return const RateCalculatorConfig.linear('Production Tank',
            defaultFactor: 1.67);
      default:
        return null;
    }
  }
}

class RateCalculatorScreen extends StatefulWidget {
  final RateCalculatorConfig config;
  const RateCalculatorScreen({super.key, required this.config});

  // Backward compatibility for old routes still passing a tank name.
  factory RateCalculatorScreen.legacy({Key? key, required String tankName}) {
    switch (tankName) {
      case 'SandX':
        return RateCalculatorScreen(
            key: key,
            config: const RateCalculatorConfig.chart('SandX G3', 'sandx'));
      case 'Flowback':
        return RateCalculatorScreen(
            key: key,
            config: const RateCalculatorConfig.chart(
                '500 BBL Flowback Tank', 'flowback500'));
      case 'Flowback Round Bottom':
        return RateCalculatorScreen(
            key: key,
            config: const RateCalculatorConfig.chart(
                'Flowback Tank - Round Bottom', 'flowback_round_bottom'));
      case 'Production Tank':
        return RateCalculatorScreen(
            key: key,
            config: const RateCalculatorConfig.linear('Production Tank',
                defaultFactor: 1.67));
      case 'FS3':
      default:
        return RateCalculatorScreen(
            key: key,
            config: const RateCalculatorConfig.chart('FS3 Tank', 'fs3'));
    }
  }

  @override
  State<RateCalculatorScreen> createState() => _RateCalculatorScreenState();
}

class _RateCalculatorScreenState extends State<RateCalculatorScreen>
    with WidgetsBindingObserver {
  static const _timerMinutesPrefKey = 'wellwerks_rate_timer_minutes';
  final _settingsService = AppSettingsService();
  final _jobStorage = JobStorageService();
  final _rateTimerService = RateTimerService();
  final _rateTimerNotifications = RateTimerNotificationService.instance;

  final startGauge = TextEditingController();
  final endGauge = TextEditingController();
  final minutes = TextEditingController();
  late final TextEditingController factor;
  _KeypadTarget? _activeKeypadTarget;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  bool _thirtySecondAlertShown = false;
  bool _timerFinished = false;
  _RateDisplayUnit _rateDisplayUnit = _RateDisplayUnit.bblPerMin;
  bool _rateLogEnabled = false;
  bool _rateLogExpanded = false;
  final List<_RateLogEntry> _rateLogEntries = <_RateLogEntry>[];
  DateTime? _timerEndsAt;
  RateTimerState? _activeTimerState;

  static const int _minMinutes = 1;
  static const int _maxMinutes = 60;
  static const double _minuteRowHeight = 64;

  double? bblPerMin;
  double? bblPerHr;
  double? bblPerDay;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    factor = TextEditingController(
        text: (widget.config.defaultFactor ?? 1.67).toString());
    minutes.addListener(_handleMinutesChanged);
    _loadSavedTimerMinutes().then((_) async {
      await _applyPendingNotificationAction();
      await _restoreTimerState();
    });
    _loadSavedDisplayUnit();
    _loadRateLogState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _persistTimerState();
      _saveRateLogState();
    }
    if (state == AppLifecycleState.resumed) {
      _applyPendingNotificationAction();
      _restoreTimerState();
      _loadRateLogState();
    }
  }

  String get _calculatorStorageId {
    return (widget.config.chartId ?? widget.config.title)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  String get _rateLogEnabledPrefKey =>
      'wellwerks_rate_log_enabled_$_calculatorStorageId';

  String get _rateLogEntriesPrefKey =>
      'wellwerks_rate_log_entries_$_calculatorStorageId';

  String get _displayUnitPrefKey {
    return 'wellwerks_rate_display_unit_$_calculatorStorageId';
  }

  Future<void> _loadRateLogState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEnabled = prefs.getBool(_rateLogEnabledPrefKey) ?? false;
    final rawEntries = prefs.getString(_rateLogEntriesPrefKey);

    final loadedEntries = <_RateLogEntry>[];
    if (rawEntries != null && rawEntries.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawEntries);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final timestampMs = item['timestampMs'];
            final rateValue = item['rateValue'];
            final rateUnit = item['rateUnit'];
            final selected = item['selected'];
            if (timestampMs is! int) continue;
            if (rateValue is! num) continue;
            if (rateUnit is! String || rateUnit.isEmpty) continue;
            loadedEntries.add(
              _RateLogEntry(
                timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
                rateValue: rateValue.toDouble(),
                rateUnit: rateUnit,
                selected: selected is bool ? selected : true,
              ),
            );
          }
        }
      } catch (_) {
        // Ignore malformed persisted data and start with an empty log.
      }
    }

    if (loadedEntries.isNotEmpty) {
      loadedEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      loadedEntries[0] = loadedEntries[0].copyWith(selected: true);
    }

    if (!mounted) return;
    setState(() {
      _rateLogEnabled = savedEnabled;
      _rateLogEntries
        ..clear()
        ..addAll(loadedEntries);
    });
  }

  Future<void> _saveRateLogState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rateLogEnabledPrefKey, _rateLogEnabled);
    final payload = _rateLogEntries
        .map(
          (entry) => <String, Object>{
            'timestampMs': entry.timestamp.millisecondsSinceEpoch,
            'rateValue': entry.rateValue,
            'rateUnit': entry.rateUnit,
            'selected': entry.selected,
          },
        )
        .toList();
    await prefs.setString(_rateLogEntriesPrefKey, jsonEncode(payload));
  }

  Future<void> _loadSavedDisplayUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_displayUnitPrefKey);
    final settings = await _settingsService.load();
    if (!mounted) return;
    setState(() {
      final resolved = saved ?? settings.completionsRateDisplayDefault;
      _rateDisplayUnit = resolved == 'bbl_hr'
          ? _RateDisplayUnit.bblPerHr
          : _RateDisplayUnit.bblPerMin;
    });
  }

  Future<void> _saveDisplayUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final value =
        _rateDisplayUnit == _RateDisplayUnit.bblPerHr ? 'bbl_hr' : 'bbl_min';
    await prefs.setString(_displayUnitPrefKey, value);
  }

  String get _selectedRateUnitLabel =>
      _rateDisplayUnit == _RateDisplayUnit.bblPerHr ? 'BBL/hr' : 'BBL/min';

  double? get _selectedRateValue {
    if (_rateDisplayUnit == _RateDisplayUnit.bblPerHr) {
      return bblPerHr;
    }
    return bblPerMin;
  }

  String _formatSelectedRateValue(double? value) {
    if (value == null) return '-';
    return _rateDisplayUnit == _RateDisplayUnit.bblPerHr
        ? value.toStringAsFixed(1)
        : value.toStringAsFixed(3);
  }

  String _formatLogTimestamp(DateTime value) {
    final hour24 = value.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final m = value.minute.toString().padLeft(2, '0');
    return '$hour12:$m $period';
  }

  String _formatRateForUnit(double value, String unit) {
    if (unit == 'BBL/hr') {
      return value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(3);
  }

  void _setDisplayUnit(_RateDisplayUnit unit) {
    if (_rateDisplayUnit == unit) return;
    setState(() => _rateDisplayUnit = unit);
    _saveDisplayUnit();
  }

  void _showShareMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _copyRateUpdate() async {
    if (_rateLogEntries.isEmpty) {
      _showShareMessage('Calculate a rate before sharing.');
      return;
    }

    final selectedEntries = <_RateLogEntry>[];
    final newest = _rateLogEntries.first;
    selectedEntries.add(newest);
    for (int i = 1; i < _rateLogEntries.length; i++) {
      final entry = _rateLogEntries[i];
      if (entry.selected) {
        selectedEntries.add(entry);
      }
    }

    final lines = selectedEntries
        .map(
          (entry) =>
              '${_formatLogTimestamp(entry.timestamp)} - ${_formatRateForUnit(entry.rateValue, entry.rateUnit)} ${entry.rateUnit}',
        )
        .join('\n');
    final text = '${widget.config.title} Rates\n\n$lines';

    try {
      await Clipboard.setData(ClipboardData(text: text));
      _showShareMessage('Rate update copied to clipboard.');
    } catch (err) {
      debugPrint('Rate copy failed: $err');
      _showShareMessage('Unable to copy rate update.');
    }
  }

  Future<void> _persistTimerState() async {
    final active = _activeTimerState;
    if (_timerRunning && active != null) {
      await _rateTimerService.saveActiveTimer(active);
    }
  }

  Future<void> _clearTimerStatePersistence({bool forceAll = false}) async {
    final active = await _rateTimerService.loadActiveTimer();
    if (active != null) {
      if (!forceAll && active.calculatorId != _calculatorStorageId) {
        return;
      }
      await _rateTimerNotifications.cancelNotifications(active);
    }
    await _rateTimerService.clearActiveTimer();
  }

  Future<void> _restoreTimerState() async {
    final active = await _rateTimerService.loadActiveTimer();
    final now = DateTime.now();
    final remaining = active?.remainingSecondsAt(now) ?? 0;

    _countdownTimer?.cancel();
    _countdownTimer = null;

    if (!mounted) return;

    if (active == null || remaining <= 0) {
      setState(() {
        _activeTimerState = null;
        _timerEndsAt = null;
        _remainingSeconds = 0;
        _timerFinished = false;
        _thirtySecondAlertShown = false;
      });
      if (active != null) {
        await _rateTimerNotifications.cancelNotifications(active);
      }
      await _rateTimerService.clearActiveTimer();
      return;
    }

    if (active.calculatorId != _calculatorStorageId) {
      setState(() {
        _activeTimerState = active;
        _timerEndsAt = null;
        _remainingSeconds = 0;
        _timerFinished = false;
        _thirtySecondAlertShown = false;
      });
      return;
    }

    setState(() {
      _activeTimerState = active;
      _timerEndsAt = active.endsAt;
      _remainingSeconds = remaining;
      _timerFinished = false;
      _thirtySecondAlertShown = remaining <= 30;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _syncTimerFromClock(timer);
    });
  }

  void _syncTimerFromClock(Timer timer) {
    final end = _timerEndsAt;
    if (!mounted || end == null) {
      timer.cancel();
      _countdownTimer = null;
      return;
    }

    final nextSeconds = end.difference(DateTime.now()).inSeconds;
    if (nextSeconds <= 0) {
      timer.cancel();
      _countdownTimer = null;
      setState(() {
        _remainingSeconds = 0;
        _timerFinished = true;
        _thirtySecondAlertShown = true;
      });
      _clearTimerStatePersistence();
      _vibrateThreeQuickTimes();
      return;
    }

    if (nextSeconds == 30 && !_thirtySecondAlertShown) {
      _thirtySecondAlertShown = true;
      _vibrateOnce();
    }

    setState(() {
      _remainingSeconds = nextSeconds;
    });
  }

  Future<void> _clearRateLogWithConfirmation() async {
    if (_rateLogEntries.isEmpty) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear Rate Log?'),
            content: const Text(
              'This will permanently remove all logged rates.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear Log'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() {
      _rateLogEntries.clear();
      _rateLogExpanded = false;
    });
    await _saveRateLogState();
  }

  void _toggleRateLogEntrySelection(int index) {
    if (index <= 0 || index >= _rateLogEntries.length) {
      return;
    }
    setState(() {
      final entry = _rateLogEntries[index];
      _rateLogEntries[index] = entry.copyWith(selected: !entry.selected);
    });
    _saveRateLogState();
  }

  bool get _timerRunning => _countdownTimer != null;

  Future<void> _loadSavedTimerMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final savedText = prefs.getString(_timerMinutesPrefKey);
    final savedLegacyInt = prefs.getInt(_timerMinutesPrefKey);
    final settings = await _settingsService.load();
    if (!mounted) return;

    if (savedText != null && savedText.trim().isNotEmpty) {
      final parsed = int.tryParse(savedText.trim());
      if (parsed != null && parsed >= _minMinutes && parsed <= _maxMinutes) {
        minutes.text = parsed.toString();
      } else {
        minutes.text = _minMinutes.toString();
      }
      _remainingSeconds = _minutesToDurationSeconds();
      return;
    }

    if (savedLegacyInt != null &&
        savedLegacyInt >= _minMinutes &&
        savedLegacyInt <= _maxMinutes) {
      minutes.text = savedLegacyInt.toString();
      _remainingSeconds = _minutesToDurationSeconds();
      return;
    }

    final fallback = settings.completionsTimerDefaultMinutes
        .clamp(_minMinutes, _maxMinutes)
        .toString();
    minutes.text = fallback;
    _remainingSeconds = _minutesToDurationSeconds();
  }

  Future<void> _saveTimerMinutes(String valueText) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_timerMinutesPrefKey, valueText);
  }

  int _minutesToDurationSeconds() {
    final parsedMinutes = int.tryParse(minutes.text.trim()) ?? 0;
    if (parsedMinutes < _minMinutes || parsedMinutes > _maxMinutes) return 0;
    return (parsedMinutes * 60).round();
  }

  void _handleMinutesChanged() {
    final parsedMinutes = int.tryParse(minutes.text.trim());
    if (parsedMinutes != null &&
        parsedMinutes >= _minMinutes &&
        parsedMinutes <= _maxMinutes) {
      _saveTimerMinutes(parsedMinutes.toString());
    }

    if (_timerRunning || !mounted) return;

    final nextSeconds = _minutesToDurationSeconds();
    if (_remainingSeconds == nextSeconds && !_timerFinished) return;

    setState(() {
      _remainingSeconds = nextSeconds;
      _timerFinished = false;
    });
  }

  String _timerText() {
    final minutesPart = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final secondsPart = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$minutesPart:$secondsPart';
  }

  Future<void> _vibrateOnce() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (!hasVibrator) return;
    await Vibration.vibrate(duration: 120);
  }

  Future<void> _vibrateThreeQuickTimes() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (!hasVibrator) return;
    for (int i = 0; i < 3; i++) {
      await Vibration.vibrate(duration: 100);
      if (i < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
  }

  void _startTimedRate() {
    final configuredSeconds = _minutesToDurationSeconds();
    if (configuredSeconds <= 0) {
      setState(() {
        error = 'Minutes must be greater than zero.';
        _timerFinished = false;
        _remainingSeconds = 0;
      });
      return;
    }

    _startTimedRateWithConflictHandling(configuredSeconds);
  }

  Future<void> _startTimedRateWithConflictHandling(
      int configuredSeconds) async {
    final existing = await _rateTimerService.loadActiveTimer();
    final now = DateTime.now();
    if (existing != null && existing.isRunningAt(now)) {
      if (existing.calculatorId == _calculatorStorageId) {
        await _startFreshTimer(configuredSeconds);
        return;
      }
      if (!mounted) return;
      final restart = await _showTimerAlreadyRunningDialog(existing);
      if (restart == true) {
        await _rateTimerNotifications.cancelNotifications(existing);
        await _rateTimerService.clearActiveTimer();
        await _startFreshTimer(configuredSeconds);
      }
      return;
    }
    await _startFreshTimer(configuredSeconds);
  }

  Future<void> _startFreshTimer(int configuredSeconds) async {
    final activeJob = await _jobStorage.loadActiveJob();
    final wellOrJob = (activeJob?.primaryWell.trim().isNotEmpty ?? false)
        ? activeJob!.primaryWell.trim()
        : (activeJob?.padName.trim().isNotEmpty ?? false)
            ? activeJob!.padName.trim()
            : widget.config.title;

    final state = await _rateTimerService.createState(
      calculatorId: _calculatorStorageId,
      calculatorTitle: widget.config.title,
      wellOrJob: wellOrJob,
      durationSeconds: configuredSeconds,
    );
    final settings = await _settingsService.load();
    final permissionResult =
        await _rateTimerNotifications.ensurePermissionIfNeeded();
    if (settings.rateTimerNotificationsEnabled &&
        !permissionResult &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Timer started. Notifications are disabled. Open Settings > Notifications to enable alerts.',
          ),
        ),
      );
    }

    await _rateTimerService.saveActiveTimer(state);
    await _rateTimerNotifications.scheduleNotifications(
        timer: state, settings: settings);

    _countdownTimer?.cancel();
    setState(() {
      _activeTimerState = state;
      _timerEndsAt = state.endsAt;
      _remainingSeconds = configuredSeconds;
      _thirtySecondAlertShown = false;
      _timerFinished = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _syncTimerFromClock(timer);
    });
  }

  Future<bool?> _showTimerAlreadyRunningDialog(RateTimerState existing) async {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final remaining = existing.remainingSecondsAt(DateTime.now());
        final mm = (remaining ~/ 60).toString().padLeft(2, '0');
        final ss = (remaining % 60).toString().padLeft(2, '0');
        return AlertDialog(
          title: const Text('Rate Timer Already Running'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('A timer is currently active for:'),
              const SizedBox(height: 8),
              Text(
                existing.wellOrJob.isEmpty
                    ? existing.calculatorTitle
                    : existing.wellOrJob,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              const Text('Remaining Time:'),
              const SizedBox(height: 6),
              Text(
                '$mm:$ss',
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
                _openActiveRateCalculator(existing);
              },
              child: const Text('Continue Current'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Restart Timer'),
            ),
          ],
        );
      },
    );
  }

  void _openActiveRateCalculator(RateTimerState state) {
    final config = RateCalculatorConfig.fromStorageId(state.calculatorId);
    if (config == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RateCalculatorScreen(config: config),
      ),
    );
  }

  Future<void> _applyPendingNotificationAction() async {
    final action = await _rateTimerService.consumePendingAction();
    if (action == null) return;
    final targetCalculatorId =
        (action.payload['calculatorId'] as String? ?? '').trim();

    if (action.type == RateTimerPendingActionType.openCalculator) {
      final config = RateCalculatorConfig.fromStorageId(targetCalculatorId);
      if (config != null &&
          mounted &&
          targetCalculatorId != _calculatorStorageId) {
        Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => RateCalculatorScreen(config: config)),
        );
      }
      return;
    }

    if (targetCalculatorId != _calculatorStorageId) {
      return;
    }

    if (action.type == RateTimerPendingActionType.stopTimer) {
      _cancelTimedRate();
      return;
    }

    if (action.type == RateTimerPendingActionType.restartTimer) {
      final duration = (action.payload['durationSeconds'] as num?)?.toInt() ??
          _minutesToDurationSeconds();
      final safeDuration =
          duration <= 0 ? _minutesToDurationSeconds() : duration;
      await _startFreshTimer(safeDuration);
    }
  }

  void _cancelTimedRate() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _clearTimerStatePersistence();
    final configuredSeconds = _minutesToDurationSeconds();
    setState(() {
      _activeTimerState = null;
      _timerEndsAt = null;
      _remainingSeconds = configuredSeconds;
      _thirtySecondAlertShown = false;
      _timerFinished = false;
    });
  }

  bool get _hasValidMinutes => _minutesToDurationSeconds() > 0;

  bool get _hasGaugeInputs =>
      startGauge.text.trim().isNotEmpty && endGauge.text.trim().isNotEmpty;

  bool get _canCalculate => _hasGaugeInputs && _hasValidMinutes;

  bool get _showResetButton =>
      bblPerMin != null || bblPerHr != null || bblPerDay != null;

  String get _timerStatusText {
    if (_timerRunning) return 'Timer running...';
    if (_activeTimerState != null &&
        _activeTimerState!.calculatorId != _calculatorStorageId) {
      return 'Timer running in ${_activeTimerState!.calculatorTitle}.';
    }
    if (_timerFinished) return 'Ready to calculate.';
    return 'Enter gauges and start timer.';
  }

  Widget _timedRateSection() {
    final canRunTimer = _hasValidMinutes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Timed Rate',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF111418),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3A3A3A)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          color: Color(0xFFCDA56A), size: 28),
                      const SizedBox(width: 8),
                      Text(
                        _timerFinished ? 'TIME' : _timerText(),
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: _timerFinished
                              ? Colors.redAccent
                              : const Color(0xFFCDA56A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _timerStatusText,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (_timerRunning)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        (_activeTimerState?.wellOrJob.trim().isNotEmpty ??
                                false)
                            ? _activeTimerState!.wellOrJob.trim()
                            : widget.config.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (_timerRunning)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _cancelTimedRate,
                        child: const Text('Stop Timer'),
                      ),
                    )
                  else if (_timerFinished)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: canRunTimer ? _startTimedRate : null,
                        child: const Text('Restart'),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: canRunTimer ? _startTimedRate : null,
                        child: const Text('Start'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextEditingController? get _activeKeypadController {
    switch (_activeKeypadTarget) {
      case _KeypadTarget.start:
        return startGauge;
      case _KeypadTarget.end:
        return endGauge;
      case null:
        return null;
    }
  }

  void _setActiveKeypad(_KeypadTarget target) {
    FocusScope.of(context).unfocus();
    setState(() => _activeKeypadTarget = target);
  }

  String get _minutesDisplayText {
    final raw = minutes.text.trim();
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < _minMinutes || parsed > _maxMinutes) {
      return '$_minMinutes minute';
    }
    return parsed == 1 ? '1 minute' : '$parsed minutes';
  }

  int get _selectedMinutes {
    final parsed = int.tryParse(minutes.text.trim());
    if (parsed == null || parsed < _minMinutes || parsed > _maxMinutes) {
      return _minMinutes;
    }
    return parsed;
  }

  void _applyMinutesSelection(int value) {
    final clamped = value.clamp(_minMinutes, _maxMinutes);
    minutes.text = clamped.toString();
    if (!mounted) return;
    setState(() {
      if (!_timerRunning) {
        _remainingSeconds = _minutesToDurationSeconds();
        _timerFinished = false;
      }
      error = null;
    });
  }

  Future<void> _openMinutesSelector() async {
    FocusScope.of(context).unfocus();
    if (_activeKeypadTarget != null) {
      setState(() => _activeKeypadTarget = null);
    }

    final initialMinutes = _selectedMinutes;
    final scrollController = ScrollController(
      initialScrollOffset: (initialMinutes - _minMinutes) * _minuteRowHeight,
    );

    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            color: const Color(0xFF0F1114),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select Timer Length',
                      style: TextStyle(
                        color: Color(0xFFCDA56A),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 420,
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _maxMinutes,
                    itemExtent: _minuteRowHeight,
                    itemBuilder: (context, index) {
                      final minute = index + _minMinutes;
                      final selected = minute == _selectedMinutes;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Material(
                          color: selected
                              ? const Color(0x33282E36)
                              : const Color(0xFF15181C),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.of(sheetContext).pop(minute),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      minute == 1
                                          ? '1 minute'
                                          : '$minute minutes',
                                      style: TextStyle(
                                        color: selected
                                            ? const Color(0xFFCDA56A)
                                            : Colors.white,
                                        fontSize: 20,
                                        fontWeight: selected
                                            ? FontWeight.w900
                                            : FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(
                                      Icons.check_circle,
                                      color: Color(0xFFCDA56A),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    scrollController.dispose();

    if (!mounted || picked == null) return;
    _applyMinutesSelection(picked);
  }

  void _insertKeypadText(String raw) {
    final controller = _activeKeypadController;
    if (controller == null) return;
    setState(() {
      controller.value = GaugeKeypadInput.insert(controller.value, raw);
    });
  }

  void _backspaceKeypad() {
    final controller = _activeKeypadController;
    if (controller == null) return;
    if (controller.text.isEmpty) return;
    setState(() {
      controller.value = GaugeKeypadInput.backspace(controller.value);
    });
  }

  void _clearActiveInput() {
    final controller = _activeKeypadController;
    if (controller == null) return;
    setState(controller.clear);
  }

  void _closeKeypad() {
    setState(() => _activeKeypadTarget = null);
  }

  ButtonStyle _calculateButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: const Color(0xFFCDA56A),
      foregroundColor: Colors.black,
      disabledBackgroundColor: const Color(0xFF3A3A3A),
      disabledForegroundColor: const Color(0xFF9BA0A7),
      minimumSize: const Size.fromHeight(52),
      textStyle: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  TankChart? get chart {
    switch (widget.config.chartId) {
      case 'fs3':
        return fs3Chart;
      case 'sandx':
        return sandXChart;
      case 'flowback500':
        return flowback500Chart;
      case 'flowback_round_bottom':
        return flowbackRoundBottomChart;
    }
    return null;
  }

  double parseGauge(String value) {
    return parseGaugeInput(value);
  }

  double barrelsAt(double inches) {
    final c = chart;
    if (c != null) return c.barrelsAt(inches);
    final f = double.tryParse(factor.text.trim()) ?? 1.67;
    return inches * f;
  }

  void _resetTimedRateWorkflow() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _clearTimerStatePersistence();
    setState(() {
      _activeTimerState = null;
      _timerEndsAt = null;
      startGauge.clear();
      endGauge.clear();
      bblPerMin = null;
      bblPerHr = null;
      bblPerDay = null;
      _timerFinished = false;
      _thirtySecondAlertShown = false;
      _remainingSeconds = _minutesToDurationSeconds();
      error = null;
    });
  }

  void calculate() {
    final hadKeypadOpen = _activeKeypadTarget != null;
    FocusScope.of(context).unfocus();
    if (hadKeypadOpen) {
      setState(() => _activeKeypadTarget = null);
    }

    if (!_hasGaugeInputs || minutes.text.trim().isEmpty) {
      setState(
        () => error = 'Enter Starting Gauge, Ending Gauge, and Minutes.',
      );
      return;
    }
    final m = double.tryParse(minutes.text.trim()) ?? 0;
    if (m <= 0) {
      setState(() => error = 'Minutes must be greater than zero.');
      return;
    }
    if (!widget.config.usesChart &&
        (double.tryParse(factor.text.trim()) ?? 0) <= 0) {
      setState(() => error = 'Tank factor must be greater than zero.');
      return;
    }

    final startBbl = barrelsAt(parseGauge(startGauge.text));
    final endBbl = barrelsAt(parseGauge(endGauge.text));
    final change = (endBbl - startBbl).abs();
    final perMin = change / m;
    final perHour = perMin * 60;

    _countdownTimer?.cancel();
    _countdownTimer = null;
    _clearTimerStatePersistence();

    setState(() {
      bblPerMin = perMin;
      bblPerHr = perHour;
      bblPerDay = perMin * 1440;
      _timerFinished = false;
      _thirtySecondAlertShown = false;
      _remainingSeconds = _minutesToDurationSeconds();
      error = null;
      if (_rateLogEnabled) {
        final value =
            _rateDisplayUnit == _RateDisplayUnit.bblPerHr ? perHour : perMin;
        _rateLogEntries.insert(
          0,
          _RateLogEntry(
            timestamp: DateTime.now(),
            rateValue: value,
            rateUnit: _selectedRateUnitLabel,
            selected: true,
          ),
        );
        _saveRateLogState();
      }
    });
  }

  @override
  void dispose() {
    _persistTimerState();
    _saveRateLogState();
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    minutes.removeListener(_handleMinutesChanged);
    startGauge.dispose();
    endGauge.dispose();
    minutes.dispose();
    factor.dispose();
    super.dispose();
  }

  Widget _resultsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Results',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Rate Display',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ChoiceChip(
                  selected: _rateDisplayUnit == _RateDisplayUnit.bblPerMin,
                  label: const Text('BBL/min'),
                  onSelected: (_) =>
                      _setDisplayUnit(_RateDisplayUnit.bblPerMin),
                  selectedColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.28),
                  labelStyle: TextStyle(
                    color: _rateDisplayUnit == _RateDisplayUnit.bblPerMin
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                ChoiceChip(
                  selected: _rateDisplayUnit == _RateDisplayUnit.bblPerHr,
                  label: const Text('BBL/hr'),
                  onSelected: (_) => _setDisplayUnit(_RateDisplayUnit.bblPerHr),
                  selectedColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.28),
                  labelStyle: TextStyle(
                    color: _rateDisplayUnit == _RateDisplayUnit.bblPerHr
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _formatSelectedRateValue(_selectedRateValue),
              style: const TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                color: Color(0xFFCDA56A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _selectedRateUnitLabel,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rateLogSection() {
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(
              'Rate Log (${_rateLogEntries.length})',
              style: const TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w800,
              ),
            ),
            trailing: Icon(
              _rateLogExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () => setState(() => _rateLogExpanded = !_rateLogExpanded),
          ),
          if (_rateLogExpanded) ...[
            if (_rateLogEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'No log entries yet.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    if (_rateLogEnabled && _rateLogEntries.isNotEmpty)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyRateUpdate,
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Copy Update'),
                        ),
                      ),
                    if (_rateLogEnabled && _rateLogEntries.isNotEmpty)
                      const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _clearRateLogWithConfirmation,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear Log'),
                      ),
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _rateLogEntries.length,
                  itemBuilder: (context, index) {
                    final entry = _rateLogEntries[index];
                    final value =
                        _formatRateForUnit(entry.rateValue, entry.rateUnit);
                    final isNewest = index == 0;
                    final isSelected = isNewest ? true : entry.selected;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _toggleRateLogEntrySelection(index),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${_formatLogTimestamp(entry.timestamp)} - $value ${entry.rateUnit}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check,
                                  color: Color(0xFFCDA56A),
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _sharedGaugeKeypad() {
    if (_activeKeypadTarget == null) return const SizedBox.shrink();
    final activeLabel = _activeKeypadTarget == _KeypadTarget.start
        ? 'Starting Gauge'
        : 'Ending Gauge';
    return SharedGaugeKeypad(
      activeFieldLabel: activeLabel,
      onInsert: _insertKeypadText,
      onBackspace: _backspaceKeypad,
      onClear: _clearActiveInput,
      onDone: _closeKeypad,
      showPrimaryAction: !_showResetButton,
      primaryActionEnabled: _canCalculate,
      primaryActionLabel: 'Calculate Rate',
      onPrimaryAction: calculate,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppHeader(title: widget.config.title, showBack: true),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  if (!widget.config.usesChart)
                    WwNumberField(
                        label: 'Tank Factor (BBL/In)',
                        controller: factor,
                        allowDecimal: true),
                  const SizedBox(height: 8),
                  WwGaugeField(
                    label: 'Starting Gauge',
                    controller: startGauge,
                    autofocus: true,
                    active: _activeKeypadTarget == _KeypadTarget.start,
                    onTap: () => _setActiveKeypad(_KeypadTarget.start),
                    onChanged: (_) => setState(() {}),
                  ),
                  WwGaugeField(
                    label: 'Ending Gauge',
                    controller: endGauge,
                    active: _activeKeypadTarget == _KeypadTarget.end,
                    onTap: () => _setActiveKeypad(_KeypadTarget.end),
                    onChanged: (_) => setState(() {}),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _openMinutesSelector,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF4A4A4A),
                              width: 1.2,
                            ),
                            color: const Color(0xFF121418),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Minutes',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _minutesDisplayText,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFCDA56A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _timedRateSection(),
                  const SizedBox(height: 10),
                  FilledButton(
                    style: _calculateButtonStyle(),
                    onPressed: _showResetButton
                        ? _resetTimedRateWorkflow
                        : (_canCalculate ? calculate : null),
                    child: Text(_showResetButton ? 'RESET' : 'CALCULATE'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    value: _rateLogEnabled,
                    onChanged: (value) {
                      setState(() => _rateLogEnabled = value);
                      _saveRateLogState();
                    },
                    title: const Text('Rate Log'),
                    subtitle: const Text('Save each CALCULATE result to log'),
                  ),
                  if (error != null)
                    Card(
                      color: const Color(0xFF3A1E1E),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(error!,
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  if (bblPerMin != null) ...[
                    const SizedBox(height: 10),
                    _resultsCard(),
                    _rateLogSection(),
                  ] else if (_rateLogEntries.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _rateLogSection(),
                  ],
                ],
              ),
            ),
            _sharedGaugeKeypad(),
          ],
        ),
      );
}
