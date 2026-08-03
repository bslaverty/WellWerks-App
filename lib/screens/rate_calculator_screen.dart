import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import '../services/app_settings_service.dart';
import '../services/job_storage_service.dart';
import '../services/operations_log_service.dart';
import '../services/rate_calculator_session_service.dart';
import '../services/rate_timer_notification_service.dart';
import '../services/rate_timer_service.dart';
import '../services/wellwerks_qr_transfer_service.dart';
import '../data/tank_charts.dart';
import '../utils/gauge_keypad_input.dart';
import '../utils/gauge_parser.dart';
import '../widgets/app_header.dart';
import '../widgets/shared_gauge_keypad.dart';
import '../widgets/ww_number_field.dart';
import 'wellwerks_qr_scanner_screen.dart';

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
  final String? storageId;
  final bool allowOperationsLogAutoSave;
  final bool rateLogEnabledByDefault;

  const RateCalculatorConfig.chart(
    this.title,
    this.chartId, {
    this.storageId,
    this.allowOperationsLogAutoSave = true,
    this.rateLogEnabledByDefault = false,
  }) : defaultFactor = null;
  const RateCalculatorConfig.linear(
    this.title, {
    required this.defaultFactor,
    this.storageId,
    this.allowOperationsLogAutoSave = true,
    this.rateLogEnabledByDefault = false,
  }) : chartId = null;

  bool get usesChart => chartId != null;

  static RateCalculatorConfig? fromStorageId(String storageId) {
    switch (storageId) {
      case 'fs3':
        return const RateCalculatorConfig.chart('FS3 Tank', 'fs3');
      case 'sandx':
        return const RateCalculatorConfig.chart('SandX G3', 'sandx');
      case 'flowback500':
        return const RateCalculatorConfig.chart('V-Bottom', 'flowback500');
      case 'flowback_round_bottom':
        return const RateCalculatorConfig.chart(
            'Round Bottom', 'flowback_round_bottom');
      case 'mr_810039':
        return const RateCalculatorConfig.chart(
          'Flowback Tank (MR 810039)',
          'mr_810039',
          storageId: 'mr_810039',
        );
      case 'production_tank':
        return const RateCalculatorConfig.linear('Production Tank',
            defaultFactor: 1.67);
      case 'production_flowback500':
        return const RateCalculatorConfig.chart(
          'Production V-Bottom',
          'flowback500',
          storageId: 'production_flowback500',
          allowOperationsLogAutoSave: false,
          rateLogEnabledByDefault: true,
        );
      case 'production_flowback_round_bottom':
        return const RateCalculatorConfig.chart(
          'Production Round Bottom',
          'flowback_round_bottom',
          storageId: 'production_flowback_round_bottom',
          allowOperationsLogAutoSave: false,
          rateLogEnabledByDefault: true,
        );
      case 'production_tank_linear':
        return const RateCalculatorConfig.linear(
          'Production Tank',
          defaultFactor: 1.67,
          storageId: 'production_tank_linear',
          allowOperationsLogAutoSave: false,
          rateLogEnabledByDefault: true,
        );
      default:
        return null;
    }
  }
}

class HomeRateTabSpec {
  const HomeRateTabSpec({
    required this.config,
    required this.instanceId,
  });

  final RateCalculatorConfig config;
  final String instanceId;
}

const List<RateCalculatorConfig> kDefaultRateCalculatorConfigs = [
  RateCalculatorConfig.chart('FS3 Tank', 'fs3'),
  RateCalculatorConfig.chart('SandX G3', 'sandx'),
  RateCalculatorConfig.chart('V-Bottom', 'flowback500'),
  RateCalculatorConfig.chart('Round Bottom', 'flowback_round_bottom'),
  RateCalculatorConfig.chart(
    'Flowback Tank (MR 810039)',
    'mr_810039',
    storageId: 'mr_810039',
  ),
  RateCalculatorConfig.linear('Production Tank', defaultFactor: 1.67),
];

const List<RateCalculatorConfig> kProductionRateCalculatorConfigs = [
  RateCalculatorConfig.chart(
    'V-Bottom',
    'flowback500',
    storageId: 'production_flowback500',
    allowOperationsLogAutoSave: false,
    rateLogEnabledByDefault: true,
  ),
  RateCalculatorConfig.chart(
    'Round Bottom',
    'flowback_round_bottom',
    storageId: 'production_flowback_round_bottom',
    allowOperationsLogAutoSave: false,
    rateLogEnabledByDefault: true,
  ),
  RateCalculatorConfig.chart(
    'Flowback Tank (MR 810039)',
    'mr_810039',
    storageId: 'mr_810039',
    rateLogEnabledByDefault: true,
  ),
  RateCalculatorConfig.linear(
    'Production Tank',
    defaultFactor: 1.67,
    storageId: 'production_tank_linear',
    allowOperationsLogAutoSave: false,
    rateLogEnabledByDefault: true,
  ),
];

