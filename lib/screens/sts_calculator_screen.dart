import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/casing_database.dart';
import '../services/app_settings_service.dart';
import '../services/rate_timer_service.dart';
import '../services/rate_timer_notification_service.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

/// STS (Surface to Surface) Calculator.
///
/// Estimates total circulation time from surface, down the work string
/// (coil tubing or stick pipe), and back to surface via the annulus.
class StsCalculatorScreen extends StatefulWidget {
  const StsCalculatorScreen({super.key});

  @override
  State<StsCalculatorScreen> createState() => _StsCalculatorScreenState();
}

enum _PipeType { coilTubing, stickPipe }

class _PipeOdOption {
  final String label;
  final double od;
  final double capacity;
  final bool custom;

  const _PipeOdOption(this.label, this.od, this.capacity,
      {this.custom = false});
}

class _StsCalculatorScreenState extends State<StsCalculatorScreen>
    with WidgetsBindingObserver {
  static const _calculatorId = 'sts_calculator';
  static const _instanceStorageId = 'sts_calculator';
  static const _pausedRemainingKey = 'wellwerks_sts_timer_paused_remaining_v1';
  static const _pausedFlagKey = 'wellwerks_sts_timer_paused_flag_v1';
  static const _totalDurationKey = 'wellwerks_sts_timer_total_duration_v1';

  final _rateTimerService = RateTimerService();
  final _settingsService = AppSettingsService();
  final _notificationService = RateTimerNotificationService.instance;

  Color get _gold => Theme.of(context).colorScheme.primary;

  static const _pipeOdOptions = <_PipeOdOption>[
    _PipeOdOption('2-3/8" EUE', 2.375, 0.00387),
    _PipeOdOption('2-7/8" EUE', 2.875, 0.00579),
    _PipeOdOption('3-1/2"', 3.5, 0.00870),
    _PipeOdOption('4-1/2"', 4.5, 0.01422),
    _PipeOdOption('5"', 5.0, 0.01730),
    _PipeOdOption('5-1/2"', 5.5, 0.02000),
    _PipeOdOption('7"', 7.0, 0.03640),
    _PipeOdOption('9-5/8"', 9.625, 0.07400),
    _PipeOdOption('Custom OD', 0, 0, custom: true),
  ];

  _PipeType pipeType = _PipeType.coilTubing;
  _PipeOdOption selectedPipe = _pipeOdOptions[1];
  CasingSizeOption selectedCasing = CasingDatabase.sizes[2];
  CasingWeightOption? selectedCasingWeight;

  final pipeOd = TextEditingController(
    text: _pipeOdOptions[1].od.toStringAsFixed(3),
  );
  final coilBarrelCapacity = TextEditingController();
  final bitDepth = TextEditingController();
  final pumpRate = TextEditingController();
  final flowbackReturnRate = TextEditingController();

  bool _calculated = false;

  // Live STS timer state.
  Timer? _countdownTimer;
  bool _timerRunning = false;
  bool _timerPaused = false;
  bool _timerFinished = false;
  DateTime? _timerEndsAt;
  int _remainingSeconds = 0;
  int _totalDurationSeconds = 0;
  bool _notifyAtArrival = true;
  bool _earlyNotification = true;
  int _earlyWarningMinutes = 5;

  double get _pipeOd => double.tryParse(pipeOd.text.trim()) ?? 0;
  double get _coilBarrelCapacity =>
      double.tryParse(coilBarrelCapacity.text.trim()) ?? 0;
  double get _bitDepth => double.tryParse(bitDepth.text.trim()) ?? 0;
  double get _pumpRate => double.tryParse(pumpRate.text.trim()) ?? 0;
  double get _flowbackReturnRate =>
      double.tryParse(flowbackReturnRate.text.trim()) ?? 0;

  double? get _casingId => selectedCasingWeight?.id;

  bool get _isCoilTubing => pipeType == _PipeType.coilTubing;

  double? get annularCapacity {
    final id = _casingId;
    if (id == null || _pipeOd <= 0 || id <= _pipeOd || _bitDepth <= 0) {
      return null;
    }
    return (id * id - _pipeOd * _pipeOd) / 1029.4 * _bitDepth;
  }

  double? get pipeCapacity {
    if (_isCoilTubing) {
      return _coilBarrelCapacity > 0 ? _coilBarrelCapacity : null;
    }
    if (selectedPipe.custom) {
      // Custom stick pipe capacity is entered as BBL/ft via the OD field's
      // paired capacity input; fall back to none if unset.
      return null;
    }
    if (_bitDepth <= 0) return null;
    return selectedPipe.capacity * _bitDepth;
  }

  double? get pumpDownMinutes {
    final capacity = pipeCapacity;
    if (capacity == null || _pumpRate <= 0) return null;
    return capacity / _pumpRate;
  }

  double? get returnMinutes {
    final capacity = annularCapacity;
    if (capacity == null || _flowbackReturnRate <= 0) return null;
    return capacity / _flowbackReturnRate;
  }

  double? get stsMinutes {
    final pumpDown = pumpDownMinutes;
    final returnTime = returnMinutes;
    if (pumpDown == null || returnTime == null) return null;
    return pumpDown + returnTime;
  }

  String get arrivalTime {
    final mins = stsMinutes;
    if (mins == null) return '--';
    final eta = DateTime.now().add(Duration(seconds: (mins * 60).round()));
    return DateFormat('h:mm a').format(eta);
  }

  String _hourMinuteText(double? mins) {
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
      pipeOd,
      coilBarrelCapacity,
      bitDepth,
      pumpRate,
      flowbackReturnRate,
    ]) {
      controller.addListener(_handleInputChanged);
    }
    _restoreTimerState();
    _loadNotificationDefaults();
  }

  Future<void> _loadNotificationDefaults() async {
    final settings = await _settingsService.load();
    if (!mounted) return;
    setState(() {
      _notifyAtArrival = settings.calculatorArrivalNotificationsEnabled;
      _earlyNotification = settings.calculatorEarlyNotificationsEnabled;
      _earlyWarningMinutes = settings.calculatorEarlyWarningMinutes;
    });
  }

  void _handleInputChanged() {
    if (_timerRunning || _timerPaused) return;
    if (_calculated) {
      setState(() => _calculated = false);
    } else {
      setState(() {});
    }
  }

  void _selectPipeType(_PipeType type) {
    setState(() {
      pipeType = type;
      _calculated = false;
    });
  }

  void _selectPipe(_PipeOdOption pipe) {
    setState(() {
      selectedPipe = pipe;
      if (!pipe.custom) {
        pipeOd.text = pipe.od.toStringAsFixed(3);
      } else {
        pipeOd.clear();
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
    if (stsMinutes == null) return;
    setState(() => _calculated = true);
    _scheduleNotifications();
  }

  Future<void> _scheduleNotifications() async {
    final mins = stsMinutes;
    if (mins == null) return;
    final settings = await _settingsService.load();
    try {
      await _notificationService.scheduleCalculatorArrivalNotifications(
        calculator: 'STS',
        arrivalAt: DateTime.now().add(Duration(seconds: (mins * 60).round())),
        arrivalEnabled: _notifyAtArrival && settings.appNotifications,
        earlyEnabled: _earlyNotification && settings.appNotifications,
        earlyWarningMinutes: _earlyWarningMinutes,
      );
    } catch (_) {
      // Notification plugins are unavailable in some widget-test environments.
    }
  }

  void clearAll() {
    setState(() {
      pipeType = _PipeType.coilTubing;
      selectedPipe = _pipeOdOptions[1];
      selectedCasing = CasingDatabase.sizes[2];
      selectedCasingWeight = selectedCasing.weights.isNotEmpty
          ? selectedCasing.weights.first
          : null;
      pipeOd.text = _pipeOdOptions[1].od.toStringAsFixed(3);
      coilBarrelCapacity.clear();
      bitDepth.clear();
      pumpRate.clear();
      flowbackReturnRate.clear();
      _calculated = false;
    });
  }

  Future<void> copyResults() async {
    final sts = stsMinutes;
    final pumpDown = pumpDownMinutes;
    final returnTime = returnMinutes;
    final pipeCap = pipeCapacity;
    final annularCap = annularCapacity;
    if (sts == null ||
        pumpDown == null ||
        returnTime == null ||
        pipeCap == null ||
        annularCap == null) {
      return;
    }

    final text = '''STS Calculator (Surface to Surface)
Pipe Type: ${_isCoilTubing ? 'Coil Tubing' : 'Stick Pipe (Rig)'}
Pipe OD: ${selectedPipe.custom ? '${_pipeOd.toStringAsFixed(3)}"' : selectedPipe.label}
Casing OD: ${selectedCasing.label}
Casing Weight: ${selectedCasingWeight?.label ?? '--'}
Casing ID: ${_casingId?.toStringAsFixed(3) ?? '--'}"
Bit Depth: ${_bitDepth.toStringAsFixed(0)} ft
Pump Rate: ${_pumpRate.toStringAsFixed(2)} BBL/min
Flowback Return Rate: ${_flowbackReturnRate.toStringAsFixed(2)} BBL/min
Pipe Capacity: ${pipeCap.toStringAsFixed(2)} BBL
Annular Capacity: ${annularCap.toStringAsFixed(2)} BBL
Pump Down Time: ${pumpDown.toStringAsFixed(2)} min
Return Time: ${returnTime.toStringAsFixed(2)} min
STS Time: ${sts.toStringAsFixed(2)} min (${_hourMinuteText(sts)})
Estimated Arrival: $arrivalTime''';

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('STS results copied')));
  }

  // ---------------------------------------------------------------------
  // Live STS Timer
  // ---------------------------------------------------------------------

  Future<void> _startTimer() async {
    final mins = stsMinutes;
    if (mins == null) return;
    final durationSeconds = (mins * 60).round();
    if (durationSeconds <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pausedRemainingKey);
    await prefs.remove(_pausedFlagKey);
    await prefs.setInt(_totalDurationKey, durationSeconds);

    final state = await _rateTimerService.createState(
      calculatorId: _calculatorId,
      calculatorTitle: 'STS Calculator',
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
      calculatorTitle: 'STS Calculator',
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

    final mins = stsMinutes;
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
    pipeOd.dispose();
    coilBarrelCapacity.dispose();
    bitDepth.dispose();
    pumpRate.dispose();
    flowbackReturnRate.dispose();
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
    final sts = stsMinutes;
    final pumpDown = pumpDownMinutes;
    final returnTime = returnMinutes;
    final pipeCap = pipeCapacity;
    final annularCap = annularCapacity;
    final showResults = _calculated &&
        sts != null &&
        pumpDown != null &&
        returnTime != null &&
        pipeCap != null &&
        annularCap != null;
    final casingIdText = _casingId?.toStringAsFixed(3) ?? '--';

    return Scaffold(
      appBar: const AppHeader(title: 'STS Calculator', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Surface to Surface (STS): total circulation time down the '
            'work string and back to surface via the annulus.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pipe Type',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<_PipeType>(
                  segments: const [
                    ButtonSegment(
                      value: _PipeType.coilTubing,
                      label: Text('Coil Tubing'),
                    ),
                    ButtonSegment(
                      value: _PipeType.stickPipe,
                      label: Text('Stick Pipe (Rig)'),
                    ),
                  ],
                  selected: {pipeType},
                  onSelectionChanged: (selection) {
                    _selectPipeType(selection.first);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            child: Column(
              children: [
                _dropdownField<_PipeOdOption>(
                  label: _isCoilTubing ? 'Tubing OD' : 'Pipe OD',
                  value: selectedPipe,
                  items: _pipeOdOptions
                      .map(
                        (pipe) => DropdownMenuItem<_PipeOdOption>(
                          value: pipe,
                          child: Text(pipe.label),
                        ),
                      )
                      .toList(),
                  onChanged: (pipe) {
                    if (pipe != null) _selectPipe(pipe);
                  },
                ),
                const SizedBox(height: 14),
                WwNumberField(
                  label: _isCoilTubing ? 'Tubing OD (in)' : 'Pipe OD (in)',
                  controller: pipeOd,
                  allowDecimal: true,
                ),
                if (_isCoilTubing)
                  WwNumberField(
                    label: 'Coil Barrel Capacity (BBL)',
                    controller: coilBarrelCapacity,
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
            label: 'Pump Rate (BBL/min)',
            controller: pumpRate,
            allowDecimal: true,
          ),
          WwNumberField(
            label: 'Flowback Return Rate (BBL/min)',
            controller: flowbackReturnRate,
            allowDecimal: true,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton(
              onPressed: sts == null ? null : _calculate,
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
                  'Enter pipe type, bit depth, casing selection, pump rate, '
                  'and flowback return rate, then press Calculate.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            )
          else ...[
            _PrimaryResultCard(label: 'STS TIME', value: _hourMinuteText(sts)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ResultCard(
                    label: 'Pump Down Time',
                    value: pumpDown.toStringAsFixed(2),
                    unit: 'min',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ResultCard(
                    label: 'Return Time',
                    value: returnTime.toStringAsFixed(2),
                    unit: 'min',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ResultCard(
                    label: 'Pipe Capacity',
                    value: pipeCap.toStringAsFixed(2),
                    unit: 'BBL',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ResultCard(
                    label: 'Annular Capacity',
                    value: annularCap.toStringAsFixed(2),
                    unit: 'BBL',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _timerSection(),
            const SizedBox(height: 16),
            _notificationSection(),
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
          label: const Text('START STS TIMER'),
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

  Widget _notificationSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Estimated Arrival',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(arrivalTime,
                style: TextStyle(
                    color: _gold, fontSize: 20, fontWeight: FontWeight.bold)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notify at Arrival'),
              value: _notifyAtArrival,
              onChanged: (value) {
                setState(() => _notifyAtArrival = value ?? false);
                if (_calculated) _scheduleNotifications();
              },
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Early Notification'),
              value: _earlyNotification,
              onChanged: (value) {
                setState(() => _earlyNotification = value ?? false);
                if (_calculated) _scheduleNotifications();
              },
            ),
            if (_earlyNotification)
              Row(
                children: [
                  const Expanded(child: Text('Early Warning')),
                  IconButton(
                    onPressed: _earlyWarningMinutes <= 1
                        ? null
                        : () {
                            setState(() => _earlyWarningMinutes =
                                _previousWarning(_earlyWarningMinutes));
                            if (_calculated) _scheduleNotifications();
                          },
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$_earlyWarningMinutes minutes'),
                  IconButton(
                    onPressed: _earlyWarningMinutes >= 30
                        ? null
                        : () {
                            setState(() => _earlyWarningMinutes =
                                _nextWarning(_earlyWarningMinutes));
                            if (_calculated) _scheduleNotifications();
                          },
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  int _previousWarning(int value) {
    const values = [1, 2, 3, 5, 10, 15, 20, 30];
    return values.lastWhere((item) => item < value, orElse: () => 1);
  }

  int _nextWarning(int value) {
    const values = [1, 2, 3, 5, 10, 15, 20, 30];
    return values.firstWhere((item) => item > value, orElse: () => 30);
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
