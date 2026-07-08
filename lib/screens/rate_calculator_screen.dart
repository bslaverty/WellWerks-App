import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import '../data/tank_charts.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

enum _KeypadTarget { start, end }

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

class _RateCalculatorScreenState extends State<RateCalculatorScreen> {
  static const _timerMinutesPrefKey = 'wellwerks_rate_timer_minutes';

  final startGauge = TextEditingController();
  final endGauge = TextEditingController();
  final minutes = TextEditingController();
  late final TextEditingController factor;
  _KeypadTarget? _activeKeypadTarget;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  bool _thirtySecondAlertShown = false;
  bool _timerFinished = false;

  static const List<String> _gaugeMainKeys = <String>[
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '.',
    '0',
    '/',
  ];

  static const int _minMinutes = 1;
  static const int _maxMinutes = 60;
  static const double _minuteRowHeight = 64;

  static const List<String> _gaugeFractionShortcuts = <String>[
    '1/8',
    '1/4',
    '3/8',
    '1/2',
    '5/8',
    '3/4',
    '7/8',
  ];

  double? bblPerMin;
  double? bblPerHr;
  double? bblPerDay;
  String? error;

  @override
  void initState() {
    super.initState();
    factor = TextEditingController(
        text: (widget.config.defaultFactor ?? 1.67).toString());
    minutes.addListener(_handleMinutesChanged);
    _loadSavedTimerMinutes();
  }

  bool get _timerRunning => _countdownTimer != null;

  Future<void> _loadSavedTimerMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final savedText = prefs.getString(_timerMinutesPrefKey);
    final savedLegacyInt = prefs.getInt(_timerMinutesPrefKey);
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

    minutes.text = _minMinutes.toString();
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
    setState(() {
      _remainingSeconds = configuredSeconds;
      _thirtySecondAlertShown = false;
      _timerFinished = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        _countdownTimer = null;
        return;
      }

      final nextSeconds = _remainingSeconds - 1;
      if (nextSeconds <= 0) {
        timer.cancel();
        _countdownTimer = null;
        setState(() {
          _remainingSeconds = 0;
          _timerFinished = true;
        });
        _vibrateThreeQuickTimes();
        return;
      }

      if (nextSeconds == 30 && !_thirtySecondAlertShown) {
        _thirtySecondAlertShown = true;
        setState(() {
          _remainingSeconds = nextSeconds;
        });
        _vibrateOnce();
        return;
      }

      setState(() {
        _remainingSeconds = nextSeconds;
      });
    });
  }

  void _cancelTimedRate() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    final configuredSeconds = _minutesToDurationSeconds();
    setState(() {
      _remainingSeconds = configuredSeconds;
      _thirtySecondAlertShown = false;
      _timerFinished = false;
    });
  }

  bool get _hasValidMinutes => _minutesToDurationSeconds() > 0;

  bool get _hasGaugeInputs =>
      startGauge.text.trim().isNotEmpty && endGauge.text.trim().isNotEmpty;

  bool get _canCalculate =>
      _hasGaugeInputs && _hasValidMinutes && _timerFinished && !_timerRunning;

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
    if (!_timerFinished) {
      setState(() => error = 'Finish the timer before calculating.');
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

    setState(() {
      bblPerMin = perMin;
      bblPerHr = perMin * 60;
      bblPerDay = perMin * 1440;
      startGauge.clear();
      endGauge.clear();
      _timerFinished = false;
      _thirtySecondAlertShown = false;
      _remainingSeconds = _minutesToDurationSeconds();
      error = null;
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    minutes.removeListener(_handleMinutesChanged);
    startGauge.dispose();
    endGauge.dispose();
    minutes.dispose();
    factor.dispose();
    super.dispose();
  }

  Widget _resultCard(String label, String value) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFFCDA56A), fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(value,
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );

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
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ..._gaugeFractionShortcuts.map((value) => _gaugeKeyButton(
                        value,
                        compact: true,
                        onPressed: () => _insertKeypadText(value),
                      )),
                  _gaugeKeyButton('Space',
                      compact: true,
                      onPressed: () => _insertKeypadText('Space')),
                  _gaugeKeyButton('⌫',
                      compact: true, onPressed: _backspaceKeypad),
                ],
              ),
            ],
            const SizedBox(height: 8),
            GridView.builder(
              itemCount: _gaugeMainKeys.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 2.6,
              ),
              itemBuilder: (context, index) {
                final key = _gaugeMainKeys[index];
                if (key == '⌫') {
                  return _gaugeKeyButton(key, onPressed: _backspaceKeypad);
                }
                return _gaugeKeyButton(key,
                    onPressed: () => _insertKeypadText(key));
              },
            ),
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
                    onPressed: _canCalculate ? calculate : null,
                    child: const Text('Calculate'),
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
                    _resultCard('BBL/min', bblPerMin!.toStringAsFixed(3)),
                    _resultCard('BBL/hr', bblPerHr!.toStringAsFixed(1)),
                    _resultCard('BBL/day', bblPerDay!.toStringAsFixed(1)),
                  ],
                ],
              ),
            ),
            _sharedGaugeKeypad(),
          ],
        ),
      );
}
