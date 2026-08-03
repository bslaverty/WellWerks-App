import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/job_setup.dart';
import '../widgets/app_header.dart';
import '../widgets/tool_card.dart';
import '../services/app_settings_service.dart';
import '../services/job_storage_service.dart';
import '../services/operations_log_service.dart';
import '../services/rate_timer_notification_service.dart';
import '../services/rate_timer_service.dart';
import '../services/recovery_state_service.dart';
import 'module_menu_screen.dart';
import 'completions_calculators_screen.dart';
import 'conversion_calculator_screen.dart';
import 'rate_calculator_screen.dart';
import 'equipment_layout_screen.dart';
import 'rig_up_inventory_screen.dart';
import 'rig_up_history_screen.dart';
import 'jsa_screen.dart';
import 'production_dashboard_screen.dart';
import 'rate_calculator_menu_screen.dart';
import 'production_history_screen.dart';
import 'chart_reference_screen.dart';
import 'tank_charts_menu_screen.dart';
import 'settings_screen.dart';
import 'about_support_screen.dart';
import 'drillout_cleanout_module_screen.dart';
import 'flywheel_diesel_tank_screen.dart';
import 'operations_log_screen.dart';

class _HomeRecentItem {
  const _HomeRecentItem({
    required this.toolId,
    required this.lastUsedMs,
  });

