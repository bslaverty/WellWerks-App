import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import '../services/app_settings_service.dart';
import '../data/tank_charts.dart';
import '../widgets/app_header.dart';
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
  DateTime? _timerStartedAt;
  DateTime? _timerEndsAt;

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
    _loadSavedTimerMinutes().then((_) => _restoreTimerState());
    _loadSavedDisplayUnit();
    _loadRateLogState();
  }

  String get _timerRunningPrefKey =>
      'wellwerks_rate_timer_running_$_calculatorStorageId';

  String get _timerStartPrefKey =>
      'wellwerks_rate_timer_start_ms_$_calculatorStorageId';

  String get _timerEndPrefKey =>
      'wellwerks_rate_timer_end_ms_$_calculatorStorageId';

  String get _timerMinutesDuringRunPrefKey =>
      'wellwerks_rate_timer_minutes_run_$_calculatorStorageId';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _persistTimerState();
      _saveRateLogState();
    }
    if (state == AppLifecycleState.resumed) {
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
    final prefs = await SharedPreferences.getInstance();
    final running = _timerRunning;
    await prefs.setBool(_timerRunningPrefKey, running);
    await prefs.setInt(_timerMinutesDuringRunPrefKey, _selectedMinutes);
    if (running && _timerStartedAt != null && _timerEndsAt != null) {
      await prefs.setInt(
        _timerStartPrefKey,
        _timerStartedAt!.millisecondsSinceEpoch,
      );
      await prefs.setInt(
          _timerEndPrefKey, _timerEndsAt!.millisecondsSinceEpoch);
    }
  }

  Future<void> _clearTimerStatePersistence() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_timerRunningPrefKey, false);
    await prefs.remove(_timerStartPrefKey);
    await prefs.remove(_timerEndPrefKey);
  }

  Future<void> _restoreTimerState() async {
    final prefs = await SharedPreferences.getInstance();
    final running = prefs.getBool(_timerRunningPrefKey) ?? false;
    final startMs = prefs.getInt(_timerStartPrefKey);
    final endMs = prefs.getInt(_timerEndPrefKey);
    final savedRunMinutes = prefs.getInt(_timerMinutesDuringRunPrefKey);

    if (savedRunMinutes != null &&
        savedRunMinutes >= _minMinutes &&
        savedRunMinutes <= _maxMinutes) {
      minutes.text = savedRunMinutes.toString();
    }

    if (!running || startMs == null || endMs == null) {
      if (!mounted) return;
      setState(() {
        _timerStartedAt = null;
        _timerEndsAt = null;
      });
      return;
    }

    final now = DateTime.now();
    final start = DateTime.fromMillisecondsSinceEpoch(startMs);
    final end = DateTime.fromMillisecondsSinceEpoch(endMs);
    final remaining = end.difference(now).inSeconds;

    _countdownTimer?.cancel();
    _countdownTimer = null;

    if (!mounted) return;

    if (remaining <= 0) {
      setState(() {
        _timerStartedAt = start;
        _timerEndsAt = end;
        _remainingSeconds = 0;
        _timerFinished = true;
        _thirtySecondAlertShown = true;
      });
      await _clearTimerStatePersistence();
      return;
    }

    setState(() {
      _timerStartedAt = start;
      _timerEndsAt = end;
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

    _countdownTimer?.cancel();
    final now = DateTime.now();
    final endAt = now.add(Duration(seconds: configuredSeconds));
    setState(() {
      _timerStartedAt = now;
      _timerEndsAt = endAt;
      _remainingSeconds = configuredSeconds;
      _thirtySecondAlertShown = false;
      _timerFinished = false;
    });
    _persistTimerState();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _syncTimerFromClock(timer);
    });
  }

  void _cancelTimedRate() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _clearTimerStatePersistence();
    final configuredSeconds = _minutesToDurationSeconds();
    setState(() {
      _timerStartedAt = null;
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
                  const SizedBox(height: 10),
                  if (_timerRunning)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _cancelTimedRate,
                        child: const Text('Cancel'),
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

  bool get _isGaugeMode {
    return _activeKeypadTarget == _KeypadTarget.start ||
        _activeKeypadTarget == _KeypadTarget.end;
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

    final isGaugeFraction = _isGaugeMode && RegExp(r'^\d+/\d+$').hasMatch(raw);
    final insertText = raw == 'Space'
        ? ' '
        : (isGaugeFraction ? _fractionInsertText(controller.text, raw) : raw);
    final selection = controller.selection;
    final text = controller.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final next = _normalizeSpaces(text.replaceRange(start, end, insertText));
    final cursor = start + insertText.length;

    setState(() {
      controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: cursor),
      );
    });
  }

  void _backspaceKeypad() {
    final controller = _activeKeypadController;
    if (controller == null) return;
    final text = controller.text;
    if (text.isEmpty) return;

    final selection = controller.selection;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;

    setState(() {
      if (start != end) {
        final updated = _trimTrailingSpaceOnDelete(
          text.replaceRange(start, end, ''),
        );
        controller.value = TextEditingValue(
          text: updated,
          selection: TextSelection.collapsed(
            offset: start > updated.length ? updated.length : start,
          ),
        );
      } else if (start > 0) {
        final updated = _trimTrailingSpaceOnDelete(
          text.replaceRange(start - 1, start, ''),
        );
        final nextCursor =
            (start - 1) > updated.length ? updated.length : (start - 1);
        controller.value = TextEditingValue(
          text: updated,
          selection: TextSelection.collapsed(offset: nextCursor),
        );
      }
    });
  }

  String _fractionInsertText(String currentText, String fraction) {
    if (currentText.isEmpty) return fraction;
    return currentText.endsWith(' ') ? fraction : ' $fraction';
  }

  String _normalizeSpaces(String value) {
    return value.replaceAll(RegExp(r' {2,}'), ' ');
  }

  String _trimTrailingSpaceOnDelete(String value) {
    return value.replaceFirst(RegExp(r'\s+$'), '');
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
    }
    return null;
  }

  double parseGauge(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return 0;
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length == 2 && parts[1].contains('/')) {
      final whole = double.tryParse(parts[0]) ?? 0;
      final frac = parts[1].split('/');
      final numerator = double.tryParse(frac.first) ?? 0;
      final denominator = frac.length > 1 ? (double.tryParse(frac[1]) ?? 1) : 1;
      return whole + (numerator / denominator);
    }
    if (clean.contains('/')) {
      final frac = clean.split('/');
      final numerator = double.tryParse(frac.first) ?? 0;
      final denominator = frac.length > 1 ? (double.tryParse(frac[1]) ?? 1) : 1;
      return numerator / denominator;
    }
    return double.tryParse(clean) ?? 0;
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
      _timerStartedAt = null;
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
                  selectedColor: const Color(0xFFCDA56A),
                  labelStyle: TextStyle(
                    color: _rateDisplayUnit == _RateDisplayUnit.bblPerMin
                        ? Colors.black
                        : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                ChoiceChip(
                  selected: _rateDisplayUnit == _RateDisplayUnit.bblPerHr,
                  label: const Text('BBL/hr'),
                  onSelected: (_) => _setDisplayUnit(_RateDisplayUnit.bblPerHr),
                  selectedColor: const Color(0xFFCDA56A),
                  labelStyle: TextStyle(
                    color: _rateDisplayUnit == _RateDisplayUnit.bblPerHr
                        ? Colors.black
                        : Colors.white,
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

  Widget _gaugeKeyButton(String label,
      {VoidCallback? onPressed, bool compact = false}) {
    return SizedBox(
      height: compact ? 34 : 40,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFCDA56A)),
          backgroundColor: const Color(0xFF15181C),
          foregroundColor: Colors.white,
          padding:
              EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 6),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: compact ? 12 : 16, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _keypadRow(List<Widget> children) {
    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i != children.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _keypadNumericButton(String value) {
    return _gaugeKeyButton(
      value,
      onPressed: () => _insertKeypadText(value),
    );
  }

  Widget _keypadCalculateButton() {
    return SizedBox(
      height: 40,
      child: FilledButton(
        onPressed: _canCalculate ? calculate : null,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFCDA56A),
          foregroundColor: Colors.black,
          disabledBackgroundColor: const Color(0xFF3A3A3A),
          disabledForegroundColor: const Color(0xFF9BA0A7),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        child: const Text('CALCULATE'),
      ),
    );
  }

  Widget _sharedGaugeKeypad() {
    if (_activeKeypadTarget == null) return const SizedBox.shrink();
    final activeLabel = _activeKeypadTarget == _KeypadTarget.start
        ? 'Starting Gauge'
        : 'Ending Gauge';
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1114),
        border: Border(top: BorderSide(color: Color(0xFF3A3A3A))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_isGaugeMode ? 'Gauge' : 'Number'} Keypad • $activeLabel',
                    style: const TextStyle(
                      color: Color(0xFFCDA56A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                    onPressed: _clearActiveInput, child: const Text('CLR')),
                const SizedBox(width: 6),
                FilledButton(
                    onPressed: _closeKeypad, child: const Text('Done')),
              ],
            ),
            if (_isGaugeMode) ...[
              const SizedBox(height: 6),
              _keypadRow([
                _gaugeKeyButton(
                  '1/8',
                  compact: true,
                  onPressed: () => _insertKeypadText('1/8'),
                ),
                _gaugeKeyButton(
                  '1/4',
                  compact: true,
                  onPressed: () => _insertKeypadText('1/4'),
                ),
                _gaugeKeyButton(
                  '3/8',
                  compact: true,
                  onPressed: () => _insertKeypadText('3/8'),
                ),
                _gaugeKeyButton(
                  '1/2',
                  compact: true,
                  onPressed: () => _insertKeypadText('1/2'),
                ),
                _gaugeKeyButton(
                  '5/8',
                  compact: true,
                  onPressed: () => _insertKeypadText('5/8'),
                ),
              ]),
              const SizedBox(height: 6),
              _keypadRow([
                _gaugeKeyButton(
                  '3/4',
                  compact: true,
                  onPressed: () => _insertKeypadText('3/4'),
                ),
                _gaugeKeyButton(
                  '7/8',
                  compact: true,
                  onPressed: () => _insertKeypadText('7/8'),
                ),
                _gaugeKeyButton(
                  'Space',
                  compact: true,
                  onPressed: () => _insertKeypadText('Space'),
                ),
                _gaugeKeyButton(
                  'Backspace',
                  compact: true,
                  onPressed: _backspaceKeypad,
                ),
                _keypadCalculateButton(),
              ]),
              const SizedBox(height: 8),
              _keypadRow([
                _keypadNumericButton('1'),
                _keypadNumericButton('2'),
                _keypadNumericButton('3'),
              ]),
              const SizedBox(height: 6),
              _keypadRow([
                _keypadNumericButton('4'),
                _keypadNumericButton('5'),
                _keypadNumericButton('6'),
              ]),
              const SizedBox(height: 6),
              _keypadRow([
                _keypadNumericButton('7'),
                _keypadNumericButton('8'),
                _keypadNumericButton('9'),
              ]),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Spacer(),
                  Expanded(child: _keypadNumericButton('0')),
                  const Spacer(),
                ],
              ),
            ],
          ],
        ),
      ),
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
                    activeThumbColor: const Color(0xFFCDA56A),
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