class RateCalculatorScreen extends StatefulWidget {
  final RateCalculatorConfig config;
  final String? instanceId;
  final bool homeMultiMode;
  final List<RateCalculatorConfig>? availableConfigs;
  final List<HomeRateTabSpec>? homeTabs;
  const RateCalculatorScreen(
      {super.key,
      required this.config,
      this.instanceId,
      this.homeMultiMode = false,
      this.availableConfigs,
      this.homeTabs});

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
            config:
                const RateCalculatorConfig.chart('V-Bottom', 'flowback500'));
      case 'Flowback Round Bottom':
        return RateCalculatorScreen(
            key: key,
            config: const RateCalculatorConfig.chart(
                'Round Bottom', 'flowback_round_bottom'));
      case 'Flowback Tank (MR 810039)':
      case 'MR 810039':
        return RateCalculatorScreen(
            key: key,
            config: const RateCalculatorConfig.chart(
              'Flowback Tank (MR 810039)',
              'mr_810039',
              storageId: 'mr_810039',
            ));
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
  static const _rateLogQrFileType = 'wellwerks_rate_log';
  static const _rateLogQrSchemaVersion = '1.0.0';
  static const _homeTabsPrefKey = 'wellwerks_home_rate_tabs_v1';
  final _settingsService = AppSettingsService();
  final _jobStorage = JobStorageService();
  final _operationsLogService = OperationsLogService();
  final _sessionService = RateCalculatorSessionService.instance;
  final _rateTimerService = RateTimerService();
  final _rateTimerNotifications = RateTimerNotificationService.instance;
  final _qrTransferService = const WellWerksQrTransferService();
  final _imagePicker = ImagePicker();
  late final String _instanceStorageId;

  final startGauge = TextEditingController();
  final endGauge = TextEditingController();
  final fluidHauled = TextEditingController();
  final minutes = TextEditingController();
  late final TextEditingController factor;
  _KeypadTarget? _activeKeypadTarget;
  Timer? _countdownTimer;
  Timer? _liveClockTicker;
  int _remainingSeconds = 0;
  int _liveClockElapsedSeconds = 0;
  bool _thirtySecondAlertShown = false;
  bool _timerFinished = false;
  bool _useLiveClock = false;
  DateTime? _liveClockStartedAt;
  _RateDisplayUnit _rateDisplayUnit = _RateDisplayUnit.bblPerMin;
  bool _rateLogEnabled = false;
  bool _rateLogExpanded = false;
  bool _fluidHauledEnabled = false;
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
  bool _initializing = true;
  List<HomeRateTabSpec> _homeTabs = <HomeRateTabSpec>[];
  Map<String, RateTimerState> _homeTabTimers = <String, RateTimerState>{};
  Timer? _activeTankTicker;
  int _activeTankRefreshTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _instanceStorageId = _buildInstanceStorageId();
    factor = TextEditingController(
        text: (widget.config.defaultFactor ?? 1.67).toString());
    startGauge.addListener(_handleSessionFieldChanged);
    endGauge.addListener(_handleSessionFieldChanged);
    fluidHauled.addListener(_handleSessionFieldChanged);
    factor.addListener(_handleSessionFieldChanged);
    minutes.addListener(_handleMinutesChanged);
    _initializeSession();
  }

  String _buildInstanceStorageId() {
    final provided = widget.instanceId?.trim() ?? '';
    if (provided.isNotEmpty) return provided;
    if (!widget.homeMultiMode) return _calculatorStorageId;
    return '${_calculatorStorageId}_${DateTime.now().microsecondsSinceEpoch}';
  }

  String get _storageScopeKey =>
      widget.homeMultiMode ? _instanceStorageId : _calculatorStorageId;

  Future<void> _initializeSession() async {
    await _sessionService.ensureInitialized();
    await _loadHomeTabsState();
    await _refreshHomeTabTimers();
    _startActiveTankTicker();

    final redirected = await _redirectToActiveCalculatorIfNeeded();
    if (redirected) {
      if (mounted) {
        setState(() => _initializing = false);
      }
      return;
    }

    final restored = await _restoreCalculatorSession();
    if (!restored) {
      await _loadSavedTimerMinutes();
      await _loadSavedDisplayUnit();
      await _loadRateLogState();
    } else {
      // Build 205 used separate persistence stores for rate log/display unit.
      // Backfill from legacy keys only when missing from restored session.
      if (_rateLogEntries.isEmpty) {
        await _loadRateLogState();
      }
      if (_rateDisplayUnit == _RateDisplayUnit.bblPerMin &&
          bblPerMin == null &&
          bblPerHr == null) {
        await _loadSavedDisplayUnit();
      }
      if (minutes.text.trim().isEmpty) {
        await _loadSavedTimerMinutes();
      }
    }

    await _applyPendingNotificationAction();
    await _restoreTimerState();
    await _persistCalculatorSession();

    if (!mounted) return;
    setState(() => _initializing = false);
  }

  Future<bool> _redirectToActiveCalculatorIfNeeded() async {
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _persistTimerState();
      _persistCalculatorSession();
      _saveRateLogState();
    }
    if (state == AppLifecycleState.resumed) {
      _applyPendingNotificationAction();
      _restoreTimerState();
      _loadRateLogState();
      _refreshHomeTabTimers();
      _startActiveTankTicker();
      if (_liveClockRunning) {
        _startLiveClockTicker();
      }
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _activeTankTicker?.cancel();
      _activeTankTicker = null;
    }
  }

  Future<void> _refreshHomeTabTimers() async {
    if (!widget.homeMultiMode) return;
    final tabs = _resolvedHomeTabs();
    final timers = <String, RateTimerState>{};
    for (final tab in tabs) {
      final timer = await _rateTimerService.loadActiveTimerForInstance(
        tab.instanceId,
      );
      if (timer != null) {
        timers[tab.instanceId] = timer;
      }
    }
    if (!mounted) return;
    setState(() {
      _homeTabTimers = timers;
    });
  }

  void _startActiveTankTicker() {
    _activeTankTicker?.cancel();
    if (!widget.homeMultiMode) return;
    _activeTankTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _activeTankRefreshTick++;
      if (_activeTankRefreshTick % 5 == 0) {
        _refreshHomeTabTimers();
      }
      setState(() {});
    });
  }

  String get _calculatorStorageId {
    return (widget.config.storageId ??
            widget.config.chartId ??
            widget.config.title)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  String _calculatorIdForConfig(RateCalculatorConfig config) {
    return (config.storageId ?? config.chartId ?? config.title)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  Future<void> _loadHomeTabsState() async {
    if (!widget.homeMultiMode) return;

    final tabs = <HomeRateTabSpec>[];

    void addUnique(HomeRateTabSpec tab) {
      final exists = tabs.any((item) => item.instanceId == tab.instanceId);
      if (!exists) {
        tabs.add(tab);
      }
    }

    if (widget.homeTabs != null && widget.homeTabs!.isNotEmpty) {
      for (final tab in widget.homeTabs!) {
        addUnique(tab);
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_homeTabsPrefKey) ?? '';
      if (raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is! Map) continue;
              final map = Map<String, dynamic>.from(item);
              final calculatorId =
                  (map['calculatorId'] as String? ?? '').trim();
              final instanceId = (map['instanceId'] as String? ?? '').trim();
              if (calculatorId.isEmpty || instanceId.isEmpty) continue;

              RateCalculatorConfig? config =
                  RateCalculatorConfig.fromStorageId(calculatorId);
              if (config == null) {
                final available =
                    widget.availableConfigs ?? const <RateCalculatorConfig>[];
                for (final candidate in available) {
                  if (_calculatorIdForConfig(candidate) == calculatorId) {
                    config = candidate;
                    break;
                  }
                }
              }
              if (config == null) continue;
              addUnique(
                HomeRateTabSpec(config: config, instanceId: instanceId),
              );
            }
          }
        } catch (_) {
          // Ignore malformed saved tabs.
        }
      }
    }

    if (!tabs.any((tab) => tab.instanceId == _instanceStorageId)) {
      tabs.insert(
        0,
        HomeRateTabSpec(
          config: widget.config,
          instanceId: _instanceStorageId,
        ),
      );
    }

    _homeTabs = tabs;
    await _persistHomeTabsState();
  }

  Future<void> _persistHomeTabsState() async {
    if (!widget.homeMultiMode) return;
    final prefs = await SharedPreferences.getInstance();
    final payload = _homeTabs
        .map(
          (tab) => <String, String>{
            'calculatorId': _calculatorIdForConfig(tab.config),
            'instanceId': tab.instanceId,
          },
        )
        .toList(growable: false);
    await prefs.setString(_homeTabsPrefKey, jsonEncode(payload));
  }

  List<HomeRateTabSpec> _resolvedHomeTabs() {
    if (!widget.homeMultiMode) return const <HomeRateTabSpec>[];

    final tabs = List<HomeRateTabSpec>.from(_homeTabs);

    if (tabs.isEmpty) {
      tabs.add(
        HomeRateTabSpec(
          config: widget.config,
          instanceId: _instanceStorageId,
        ),
      );
      return tabs;
    }

    final hasCurrent = tabs.any((tab) => tab.instanceId == _instanceStorageId);
    if (!hasCurrent) {
      tabs.insert(
        0,
        HomeRateTabSpec(
          config: widget.config,
          instanceId: _instanceStorageId,
        ),
      );
      _homeTabs = tabs;
      _persistHomeTabsState();
    }
    return tabs;
  }

  int _currentHomeTabIndex(List<HomeRateTabSpec> tabs) {
    final byInstance = tabs.indexWhere(
      (tab) => tab.instanceId == _instanceStorageId,
    );
    if (byInstance >= 0) return byInstance;

    final byConfig = tabs.indexWhere(
      (tab) => _calculatorIdForConfig(tab.config) == _calculatorStorageId,
    );
    return byConfig >= 0 ? byConfig : 0;
  }

  List<RateCalculatorConfig> get _selectorConfigs {
    final configs = <RateCalculatorConfig>[];

    void addUnique(RateCalculatorConfig config) {
      final calculatorId = _calculatorIdForConfig(config);
      final exists = configs.any(
        (existing) => _calculatorIdForConfig(existing) == calculatorId,
      );
      if (!exists) {
        configs.add(config);
      }
    }

    addUnique(widget.config);
    for (final config
        in widget.availableConfigs ?? const <RateCalculatorConfig>[]) {
      addUnique(config);
    }

    if (configs.length == 1 && widget.homeMultiMode) {
      for (final tab in _resolvedHomeTabs()) {
        addUnique(tab.config);
      }
    }

    return configs;
  }

  int _selectedSelectorIndex(List<RateCalculatorConfig> configs) {
    final currentId = _calculatorIdForConfig(widget.config);
    final index = configs.indexWhere(
      (config) => _calculatorIdForConfig(config) == currentId,
    );
    return index >= 0 ? index : 0;
  }

  Future<void> _switchCalculatorConfig(RateCalculatorConfig config) async {
    final calculatorId = _calculatorIdForConfig(config);
    String? instanceId;
    if (widget.homeMultiMode) {
      final activeTimer = await _rateTimerService.loadActiveTimerForCalculator(
        calculatorId,
      );
      instanceId = activeTimer?.instanceId.isNotEmpty == true
          ? activeTimer!.instanceId
          : _sessionService.sessionKeyForCalculator(calculatorId);
    }

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RateCalculatorScreen(
          config: config,
          instanceId: instanceId,
          homeMultiMode: widget.homeMultiMode,
          availableConfigs: widget.availableConfigs,
          homeTabs: widget.homeTabs,
        ),
      ),
    );
  }

  void _openHomeTab(int index) {
    final tabs = _resolvedHomeTabs();
    if (index < 0 || index >= tabs.length) return;
    final selected = tabs[index];
    if (selected.instanceId == _instanceStorageId) return;
    _homeTabs = tabs;
    _persistHomeTabsState();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RateCalculatorScreen(
          config: selected.config,
          instanceId: selected.instanceId,
          homeMultiMode: true,
          availableConfigs: widget.availableConfigs,
          homeTabs: tabs,
        ),
      ),
    );
  }

  Future<void> _deleteHomeTab(int index) async {
    final tabs = _resolvedHomeTabs();
    if (index < 0 || index >= tabs.length) return;
    if (tabs.length == 1) {
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete Tank?'),
          content: const Text(
            'This will remove the last saved tank setup and clear its session.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (shouldDelete != true) return;
    }

    final removed = tabs[index];
    final nextTabs = List<HomeRateTabSpec>.from(tabs)..removeAt(index);
    if (nextTabs.isEmpty) {
      _homeTabs = nextTabs;
      await _persistHomeTabsState();
      await _sessionService.clearSession(removed.instanceId);
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }

    _homeTabs = nextTabs;
    await _persistHomeTabsState();
    await _sessionService.clearSession(removed.instanceId);

    if (!mounted) return;
    final nextIndex = index.clamp(0, nextTabs.length - 1);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RateCalculatorScreen(
          config: nextTabs[nextIndex].config,
          instanceId: nextTabs[nextIndex].instanceId,
          homeMultiMode: true,
          availableConfigs: widget.availableConfigs,
          homeTabs: nextTabs,
        ),
      ),
    );
  }

  Widget _tankSelectionSection() {
    final configs = _selectorConfigs;
    if (configs.length <= 1) return const SizedBox.shrink();

    final currentIndex = _selectedSelectorIndex(configs);
    final currentConfig = configs[currentIndex];
    final tankSubtitle = currentConfig.usesChart
        ? 'Chart-based tank • ${currentConfig.chartId ?? ''}'
        : 'Editable tank factor';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Theme.of(context).cardColor,
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.95),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TANK SELECTION',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<RateCalculatorConfig>(
                      value: currentConfig,
                      decoration: const InputDecoration(labelText: 'Tank'),
                      items: configs
                          .map(
                            (config) => DropdownMenuItem<RateCalculatorConfig>(
                              value: config,
                              child: Text(config.title),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (selected) {
                        if (selected == null) return;
                        final selectedId = _calculatorIdForConfig(selected);
                        final currentId = _calculatorIdForConfig(currentConfig);
                        if (selectedId == currentId) return;
                        _switchCalculatorConfig(selected);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: FilledButton(
                      onPressed: widget.homeMultiMode &&
                              (widget.availableConfigs?.isNotEmpty ?? false)
                          ? _openAddAnotherTankPicker
                          : () =>
                              _switchCalculatorConfig(configs[currentIndex]),
                      child: Text(
                        widget.homeMultiMode &&
                                (widget.availableConfigs?.isNotEmpty ?? false)
                            ? 'Add Tank'
                            : 'Open',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                tankSubtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              if (widget.homeMultiMode) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _selectorChip(
                      currentConfig.usesChart ? 'Chart tank' : 'Custom factor',
                    ),
                    if (widget.availableConfigs?.isNotEmpty ?? false)
                      _selectorChip('${configs.length} tanks available'),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  String _activeTankTimerText(HomeRateTabSpec tab) {
    final timer = _homeTabTimers[tab.instanceId];
    if (timer == null) return 'No timer';
    final remaining = timer.remainingSecondsAt(DateTime.now());
    if (remaining <= 0) return 'Finished';
    final mm = (remaining ~/ 60).toString().padLeft(2, '0');
    final ss = (remaining % 60).toString().padLeft(2, '0');
    return 'Running $mm:$ss';
  }

  Widget _activeTanksSection() {
    if (!widget.homeMultiMode) return const SizedBox.shrink();
    final tabs = _resolvedHomeTabs();
    if (tabs.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Theme.of(context).cardColor,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.95),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ACTIVE CALCULATORS',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final tab = tabs[index];
                    final isCurrent = tab.instanceId == _instanceStorageId;
                    final timerText = _activeTankTimerText(tab);
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _openHomeTab(index),
                      child: Container(
                        width: 180,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: isCurrent
                              ? scheme.primary.withValues(alpha: 0.12)
                              : Theme.of(context).cardColor,
                          border: Border.all(
                            color: isCurrent
                                ? scheme.primary
                                : scheme.outlineVariant.withValues(alpha: 0.95),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              tab.config.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              timerText,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isCurrent ? 'Current' : 'Tap to open',
                              style: TextStyle(
                                color: isCurrent
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _selectorChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.20),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String get _rateLogEnabledPrefKey =>
      'wellwerks_rate_log_enabled_$_storageScopeKey';

  String get _rateLogEntriesPrefKey =>
      'wellwerks_rate_log_entries_$_storageScopeKey';

  String get _displayUnitPrefKey {
    return 'wellwerks_rate_display_unit_$_storageScopeKey';
  }

  Future<void> _loadRateLogState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEnabled = prefs.getBool(_rateLogEnabledPrefKey) ??
        widget.config.rateLogEnabledByDefault;
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

  void _handleSessionFieldChanged() {
    _persistCalculatorSession();
  }

  bool get _hasSessionData {
    final defaultFactor = (widget.config.defaultFactor ?? 1.67).toString();
    final customFactorEntered =
        !widget.config.usesChart && factor.text.trim() != defaultFactor;
    final hasCurrentTimer = _activeTimerState?.instanceId == _instanceStorageId;
    return startGauge.text.trim().isNotEmpty ||
        endGauge.text.trim().isNotEmpty ||
        (widget.homeMultiMode &&
            (_fluidHauledEnabled || fluidHauled.text.trim().isNotEmpty)) ||
        customFactorEntered ||
        bblPerMin != null ||
        bblPerHr != null ||
        bblPerDay != null ||
        _timerRunning ||
        _liveClockRunning ||
        _liveClockElapsedSeconds > 0 ||
        _useLiveClock ||
        hasCurrentTimer ||
        _timerFinished ||
        _rateLogEnabled ||
        _rateLogEntries.isNotEmpty ||
        (error?.trim().isNotEmpty ?? false);
  }

  List<RateCalculatorSessionLogEntry> _sessionLogEntries() {
    return _rateLogEntries
        .map(
          (entry) => RateCalculatorSessionLogEntry(
            timestampMs: entry.timestamp.millisecondsSinceEpoch,
            rateValue: entry.rateValue,
            rateUnit: entry.rateUnit,
            selected: entry.selected,
          ),
        )
        .toList(growable: false);
  }

  List<_RateLogEntry> _rateLogEntriesFromSession(
    List<RateCalculatorSessionLogEntry> entries,
  ) {
    final restored = entries
        .map(
          (entry) => _RateLogEntry(
            timestamp: DateTime.fromMillisecondsSinceEpoch(entry.timestampMs),
            rateValue: entry.rateValue,
            rateUnit: entry.rateUnit,
            selected: entry.selected,
          ),
        )
        .toList(growable: false)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (restored.isNotEmpty) {
      restored[0] = restored[0].copyWith(selected: true);
    }
    return restored;
  }

  RateCalculatorSession _buildSessionSnapshot() {
    final activeState = _activeTimerState?.instanceId == _instanceStorageId
        ? _activeTimerState
        : null;
    final liveClockStartedAtMs = _liveClockStartedAt?.millisecondsSinceEpoch;
    return RateCalculatorSession(
      calculatorId: _calculatorStorageId,
      calculatorTitle: widget.config.title,
      chartId: widget.config.chartId ?? '',
      usesChart: widget.config.usesChart,
      startGauge: startGauge.text,
      endGauge: endGauge.text,
      fluidHauledEnabled: widget.homeMultiMode ? _fluidHauledEnabled : false,
      fluidHauledBarrels: widget.homeMultiMode ? fluidHauled.text : '',
      minutes: minutes.text,
      factor: factor.text,
      rateDisplayUnit:
          _rateDisplayUnit == _RateDisplayUnit.bblPerHr ? 'bbl_hr' : 'bbl_min',
      rateLogEnabled: _rateLogEnabled,
      rateLogExpanded: _rateLogExpanded,
      useLiveClock: _useLiveClock,
      liveClockElapsedSeconds: _liveClockRunning
          ? _currentLiveClockElapsedSeconds()
          : _liveClockElapsedSeconds,
      bblPerMin: bblPerMin,
      bblPerHr: bblPerHr,
      bblPerDay: bblPerDay,
      error: error,
      timerFinished: _timerFinished,
      remainingSeconds: _liveClockRunning
          ? _currentLiveClockElapsedSeconds()
          : _remainingSeconds,
      thirtySecondAlertShown: _thirtySecondAlertShown,
      timerStartedAtMs: activeState?.startedAtMs ?? liveClockStartedAtMs,
      timerEndsAtMs: activeState?.endsAtMs,
      timerDurationSeconds: activeState?.durationSeconds,
      rateLogEntries: _sessionLogEntries(),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _persistCalculatorSession() async {
    if (!_hasSessionData) {
      await _sessionService.clearSession(_instanceStorageId);
      return;
    }
    await _sessionService.saveSession(
      _buildSessionSnapshot(),
      sessionKey: _instanceStorageId,
      setActive: true,
    );
  }

  Future<void> _clearCalculatorSession() async {
    await _sessionService.clearSession(_instanceStorageId);
  }

  Future<bool> _restoreCalculatorSession() async {
    final session = _sessionService.sessionForInstance(_instanceStorageId) ??
        _sessionService.sessionForCalculator(_calculatorStorageId);
    if (session == null) return false;
    if (!mounted) return false;

    setState(() {
      startGauge.text = session.startGauge;
      endGauge.text = session.endGauge;
      if (session.minutes.trim().isNotEmpty) {
        minutes.text = session.minutes;
      }
      fluidHauled.text = widget.homeMultiMode ? session.fluidHauledBarrels : '';
      _fluidHauledEnabled = widget.homeMultiMode && session.fluidHauledEnabled;
      if (session.factor.trim().isNotEmpty) {
        factor.text = session.factor;
      }

      bblPerMin = session.bblPerMin;
      bblPerHr = session.bblPerHr;
      bblPerDay = session.bblPerDay;
      error = (session.error ?? '').trim().isEmpty ? null : session.error;
      _timerFinished = session.timerFinished;
      _remainingSeconds = session.remainingSeconds;
      _thirtySecondAlertShown = session.thirtySecondAlertShown;
      _rateLogEnabled = session.rateLogEnabled;
      _rateLogExpanded = session.rateLogExpanded;
      _useLiveClock = session.useLiveClock;
      _liveClockElapsedSeconds = session.liveClockElapsedSeconds;
      _rateLogEntries
        ..clear()
        ..addAll(_rateLogEntriesFromSession(session.rateLogEntries));

      if (session.rateDisplayUnit == 'bbl_hr') {
        _rateDisplayUnit = _RateDisplayUnit.bblPerHr;
      } else {
        _rateDisplayUnit = _RateDisplayUnit.bblPerMin;
      }

      final hasCountdownPersisted = session.timerStartedAtMs != null &&
          session.timerEndsAtMs != null &&
          session.timerDurationSeconds != null;
      if (!hasCountdownPersisted &&
          widget.homeMultiMode &&
          _useLiveClock &&
          session.timerStartedAtMs != null) {
        final restoredStart =
            DateTime.fromMillisecondsSinceEpoch(session.timerStartedAtMs!);
        _liveClockStartedAt = restoredStart;
        _liveClockElapsedSeconds = DateTime.now()
            .difference(restoredStart)
            .inSeconds
            .clamp(0, 1 << 30);
      } else if (_useLiveClock && _liveClockElapsedSeconds > 0) {
        _liveClockStartedAt = null;
      } else {
        _liveClockStartedAt = null;
        _liveClockElapsedSeconds = 0;
      }
    });

    if (_liveClockRunning) {
      _startLiveClockTicker();
    }
    return true;
  }

  Future<void> _loadSavedDisplayUnit() async {
    await _sessionService.ensureInitialized();
    final session = _sessionService.sessionForInstance(_instanceStorageId) ??
        _sessionService.sessionForCalculator(_calculatorStorageId);
    if (session != null && session.rateDisplayUnit.trim().isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _rateDisplayUnit = session.rateDisplayUnit == 'bbl_hr'
            ? _RateDisplayUnit.bblPerHr
            : _RateDisplayUnit.bblPerMin;
      });
      return;
    }

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
    _persistCalculatorSession();
  }

  void _showShareMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _rateUpdateText() {
    if (_rateLogEntries.isEmpty) {
      return '';
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
    return '${widget.config.title} Rates\n\n$lines';
  }

  Future<void> _copyRateUpdate() async {
    final text = _rateUpdateText();
    if (text.isEmpty) {
      _showShareMessage('Calculate a rate before sharing.');
      return;
    }

    try {
      await Clipboard.setData(ClipboardData(text: text));
      _showShareMessage('Rate update copied to clipboard.');
    } catch (err) {
      debugPrint('Rate copy failed: $err');
      _showShareMessage('Unable to copy rate update.');
    }
  }

  String _rateLogEntryKey(_RateLogEntry entry) {
    final value = entry.rateValue.toStringAsFixed(6);
    return '${entry.timestamp.millisecondsSinceEpoch}|${entry.rateUnit}|$value';
  }

  Map<String, dynamic> _buildRateLogPackage() {
    return <String, dynamic>{
      'fileType': _rateLogQrFileType,
      'schemaVersion': _rateLogQrSchemaVersion,
      'calculatorId': _calculatorStorageId,
      'calculatorTitle': widget.config.title,
      'exportedAt': DateTime.now().toIso8601String(),
      'entries': _rateLogEntries
          .map(
            (entry) => <String, Object>{
              'timestampMs': entry.timestamp.millisecondsSinceEpoch,
              'rateValue': entry.rateValue,
              'rateUnit': entry.rateUnit,
            },
          )
          .toList(growable: false),
    };
  }

  String _encodeRateLogPackage() {
    final payload = _buildRateLogPackage();
    return _qrTransferService.encodeStructuredPayload(jsonEncode(payload));
  }

  List<_RateLogEntry> _decodeRateLogPackage(String rawValue) {
    final rawJson = _qrTransferService.decodeStructuredPayload(rawValue);
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid rate log package.');
    }
    if ((decoded['fileType'] as String? ?? '') != _rateLogQrFileType) {
      throw const FormatException('Unsupported rate log package type.');
    }
    final rawEntries = decoded['entries'];
    if (rawEntries is! List) {
      throw const FormatException('Rate log package has no entries.');
    }
    final entries = <_RateLogEntry>[];
    for (final item in rawEntries) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final timestampMs = map['timestampMs'];
      final rateValue = map['rateValue'];
      final rateUnit = map['rateUnit'];
      if (timestampMs is! int || rateValue is! num || rateUnit is! String) {
        continue;
      }
      entries.add(
        _RateLogEntry(
          timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
          rateValue: rateValue.toDouble(),
          rateUnit: rateUnit,
          selected: true,
        ),
      );
    }
    if (entries.isEmpty) {
      throw const FormatException('Rate log package has no valid entries.');
    }
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    entries[0] = entries[0].copyWith(selected: true);
    return entries;
  }

  Future<void> _showRateLogQrDialog(String qrValue) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Share Rate Log QR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: qrValue,
              version: QrVersions.auto,
              errorCorrectionLevel: QrErrorCorrectLevel.L,
              size: 280,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 10),
            const Text(
              'Scan this QR nearby or tap Share QR to send it as an image.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
          Builder(
            builder: (buttonContext) => FilledButton(
              onPressed: () async {
                try {
                  await _qrTransferService.shareQrPng(
                    qrValue: qrValue,
                    fileName: '${widget.config.title}_Rate_Log',
                    shareContext: buttonContext,
                    subject: '${widget.config.title} Rate Log',
                  );
                } catch (_) {
                  if (!mounted || !buttonContext.mounted) return;
                  ScaffoldMessenger.of(buttonContext).showSnackBar(
                    const SnackBar(
                      content: Text('The QR image could not be shared.'),
                    ),
                  );
                }
              },
              child: const Text('Share QR'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareRateLogQr() async {
    if (_rateLogEntries.isEmpty) {
      _showShareMessage('Rate log is empty. Calculate a rate first.');
      return;
    }
    try {
      final qrValue = _encodeRateLogPackage();
      await _showRateLogQrDialog(qrValue);
    } on FormatException catch (error) {
      _showShareMessage(error.message);
    } catch (_) {
      _showShareMessage('Unable to create a QR package right now.');
    }
  }

  Future<void> _importRateLogQr() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import Rate Log'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('scan'),
            child: const Text('Scan QR'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop('photos'),
            child: const Text('Choose QR from Photos'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (!mounted) return;

    String? raw;
    if (choice == 'scan') {
      raw = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => const WellWerksQrScannerScreen(
            title: 'Scan Rate Log QR',
            prompt: 'Center the rate log QR code in view.',
          ),
        ),
      );
    } else {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        raw = await _qrTransferService.decodeFirstQrFromImagePath(picked.path);
      }
    }

    if (raw == null || raw.trim().isEmpty) {
      _showShareMessage('No QR data found to import.');
      return;
    }
    await _importRateLogFromRaw(raw);
  }

  Future<void> _importRateLogFromRaw(String rawValue) async {
    try {
      final incomingEntries = _decodeRateLogPackage(rawValue);
      final existingKeys = _rateLogEntries.map(_rateLogEntryKey).toSet();
      final duplicateCount = incomingEntries
          .where((entry) => existingKeys.contains(_rateLogEntryKey(entry)))
          .length;

      final mode = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Import Rate Log'),
          content: Text(
            'Incoming entries: ${incomingEntries.length}\n'
            'Detected duplicates: $duplicateCount\n\n'
            'Choose how to import this rate log.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop('skipDuplicates'),
              child: const Text('Skip Duplicates'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop('mergeAll'),
              child: const Text('Merge'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('replace'),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (mode == null) return;

      final merged = <_RateLogEntry>[];
      if (mode == 'replace') {
        merged.addAll(incomingEntries);
      } else if (mode == 'mergeAll') {
        merged.addAll(_rateLogEntries);
        merged.addAll(incomingEntries);
      } else {
        merged.addAll(_rateLogEntries);
        for (final entry in incomingEntries) {
          final key = _rateLogEntryKey(entry);
          final alreadyExists =
              merged.any((item) => _rateLogEntryKey(item) == key);
          if (!alreadyExists) {
            merged.add(entry);
          }
        }
      }

      if (merged.isNotEmpty) {
        merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        merged[0] = merged[0].copyWith(selected: true);
      }

      setState(() {
        _rateLogEntries
          ..clear()
          ..addAll(merged);
        _rateLogExpanded = true;
        _rateLogEnabled = true;
      });
      await _saveRateLogState();
      _showShareMessage('Imported ${incomingEntries.length} rate log entries.');
    } on FormatException catch (error) {
      _showShareMessage(error.message);
    } catch (_) {
      _showShareMessage('Unable to import this rate log package.');
    }
  }

  Future<void> _persistTimerState() async {
    final active = _activeTimerState;
    if (_timerRunning &&
        active != null &&
        active.instanceId == _instanceStorageId) {
      await _rateTimerService.saveActiveTimer(active);
    }
  }

  Future<void> _clearTimerStatePersistence() async {
    final active = await _rateTimerService.loadActiveTimerForInstance(
      _instanceStorageId,
    );
    if (active != null) {
      await _rateTimerNotifications.cancelNotifications(active);
    }
    await _rateTimerService.clearActiveTimer(instanceId: _instanceStorageId);
  }

  Future<void> _restoreTimerState() async {
    final active = await _rateTimerService.loadActiveTimerForInstance(
      _instanceStorageId,
    );
    final now = DateTime.now();
    final remaining = active?.remainingSecondsAt(now) ?? 0;

    _countdownTimer?.cancel();
    _countdownTimer = null;

    if (!mounted) return;

    if (active == null || remaining <= 0) {
      setState(() {
        _activeTimerState = null;
        _timerEndsAt = null;
        if (_remainingSeconds <= 0 && !_timerFinished) {
          _remainingSeconds = _minutesToDurationSeconds();
        }
        _thirtySecondAlertShown =
            _timerRunning ? _thirtySecondAlertShown : false;
      });
      if (active != null) {
        await _rateTimerNotifications.cancelNotifications(active);
      }
      await _rateTimerService.clearActiveTimer(instanceId: _instanceStorageId);
      _persistCalculatorSession();
      return;
    }

    setState(() {
      _activeTimerState = active;
      _timerEndsAt = active.endsAt;
      _remainingSeconds = remaining;
      _timerFinished = false;
      _thirtySecondAlertShown = remaining <= 30;
    });
    _persistCalculatorSession();
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
      _persistCalculatorSession();
      return;
    }

    final shouldAlert = nextSeconds <= 30;
    if (shouldAlert && !_thirtySecondAlertShown) {
      _vibrateOnce();
    }

    setState(() {
      _remainingSeconds = nextSeconds;
      if (shouldAlert) {
        _thirtySecondAlertShown = true;
      }
    });
  }

  bool get _timerRunning =>
      _timerEndsAt != null && _remainingSeconds > 0 && !_timerFinished;

  bool get _liveClockAvailable => widget.homeMultiMode;

  bool get _liveClockRunning => _liveClockStartedAt != null;

  int _currentLiveClockElapsedSeconds() {
    final startedAt = _liveClockStartedAt;
    if (startedAt == null) {
      return _liveClockElapsedSeconds;
    }
    final elapsed = DateTime.now().difference(startedAt).inSeconds;
    return elapsed < 0 ? 0 : elapsed;
  }

  String _liveClockText() {
    final seconds = _currentLiveClockElapsedSeconds();
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String _liveClockStartedText() {
    final startedAt = _liveClockStartedAt;
    if (startedAt == null) return '--';
    return TimeOfDay.fromDateTime(startedAt).format(context);
  }

  void _startLiveClockTicker() {
    _liveClockTicker?.cancel();
    _liveClockTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_liveClockRunning) return;
      setState(() {
        _liveClockElapsedSeconds = _currentLiveClockElapsedSeconds();
      });
    });
  }

  void _stopLiveClockTicker() {
    _liveClockTicker?.cancel();
    _liveClockTicker = null;
  }

  int _minutesToDurationSeconds() {
    final parsedMinutes = int.tryParse(minutes.text.trim());
    if (parsedMinutes == null) return 0;
    if (parsedMinutes < _minMinutes || parsedMinutes > _maxMinutes) return 0;
    return (parsedMinutes * 60).round();
  }

  Future<void> _loadSavedTimerMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_timerMinutesPrefKey) ?? _minMinutes.toString();
    final parsed = int.tryParse(raw);
    final resolved =
        (parsed != null && parsed >= _minMinutes && parsed <= _maxMinutes)
            ? parsed
            : _minMinutes;

    minutes.text = resolved.toString();
    if (!mounted) return;
    if (!_timerRunning) {
      setState(() {
        _remainingSeconds = resolved * 60;
      });
    }
  }

  Future<void> _saveTimerMinutes(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_timerMinutesPrefKey, value);
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
    _persistCalculatorSession();
  }

  Future<void> _clearRateLogWithConfirmation() async {
    if (_rateLogEntries.isEmpty) return;
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Rate Log?'),
        content: const Text('This will remove all saved rate log entries.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (shouldClear != true || !mounted) return;
    setState(() {
      _rateLogEntries.clear();
      _rateLogExpanded = false;
    });
    await _saveRateLogState();
    await _persistCalculatorSession();
  }

  void _toggleRateLogEntrySelection(int index) {
    if (index < 0 || index >= _rateLogEntries.length) return;
    if (index == 0) return;

    setState(() {
      final current = _rateLogEntries[index];
      _rateLogEntries[index] = current.copyWith(selected: !current.selected);
    });
    _saveRateLogState();
    _persistCalculatorSession();
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

  void _startTimedRate() {
    if (_liveClockRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stop live clock before starting countdown timer.'),
        ),
      );
      return;
    }

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

  void _startLiveClock() {
    if (_timerRunning || _isCurrentCalculatorTimerActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stop the countdown timer before starting live clock.'),
        ),
      );
      return;
    }

    setState(() {
      _liveClockStartedAt = DateTime.now();
      _liveClockElapsedSeconds = 0;
      _timerFinished = false;
      error = null;
    });
    _startLiveClockTicker();
  }

  void _stopLiveClock() {
    if (!_liveClockRunning) return;
    final elapsedSeconds = _currentLiveClockElapsedSeconds();
    _stopLiveClockTicker();
    setState(() {
      _liveClockStartedAt = null;
      _liveClockElapsedSeconds = elapsedSeconds;
      error = null;
    });

    if (elapsedSeconds <= 0) {
      setState(() {
        error = 'Live clock needs at least 1 second before stopping.';
      });
      return;
    }
    _persistCalculatorSession();
  }

  Future<void> _startTimedRateWithConflictHandling(
      int configuredSeconds) async {
    final existing = await _rateTimerService.loadActiveTimerForInstance(
      _instanceStorageId,
    );
    if (existing != null && existing.isRunningAt(DateTime.now())) {
      await _restoreTimerState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A timer is already running for this calculator.'),
          ),
        );
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
    final instanceState = state.copyWith(instanceId: _instanceStorageId);
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

    await _rateTimerService.saveActiveTimer(instanceState);
    await _rateTimerNotifications.scheduleNotifications(
        timer: instanceState, settings: settings);

    _countdownTimer?.cancel();
    setState(() {
      _activeTimerState = instanceState;
      _timerEndsAt = instanceState.endsAt;
      _remainingSeconds = configuredSeconds;
      _thirtySecondAlertShown = false;
      _timerFinished = false;
    });
    _persistCalculatorSession();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _syncTimerFromClock(timer);
    });
  }

  Future<void> _applyPendingNotificationAction() async {
    final action = await _rateTimerService.consumePendingAction();
    if (action == null) return;
    final targetCalculatorId =
        (action.payload['calculatorId'] as String? ?? '').trim();
    final targetInstanceId =
        (action.payload['instanceId'] as String? ?? '').trim();

    if (action.type == RateTimerPendingActionType.openCalculator) {
      final config = RateCalculatorConfig.fromStorageId(targetCalculatorId);
      if (config != null && mounted) {
        if (targetInstanceId == _instanceStorageId) {
          await _restoreTimerState();
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RateCalculatorScreen(
                config: config,
                instanceId:
                    targetInstanceId.isNotEmpty ? targetInstanceId : null,
              ),
            ),
          );
        }
      }
      return;
    }

    if (targetInstanceId.isNotEmpty && targetInstanceId != _instanceStorageId) {
      return;
    }

    if (action.type == RateTimerPendingActionType.stopTimer) {
      _cancelTimedRate(discardSession: false);
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

  Future<void> _confirmStopTimerDiscard() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop Timer'),
        content: const Text(
          'Do you want to keep this calculation session or discard it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop('keep'),
            child: const Text('Stop, Keep Session'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: const Text('Stop & Discard'),
          ),
        ],
      ),
    );

    if (choice == 'keep') {
      _cancelTimedRate(discardSession: false);
      return;
    }
    if (choice == 'discard') {
      _cancelTimedRate(discardSession: true);
    }
  }

  void _cancelTimedRate({required bool discardSession}) {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _stopLiveClockTicker();
    _clearTimerStatePersistence();
    final configuredSeconds = _minutesToDurationSeconds();
    setState(() {
      _activeTimerState = null;
      _timerEndsAt = null;
      _liveClockStartedAt = null;
      _liveClockElapsedSeconds = 0;
      _remainingSeconds = configuredSeconds;
      _thirtySecondAlertShown = false;
      _timerFinished = false;
      if (discardSession) {
        startGauge.clear();
        endGauge.clear();
        bblPerMin = null;
        bblPerHr = null;
        bblPerDay = null;
        error = null;
      }
    });
    if (discardSession) {
      _clearCalculatorSession();
      return;
    }
    _persistCalculatorSession();
  }

  void _resetTimerOnly() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _clearTimerStatePersistence();
    setState(() {
      _activeTimerState = null;
      _timerEndsAt = null;
      _remainingSeconds = _minutesToDurationSeconds();
      _thirtySecondAlertShown = false;
      _timerFinished = false;
      error = null;
    });
    _persistCalculatorSession();
  }

  void _resetLiveClockOnly() {
    _stopLiveClockTicker();
    setState(() {
      _liveClockStartedAt = null;
      _liveClockElapsedSeconds = 0;
      error = null;
    });
    _persistCalculatorSession();
  }

  bool get _hasValidMinutes => _minutesToDurationSeconds() > 0;

  bool get _hasGaugeInputs =>
      startGauge.text.trim().isNotEmpty && endGauge.text.trim().isNotEmpty;

  bool get _canCalculate {
    if (!_hasGaugeInputs) return false;
    if (_useLiveClock) {
      final elapsedSeconds = _liveClockElapsedSeconds > 0
          ? _liveClockElapsedSeconds
          : _currentLiveClockElapsedSeconds();
      return !_liveClockRunning && elapsedSeconds > 0;
    }
    return _hasValidMinutes;
  }

  bool get _canResetTimer =>
      _timerRunning ||
      _isCurrentCalculatorTimerActive ||
      _timerFinished ||
      _remainingSeconds != _minutesToDurationSeconds();

  bool get _canResetCalculator =>
      startGauge.text.trim().isNotEmpty ||
      endGauge.text.trim().isNotEmpty ||
      bblPerMin != null ||
      bblPerHr != null ||
      bblPerDay != null ||
      _timerRunning ||
      _liveClockRunning ||
      _liveClockElapsedSeconds > 0 ||
      _timerFinished ||
      (error?.trim().isNotEmpty ?? false);

  bool get _isCurrentCalculatorTimerActive =>
      _activeTimerState?.instanceId == _instanceStorageId;

  String _timerStartedText() {
    final state = _activeTimerState;
    if (state == null || !_isCurrentCalculatorTimerActive) return '--';
    return TimeOfDay.fromDateTime(state.startedAt).format(context);
  }

  String _timerElapsedText() {
    final state = _activeTimerState;
    if (state == null || !_isCurrentCalculatorTimerActive) return '--';
    final elapsed = DateTime.now().difference(state.startedAt).inSeconds;
    final safeElapsed = elapsed < 0 ? 0 : elapsed;
    final mm = (safeElapsed ~/ 60).toString().padLeft(2, '0');
    final ss = (safeElapsed % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String get _timerStatusText {
    if (_timerRunning) return 'Timer running...';
    if (_timerFinished) return 'Ready to calculate.';
    return 'Enter gauges and start timer.';
  }

  void _setTimerMode(bool useLiveClock) {
    if (!_liveClockAvailable) return;
    if (_useLiveClock == useLiveClock) return;

    if (useLiveClock && (_timerRunning || _isCurrentCalculatorTimerActive)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stop countdown timer before switching to live clock.'),
        ),
      );
      return;
    }

    if (!useLiveClock && _liveClockRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stop live clock before switching timer mode.'),
        ),
      );
      return;
    }

    setState(() {
      _useLiveClock = useLiveClock;
      error = null;
    });
    _persistCalculatorSession();
  }

  Widget _timerModeSelector() {
    if (!_liveClockAvailable) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Timer Mode',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ChoiceChip(
                  selected: !_useLiveClock,
                  onSelected: (_) => _setTimerMode(false),
                  label: const Text('Timed Rate'),
                ),
                ChoiceChip(
                  selected: _useLiveClock,
                  onSelected: (_) => _setTimerMode(true),
                  label: const Text('Live Clock'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _timedRateSection() {
    final scheme = Theme.of(context).colorScheme;
    final canRunTimer =
        _hasValidMinutes && !_isCurrentCalculatorTimerActive && !_timerRunning;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Timed Rate',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer_outlined,
                          color: scheme.primary, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        _timerFinished ? 'TIME' : _timerText(),
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: _timerFinished
                              ? Colors.redAccent
                              : scheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _timerStatusText,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Started: ${_timerStartedText()}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Elapsed: ${_timerElapsedText()}',
                          textAlign: TextAlign.end,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_timerRunning)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _confirmStopTimerDiscard,
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
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _canResetTimer ? _resetTimerOnly : null,
                      child: const Text('Reset Timer'),
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

  Widget _liveClockSection() {
    if (!_liveClockAvailable) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Live Clock',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start timer, stop at stick pull, enter ending gauge, then tap CALCULATE.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.av_timer, color: scheme.primary, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        _liveClockText(),
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _liveClockRunning
                        ? 'Live clock running... stop when you pull the stick.'
                        : 'Stopped. Enter ending gauge, then tap CALCULATE.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Started: ${_liveClockStartedText()}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: _liveClockRunning
                              ? OutlinedButton(
                                  onPressed: _stopLiveClock,
                                  child: const Text('Stop Live Clock'),
                                )
                              : FilledButton(
                                  onPressed: _startLiveClock,
                                  child: const Text('Start Live Clock'),
                                ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: (_liveClockRunning ||
                                    _liveClockElapsedSeconds > 0)
                                ? _resetLiveClockOnly
                                : null,
                            child: const Text('Reset Live Clock'),
                          ),
                        ),
                      ],
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
    _persistCalculatorSession();
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
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Container(
            color: scheme.surface,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select Timer Length',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Choose the timer length for this run.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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
                              ? scheme.primary.withValues(alpha: 0.2)
                              : scheme.surfaceContainerHigh
                                  .withValues(alpha: 0.45),
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
                                            ? scheme.primary
                                            : scheme.onSurface,
                                        fontSize: 20,
                                        fontWeight: selected
                                            ? FontWeight.w900
                                            : FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (selected)
                                    Icon(
                                      Icons.check_circle,
                                      color: scheme.primary,
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
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      disabledBackgroundColor: scheme.surfaceContainerHighest,
      disabledForegroundColor: scheme.onSurfaceVariant,
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
      case 'mr_810039':
        return mr810039FlowbackChart;
    }
    return null;
  }

  String get _activeTankName {
    final title = widget.config.title.trim();
    return title.isEmpty ? 'tank' : title;
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
    _stopLiveClockTicker();
    _clearTimerStatePersistence();
    setState(() {
      _activeTimerState = null;
      _timerEndsAt = null;
      _liveClockStartedAt = null;
      _liveClockElapsedSeconds = 0;
      startGauge.clear();
      endGauge.clear();
      fluidHauled.clear();
      _fluidHauledEnabled = false;
      bblPerMin = null;
      bblPerHr = null;
      bblPerDay = null;
      _timerFinished = false;
      _thirtySecondAlertShown = false;
      _remainingSeconds = _minutesToDurationSeconds();
      error = null;
    });
    _clearCalculatorSession();
  }

  Future<void> _autoSaveCalculationToOperationsLog({
    required DateTime readingTimestamp,
    required String startGaugeValue,
    required String endGaugeValue,
    required double elapsedMinutes,
    required double startInches,
    required double endInches,
    required double startBarrels,
    required double endBarrels,
    required double barrelChange,
    required double fluidHauledBarrels,
    required double adjustedBarrelChange,
    required double bblPerMinute,
    required double bblPerHour,
  }) async {
    if (!widget.config.allowOperationsLogAutoSave) return;
    final settings = await _settingsService.load();
    if (!settings.autoSaveRateCalculationsToOperationsLog) return;

    final activeJob = await _jobStorage.ensureActiveJobLoaded();
    if (activeJob == null || activeJob.id.trim().isEmpty) {
      return;
    }

    final workflowName = activeJob.workflow.trim().toLowerCase();
    final workflow = workflowName == OperationsLogWorkflow.cleanout.name
        ? OperationsLogWorkflow.cleanout
        : OperationsLogWorkflow.drillout;
    final wellEntries = activeJob.resolvedWellEntries;
    final wellId = wellEntries.isNotEmpty ? wellEntries.first.id : '';
    final wellName = activeJob.primaryWell.trim().isNotEmpty
        ? activeJob.primaryWell.trim()
        : activeJob.padName.trim();
    if (wellName.isEmpty) return;

    final selectedRateValue = _rateDisplayUnit == _RateDisplayUnit.bblPerHr
        ? bblPerHour
        : bblPerMinute;
    final selectedRateUnit = _selectedRateUnitLabel;
    final rateText = _rateDisplayUnit == _RateDisplayUnit.bblPerHr
        ? selectedRateValue.toStringAsFixed(1)
        : selectedRateValue.toStringAsFixed(3);
    final elapsedSeconds = (elapsedMinutes * 60).round();
    final elapsedDuration = Duration(seconds: elapsedSeconds);
    final elapsedLabel =
        '${elapsedDuration.inMinutes}:${(elapsedDuration.inSeconds % 60).toString().padLeft(2, '0')}';
    final generatedText =
        'RATE\n\n${widget.config.title}\n\nRate: $rateText $selectedRateUnit\n\n$startGaugeValue" -> $endGaugeValue"\n\nElapsed: $elapsedLabel';

    final stage = (activeJob.drilloutSetup['status'] as String? ??
            activeJob.drilloutSetup['stage'] as String? ??
            '')
        .trim();
    final entry = await _operationsLogService.createLocalEntry(
      workflow: workflow,
      jobId: activeJob.id,
      wellId: wellId,
      wellName: wellName,
      readingTimestamp: readingTimestamp,
      entryType: 'manualReading',
      generatedText: generatedText,
      structuredData: <String, dynamic>{
        'rateCalculationRecordType': 'autoSave',
        'rateCalculatorTankType': widget.config.title,
        'rateCalculatorGaugeUnit': 'inches',
        'rateCalculatorStartGauge': startGaugeValue,
        'rateCalculatorEndGauge': endGaugeValue,
        'rateCalculatorElapsedMinutes': elapsedMinutes,
        'rateCalculatorStartInches': startInches,
        'rateCalculatorEndInches': endInches,
        'rateCalculatorStartBarrels': startBarrels,
        'rateCalculatorEndBarrels': endBarrels,
        'rateCalculatorBarrelChange': barrelChange,
        'rateCalculatorFluidHauledBarrels': fluidHauledBarrels,
        'rateCalculatorAdjustedBarrelChange': adjustedBarrelChange,
        'rateCalculatorBblPerMinute': bblPerMinute,
        'rateCalculatorBblPerHour': bblPerHour,
        'rateCalculatorSelectedRateValue': selectedRateValue,
        'rateCalculatorSelectedRateUnit': selectedRateUnit,
      },
      operationStage: stage,
      returnsRate: bblPerMinute.toStringAsFixed(3),
      notes: 'Auto-saved from Rate Calculator.',
    );

    await _operationsLogService.upsertEntry(
      workflow: workflow,
      jobId: activeJob.id,
      entry: entry,
    );
  }

  Future<void> calculate() async {
    final hadKeypadOpen = _activeKeypadTarget != null;
    FocusScope.of(context).unfocus();
    if (hadKeypadOpen) {
      setState(() => _activeKeypadTarget = null);
    }

    final startText = startGauge.text.trim();
    final endText = endGauge.text.trim();

    if (startText.isEmpty) {
      setState(() => error = 'Enter a starting gauge.');
      return;
    }
    if (endText.isEmpty) {
      setState(() => error = 'Enter an ending gauge.');
      return;
    }

    if (_useLiveClock) {
      if (_liveClockRunning) {
        setState(() => error = 'Stop live clock before calculating.');
        return;
      }

      final elapsedSeconds = _liveClockElapsedSeconds > 0
          ? _liveClockElapsedSeconds
          : _currentLiveClockElapsedSeconds();
      if (elapsedSeconds <= 0) {
        setState(
            () => error = 'Start and stop live clock to capture elapsed time.');
        return;
      }

      await _calculateFromElapsedMinutes(elapsedSeconds / 60.0);
      return;
    }

    final minutesText = minutes.text.trim();
    if (minutesText.isEmpty) {
      setState(() => error = 'Select the number of minutes.');
      return;
    }

    final m = double.tryParse(minutesText) ?? 0;
    if (m <= 0) {
      setState(() => error = 'Select the number of minutes.');
      return;
    }

    await _calculateFromElapsedMinutes(m);
  }

  Future<void> _calculateFromElapsedMinutes(double elapsedMinutes) async {
    final startText = startGauge.text.trim();
    final endText = endGauge.text.trim();

    if (startText.isEmpty) {
      setState(() => error = 'Enter a starting gauge.');
      return;
    }
    if (endText.isEmpty) {
      setState(() => error = 'Enter an ending gauge.');
      return;
    }

    if (elapsedMinutes <= 0) {
      setState(() => error = 'Elapsed time must be greater than zero.');
      return;
    }

    if (!widget.config.usesChart &&
        (double.tryParse(factor.text.trim()) ?? 0) <= 0) {
      setState(() => error = 'Tank factor must be greater than zero.');
      return;
    }

    final startInches = parseGauge(startText);
    final endInches = parseGauge(endText);
    final hasNegativeGauge = startInches < 0 || endInches < 0;
    final hauledText = fluidHauled.text.trim();
    final fluidHauledBarrels =
        _fluidHauledEnabled ? (double.tryParse(hauledText) ?? 0) : 0.0;

    if (_fluidHauledEnabled && fluidHauledBarrels < 0) {
      setState(() {
        error = 'Fluid hauled must be zero or greater.';
        bblPerMin = null;
        bblPerHr = null;
        bblPerDay = null;
      });
      return;
    }

    if (hasNegativeGauge) {
      setState(() {
        error =
            'Negative gauge detected. Enter non-negative gauge values before calculating.';
        bblPerMin = null;
        bblPerHr = null;
        bblPerDay = null;
      });
      return;
    }

    final activeChart = chart;
    if (activeChart != null) {
      if (!activeChart.supportsGauge(startInches) ||
          !activeChart.supportsGauge(endInches)) {
        setState(() {
          error =
              'Gauge reading is outside the supported $_activeTankName chart.';
        });
        return;
      }
    }

    final startBbl = barrelsAt(startInches);
    final endBbl = barrelsAt(endInches);
    final change = endBbl - startBbl;
    final adjustedChange = change + fluidHauledBarrels;
    if (adjustedChange <= 0) {
      setState(() {
        error =
            'Adjusted barrel change must be greater than zero. Increase ending gauge or fluid hauled.';
        bblPerMin = null;
        bblPerHr = null;
        bblPerDay = null;
      });
      return;
    }
    final perMin = adjustedChange / elapsedMinutes;
    final perHour = perMin * 60;

    _countdownTimer?.cancel();
    _countdownTimer = null;
    _stopLiveClockTicker();
    _clearTimerStatePersistence();

    final now = DateTime.now();
    setState(() {
      bblPerMin = perMin;
      bblPerHr = perHour;
      bblPerDay = perMin * 1440;
      _liveClockStartedAt = null;
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
            timestamp: now,
            rateValue: value,
            rateUnit: _selectedRateUnitLabel,
            selected: true,
          ),
        );
        _saveRateLogState();
      }
    });

    try {
      await _autoSaveCalculationToOperationsLog(
        readingTimestamp: now,
        startGaugeValue: startText,
        endGaugeValue: endText,
        elapsedMinutes: elapsedMinutes,
        startInches: startInches,
        endInches: endInches,
        startBarrels: startBbl,
        endBarrels: endBbl,
        barrelChange: change,
        fluidHauledBarrels: fluidHauledBarrels,
        adjustedBarrelChange: adjustedChange,
        bblPerMinute: perMin,
        bblPerHour: perHour,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[RateCalculator] Failed to auto-save Operations Log rate entry: $error\n$stackTrace',
      );
    }

    _persistCalculatorSession();
  }

  @override
  void dispose() {
    _persistTimerState();
    _persistCalculatorSession();
    _saveRateLogState();
    _persistHomeTabsState();
    WidgetsBinding.instance.removeObserver(this);
    _activeTankTicker?.cancel();
    _countdownTimer?.cancel();
    _liveClockTicker?.cancel();
    startGauge.removeListener(_handleSessionFieldChanged);
    endGauge.removeListener(_handleSessionFieldChanged);
    fluidHauled.removeListener(_handleSessionFieldChanged);
    factor.removeListener(_handleSessionFieldChanged);
    minutes.removeListener(_handleMinutesChanged);
    startGauge.dispose();
    endGauge.dispose();
    fluidHauled.dispose();
    minutes.dispose();
    factor.dispose();
    super.dispose();
  }

  Widget _resultsCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Results',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Rate Display',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
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
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _selectedRateUnitLabel,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rateLogSection() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(
              'Rate Log (${_rateLogEntries.length})',
              style: TextStyle(
                color: scheme.primary,
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
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'No log entries yet.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final actions = <Widget>[];
                    if (_rateLogEnabled && _rateLogEntries.isNotEmpty) {
                      actions.add(
                        OutlinedButton.icon(
                          onPressed: _copyRateUpdate,
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('Copy Update'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            alignment: Alignment.center,
                            textStyle:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      );
                      actions.add(
                        OutlinedButton.icon(
                          onPressed: _shareRateLogQr,
                          icon: const Icon(Icons.qr_code_2_outlined),
                          label: const Text('Share QR'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            alignment: Alignment.center,
                            textStyle:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      );
                    }
                    actions.add(
                      OutlinedButton.icon(
                        onPressed: _clearRateLogWithConfirmation,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear Log'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          alignment: Alignment.center,
                          textStyle:
                              const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    );

                    final compactTwoAcross = constraints.maxWidth < 520;
                    final columns = compactTwoAcross ? 2 : actions.length;
                    final spacing = 10.0;
                    final itemWidth =
                        (constraints.maxWidth - ((columns - 1) * spacing)) /
                            columns;

                    return Wrap(
                      spacing: spacing,
                      runSpacing: 10,
                      children: actions
                          .map(
                            (button) => SizedBox(
                              width: itemWidth,
                              child: IconTheme(
                                data: const IconThemeData(size: 20),
                                child: button,
                              ),
                            ),
                          )
                          .toList(growable: false),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _importRateLogQr,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Import QR'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                  ),
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
                                Icon(
                                  Icons.check,
                                  color: scheme.primary,
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
      showPrimaryAction: true,
      primaryActionEnabled: true,
      primaryActionLabel: 'Calculate Rate',
      onPrimaryAction: calculate,
    );
  }

  Future<void> _openAddAnotherTankPicker() async {
    final configs = widget.availableConfigs ?? const <RateCalculatorConfig>[];
    if (configs.isEmpty || !widget.homeMultiMode) return;

    final selected = await showModalBottomSheet<RateCalculatorConfig>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: configs.length,
            itemBuilder: (context, index) {
              final config = configs[index];
              final isCurrent = config.title == widget.config.title &&
                  config.chartId == widget.config.chartId;
              return ListTile(
                leading: const Icon(Icons.speed),
                title: Text(config.title),
                subtitle: isCurrent
                    ? const Text('Current tank')
                    : const Text('Start separate timer'),
                onTap: isCurrent
                    ? null
                    : () => Navigator.of(sheetContext).pop(config),
              );
            },
          ),
        );
      },
    );

    if (!mounted || selected == null) return;
    await _sessionService.ensureInitialized();
    final selectedCalculatorId = _calculatorIdForConfig(selected);

    final activeTimer = await _rateTimerService.loadActiveTimerForCalculator(
      selectedCalculatorId,
    );
    final restoredInstanceId = activeTimer?.instanceId.isNotEmpty == true
        ? activeTimer!.instanceId
        : _sessionService.sessionKeyForCalculator(selectedCalculatorId);
    final nextInstanceId = (restoredInstanceId ??
            '${selectedCalculatorId}_${DateTime.now().microsecondsSinceEpoch}')
        .trim();

    final existingTabs = _resolvedHomeTabs();
    final alreadyOpenIndex = existingTabs.indexWhere(
      (tab) => tab.instanceId == nextInstanceId,
    );
    final nextTabs = List<HomeRateTabSpec>.from(existingTabs);
    if (alreadyOpenIndex < 0) {
      nextTabs.add(
        HomeRateTabSpec(config: selected, instanceId: nextInstanceId),
      );
    }
    _homeTabs = nextTabs;
    await _persistHomeTabsState();
    await _refreshHomeTabTimers();

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RateCalculatorScreen(
          config: selected,
          instanceId: nextInstanceId,
          homeMultiMode: true,
          availableConfigs: configs,
          homeTabs: nextTabs,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return Scaffold(
        appBar: AppHeader(title: widget.config.title, showBack: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        _persistTimerState();
        _persistCalculatorSession();
        _saveRateLogState();
        _persistHomeTabsState();
      },
      child: Scaffold(
        appBar: AppHeader(title: widget.config.title, showBack: true),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _tankSelectionSection(),
                  _activeTanksSection(),
                  if (!widget.config.usesChart)
                    WwNumberField(
                      label: 'Tank Factor (BBL/In)',
                      helperText:
                          'Default: ${(widget.config.defaultFactor ?? 1.67).toStringAsFixed(2)}. Change it if your tank factor is different.',
                      controller: factor,
                      allowDecimal: true,
                    ),
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
                  if (widget.homeMultiMode) ...[
                    SwitchListTile.adaptive(
                      value: _fluidHauledEnabled,
                      onChanged: (value) {
                        setState(() {
                          _fluidHauledEnabled = value;
                          if (!value) {
                            fluidHauled.clear();
                          }
                        });
                        _persistCalculatorSession();
                      },
                      title: const Text('Include Fluid Hauled'),
                      subtitle: const Text(
                        'Optionally add hauled-off volume to the total barrel change.',
                      ),
                    ),
                    if (_fluidHauledEnabled)
                      WwNumberField(
                        label: 'Fluid Hauled (BBL)',
                        helperText:
                            'Optional hauled volume to add to gauge-based barrel change.',
                        controller: fluidHauled,
                        allowDecimal: true,
                        onChanged: (_) => setState(() {}),
                      ),
                  ],
                  if (!_useLiveClock)
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                                width: 1.2,
                              ),
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh
                                  .withValues(alpha: 0.35),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Minutes',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _minutesDisplayText,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  _timerModeSelector(),
                  const SizedBox(height: 10),
                  if (_useLiveClock)
                    _liveClockSection()
                  else
                    _timedRateSection(),
                  const SizedBox(height: 10),
                  FilledButton(
                    style: _calculateButtonStyle(),
                    onPressed: _canCalculate ? calculate : null,
                    child: const Text('CALCULATE'),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed:
                          _canResetCalculator ? _resetTimedRateWorkflow : null,
                      child: const Text('Reset Calculator'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    value: _rateLogEnabled,
                    onChanged: (value) {
                      setState(() => _rateLogEnabled = value);
                      _saveRateLogState();
                      _persistCalculatorSession();
                    },
                    title: const Text('Rate Log'),
                    subtitle: const Text('Save each CALCULATE result to log'),
                  ),
                  if (error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
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
      ),
    );
  }
}
