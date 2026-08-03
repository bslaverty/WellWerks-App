import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/job_setup.dart';
import '../models/jsa_draft.dart';
import '../models/jsa_template.dart';
import '../services/jsa_export_service.dart';
import '../services/active_company_service.dart';
import '../services/active_workflow_mode_service.dart';
import '../services/job_profile_defaults_service.dart';
import '../services/job_storage_service.dart';
import '../services/jsa_storage_service.dart';
import '../services/recovery_state_service.dart';
import '../services/app_settings_service.dart';
import '../utils/jsa_time_format.dart';
import '../widgets/app_header.dart';
import '../widgets/jsa_history_pane.dart';
import '../widgets/time_wheel_picker_sheet.dart';

class JsaScreen extends StatefulWidget {
  const JsaScreen({
    super.key,
    this.initialActiveJobId,
    this.initialDate,
  });

  final String? initialActiveJobId;
  final String? initialDate;

  @override
  State<JsaScreen> createState() => _JsaScreenState();
}

enum _JsaShareFormat {
  pdf,
  pageImages,
}

class _JsaExportDialogResult {
  const _JsaExportDialogResult({
    required this.format,
    required this.baseFileName,
  });

  final _JsaShareFormat format;
  final String baseFileName;
}

class _JsaScreenState extends State<JsaScreen>
    with SingleTickerProviderStateMixin {
  Color get gold => Theme.of(context).colorScheme.primary;

  final _storage = JsaStorageService();
  final _exportService = JsaExportService();
  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();
  final _location = TextEditingController();
  final _wellName = TextEditingController();
  final _county = TextEditingController();
  final _cityState = TextEditingController();
  final _gpsCoordinates = TextEditingController();
  final _notes = TextEditingController();
  final _weatherTemperature = TextEditingController();
  final _weatherConditions = TextEditingController();
  final _weatherWind = TextEditingController();
  final _emergencyHospitalName = TextEditingController();
  final _emergencyHospitalAddress = TextEditingController();
  final _stepsEditor = TextEditingController();
  final _hazardsEditor = TextEditingController();
  final _recommendationsEditor = TextEditingController();

  final _employeeNames = List.generate(6, (_) => TextEditingController());
  final _employeeCompanies = List.generate(6, (_) => TextEditingController());
  final _signatures = List.generate(
    6,
    (_) => SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.white,
      exportBackgroundColor: const Color(0xFF111111),
    ),
  );

  String _company = JobProfileDefaultsService.companyNone;
  String _selectedTemplateId = '';
  String _selectedTemplateName = '';
  JobSetup? _activeJob;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  bool _exporting = false;
  bool _weatherLoading = false;
  bool _hospitalLoading = false;
  Position? _currentPosition;
  String _emergencyHospitalCoordinates = '';
  bool _emergencyHospitalIsManual = false;
  bool _hasLoadedDraft = false;
  final _settingsService = AppSettingsService();
  final _activeCompanyService = ActiveCompanyService.instance;
  final _workflowModeService = ActiveWorkflowModeService.instance;
  late final TabController _tabController;
  late AppSettingsData _settings;

  static const List<Tab> _tabs = <Tab>[
    Tab(text: 'Current JSA'),
    Tab(text: 'Templates'),
    Tab(text: 'History'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _settings = const AppSettingsData(
      defaultGasUnit: AppSettingsDefaults.gasUnit,
      defaultGaugeType: AppSettingsDefaults.gaugeType,
      defaultBblPerInch: AppSettingsDefaults.bblPerInch,
      defaultGasCalculationMethod: AppSettingsDefaults.gasCalculationMethod,
      defaultChokeDisplay: AppSettingsDefaults.chokeDisplay,
      defaultOptionalReportSections: AppSettingsDefaults.optionalReportSections,
      productionActiveJobDefaults:
          AppSettingsDefaults.productionActiveJobDefaults,
      productionReportLayout: AppSettingsDefaults.productionReportLayout,
      productionTextUpdateLayout:
          AppSettingsDefaults.productionTextUpdateLayout,
      completionsRateDisplayDefault:
          AppSettingsDefaults.completionsRateDisplayDefault,
      completionsTimerDefaultMinutes:
          AppSettingsDefaults.completionsTimerDefaultMinutes,
      jsaAutoDate: AppSettingsDefaults.jsaAutoDate,
      jsaAutoTime: AppSettingsDefaults.jsaAutoTime,
      jsaAutoLocation: AppSettingsDefaults.jsaAutoLocation,
      jsaAutoWeather: AppSettingsDefaults.jsaAutoWeather,
      jsaCompanyDefault: AppSettingsDefaults.jsaCompanyDefault,
      layoutInventoryMode: AppSettingsDefaults.layoutInventoryMode,
      layoutDefaultEquipment: AppSettingsDefaults.layoutDefaultEquipment,
      chartsChloridesDefault: AppSettingsDefaults.chartsChloridesDefault,
      chartsUnits: AppSettingsDefaults.chartsUnits,
      historyRetentionDays: AppSettingsDefaults.historyRetentionDays,
      historyExportMode: AppSettingsDefaults.historyExportMode,
      appNotifications: AppSettingsDefaults.appNotifications,
      appTheme: AppSettingsDefaults.appTheme,
    );
    _recoveryState.saveLastModule(RecoveryModules.jsa);
    _loadDraft();
    _loadSettingsAndAutoFill();
  }

  Future<void> _loadDraft() async {
    final requestedJobId = widget.initialActiveJobId?.trim() ?? '';
    final requestedDate = widget.initialDate?.trim() ?? '';
    final liveActiveJob = await _jobStorage.loadActiveJob();
    final targetJob = requestedJobId.isNotEmpty
        ? await _jobStorage.loadJobById(requestedJobId)
        : liveActiveJob;
    final workflow = _resolveWorkflowFromJob(
      targetJob,
      await _workflowModeService.ensureLoaded(),
    );
    final draft = requestedJobId.isNotEmpty || requestedDate.isNotEmpty
        ? await _storage.loadDraft(
            activeJobId: requestedJobId,
            date: requestedDate,
          )
        : (targetJob != null
            ? await _storage.loadTodayForJob(targetJob.id)
            : await _storage.loadDraft());
    if (!mounted) return;
    setState(() {
      _activeJob = targetJob;
      _clearFormValues(resetDateTime: false);
      if (draft != null) {
        _hasLoadedDraft = true;
        _applyDraft(draft);
      } else {
        _applyActiveJobDefaults(targetJob, workflow);
      }
      if (targetJob != null) {
        final normalized =
            JobProfileDefaultsService().normalizeCompany(targetJob.company);
        if (normalized != JobProfileDefaultsService.companyNone) {
          _company = normalized;
        }
      }
    });
  }

  void _applyActiveJobDefaults(
    JobSetup? targetJob,
    ActiveWorkflowMode workflow,
  ) {
    if (targetJob != null) {
      final normalizedCompany =
          JobProfileDefaultsService().normalizeCompany(targetJob.company);
      if (normalizedCompany != JobProfileDefaultsService.companyNone) {
        _company = normalizedCompany;
      }
      final pad = targetJob.padName.trim();
      if (pad.isNotEmpty) {
        _location.text = pad;
      }
      final well = targetJob.primaryWell.trim();
      if (well.isNotEmpty) {
        _wellName.text = well;
      }
      if (_county.text.trim().isEmpty && targetJob.county.trim().isNotEmpty) {
        _county.text = targetJob.county.trim();
      }
      if (_cityState.text.trim().isEmpty && targetJob.state.trim().isNotEmpty) {
        _cityState.text = targetJob.state.trim();
      }

      final setup = targetJob.drilloutSetup;
      final latitude = (setup['locationLatitude'] ?? '')
              .toString()
              .trim()
              .isEmpty
          ? (setup['gpsLatitude'] ?? setup['latitude'] ?? '').toString().trim()
          : (setup['locationLatitude'] ?? '').toString().trim();
      final longitude =
          (setup['locationLongitude'] ?? '').toString().trim().isEmpty
              ? (setup['gpsLongitude'] ?? setup['longitude'] ?? '')
                  .toString()
                  .trim()
              : (setup['locationLongitude'] ?? '').toString().trim();
      if (latitude.isNotEmpty && longitude.isNotEmpty) {
        final pinnedCoordinates = '$latitude, $longitude';
        if (_gpsCoordinates.text.trim().isEmpty || _settings.jsaAutoLocation) {
          _gpsCoordinates.text = pinnedCoordinates;
        }
      }
    }

    if (workflow == ActiveWorkflowMode.production) {
      return;
    }

    if (_stepsEditor.text.trim().isNotEmpty ||
        _hazardsEditor.text.trim().isNotEmpty ||
        _recommendationsEditor.text.trim().isNotEmpty) {
      return;
    }

    if (workflow == ActiveWorkflowMode.cleanout) {
      _selectedTemplateId = 'cleanout_default';
      _selectedTemplateName = 'Cleanout';
      _stepsEditor.text = _editorTextFromLines(const [
        'STEP 1',
        '• Review cleanout plan and communication roles',
        'STEP 2',
        '• Verify iron-up, pump path, and containment',
        'STEP 3',
        '• Monitor pressure, returns, and tank levels during cleanout',
      ]);
      _hazardsEditor.text = _editorTextFromLines(const [
        'STEP 1',
        '• High pressure and stored energy',
        'STEP 2',
        '• Pressurized fluid release and slippery surfaces',
        'STEP 3',
        '• Unexpected plugging, vibration, and equipment movement',
      ]);
      _recommendationsEditor.text = _editorTextFromLines(const [
        'STEP 1',
        '• Confirm line of fire controls and stop-work triggers',
        'STEP 2',
        '• Open/close valves slowly and verify flow path',
        'STEP 3',
        '• Isolate and bleed pressure before troubleshooting',
      ]);
      return;
    }

    final drillout = JsaBuiltInTemplates.byId('drillout');
    if (drillout != null) {
      _selectedTemplateId = drillout.id;
      _selectedTemplateName = drillout.name;
      _stepsEditor.text = _editorTextFromLines(drillout.basicJobSteps);
      _hazardsEditor.text = _editorTextFromLines(drillout.hazards);
      _recommendationsEditor.text =
          _editorTextFromLines(drillout.recommendedActions);
    }
  }

  ActiveWorkflowMode _resolveWorkflowFromJob(
    JobSetup? job,
    ActiveWorkflowMode fallback,
  ) {
    final raw = (job?.workflow ?? '').trim().toLowerCase();
    if (raw == 'drillout') return ActiveWorkflowMode.drillout;
    if (raw == 'cleanout') return ActiveWorkflowMode.cleanout;
    return fallback;
  }

  Future<void> _loadSettingsAndAutoFill() async {
    final loaded = await _settingsService.load();
    final activeCompany = await _activeCompanyService.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _settings = loaded;
      _company = activeCompany == JobProfileDefaultsService.companyNone
          ? ''
          : activeCompany;
      if (loaded.jsaAutoDate) {
        _date = DateTime.now();
      }
      if (loaded.jsaAutoTime && !_hasLoadedDraft) {
        _time = TimeOfDay.now();
      }
    });

    if (loaded.jsaAutoLocation || loaded.jsaAutoWeather) {
      await _refreshLocationWeather();
    }
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

  String _formatGpsCoordinates(Position position) {
    return '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
  }

  String _formatCoordinates(double lat, double lon) {
    return '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
  }

  ({double lat, double lon})? _parseCoordinates(String raw) {
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lon = double.tryParse(parts[1].trim());
    if (lat == null || lon == null) return null;
    return (lat: lat, lon: lon);
  }

  String _composeHospitalAddress(Map<String, dynamic> tags) {
    final lineParts = <String>[];
    final houseNumber = (tags['addr:housenumber'] ?? '').toString().trim();
    final street = (tags['addr:street'] ?? '').toString().trim();
    final city =
        (tags['addr:city'] ?? tags['addr:town'] ?? tags['addr:village'] ?? '')
            .toString()
            .trim();
    final state = (tags['addr:state'] ?? '').toString().trim();
    final postcode = (tags['addr:postcode'] ?? '').toString().trim();

    final streetLine =
        [houseNumber, street].where((item) => item.isNotEmpty).join(' ').trim();
    if (streetLine.isNotEmpty) lineParts.add(streetLine);

    final cityState =
        [city, state].where((item) => item.isNotEmpty).join(', ').trim();
    if (cityState.isNotEmpty) {
      if (postcode.isNotEmpty) {
        lineParts.add('$cityState $postcode');
      } else {
        lineParts.add(cityState);
      }
    } else if (postcode.isNotEmpty) {
      lineParts.add(postcode);
    }

    return lineParts.join(' • ');
  }

  bool _isHospitalOrEmergencyDepartment(Map<String, dynamic> tags) {
    final amenity = (tags['amenity'] ?? '').toString().trim().toLowerCase();
    final healthcare =
        (tags['healthcare'] ?? '').toString().trim().toLowerCase();
    final emergency = (tags['emergency'] ?? '').toString().trim().toLowerCase();

    if (amenity == 'hospital') return true;
    if (healthcare == 'hospital') return true;
    if (emergency == 'department' || emergency == 'hospital') return true;
    return false;
  }

  Future<void> _refreshNearestHospital({
    Position? position,
    bool forceReplace = true,
    bool showFeedbackOnFailure = true,
  }) async {
    if (_hospitalLoading) return;
    setState(() => _hospitalLoading = true);

    try {
      final anchor = position ?? _currentPosition ?? await _ensurePosition();
      _currentPosition = anchor;

      final overpassQuery = '''
[out:json][timeout:20];
(
  nwr(around:50000,${anchor.latitude},${anchor.longitude})["amenity"="hospital"];
  nwr(around:50000,${anchor.latitude},${anchor.longitude})["healthcare"="hospital"];
  nwr(around:50000,${anchor.latitude},${anchor.longitude})["emergency"="department"];
  nwr(around:50000,${anchor.latitude},${anchor.longitude})["emergency"="hospital"];
);
out center tags;
''';

      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'User-Agent': 'WellWerks/1.0',
        },
        body: 'data=${Uri.encodeQueryComponent(overpassQuery)}',
      );

      if (response.statusCode != 200) {
        throw StateError('Unable to fetch hospital data.');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = (decoded['elements'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      final candidates = <({
        String name,
        String address,
        String coordinates,
        double distance,
      })>[];

      for (final element in elements) {
        final tags = (element['tags'] as Map?) == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(element['tags'] as Map);
        if (!_isHospitalOrEmergencyDepartment(tags)) continue;

        final lat = (element['lat'] as num?)?.toDouble() ??
            (element['center'] is Map
                ? ((element['center'] as Map)['lat'] as num?)?.toDouble()
                : null);
        final lon = (element['lon'] as num?)?.toDouble() ??
            (element['center'] is Map
                ? ((element['center'] as Map)['lon'] as num?)?.toDouble()
                : null);
        if (lat == null || lon == null) continue;

        final name = (tags['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        final distance = Geolocator.distanceBetween(
          anchor.latitude,
          anchor.longitude,
          lat,
          lon,
        );

        candidates.add((
          name: name,
          address: _composeHospitalAddress(tags),
          coordinates: _formatCoordinates(lat, lon),
          distance: distance,
        ));
      }

      if (candidates.isEmpty) {
        if (showFeedbackOnFailure && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('No nearby hospital or emergency department found.'),
            ),
          );
        }
        return;
      }

      candidates.sort((a, b) => a.distance.compareTo(b.distance));
      final nearest = candidates.first;

      if (!forceReplace && _emergencyHospitalIsManual) {
        return;
      }

      _emergencyHospitalName.text = nearest.name;
      _emergencyHospitalAddress.text = nearest.address;
      _emergencyHospitalCoordinates = nearest.coordinates;
      _emergencyHospitalIsManual = false;
      if (mounted) {
        setState(() {});
      }
    } catch (err) {
      if (showFeedbackOnFailure && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to refresh emergency hospital: $err')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _hospitalLoading = false);
      }
    }
  }

  Future<void> _openHospitalDirections() async {
    final name = _emergencyHospitalName.text.trim();
    final address = _emergencyHospitalAddress.text.trim();
    final coords = _parseCoordinates(_emergencyHospitalCoordinates);

    if (name.isEmpty && address.isEmpty && coords == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No emergency hospital destination set.')),
      );
      return;
    }

    final destinationLabel =
        [name, address].where((item) => item.isNotEmpty).join(', ').trim();

    final googleDestination =
        coords == null ? destinationLabel : '${coords.lat},${coords.lon}';
    final googleUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(googleDestination)}',
    );

    Uri? appleUri;
    if (Platform.isIOS) {
      final appleDestination =
          coords == null ? destinationLabel : '${coords.lat},${coords.lon}';
      appleUri = Uri.parse(
        'https://maps.apple.com/?daddr=${Uri.encodeComponent(appleDestination)}&dirflg=d',
      );
    }

    bool launched = false;
    if (appleUri != null) {
      launched = await launchUrl(
        appleUri,
        mode: LaunchMode.externalApplication,
      );
    }
    if (!launched) {
      launched = await launchUrl(
        googleUri,
        mode: LaunchMode.externalApplication,
      );
    }

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open directions app.')),
      );
    }
  }

  String _countyFromAddress(Map<String, dynamic> address) {
    return (address['county'] ?? address['state_district'] ?? '')
        .toString()
        .trim();
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

  Future<void> _copyGpsCoordinates() async {
    try {
      final current = _gpsCoordinates.text.trim();
      final fallbackPosition = _currentPosition ?? await _ensurePosition();
      _currentPosition = fallbackPosition;
      final textToCopy = current.isNotEmpty
          ? current
          : _formatGpsCoordinates(fallbackPosition);
      if (current.isEmpty) {
        _gpsCoordinates.text = textToCopy;
      }
      await Clipboard.setData(
        ClipboardData(text: textToCopy),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GPS coordinates copied to clipboard.')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to copy GPS coordinates: $err')),
      );
    }
  }

  Future<void> _refreshLocationWeather() async {
    if (_weatherLoading) return;
    setState(() => _weatherLoading = true);
    try {
      final position = await _ensurePosition();
      _currentPosition = position;

      final reverseUri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${position.latitude}&lon=${position.longitude}&addressdetails=1',
      );
      final reverseResponse = await http.get(
        reverseUri,
        headers: const {'User-Agent': 'WellWerks/1.0'},
      );
      final coordsText = _formatGpsCoordinates(position);
      if (_settings.jsaAutoLocation || _gpsCoordinates.text.trim().isEmpty) {
        _gpsCoordinates.text = coordsText;
      }
      if (reverseResponse.statusCode == 200) {
        final reverseMap =
            jsonDecode(reverseResponse.body) as Map<String, dynamic>;
        final address = reverseMap['address'] as Map<String, dynamic>?;
        final countyText = address == null ? '' : _countyFromAddress(address);
        final cityStateText =
            address == null ? '' : _cityStateFromAddress(address);
        if (_settings.jsaAutoLocation || _county.text.trim().isEmpty) {
          _county.text = countyText;
        }
        if (_settings.jsaAutoLocation || _cityState.text.trim().isEmpty) {
          _cityState.text = cityStateText;
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

      _weatherTemperature.text =
          temperature == null ? '' : '${temperature.toStringAsFixed(1)} F';
      _weatherConditions.text =
          weatherCode == null ? '' : _weatherConditionFromCode(weatherCode);
      _weatherWind.text =
          windSpeed == null ? '' : '${windSpeed.toStringAsFixed(1)} mph';

      await _refreshNearestHospital(
        position: position,
        forceReplace: !_emergencyHospitalIsManual,
        showFeedbackOnFailure: false,
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to refresh weather: $err')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _weatherLoading = false);
      }
    }
  }

  String get _draftDateKey => DateFormat('yyyy-MM-dd').format(_date);

  List<String> _linesFromEditor(TextEditingController controller) {
    return controller.text
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _editorTextFromLines(List<String> items) {
    return items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join('\n');
  }

  List<String> get _steps => _linesFromEditor(_stepsEditor);
  List<String> get _hazards => _linesFromEditor(_hazardsEditor);
  List<String> get _recommendations => _linesFromEditor(_recommendationsEditor);

  String get _currentJsaTypeLabel {
    final selected = _selectedTemplateName.trim();
    if (selected.isNotEmpty) {
      return selected;
    }
    return 'General';
  }

  bool get _hasCurrentJobContent {
    return _steps.isNotEmpty ||
        _hazards.isNotEmpty ||
        _recommendations.isNotEmpty;
  }

  void _clearFormValues({required bool resetDateTime}) {
    _location.clear();
    _wellName.clear();
    _county.clear();
    _cityState.clear();
    _gpsCoordinates.clear();
    _notes.clear();
    _weatherTemperature.clear();
    _weatherConditions.clear();
    _weatherWind.clear();
    _emergencyHospitalName.clear();
    _emergencyHospitalAddress.clear();
    _emergencyHospitalCoordinates = '';
    _emergencyHospitalIsManual = false;
    _stepsEditor.clear();
    _hazardsEditor.clear();
    _recommendationsEditor.clear();
    _selectedTemplateId = '';
    _selectedTemplateName = '';
    for (final controller in _employeeNames) {
      controller.clear();
    }
    for (final controller in _employeeCompanies) {
      controller.clear();
    }
    for (final signature in _signatures) {
      signature.clear();
    }
    final activeCompany = _activeCompanyService.activeCompany.value;
    _company = activeCompany.trim().isNotEmpty
        ? (activeCompany == JobProfileDefaultsService.companyNone
            ? ''
            : activeCompany)
        : '';
    if (resetDateTime) {
      _date = DateTime.now();
      _time = TimeOfDay.now();
    }
  }

  void _applyDraft(JsaDraft draft) {
    final activeCompany = _activeCompanyService.activeCompany.value;
    _company = activeCompany == JobProfileDefaultsService.companyNone
        ? ''
        : activeCompany;
    _selectedTemplateId = draft.templateId.trim();
    _selectedTemplateName = draft.templateName.trim();
    _location.text = draft.location;
    _wellName.text = draft.wellName;
    _county.text = draft.county;
    _cityState.text = draft.cityState;
    _gpsCoordinates.text = draft.gpsCoordinates;
    _notes.text = draft.notes;
    _weatherTemperature.text = draft.weatherTemperature;
    _weatherConditions.text = draft.weatherConditions;
    _weatherWind.text = draft.weatherWind;
    _emergencyHospitalName.text = draft.emergencyHospitalName;
    _emergencyHospitalAddress.text = draft.emergencyHospitalAddress;
    _emergencyHospitalCoordinates = draft.emergencyHospitalCoordinates;
    _emergencyHospitalIsManual = draft.emergencyHospitalIsManual;
    _stepsEditor.text = _editorTextFromLines(draft.steps);
    _hazardsEditor.text = _editorTextFromLines(draft.hazards);
    _recommendationsEditor.text = _editorTextFromLines(draft.recommendations);
    _date = DateTime.tryParse(draft.date) ?? _date;
    final parsedTime = parseJsaTime(draft.time);
    if (parsedTime != null) {
      _time = parsedTime;
    }
    for (var i = 0; i < draft.employees.length && i < 6; i++) {
      final employee = draft.employees[i];
      _employeeNames[i].text = employee.name;
      _employeeCompanies[i].text = employee.company;
      if (employee.signaturePoints.isNotEmpty) {
        _signatures[i].points = employee.signaturePoints
            .map(
              (point) => Point(
                Offset(point.x, point.y),
                point.type == 'move' ? PointType.move : PointType.tap,
                point.pressure,
              ),
            )
            .toList();
        _signatures[i].pushCurrentStateToUndoStack();
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _location.dispose();
    _wellName.dispose();
    _county.dispose();
    _cityState.dispose();
    _gpsCoordinates.dispose();
    _notes.dispose();
    _weatherTemperature.dispose();
    _weatherConditions.dispose();
    _weatherWind.dispose();
    _emergencyHospitalName.dispose();
    _emergencyHospitalAddress.dispose();
    _stepsEditor.dispose();
    _hazardsEditor.dispose();
    _recommendationsEditor.dispose();
    for (final controller in _employeeNames) {
      controller.dispose();
    }
    for (final controller in _employeeCompanies) {
      controller.dispose();
    }
    for (final controller in _signatures) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimeWheelPickerSheet(
      context,
      initialTime: _time,
    );
    if (picked != null) {
      setState(() => _time = picked);
    }
  }

  Future<JsaDraft> _buildDraft() async {
    final employees = <JsaEmployee>[];
    for (var i = 0; i < 6; i++) {
      final png = await _signatures[i].toPngBytes();
      employees.add(JsaEmployee(
        name: _employeeNames[i].text.trim(),
        company: _employeeCompanies[i].text.trim(),
        signaturePngBase64: png == null ? null : base64Encode(png),
        signaturePoints: _signatures[i]
            .points
            .map(
              (point) => JsaSignaturePoint(
                x: point.offset.dx,
                y: point.offset.dy,
                type: point.type == PointType.move ? 'move' : 'tap',
                pressure: point.pressure,
              ),
            )
            .toList(),
      ));
    }
    final selectedType = _currentJsaTypeLabel;
    return JsaDraft(
      activeJobId: _activeJob?.id ?? '',
      templateId: _selectedTemplateId,
      templateName: _selectedTemplateName,
      company: _company,
      date: DateFormat('yyyy-MM-dd').format(_date),
      time: formatJsaTime(_time),
      location: _location.text.trim(),
      wellName: _wellName.text.trim(),
      county: _county.text.trim(),
      cityState: _cityState.text.trim(),
      gpsCoordinates: _gpsCoordinates.text.trim(),
      task: selectedType,
      tasks: <String>[selectedType],
      steps: _steps,
      hazards: _hazards,
      recommendations: _recommendations,
      employees: employees,
      notes: _notes.text.trim(),
      weatherTemperature: _weatherTemperature.text.trim(),
      weatherConditions: _weatherConditions.text.trim(),
      weatherWind: _weatherWind.text.trim(),
      emergencyHospitalName: _emergencyHospitalName.text.trim(),
      emergencyHospitalAddress: _emergencyHospitalAddress.text.trim(),
      emergencyHospitalCoordinates: _emergencyHospitalCoordinates.trim(),
      emergencyHospitalIsManual: _emergencyHospitalIsManual,
    );
  }

  Future<JsaDraft> _saveDraft({bool showFeedback = true}) async {
    final draft = await _buildDraft();
    await _storage.saveDraft(draft);
    if (!mounted) return draft;
    if (showFeedback) {
      final persisted = await _storage.loadDraft(
        activeJobId: draft.activeJobId,
        date: draft.date,
      );
      if (!mounted) return draft;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            persisted != null
                ? 'Saved to JSA History.'
                : 'Unable to verify JSA in History. Please try again.',
          ),
        ),
      );
    }
    return draft;
  }

  Future<bool> _confirmTemplateReplace(String templateName) async {
    if (!_hasCurrentJobContent) {
      return true;
    }
    final decision = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace Current JSA Content?'),
        content: Text(
          'Using "$templateName" will replace current Basic Job Steps, Hazards, and Recommended Actions. '
          'Header/job information stays the same. Signatures are never copied from templates.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Use Template'),
          ),
        ],
      ),
    );
    return decision ?? false;
  }

  Future<void> _useTemplate(JsaTemplateDefinition template) async {
    final changingTemplate = _selectedTemplateId.trim() != template.id;
    if (changingTemplate) {
      final confirmed = await _confirmTemplateReplace(template.name);
      if (!confirmed || !mounted) {
        return;
      }
    }

    setState(() {
      _selectedTemplateId = template.id;
      _selectedTemplateName = template.name;
      _stepsEditor.text = _editorTextFromLines(template.basicJobSteps);
      _hazardsEditor.text = _editorTextFromLines(template.hazards);
      _recommendationsEditor.text =
          _editorTextFromLines(template.recommendedActions);
      _tabController.animateTo(0);
    });
    await _saveDraft(showFeedback: false);
  }

  Future<void> _openDraftFromHistory(JsaDraft draft) async {
    setState(() {
      _clearFormValues(resetDateTime: false);
      _applyDraft(draft);
      _tabController.animateTo(0);
    });
  }

  Widget _activeJobBanner() {
    final scheme = Theme.of(context).colorScheme;
    final activeJob = _activeJob;
    if (activeJob == null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Active Job',
                style: TextStyle(color: gold, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'No active job found. Start a job first so this JSA can save under the current job.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final bestIdentifier = activeJob.primaryWell.trim().isNotEmpty
        ? activeJob.primaryWell.trim()
        : (activeJob.padName.trim().isNotEmpty
            ? activeJob.padName.trim()
            : '-');
    final workflow = activeJob.workflow.trim().isEmpty
        ? ActiveWorkflowModeService.labelFor(_workflowModeService.mode.value)
        : '${activeJob.workflow[0].toUpperCase()}${activeJob.workflow.substring(1)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active Job',
              style: TextStyle(color: gold, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              activeJob.company.trim().isEmpty
                  ? 'No company entered'
                  : activeJob.company,
              style: TextStyle(color: gold, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              bestIdentifier,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$workflow • ${activeJob.shift.trim().isEmpty ? '-' : activeJob.shift.trim()} Shift',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              'JSA will save under this active job.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  String _defaultExportBaseName(JsaDraft draft) {
    return _exportService.suggestBaseFileName(draft);
  }

  Future<_JsaExportDialogResult?> _showExportDialog(String initialBaseName) {
    final controller = TextEditingController(text: initialBaseName);
    return showDialog<_JsaExportDialogResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export JSA'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('jsa-export-filename-field'),
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'File Name',
                helperText: 'Edit the base filename before exporting.',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('jsa-export-save-pdf'),
                onPressed: () {
                  Navigator.of(context).pop(
                    _JsaExportDialogResult(
                      format: _JsaShareFormat.pdf,
                      baseFileName: controller.text,
                    ),
                  );
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Save PDF'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('jsa-export-page-images'),
                onPressed: () {
                  Navigator.of(context).pop(
                    _JsaExportDialogResult(
                      format: _JsaShareFormat.pageImages,
                      baseFileName: controller.text,
                    ),
                  );
                },
                icon: const Icon(Icons.image_outlined),
                label: const Text('Export Page Images'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _shareSend() async {
    if (_exporting) return;

    final draft = await _buildDraft();
    if (!mounted) return;
    final exportRequest =
        await _showExportDialog(_defaultExportBaseName(draft));
    if (exportRequest == null) {
      return;
    }

    final baseName = exportRequest.baseFileName.trim();

    setState(() => _exporting = true);
    try {
      if (exportRequest.format == _JsaShareFormat.pdf) {
        final exported = await _exportService.exportPdf(
          draft: draft,
          activeJob: _activeJob,
          baseFileName: baseName,
        );
        await _shareFiles(
          <ExportedJsaFile>[exported],
          successMessage: 'JSA PDF ready to share.',
        );
      } else {
        final images = await _exportService.exportPageImages(
          draft: draft,
          activeJob: _activeJob,
          baseFileName: baseName,
        );
        await _shareFiles(
          images,
          successMessage: 'JSA page images ready to share.',
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Unable to export JSA. Check required fields and try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _shareFiles(
    List<ExportedJsaFile> exportedFiles, {
    required String successMessage,
  }) async {
    final box = context.findRenderObject() as RenderBox?;
    final shareOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);

    final filesToShare = exportedFiles.map((exported) {
      final lowerName = exported.fileName.toLowerCase();
      final mimeType = lowerName.endsWith('.png')
          ? 'image/png'
          : (lowerName.endsWith('.pdf') ? 'application/pdf' : null);
      return mimeType == null
          ? XFile(exported.filePath)
          : XFile(exported.filePath, mimeType: mimeType);
    }).toList();

    final isSinglePdf = filesToShare.length == 1 &&
        filesToShare.first.name.toLowerCase().endsWith('.pdf');

    await Share.shareXFiles(
      filesToShare,
      subject: isSinglePdf ? 'WellWerks JSA' : 'WellWerks JSA Page Images',
      text: isSinglePdf
          ? 'JSA exported from WellWerks.'
          : 'JSA page images exported from WellWerks.',
      sharePositionOrigin: shareOrigin,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(successMessage)),
    );
  }

  Future<void> _clearDraft() async {
    await _storage.deleteDraft(
      activeJobId: _activeJob?.id ?? '',
      date: _draftDateKey,
    );
    await _storage.clearDraft();
    if (!mounted) return;
    setState(() {
      _clearFormValues(resetDateTime: true);
    });
  }

  Widget _editableListSection({
    required String label,
    required TextEditingController controller,
    required String helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
        ),
      ),
    );
  }

  Widget _currentJsaTab() {
    final dateText = DateFormat('MM/dd/yyyy').format(_date);
    final timeText = formatJsaTime(_time);

    return ListView(
      key: const Key('jsa-current-tab'),
      padding: const EdgeInsets.all(18),
      children: [
        _activeJobBanner(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'JSA Type: $_currentJsaTypeLabel',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _section('Job Info'),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Company'),
          child: Text(_company.trim().isEmpty ? 'None' : _company),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _location,
          decoration: const InputDecoration(
            labelText: 'Location / Pad',
            helperText: 'Lease name, pad name, or job location',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _wellName,
          decoration: const InputDecoration(
            labelText: 'Well Name (optional)',
            helperText: 'Optional well identifier for exports and history.',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _pickDate,
                child: Text('Date: $dateText'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _pickTime,
                child: Text('Time: $timeText'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _county,
          readOnly: true,
          decoration: const InputDecoration(labelText: 'County'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _cityState,
          readOnly: true,
          decoration: const InputDecoration(labelText: 'City, State'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _gpsCoordinates,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'GPS Coordinates'),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: _copyGpsCoordinates,
              icon: const Icon(Icons.content_copy),
              tooltip: 'Copy GPS coordinates',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _weatherTemperature,
                decoration: const InputDecoration(labelText: 'Temperature'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _weatherWind,
                decoration: const InputDecoration(labelText: 'Wind'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _weatherConditions,
          decoration: const InputDecoration(labelText: 'Conditions'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _weatherLoading ? null : _refreshLocationWeather,
            icon: _weatherLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync_outlined),
            label: const Text('Refresh Weather'),
          ),
        ),
        const SizedBox(height: 18),
        _section('Emergency Information'),
        TextField(
          controller: _emergencyHospitalName,
          decoration: const InputDecoration(
            labelText: 'Nearest Hospital / ED',
            helperText:
                'Auto-filled from nearby hospital or emergency department. You can edit manually.',
          ),
          onChanged: (_) {
            if (!_emergencyHospitalIsManual) {
              setState(() => _emergencyHospitalIsManual = true);
            }
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emergencyHospitalAddress,
          decoration: const InputDecoration(
            labelText: 'Hospital Address',
            helperText: 'Optional destination details for navigation.',
          ),
          onChanged: (_) {
            if (!_emergencyHospitalIsManual) {
              setState(() => _emergencyHospitalIsManual = true);
            }
          },
        ),
        const SizedBox(height: 8),
        Text(
          _emergencyHospitalCoordinates.trim().isEmpty
              ? (_emergencyHospitalIsManual
                  ? 'Destination manually entered.'
                  : 'Destination coordinates unavailable.')
              : 'Destination coordinates: $_emergencyHospitalCoordinates',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: _hospitalLoading ? null : _openHospitalDirections,
              icon: const Icon(Icons.directions_outlined),
              label: const Text('Open Directions'),
            ),
            OutlinedButton.icon(
              onPressed: _hospitalLoading
                  ? null
                  : () => _refreshNearestHospital(forceReplace: true),
              icon: _hospitalLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.local_hospital_outlined),
              label: const Text('Refresh Hospital'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _section('JSA Job Content'),
        _editableListSection(
          label: 'Basic Job Steps',
          controller: _stepsEditor,
          helper: 'One step per line.',
        ),
        _editableListSection(
          label: 'Hazards',
          controller: _hazardsEditor,
          helper: 'One hazard per line.',
        ),
        _editableListSection(
          label: 'Recommended Actions',
          controller: _recommendationsEditor,
          helper: 'One recommended action per line.',
        ),
        _section('Notes'),
        TextField(
          controller: _notes,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Additional notes'),
        ),
        const SizedBox(height: 18),
        _section('Employees & Signatures'),
        for (var i = 0; i < 6; i++) _employeeCard(i),
        const SizedBox(height: 18),
        FilledButton.icon(
          key: const Key('jsa-save-button'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          onPressed: _exporting ? null : () => _saveDraft(),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          onPressed: _exporting ? null : _shareSend,
          icon: const Icon(Icons.share_outlined),
          label: const Text('Share / Send'),
        ),
        const SizedBox(height: 10),
        TextButton(onPressed: _clearDraft, child: const Text('Clear JSA')),
      ],
    );
  }

  Widget _templatesTab() {
    return ListView(
      key: const Key('jsa-templates-tab'),
      padding: const EdgeInsets.all(18),
      children: [
        for (final template in JsaBuiltInTemplates.all)
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Built-in approved JSA safety content. Loading a template replaces only Basic Job Steps, Hazards, and Recommended Actions.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: Key('use-template-${template.id}'),
                      onPressed: () => _useTemplate(template),
                      child: const Text('Use Template'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'JSA', showBack: true),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).cardColor,
            child: TabBar(
              key: const Key('jsa-tab-bar'),
              controller: _tabController,
              tabs: _tabs,
              isScrollable: false,
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _currentJsaTab(),
                _templatesTab(),
                JsaHistoryPane(
                  key: const Key('jsa-history-tab'),
                  onOpenDraft: _openDraftFromHistory,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title,
            style: TextStyle(
                color: gold, fontSize: 18, fontWeight: FontWeight.w800)),
      );

  Widget _employeeCard(int index) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Employee ${index + 1}',
                  style: TextStyle(color: gold, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextField(
                  controller: _employeeNames[index],
                  decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(
                  controller: _employeeCompanies[index],
                  decoration: const InputDecoration(labelText: 'Company')),
              const SizedBox(height: 12),
              Container(
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Signature(
                      controller: _signatures[index],
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => _signatures[index].clear(),
                    child: const Text('Clear Signature')),
              ),
            ],
          ),
        ),
      );
}
