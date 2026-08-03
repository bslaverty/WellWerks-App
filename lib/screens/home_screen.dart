import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/job_setup.dart';
import '../widgets/app_header.dart';
import '../services/app_settings_service.dart';
import '../services/job_storage_service.dart';
import '../services/operations_log_service.dart';
import '../services/rate_timer_notification_service.dart';
import '../services/rate_timer_service.dart';
import '../services/recovery_state_service.dart';
import 'module_menu_screen.dart';
import 'completions_dashboard_screen.dart';
import 'conversion_calculator_screen.dart';
import 'rate_calculator_screen.dart';
import 'equipment_layout_screen.dart';
import 'rig_up_inventory_screen.dart';
import 'rig_up_history_screen.dart';
import 'jsa_screen.dart';
import 'production_dashboard_screen.dart';
import 'production_history_screen.dart';
import 'chart_reference_screen.dart';
import 'tank_charts_menu_screen.dart';
import 'settings_screen.dart';
import 'about_support_screen.dart';
import 'drillout_cleanout_module_screen.dart';
import 'flywheel_diesel_tank_screen.dart';
import 'operations_log_screen.dart';
import 'rig_up_dashboard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();
  final _rateTimerService = RateTimerService();
  final _settingsService = AppSettingsService();
  final _rateTimerNotifications = RateTimerNotificationService.instance;

  bool _loading = true;
  bool _weatherLoading = false;
  String? _weatherTemp;
  String? _weatherSummary;
  String? _weatherWind;
  String? _weatherCoordKey;
  DateTime? _weatherFetchedAt;
  Timer? _weatherRefreshTimer;
  static const Duration _weatherRefreshInterval = Duration(hours: 1);

  @override
  void initState() {
    super.initState();
    _jobStorage.activeJobListenable.addListener(_handleActiveJobChanged);
    _startWeatherRefreshTicker();
    _loadRecovery();
  }

  @override
  void dispose() {
    _jobStorage.activeJobListenable.removeListener(_handleActiveJobChanged);
    _weatherRefreshTimer?.cancel();
    super.dispose();
  }

  void _startWeatherRefreshTicker() {
    _weatherRefreshTimer?.cancel();
    _weatherRefreshTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _loadPinnedWeatherForActiveJob();
    });
  }

  void _handleActiveJobChanged() {
    if (!mounted) return;
    setState(() {});
    _loadPinnedWeatherForActiveJob();
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
    _loadPinnedWeatherForActiveJob();
    _handlePendingRateTimerAction();
    _handlePendingEstimatedStsAction();
  }

  JobSetup? get _activeJob => _jobStorage.activeJobListenable.value;

  (String, String)? _activeJobCoordinates() {
    final activeJob = _activeJob;
    if (activeJob == null) return null;
    final setup = activeJob.drilloutSetup;
    final latitude = (setup['locationLatitude'] ?? '').toString().trim().isEmpty
        ? (setup['gpsLatitude'] ?? setup['latitude'] ?? '').toString().trim()
        : (setup['locationLatitude'] ?? '').toString().trim();
    final longitude = (setup['locationLongitude'] ?? '')
            .toString()
            .trim()
            .isEmpty
        ? (setup['gpsLongitude'] ?? setup['longitude'] ?? '').toString().trim()
        : (setup['locationLongitude'] ?? '').toString().trim();
    if (latitude.isEmpty || longitude.isEmpty) return null;
    return (latitude, longitude);
  }

  String _weatherCodeLabel(int code) {
    if (code == 0) return 'Clear';
    if (code <= 3) return 'Cloudy';
    if (code == 45 || code == 48) return 'Fog';
    if (code >= 51 && code <= 67) return 'Drizzle/Rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Showers';
    if (code >= 95) return 'Storm';
    return 'Weather';
  }

  String _formatCoordinateLabel(String raw, {required bool latitude}) {
    final value = double.tryParse(raw);
    if (value == null) return raw;
    final abs = value.abs().toStringAsFixed(4);
    final suffix =
        latitude ? (value >= 0 ? 'N' : 'S') : (value >= 0 ? 'E' : 'W');
    return '$abs° $suffix';
  }

  Future<void> _loadPinnedWeatherForActiveJob(
      {bool forceRefresh = false}) async {
    final coordinates = _activeJobCoordinates();
    if (coordinates == null) {
      if (!mounted) return;
      setState(() {
        _weatherCoordKey = null;
        _weatherLoading = false;
        _weatherTemp = null;
        _weatherSummary = null;
        _weatherWind = null;
        _weatherFetchedAt = null;
      });
      return;
    }

    final latitude = coordinates.$1;
    final longitude = coordinates.$2;
    final key = '$latitude,$longitude';
    final hasFreshWeatherForPinnedLocation = _weatherCoordKey == key &&
        _weatherFetchedAt != null &&
        DateTime.now().difference(_weatherFetchedAt!) < _weatherRefreshInterval;

    if (_weatherLoading ||
        (!forceRefresh && hasFreshWeatherForPinnedLocation)) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _weatherCoordKey = key;
      _weatherLoading = true;
    });

    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': latitude,
        'longitude': longitude,
        'current': 'temperature_2m,weather_code,wind_speed_10m',
        'temperature_unit': 'fahrenheit',
        'wind_speed_unit': 'mph',
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw StateError('Weather request failed.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Weather payload was invalid.');
      }
      final current = decoded['current'];
      if (current is! Map<String, dynamic>) {
        throw const FormatException('Weather values missing.');
      }
      final temperature = (current['temperature_2m'] as num?)?.toDouble();
      final weatherCode = (current['weather_code'] as num?)?.toInt();
      final wind = (current['wind_speed_10m'] as num?)?.toDouble();

      if (!mounted) return;
      setState(() {
        _weatherTemp =
            temperature == null ? null : '${temperature.toStringAsFixed(0)}°F';
        _weatherSummary =
            weatherCode == null ? 'Weather' : _weatherCodeLabel(weatherCode);
        _weatherWind =
            wind == null ? null : 'Wind ${wind.toStringAsFixed(0)} mph';
        _weatherFetchedAt = DateTime.now();
        _weatherLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _weatherTemp = null;
        _weatherSummary = 'Weather unavailable';
        _weatherWind = null;
        _weatherFetchedAt = DateTime.now();
        _weatherLoading = false;
      });
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
    if (!mounted) return;
    switch (toolId) {
      case 'production':
        await open(context, const ProductionDashboardScreen());
        return;
      case 'completions':
        await open(
          context,
          const CompletionsDashboardScreen(),
        );
        return;
      case 'rigup':
        await open(context, const RigUpDashboardScreen());
        return;
      case 'rate':
        await open(
          context,
          const RateCalculatorScreen(
            config: RateCalculatorConfig.chart(
              'V-Bottom',
              'flowback500',
              storageId: 'production_flowback500',
              allowOperationsLogAutoSave: false,
              rateLogEnabledByDefault: true,
            ),
            homeMultiMode: true,
            availableConfigs: kProductionRateCalculatorConfigs,
          ),
        );
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

  Widget _weatherGpsCard() {
    final scheme = Theme.of(context).colorScheme;
    final coordinates = _activeJobCoordinates();
    final latitude = coordinates?.$1 ?? '';
    final longitude = coordinates?.$2 ?? '';
    final coordinatesText = coordinates == null ? '' : '$latitude, $longitude';
    final canCopy = coordinatesText.isNotEmpty;
    final weatherPrimary =
        _weatherLoading ? 'Loading...' : (_weatherTemp ?? '--°F');
    final weatherSummary = _weatherSummary ?? 'Set job coordinates';
    final weatherWind =
        _weatherWind ?? (canCopy ? '' : 'Add coordinates in Job Setup');

    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).cardColor,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Icon(Icons.wb_sunny_outlined,
                      color: scheme.primary, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          weatherPrimary,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          weatherSummary,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (weatherWind.isNotEmpty)
                          Text(
                            weatherWind,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            VerticalDivider(
              width: 20,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.85),
            ),
            Expanded(
              flex: 4,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: !canCopy
                    ? null
                    : () async {
                        await Clipboard.setData(
                            ClipboardData(text: coordinatesText));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Coordinates copied.')),
                        );
                      },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.place_outlined,
                              color: scheme.primary, size: 20),
                          const SizedBox(width: 6),
                          Text(
                            'Coordinates',
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (canCopy) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.copy_outlined,
                              size: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        canCopy
                            ? _formatCoordinateLabel(latitude, latitude: true)
                            : 'No saved location',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        canCopy
                            ? _formatCoordinateLabel(longitude, latitude: false)
                            : 'Set in Job Setup',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: canCopy
                  ? () => _loadPinnedWeatherForActiveJob(forceRefresh: true)
                  : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              child: const Text('Job Weather'),
            ),
          ],
        ),
      ),
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
                    'Open',
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