  final String toolId;
  final int lastUsedMs;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'toolId': toolId,
      'lastUsedMs': lastUsedMs,
    };
  }

  factory _HomeRecentItem.fromJson(Map<String, dynamic> map) {
    return _HomeRecentItem(
      toolId: (map['toolId'] as String? ?? '').trim(),
      lastUsedMs: (map['lastUsedMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _recentToolsPrefKey = 'wellwerks_home_recent_tools_v1';
  static const _favoriteToolsPrefKey = 'wellwerks_home_favorite_tools_v1';
  static const _maxRecentTools = 6;
  static const _maxFavorites = 3;
  static const List<String> _favoriteToolChoices = <String>[
    'production',
    'completions',
    'rigup',
    'rate',
    'jsa',
    'charts',
    'history',
  ];

  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();
  final _rateTimerService = RateTimerService();
  final _settingsService = AppSettingsService();
  final _rateTimerNotifications = RateTimerNotificationService.instance;

  bool _loading = true;
  bool _weatherLoading = false;
  String _weatherSummary = '--';
  String _windSummary = '--';
  String _gpsSummary = '--';
  String _locationSummary = '--';
  List<_HomeRecentItem> _recentTools = const <_HomeRecentItem>[];
  List<String> _favoriteToolIds = const <String>[];

  @override
  void initState() {
    super.initState();
    _jobStorage.activeJobListenable.addListener(_handleActiveJobChanged);
    _loadRecovery();
  }

  @override
  void dispose() {
    _jobStorage.activeJobListenable.removeListener(_handleActiveJobChanged);
    super.dispose();
  }

  void _handleActiveJobChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadRecovery() async {
    await _jobStorage.ensureActiveJobLoaded();
    final lastActiveJobId = await _jobStorage.loadLastActiveJobId();
    await _recoveryState.loadSnapshot(
      lastActiveJobId: lastActiveJobId,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
    _handlePendingRateTimerAction();
    _handlePendingEstimatedStsAction();
    _loadFavoriteTools();
    _loadRecentTools();
    _refreshWeatherAndGps();
  }

  JobSetup? get _activeJob => _jobStorage.activeJobListenable.value;

  Future<void> _loadRecentTools() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentToolsPrefKey) ?? '';
    if (raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loaded = <_HomeRecentItem>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final mapped = Map<String, dynamic>.from(item);
        final recent = _HomeRecentItem.fromJson(mapped);
        if (recent.toolId.isEmpty || recent.lastUsedMs <= 0) continue;
        loaded.add(recent);
      }
      loaded.sort((a, b) => b.lastUsedMs.compareTo(a.lastUsedMs));
      if (!mounted) return;
      setState(() {
        _recentTools = loaded.take(_maxRecentTools).toList(growable: false);
      });
    } catch (_) {
      // Ignore malformed saved recents.
    }
  }

  Future<void> _saveRecentTools() async {
    final prefs = await SharedPreferences.getInstance();
    final payload =
        _recentTools.map((item) => item.toJson()).toList(growable: false);
    await prefs.setString(_recentToolsPrefKey, jsonEncode(payload));
  }

  Future<void> _loadFavoriteTools() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_favoriteToolsPrefKey) ?? '';
    if (raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loaded = <String>[];
      for (final item in decoded) {
        final id = (item?.toString() ?? '').trim().toLowerCase();
        if (id.isEmpty || !_favoriteToolChoices.contains(id)) continue;
        if (loaded.contains(id)) continue;
        loaded.add(id);
        if (loaded.length >= _maxFavorites) break;
      }
      if (!mounted) return;
      setState(() {
        _favoriteToolIds = loaded;
      });
    } catch (_) {
      // Ignore malformed saved favorites.
    }
  }

  Future<void> _saveFavoriteTools() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_favoriteToolsPrefKey, jsonEncode(_favoriteToolIds));
  }

  Future<void> _recordRecentTool(String toolId) async {
    final normalized = toolId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = <_HomeRecentItem>[
      _HomeRecentItem(toolId: normalized, lastUsedMs: now),
      for (final item in _recentTools)
        if (item.toolId != normalized) item,
    ].take(_maxRecentTools).toList(growable: false);
    if (!mounted) return;
    setState(() {
      _recentTools = updated;
    });
    await _saveRecentTools();
  }

  String _weatherConditionFromCode(int code) {
    switch (code) {
      case 0:
        return 'Clear';
      case 1:
      case 2:
      case 3:
        return 'Partly Cloudy';
      case 45:
      case 48:
        return 'Fog';
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return 'Drizzle';
      case 61:
      case 63:
      case 65:
      case 66:
      case 67:
        return 'Rain';
      case 71:
      case 73:
      case 75:
      case 77:
        return 'Snow';
      case 80:
      case 81:
      case 82:
        return 'Rain Showers';
      case 95:
      case 96:
      case 99:
        return 'Thunderstorm';
      default:
        return 'Unknown';
    }
  }

  Future<Position> _ensurePosition() async {
    final locationEnabled = await Geolocator.isLocationServiceEnabled();
    if (!locationEnabled) {
      throw StateError('Location services are disabled.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission denied.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  String _cityStateFromAddress(Map<String, dynamic> address) {
    final city = (address['city'] ??
            address['town'] ??
            address['village'] ??
            address['hamlet'] ??
            '')
        .toString()
        .trim();
    final state = (address['state'] ?? '').toString().trim();
    if (city.isEmpty) return state;
    if (state.isEmpty) return city;
    return '$city, $state';
  }

  Future<void> _refreshWeatherAndGps() async {
    if (_weatherLoading) return;
    if (!mounted) return;
    setState(() => _weatherLoading = true);
    try {
      final position = await _ensurePosition();
      final gps =
          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';

      var locationText = '--';
      final reverseUri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${position.latitude}&lon=${position.longitude}&addressdetails=1',
      );
      final reverseResponse = await http.get(
        reverseUri,
        headers: const {'User-Agent': 'WellWerks/1.0'},
      );
      if (reverseResponse.statusCode == 200) {
        final reverseMap =
            jsonDecode(reverseResponse.body) as Map<String, dynamic>;
        final address = reverseMap['address'] as Map<String, dynamic>?;
        if (address != null) {
          final county = (address['county'] ?? '').toString().trim();
          final cityState = _cityStateFromAddress(address);
          final composed = [county, cityState]
              .where((item) => item.trim().isNotEmpty)
              .join(' • ')
              .trim();
          if (composed.isNotEmpty) {
            locationText = composed;
          }
        }
      }

      final weatherUri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${position.latitude}&longitude=${position.longitude}&current=temperature_2m,weather_code,wind_speed_10m&temperature_unit=fahrenheit&wind_speed_unit=mph',
      );
      final weatherResponse = await http.get(weatherUri);
      if (weatherResponse.statusCode != 200) {
        throw StateError('Unable to fetch weather.');
      }

      final weatherMap =
          jsonDecode(weatherResponse.body) as Map<String, dynamic>;
      final current =
          weatherMap['current'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final temperature = (current['temperature_2m'] as num?)?.toDouble();
      final weatherCode = (current['weather_code'] as num?)?.toInt();
      final windSpeed = (current['wind_speed_10m'] as num?)?.toDouble();

      final weather =
          temperature == null ? '--' : '${temperature.toStringAsFixed(0)} F';
      final condition = weatherCode == null
          ? 'Weather unavailable'
          : _weatherConditionFromCode(weatherCode);
      final wind =
          windSpeed == null ? '--' : '${windSpeed.toStringAsFixed(1)} mph';

      if (!mounted) return;
      setState(() {
        _gpsSummary = gps;
        _locationSummary = locationText;
        _weatherSummary = '$weather • $condition';
        _windSummary = wind;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _weatherSummary = 'Weather unavailable';
        _windSummary = '--';
      });
    } finally {
      if (!mounted) return;
      setState(() => _weatherLoading = false);
    }
  }

  Future<void> _handlePendingEstimatedStsAction() async {
    final payload =
        await _rateTimerNotifications.consumePendingEstimatedStsNotification();
    if (!mounted || payload == null) return;

    final expectedJobId = (payload['persistentJobId'] as String? ?? '').trim();
    final workflowRaw = (payload['workflow'] as String? ?? '').trim();

    final activeJob = await _jobStorage.ensureActiveJobLoaded();
    if (!mounted) return;

    final matchesActiveJob = expectedJobId.isNotEmpty &&
        activeJob != null &&
        activeJob.id.trim() == expectedJobId;
    if (!matchesActiveJob) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The original STS reading is no longer available.'),
        ),
      );
      return;
    }

    final normalizedWorkflow = workflowRaw.toLowerCase();
    final isCleanout = normalizedWorkflow == 'cleanout';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OperationsLogScreen(
          workflow: isCleanout
              ? OperationsLogWorkflow.cleanout
              : OperationsLogWorkflow.drillout,
          title: isCleanout ? 'Cleanout Log' : 'Drillout Log',
        ),
      ),
    );
    if (!mounted) return;
    await _loadRecovery();
  }

  Future<void> _handlePendingRateTimerAction() async {
    final action = await _rateTimerService.consumePendingAction();
    if (!mounted || action == null) return;
    final calculatorId =
        (action.payload['calculatorId'] as String? ?? '').trim();
    final instanceId = (action.payload['instanceId'] as String? ?? '').trim();
    final config = RateCalculatorConfig.fromStorageId(calculatorId);

    if (action.type == RateTimerPendingActionType.stopTimer) {
      final active = instanceId.isNotEmpty
          ? await _rateTimerService.loadActiveTimerForInstance(instanceId)
          : await _rateTimerService.loadActiveTimerForCalculator(calculatorId);
      if (active != null) {
        await _rateTimerNotifications.cancelNotifications(active);
      }
      await _rateTimerService.clearActiveTimer(
        instanceId: instanceId.isNotEmpty ? instanceId : null,
        calculatorId: instanceId.isEmpty ? calculatorId : null,
      );
      return;
    }

    if (action.type == RateTimerPendingActionType.restartTimer) {
      if (config == null) return;
      final active = instanceId.isNotEmpty
          ? await _rateTimerService.loadActiveTimerForInstance(instanceId)
          : await _rateTimerService.loadActiveTimerForCalculator(calculatorId);
      if (active != null) {
        await _rateTimerNotifications.cancelNotifications(active);
      }
      final durationSeconds =
          (action.payload['durationSeconds'] as num?)?.toInt() ?? 60;
      final fresh = await _rateTimerService.createState(
        calculatorId: calculatorId,
        calculatorTitle:
            (action.payload['calculatorTitle'] as String? ?? config.title),
        wellOrJob: (action.payload['wellOrJob'] as String? ?? '').trim(),
        durationSeconds: durationSeconds,
      );
      final timerState = instanceId.isNotEmpty
          ? fresh.copyWith(instanceId: instanceId)
          : fresh;
      await _rateTimerService.saveActiveTimer(timerState);
      final settings = await _settingsService.load();
      await _rateTimerNotifications.scheduleNotifications(
        timer: timerState,
        settings: settings,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RateCalculatorScreen(
            config: config,
            instanceId: instanceId.isNotEmpty ? instanceId : null,
          ),
        ),
      );
      if (!mounted) return;
      await _loadRecovery();
      return;
    }

    if (action.type == RateTimerPendingActionType.openCalculator &&
        config != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RateCalculatorScreen(
            config: config,
            instanceId: instanceId.isNotEmpty ? instanceId : null,
          ),
        ),
      );
      if (!mounted) return;
      await _loadRecovery();
    }
  }

  Future<void> open(BuildContext context, Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _loadRecovery();
  }

  Future<void> _openHomeTool(String toolId) async {
    await _recordRecentTool(toolId);
    if (!mounted) return;
    switch (toolId) {
      case 'production':
        await open(context, const ProductionDashboardScreen());
        return;
      case 'completions':
        await open(
          context,
          ModuleMenuScreen(
            title: 'Completions',
            tools: [
              const ModuleTool(
                icon: Icons.text_snippet_outlined,
                title: 'Drillout / Cleanout',
                subtitle:
                    'Operations Log, Rate Calculator, STS, updates, and shift tools',
                screen: DrilloutCleanoutModuleScreen(),
              ),
              const ModuleTool(
                icon: Icons.calculate_outlined,
                title: 'Calculators',
                subtitle:
                    'Gas Accum, Bottoms Up, Multiple Choke, Conversion, and Chlorides',
                screen: CompletionsCalculatorsScreen(),
              ),
            ],
            showHomeButton: true,
          ),
        );
        return;
      case 'rigup':
        await open(
          context,
          ModuleMenuScreen(
            title: 'Rig-Up',
            tools: const [
              ModuleTool(
                icon: Icons.account_tree,
                title: 'Layout Designer',
                subtitle: 'Design rig-up layouts and iron flow paths',
                screen: EquipmentLayoutScreen(),
              ),
              ModuleTool(
                icon: Icons.inventory_2_outlined,
                title: 'Rig-Up Inventory',
                subtitle: 'Track equipment, assign by well, and share summary',
                screen: RigUpInventoryScreen(),
              ),
              ModuleTool(
                icon: Icons.history,
                title: 'Rig-Up History',
                subtitle: 'Open, share, or delete saved rig-up records',
                screen: RigUpHistoryScreen(),
              ),
            ],
            showHomeButton: true,
          ),
        );
        return;
      case 'rate':
        await open(
            context, const RateCalculatorMenuScreen(homeMultiMode: true));
        return;
      case 'jsa':
        await open(context, const JsaScreen());
        return;
      case 'charts':
        await open(
          context,
          ModuleMenuScreen(
            title: 'Charts',
            tools: [
              const ModuleTool(
                icon: Icons.storage,
                title: 'Tank Charts',
                subtitle:
                    'FS3, SandX, V Bottom, Round Bottom, Gas Tank, and Production Tank',
                screen: TankChartsMenuScreen(),
              ),
              const ModuleTool(
                icon: Icons.straighten,
                title: 'Conversion Calculator',
                subtitle: 'Field and cooking unit conversions',
                screen: ConversionCalculatorScreen(),
              ),
              const ModuleTool(
                icon: Icons.local_gas_station,
                title: 'Flywheel Diesel Tank',
                subtitle: '3-compartment diesel fuel calculator',
                screen: FlywheelDieselTankScreen(),
              ),
              ModuleTool(
                icon: Icons.table_chart,
                title: 'Chlorides Chart',
                subtitle: 'Field chloride reference chart',
                screen: _chloridesCalculatorScreen(),
              ),
            ],
            showHomeButton: true,
          ),
        );
        return;
      case 'history':
        await open(context, const ProductionHistoryScreen());
        return;
    }
  }

  ({String title, String subtitle, IconData icon})? _recentMeta(String toolId) {
    switch (toolId) {
      case 'production':
        return (
          title: 'Production',
          subtitle: 'Quick Round',
          icon: Icons.oil_barrel
        );
      case 'completions':
        return (
          title: 'Completions',
          subtitle: 'Drillout Workflow',
          icon: Icons.build
        );
      case 'rigup':
        return (
          title: 'Rig-Up',
          subtitle: 'Layout & Inventory',
          icon: Icons.account_tree
        );
      case 'rate':
        return (
          title: 'Rate Calculator',
          subtitle: 'Tank Rates',
          icon: Icons.speed
        );
      case 'jsa':
        return (
          title: 'JSA',
          subtitle: 'Safety Worksheet',
          icon: Icons.assignment
        );
      case 'charts':
        return (
          title: 'Charts',
          subtitle: 'Tank & Field',
          icon: Icons.bar_chart
        );
      case 'history':
        return (
          title: 'History',
          subtitle: 'Archived Jobs',
          icon: Icons.history
        );
      default:
        return null;
    }
  }

  String _timeAgoLabel(int timestampMs) {
    final diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _chloridesCalculatorScreen() {
    return const ChartReferenceScreen(
      title: 'Chlorides Chart',
      description:
          'Chlorides reference table from the web app source with Brix to SG conversion.',
      showBrixTool: false,
      showChloridesCalculator: true,
      enableSearch: true,
      sections: [
        ChartSection(
          title: 'Water Weight and Chlorides',
          columns: ['SP.GR.', '#/G', 'CLPPM'],
          rows: [
            ['1.002', '8.36', '1755'],
            ['1.004', '8.38', '3511'],
            ['1.006', '8.40', '5267'],
            ['1.008', '8.41', '7023'],
            ['1.010', '8.43', '8779'],
            ['1.086', '9.06', '75500'],
            ['1.088', '9.08', '77260'],
            ['1.090', '9.10', '79010'],
            ['1.092', '9.11', '80770'],
            ['1.170', '9.76', '149200'],
            ['1.172', '9.78', '151000'],
            ['1.174', '9.80', '152700'],
            ['1.176', '9.81', '154501'],
          ],
        ),
        ChartSection(
          title: 'Brix to SG Reference',
          columns: ['Brix', 'SG'],
          rows: [
            ['0', '1.0000'],
            ['5', '1.0197'],
            ['10', '1.0400'],
            ['15', '1.0607'],
            ['20', '1.0829'],
            ['25', '1.1068'],
            ['30', '1.1325'],
          ],
        ),
      ],
    );
  }

  Widget _moduleCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<ModuleTool> tools,
    String? recentToolId,
  }) {
    return ToolCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () async {
        if (recentToolId != null && recentToolId.trim().isNotEmpty) {
          await _recordRecentTool(recentToolId);
        }
        if (!context.mounted) return;
        await open(
          context,
          ModuleMenuScreen(
            title: title,
            tools: tools,
            showHomeButton: true,
          ),
        );
      },
    );
  }

  Widget _activeJobCard() {
    final job = _activeJob;
    if (job == null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: ListTile(
          leading: const Icon(Icons.work_outline),
          title: const Text('No Active Job'),
          subtitle: const Text('Start a production job to see live details.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openHomeTool('production'),
        ),
      );
    }

    final countyState = [job.county.trim(), job.state.trim()]
        .where((item) => item.isNotEmpty)
        .join(', ');
    final started = job.startedAt;
    final startedText = started == null
        ? '--'
        : TimeOfDay.fromDateTime(started).format(context);
    final workflow = job.workflow.trim().isEmpty
        ? 'Production'
        : job.workflow.trim()[0].toUpperCase() +
            job.workflow.trim().substring(1);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF14181D),
        border: Border.all(color: const Color(0xFF3A3122)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openHomeTool('production'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ACTIVE JOB',
                style: TextStyle(
                  color: Color(0xFF7BDE5A),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                job.company.trim().isEmpty ? 'Job Active' : job.company.trim(),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.02,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                job.padName.trim().isEmpty
                    ? job.primaryWell.trim()
                    : job.padName.trim(),
                style: const TextStyle(
                  fontSize: 19,
                  color: Color(0xFFCDA56A),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  if (countyState.isNotEmpty)
                    _jobMetaChip(
                      icon: Icons.place,
                      text: countyState,
                    ),
                  _jobMetaChip(
                    icon: Icons.precision_manufacturing,
                    text: workflow,
                  ),
                  _jobMetaChip(
                    icon: Icons.schedule,
                    text: 'Started $startedText',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _jobMetaChip({
    required IconData icon,
    required String text,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFFCDA56A)),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
              color: Colors.white70, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _recentlyUsedSection() {
    final recents = _recentTools
        .where((item) => _recentMeta(item.toolId) != null)
        .toList(growable: false);

    if (recents.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Text(
            'RECENTLY USED',
            style: TextStyle(
              color: Color(0xFFCDA56A),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              final entry = recents[index];
              final meta = _recentMeta(entry.toolId)!;
              return SizedBox(
                width: 188,
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openHomeTool(entry.toolId),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(meta.icon, color: const Color(0xFFCDA56A)),
                          const SizedBox(height: 8),
                          Text(meta.title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(meta.subtitle,
                              style: const TextStyle(color: Colors.white70)),
                          const Spacer(),
                          Text(
                            _timeAgoLabel(entry.lastUsedMs),
                            style: const TextStyle(
                              color: Color(0xFFCDA56A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemCount: recents.length,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _weatherGpsCard() {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF14181D),
        border: Border.all(color: const Color(0xFF3A3122)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.wb_sunny_outlined,
                        color: Color(0xFFCDA56A), size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Job Weather & GPS',
                        style: TextStyle(
                          color: Color(0xFFCDA56A),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh Weather & GPS',
                      onPressed: _weatherLoading ? null : _refreshWeatherAndGps,
                      icon: _weatherLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                    ),
                  ],
                ),
                Text(_weatherSummary,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Wind $_windSummary',
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 2),
                Text(_locationSummary,
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 2),
                Text('GPS $_gpsSummary',
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _HomeRecentItem? _recentForTool(String toolId) {
    final normalized = toolId.trim().toLowerCase();
    for (final item in _recentTools) {
      if (item.toolId == normalized) return item;
    }
    return null;
  }

  List<String> _suggestedFavoriteIds() {
    final defaults = <String>['production', 'rate', 'charts'];
    final candidateIds = <String>[];

    for (final item in _recentTools) {
      if (_recentMeta(item.toolId) == null) continue;
      if (!_favoriteToolChoices.contains(item.toolId)) continue;
      if (!candidateIds.contains(item.toolId)) {
        candidateIds.add(item.toolId);
      }
      if (candidateIds.length == _maxFavorites) break;
    }

    for (final fallback in defaults) {
      if (candidateIds.length == _maxFavorites) break;
      if (!candidateIds.contains(fallback)) {
        candidateIds.add(fallback);
      }
    }
    return candidateIds;
  }

  List<String> _resolvedFavoriteIds() {
    if (_favoriteToolIds.isNotEmpty) {
      return _favoriteToolIds
          .where(_favoriteToolChoices.contains)
          .take(_maxFavorites)
          .toList(growable: false);
    }
    return _suggestedFavoriteIds();
  }

  Future<void> _openFavoritesEditor() async {
    final selected = List<String>.from(_resolvedFavoriteIds());

    final updated = await showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final available = _favoriteToolChoices
                .where((id) => !selected.contains(id))
                .toList(growable: false);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Edit Favorites',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose up to $_maxFavorites and drag to reorder.',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 220,
                      child: ReorderableListView.builder(
                        itemCount: selected.length,
                        onReorder: (oldIndex, newIndex) {
                          setSheetState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = selected.removeAt(oldIndex);
                            selected.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final id = selected[index];
                          final meta = _recentMeta(id)!;
                          return ListTile(
                            key: ValueKey('fav-$id'),
                            leading:
                                Icon(meta.icon, color: const Color(0xFFCDA56A)),
                            title: Text(meta.title),
                            subtitle: Text(meta.subtitle),
                            trailing: IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                setSheetState(() {
                                  selected.removeAt(index);
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add Tool',
                      style: TextStyle(
                        color: Color(0xFFCDA56A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in available)
                          ActionChip(
                            label: Text(_recentMeta(id)?.title ?? id),
                            onPressed: selected.length >= _maxFavorites
                                ? null
                                : () {
                                    setSheetState(() {
                                      selected.add(id);
                                    });
                                  },
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              Navigator.of(sheetContext)
                                  .pop(selected.take(_maxFavorites).toList());
                            },
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || updated == null) return;
    setState(() {
      _favoriteToolIds = updated;
    });
    await _saveFavoriteTools();
  }

  Widget _favoritesRow() {
    final candidateIds = _resolvedFavoriteIds();

    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: candidateIds.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final toolId = candidateIds[index];
          final meta = _recentMeta(toolId)!;
          final recent = _recentForTool(toolId);
          return SizedBox(
            width: 174,
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openHomeTool(toolId),
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(meta.icon, color: const Color(0xFFCDA56A), size: 29),
                      const SizedBox(height: 10),
                      Text(
                        meta.title,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(meta.subtitle,
                          style: const TextStyle(color: Colors.white70)),
                      const Spacer(),
                      Text(
                        recent == null
                            ? 'Favorite'
                            : _timeAgoLabel(recent.lastUsedMs),
                        style: const TextStyle(
                          color: Color(0xFFCDA56A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _favoritesHeaderRow() {
    return Row(
      children: [
        const Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(2, 4, 2, 9),
            child: Text(
              'FAVORITES',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: _openFavoritesEditor,
          child: const Text(
            'Edit',
            style: TextStyle(
              color: Color(0xFFCDA56A),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _moduleGrid() {
    final tiles = <({
      String id,
      String title,
      String subtitle,
      IconData icon,
      VoidCallback onTap,
    })>[
      (
        id: 'production',
        title: 'Production',
        subtitle: 'Quick Round, reports, and setup',
        icon: Icons.oil_barrel,
        onTap: () => _openHomeTool('production'),
      ),
      (
        id: 'completions',
        title: 'Completions',
        subtitle: 'Drillout workflow and calculators',
        icon: Icons.build,
        onTap: () => _openHomeTool('completions'),
      ),
      (
        id: 'rigup',
        title: 'Rig-Up',
        subtitle: 'Layout, inventory, and history',
        icon: Icons.account_tree,
        onTap: () => _openHomeTool('rigup'),
      ),
      (
        id: 'rate',
        title: 'Rate Calculator',
        subtitle: 'Run multiple tank calculators',
        icon: Icons.speed,
        onTap: () => _openHomeTool('rate'),
      ),
      (
        id: 'jsa',
        title: 'JSA',
        subtitle: 'Safety worksheet and signatures',
        icon: Icons.assignment,
        onTap: () => _openHomeTool('jsa'),
      ),
      (
        id: 'charts',
        title: 'Charts',
        subtitle: 'Tank and field references',
        icon: Icons.bar_chart,
        onTap: () => _openHomeTool('charts'),
      ),
      (
        id: 'history',
        title: 'History',
        subtitle: 'Archived jobs and records',
        icon: Icons.history,
        onTap: () => _openHomeTool('history'),
      ),
      (
        id: 'settings',
        title: 'Settings',
        subtitle: 'Preferences and themes',
        icon: Icons.settings,
        onTap: () => open(context, const SettingsScreen()),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.98,
      ),
      itemBuilder: (context, index) {
        final tile = tiles[index];
        final recent = _recentForTool(tile.id);
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: tile.onTap,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(tile.icon, color: const Color(0xFFCDA56A), size: 28),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: Color(0x887F8B97),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    tile.title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tile.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    recent == null ? 'Open' : _timeAgoLabel(recent.lastUsedMs),
                    style: const TextStyle(
                      color: Color(0xFFCDA56A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bottomNavShell() {
    Widget navItem({
      required IconData icon,
      required String label,
      bool active = false,
    }) {
      final color = active ? const Color(0xFFCDA56A) : Colors.white60;
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1116),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2D3C4D)),
      ),
      child: Row(
        children: [
          navItem(icon: Icons.home, label: 'Home', active: true),
          navItem(icon: Icons.work_outline, label: 'Jobs'),
          navItem(icon: Icons.add_box_outlined, label: 'New Job'),
          navItem(icon: Icons.forum_outlined, label: 'Updates'),
          navItem(icon: Icons.person_outline, label: 'Profile'),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 9),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFCDA56A),
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(showBack: false),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppHeader(
        showBack: false,
        trailingActions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => open(context, const SettingsScreen()),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'settings') {
                open(context, const SettingsScreen());
                return;
              }
              if (value == 'about') {
                open(context, const AboutSupportScreen());
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'settings',
                child: Text('Settings'),
              ),
              PopupMenuItem(
                value: 'about',
                child: Text('About & Support'),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0B0D), Color(0xFF10141A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          children: [
            _activeJobCard(),
            _recentlyUsedSection(),
            _favoritesHeaderRow(),
            _favoritesRow(),
            const SizedBox(height: 8),
            _sectionLabel('MODULES'),
            _moduleGrid(),
            const SizedBox(height: 6),
            _weatherGpsCard(),
            _bottomNavShell(),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }
}
