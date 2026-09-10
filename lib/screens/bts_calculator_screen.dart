import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/casing_database.dart';
import '../services/rate_timer_service.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

/// BTS (Bit to Surface) Calculator.
///
/// Determines how long it takes for returns to travel from the bit to the
/// surface using the annular volume between the tubing OD and casing ID,
/// divided by the actual Flowback Return Rate.
class BtsCalculatorScreen extends StatefulWidget {
  const BtsCalculatorScreen({super.key});

  @override
  State<BtsCalculatorScreen> createState() => _BtsCalculatorScreenState();
}

class _TubingOdOption {
  final String label;
  final double od;
  final bool custom;

  const _TubingOdOption(this.label, this.od, {this.custom = false});
}

class _BtsCalculatorScreenState extends State<BtsCalculatorScreen>
    with WidgetsBindingObserver {
  static const _calculatorId = 'bts_calculator';
  static const _instanceStorageId = 'bts_calculator';
  static const _pausedRemainingKey = 'wellwerks_bts_timer_paused_remaining_v1';
  static const _pausedFlagKey = 'wellwerks_bts_timer_paused_flag_v1';
  static const _totalDurationKey = 'wellwerks_bts_timer_total_duration_v1';

  final _rateTimerService = RateTimerService();

  Color get _gold => Theme.of(context).colorScheme.primary;

  static const _tubingOdOptions = <_TubingOdOption>[
    _TubingOdOption('2-3/8" EUE', 2.375),
    _TubingOdOption('2-7/8" EUE', 2.875),
    _TubingOdOption('3-1/2"', 3.5),
    _TubingOdOption('4-1/2"', 4.5),
    _TubingOdOption('5"', 5.0),
    _TubingOdOption('5-1/2"', 5.5),
    _TubingOdOption('7"', 7.0),
    _TubingOdOption('9-5/8"', 9.625),
    _TubingOdOption('Custom OD', 0, custom: true),
  ];

  _TubingOdOption selectedTubing = _tubingOdOptions[1];
  CasingSizeOption selectedCasing = CasingDatabase.sizes[2];
  CasingWeightOption? selectedCasingWeight;

  final tubingOd = TextEditingController(
    text: _tubingOdOptions[1].od.toStringAsFixed(3),
  );
  final bitDepth = TextEditingController();
  final flowbackReturnRate = TextEditingController();
  final lagFactor = TextEditingController(text: '1.00');

  bool _calculated = false;

  // Live BTS timer state.
  Timer? _countdownTimer;
  bool _timerRunning = false;
  bool _timerPaused = false;
  bool _timerFinished = false;
  DateTime? _timerEndsAt;
  int _remainingSeconds = 0;
  int _totalDurationSeconds = 0;

  double get _tubingOd => double.tryParse(tubingOd.text.trim()) ?? 0;
  double get _bitDepth => double.tryParse(bitDepth.text.trim()) ?? 0;
  double get _flowbackReturnRate =>
      double.tryParse(flowbackReturnRate.text.trim()) ?? 0;
  double get _lag => double.tryParse(lagFactor.text.trim()) ?? 1.0;

  double? get _casingId => selectedCasingWeight?.id;

  double? get annularCapacity {
    final id = _casingId;
    if (id == null || _tubingOd <= 0 || id <= _tubingOd) return null;
    return (id * id - _tubingOd * _tubingOd) / 1029.4;
  }

  double? get annularVolume {
    final capacity = annularCapacity;
    if (capacity == null || _bitDepth <= 0) return null;
    return capacity * _bitDepth * (_lag <= 0 ? 1.0 : _lag);
  }

  double? get btsMinutes {
    final volume = annularVolume;
    if (volume == null || _flowbackReturnRate <= 0) return null;
    return volume / _flowbackReturnRate;
  }

  String get arrivalTime {
    final mins = btsMinutes;
    if (mins == null) return '--';
    final eta = DateTime.now().add(Duration(seconds: (mins * 60).round()));
    return DateFormat('h:mm a').format(eta);
  }

  String get hourMinuteText {
    final mins = btsMinutes;
    if (mins == null) return '--';
    final totalMinutes = mins.round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return hours > 0 ? '$hours hr $minutes min' : '$minutes min';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    selectedCasingWeight =
        selectedCasing.weights.isNotEmpty ? selectedCasing.weights.first : null;
    for (final controller in [
      tubingOd,
      bitDepth,
      flowbackReturnRate,
      lagFactor,
    ]) {
      controller.addListener(_handleInputChanged);
    }
    _restoreTimerState();
  }

  void _handleInputChanged() {
    if (_timerRunning || _timerPaused) return;
    if (_calculated) {
      setState(() => _calculated = false);
    } else {
      setState(() {});
    }
  }

  void _selectTubing(_TubingOdOption pipe) {
    setState(() {
      selectedTubing = pipe;
      if (!pipe.custom) {
        tubingOd.text = pipe.od.toStringAsFixed(3);
      } else {
        tubingOd.clear();
      }
    });
  }

  void _selectCasing(CasingSizeOption casing) {
    setState(() {
      selectedCasing = casing;
      selectedCasingWeight =
          casing.weights.isNotEmpty ? casing.weights.first : null;
    });
  }

  void _selectCasingWeight(CasingWeightOption weight) {
    setState(() => selectedCasingWeight = weight);
  }

  void _calculate() {
    FocusScope.of(context).unfocus();
    if (btsMinutes == null) return;
    setState(() => _calculated = true);
  }

  void clearAll() {
    setState(() {
      selectedTubing = _tubingOdOptions[1];
      selectedCasing = CasingDatabase.sizes[2];
      selectedCasingWeight = selectedCasing.weights.isNotEmpty
          ? selectedCasing.weights.first
          : null;
      tubingOd.text = _tubingOdOptions[1].od.toStringAsFixed(3);
      bitDepth.clear();
      flowbackReturnRate.clear();
      lagFactor.text = '1.00';
      _calculated = false;
    });
  }

  Future<void> copyResults() async {
    final volume = annularVolume;
    final mins = btsMinutes;
    if (volume == null || mins == null) return;

    final text = '''BTS Calculator (Bit to Surface)
Tubing OD: ${selectedTubing.custom ? '${_tubingOd.toStringAsFixed(3)}"' : selectedTubing.label}
Casing OD: ${selectedCasing.label}
Casing Weight: ${selectedCasingWeight?.label ?? '--'}
Casing ID: ${_casingId?.toStringAsFixed(3) ?? '--'}"
Bit Depth: ${_bitDepth.toStringAsFixed(0)} ft
Flowback Return Rate: ${_flowbackReturnRate.toStringAsFixed(2)} BBL/min
Annular Volume: ${volume.toStringAsFixed(2)} BBL
BTS Time: ${mins.toStringAsFixed(2)} min ($hourMinuteText)
Estimated Arrival: $arrivalTime''';

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('BTS results copied')));
  }

  // ---------------------------------------------------------------------
  // Live BTS Timer
  // ---------------------------------------------------------------------

  Future<void> _startTimer() async {
    final mins = btsMinutes;
    if (mins == null) return;
    final durationSeconds = (mins * 60).round();
    if (durationSeconds <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pausedRemainingKey);
    await prefs.remove(_pausedFlagKey);
    await prefs.setInt(_totalDurationKey, durationSeconds);

    final state = await _rateTimerService.createState(
      calculatorId: _calculatorId,
      calculatorTitle: 'BTS Calculator',
      wellOrJob: '',
      durationSeconds: durationSeconds,
    );
    final instanceState = state.copyWith(instanceId: _instanceStorageId);
    await _rateTimerService.saveActiveTimer(instanceState);

    if (!mounted) return;
    setState(() {
      _timerEndsAt = instanceState.endsAt;
      _remainingSeconds = durationSeconds;
      _totalDurationSeconds = durationSeconds;
      _timerRunning = true;
      _timerPaused = false;
      _timerFinished = false;
    });
    _startTicker();
  }

  Future<void> _pauseTimer() async {
    if (!_timerRunning) return;
    final end = _timerEndsAt;
    final remaining =
        end == null ? 0 : end.difference(DateTime.now()).inSeconds;
    final clamped = remaining < 0 ? 0 : remaining;

    _countdownTimer?.cancel();
    _countdownTimer = null;
    await _rateTimerService.clearActiveTimer(instanceId: _instanceStorageId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pausedRemainingKey, clamped);
    await prefs.setBool(_pausedFlagKey, true);

    if (!mounted) return;
    setState(() {
      _timerRunning = false;
      _timerPaused = true;
      _remainingSeconds = clamped;
      _timerEndsAt = null;
    });
  }

  Future<void> _resumeTimer() async {
    if (!_timerPaused) return;
    final durationSeconds = _remainingSeconds;
    if (durationSeconds <= 0) {
      await _resetTimer();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pausedRemainingKey);
    await prefs.remove(_pausedFlagKey);

    final state = await _rateTimerService.createState(
      calculatorId: _calculatorId,
      calculatorTitle: 'BTS Calculator',
      wellOrJob: '',
      durationSeconds: durationSeconds,
    );
    final instanceState = state.copyWith(instanceId: _instanceStorageId);
    await _rateTimerService.saveActiveTimer(instanceState);

    if (!mounted) return;
    setState(() {
      _timerEndsAt = instanceState.endsAt;
      _remainingSeconds = durationSeconds;
      _timerRunning = true;
      _timerPaused = false;
      _timerFinished = false;
    });
    _startTicker();
  }

  Future<void> _resetTimer() async {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    await _rateTimerService.clearActiveTimer(instanceId: _instanceStorageId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pausedRemainingKey);
    await prefs.remove(_pausedFlagKey);
    await prefs.remove(_totalDurationKey);

    final mins = btsMinutes;
    final fullSeconds = mins == null ? 0 : (mins * 60).round();

    if (!mounted) return;
    setState(() {
      _timerRunning = false;
      _timerPaused = false;
      _timerFinished = false;
      _timerEndsAt = null;
      _remainingSeconds = fullSeconds;
      _totalDurationSeconds = fullSeconds;
    });
  }

  void _startTicker() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final end = _timerEndsAt;
      if (!mounted || end == null) {
        timer.cancel();
        _countdownTimer = null;
        return;
      }
      final next = end.difference(DateTime.now()).inSeconds;
      if (next <= 0) {
        timer.cancel();
        _countdownTimer = null;
        setState(() {
          _remainingSeconds = 0;
          _timerRunning = false;
          _timerFinished = true;
        });
        return;
      }
      setState(() => _remainingSeconds = next);
    });
  }

  Future<void> _restoreTimerState() async {
    final active =
        await _rateTimerService.loadActiveTimerForInstance(_instanceStorageId);
    final prefs = await SharedPreferences.getInstance();
    final totalDuration = prefs.getInt(_totalDurationKey) ?? 0;

    if (active != null) {
      final remaining = active.remainingSecondsAt(DateTime.now());
      if (remaining <= 0) {
        await _rateTimerService.clearActiveTimer(
            instanceId: _instanceStorageId);
        if (!mounted) return;
        setState(() {
          _timerRunning = false;
          _timerFinished = true;
          _remainingSeconds = 0;
          _totalDurationSeconds = totalDuration;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _timerEndsAt = active.endsAt;
        _remainingSeconds = remaining;
        _totalDurationSeconds =
            totalDuration > 0 ? totalDuration : active.durationSeconds;
        _timerRunning = true;
        _timerPaused = false;
        _timerFinished = false;
      });
      _startTicker();
      return;
    }

    final paused = prefs.getBool(_pausedFlagKey) ?? false;
    if (paused) {
      final remaining = prefs.getInt(_pausedRemainingKey) ?? 0;
      if (!mounted) return;
      setState(() {
        _timerRunning = false;
        _timerPaused = true;
        _remainingSeconds = remaining;
        _totalDurationSeconds = totalDuration;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restoreTimerState();
    }
  }

  String _remainingTimerText() {
    final hours = _remainingSeconds ~/ 3600;
    final minutes = (_remainingSeconds % 3600) ~/ 60;
    final seconds = _remainingSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String get _timerEtaText {
    if (!_timerRunning && !_timerPaused) return '--';
    final eta = DateTime.now().add(Duration(seconds: _remainingSeconds));
    return DateFormat('h:mm a').format(eta);
  }

  double get _timerProgress {
    if (_totalDurationSeconds <= 0) return 0;
    final elapsed = _totalDurationSeconds - _remainingSeconds;
    return (elapsed / _totalDurationSeconds).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    tubingOd.dispose();
    bitDepth.dispose();
    flowbackReturnRate.dispose();
    lagFactor.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Theme.of(context).cardColor,
      labelStyle:
          TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _gold, width: 1.4),
      ),
    );
  }

  Widget _dropdownField<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      dropdownColor: Theme.of(context).cardColor,
      iconEnabledColor: _gold,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      decoration: _fieldDecoration(label),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final volume = annularVolume;
    final mins = btsMinutes;
    final showResults = _calculated && volume != null && mins != null;
    final casingIdText = _casingId?.toStringAsFixed(3) ?? '--';

    return Scaffold(
      appBar: const AppHeader(title: 'BTS Calculator', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Bit to Surface (BTS): time for returns to travel from the bit '
            'to surface using the actual Flowback Return Rate.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            child: Column(
              children: [
                _dropdownField<_TubingOdOption>(
                  label: 'Tubing OD',
                  value: selectedTubing,
                  items: _tubingOdOptions
                      .map(
                        (pipe) => DropdownMenuItem<_TubingOdOption>(
                          value: pipe,
                          child: Text(pipe.label),
                        ),
                      )
                      .toList(),
                  onChanged: (pipe) {
                    if (pipe != null) _selectTubing(pipe);
                  },
                ),
                const SizedBox(height: 14),
                WwNumberField(
                  label: 'Tubing OD (in)',
                  controller: tubingOd,
                  allowDecimal: true,
                ),
                WwNumberField(
                  label: 'Bit Depth (ft)',
                  controller: bitDepth,
                  allowDecimal: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            child: Column(
              children: [
                _dropdownField<CasingSizeOption>(
                  label: 'Casing OD',
                  value: selectedCasing,
                  items: CasingDatabase.sizes
                      .map(
                        (casing) => DropdownMenuItem<CasingSizeOption>(
                          value: casing,
                          child: Text(casing.label),
                        ),
                      )
                      .toList(),
                  onChanged: (casing) {
                    if (casing != null) _selectCasing(casing);
                  },
                ),
                const SizedBox(height: 14),
                _dropdownField<CasingWeightOption>(
                  label: 'Casing Weight',
                  value: selectedCasingWeight ?? selectedCasing.weights.first,
                  items: selectedCasing.weights
                      .map(
                        (weight) => DropdownMenuItem<CasingWeightOption>(
                          value: weight,
                          child: Text(weight.label),
                        ),
                      )
                      .toList(),
                  onChanged: (weight) {
                    if (weight != null) _selectCasingWeight(weight);
                  },
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Casing ID: $casingIdText in',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          WwNumberField(
            label: 'Flowback Return Rate (BBL/min)',
            controller: flowbackReturnRate,
            allowDecimal: true,
            textInputAction: TextInputAction.done,
          ),
          WwNumberField(
            label: 'Lag Factor',
            controller: lagFactor,
            allowDecimal: true,
            helperText:
                'Default 1.00. Increase if you want a field safety factor.',
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton(
              onPressed: mins == null ? null : _calculate,
              style: FilledButton.styleFrom(
                textStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: const Text('CALCULATE'),
            ),
          ),
          const SizedBox(height: 16),
          if (!showResults)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Enter tubing OD, bit depth, casing selection, and '
                  'flowback return rate, then press Calculate.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            )
          else ...[
            _PrimaryResultCard(label: 'BTS TIME', value: hourMinuteText),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ResultCard(
                    label: 'Annular Volume',
                    value: volume.toStringAsFixed(2),
                    unit: 'BBL',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ResultCard(
                    label: 'Flowback Return Rate',
                    value: _flowbackReturnRate.toStringAsFixed(2),
                    unit: 'BBL/min',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _timerSection(),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: copyResults,
              icon: const Icon(Icons.copy),
              label: const Text('Copy Results'),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: clearAll,
            icon: const Icon(Icons.clear),
            label: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _timerSection() {
    if (!_timerRunning && !_timerPaused && !_timerFinished) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton.icon(
          onPressed: _startTimer,
          icon: const Icon(Icons.play_arrow),
          label: const Text('START BTS TIMER'),
        ),
      );
    }

    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Remaining',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              _timerFinished ? 'ARRIVED' : _remainingTimerText(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _timerFinished ? Colors.greenAccent : _gold,
                fontSize: 44,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _timerFinished ? 1.0 : _timerProgress,
                minHeight: 10,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(_gold),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('ETA', style: TextStyle(color: Colors.white70)),
                Text(
                  _timerFinished ? 'Now' : _timerEtaText,
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_timerRunning)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pauseTimer,
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                    ),
                  ),
                if (_timerPaused)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _resumeTimer,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Resume'),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _resetTimer,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryResultCard extends StatelessWidget {
  final String label;
  final String value;

  const _PrimaryResultCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: gold.withValues(alpha: 0.6), width: 1.4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: gold,
                fontSize: 42,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _ResultCard({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              unit.isEmpty ? value : '$value $unit',
              style: const TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
