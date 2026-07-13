import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:signature/signature.dart';

import '../models/job_setup.dart';
import '../models/jsa_draft.dart';
import '../models/jsa_template.dart';
import '../services/jsa_export_service.dart';
import '../services/active_company_service.dart';
import '../services/job_profile_defaults_service.dart';
import '../services/job_storage_service.dart';
import '../services/jsa_storage_service.dart';
import '../services/recovery_state_service.dart';
import '../services/app_settings_service.dart';
import '../widgets/app_header.dart';
import '../widgets/jsa_history_pane.dart';

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
  png,
  savePngToPhotos,
}

class _JsaScreenState extends State<JsaScreen>
    with SingleTickerProviderStateMixin {
  Color get gold => Theme.of(context).colorScheme.primary;

  final _storage = JsaStorageService();
  final _exportService = const JsaExportService();
  final _jobStorage = JobStorageService();
  final _recoveryState = RecoveryStateService();
  final _exportImageKey = GlobalKey();
  final _location = TextEditingController();
  final _county = TextEditingController();
  final _cityState = TextEditingController();
  final _gpsCoordinates = TextEditingController();
  final _notes = TextEditingController();
  final _weatherTemperature = TextEditingController();
  final _weatherConditions = TextEditingController();
  final _weatherWind = TextEditingController();
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
  JsaDraft? _exportPreviewDraft;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  bool _exporting = false;
  bool _weatherLoading = false;
  Position? _currentPosition;
  final _settingsService = AppSettingsService();
  final _activeCompanyService = ActiveCompanyService.instance;
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
        _applyDraft(draft);
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
      if (loaded.jsaAutoTime) {
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
    _county.clear();
    _cityState.clear();
    _gpsCoordinates.clear();
    _notes.clear();
    _weatherTemperature.clear();
    _weatherConditions.clear();
    _weatherWind.clear();
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
    _county.text = draft.county;
    _cityState.text = draft.cityState;
    _gpsCoordinates.text = draft.gpsCoordinates;
    _notes.text = draft.notes;
    _weatherTemperature.text = draft.weatherTemperature;
    _weatherConditions.text = draft.weatherConditions;
    _weatherWind.text = draft.weatherWind;
    _stepsEditor.text = _editorTextFromLines(draft.steps);
    _hazardsEditor.text = _editorTextFromLines(draft.hazards);
    _recommendationsEditor.text = _editorTextFromLines(draft.recommendations);
    _date = DateTime.tryParse(draft.date) ?? _date;
    final parts = draft.time.split(':');
    if (parts.length >= 2) {
      _time = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? _time.hour,
        minute: int.tryParse(parts[1]) ?? _time.minute,
      );
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
    _county.dispose();
    _cityState.dispose();
    _gpsCoordinates.dispose();
    _notes.dispose();
    _weatherTemperature.dispose();
    _weatherConditions.dispose();
    _weatherWind.dispose();
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
    final picked = await showTimePicker(context: context, initialTime: _time);
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
      time:
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      location: _location.text.trim(),
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
    );
  }

  Future<JsaDraft> _saveDraft({bool showFeedback = true}) async {
    final draft = await _buildDraft();
    await _storage.saveDraft(draft);
    _exportPreviewDraft = draft;
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
              const Text(
                'No active job found. Start a job first so this JSA can save under the current job.',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

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
            const SizedBox(height: 8),
            const Text(
              'JSA will save under this active job.',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List?> _captureExportImageBytes(JsaDraft draft) async {
    setState(() => _exportPreviewDraft = draft);
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    final boundary = _exportImageKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      return null;
    }
    final image = await boundary.toImage(pixelRatio: 2.5);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _shareSend() async {
    if (_exporting) return;

    final canSaveToPhotos =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    final format = await showDialog<_JsaShareFormat>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share As'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(_JsaShareFormat.pdf),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(_JsaShareFormat.png),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Image (PNG)'),
              ),
            ),
            if (canSaveToPhotos) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context)
                      .pop(_JsaShareFormat.savePngToPhotos),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Save Image to Photos'),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (format == null) return;

    setState(() => _exporting = true);
    try {
      final draft = await _buildDraft();
      _exportPreviewDraft = draft;

      if (format == _JsaShareFormat.pdf) {
        final exported = await _exportService.exportPdf(
          draft: draft,
          activeJob: _activeJob,
        );
        await _shareFile(
          exported,
          successMessage: 'JSA PDF ready to share.',
        );
      } else if (format == _JsaShareFormat.png) {
        final imageBytes = await _captureExportImageBytes(draft);
        if (imageBytes == null) {
          throw StateError('Unable to capture JSA image.');
        }
        final exported = await _exportService.exportImage(
          draft: draft,
          pngBytes: imageBytes,
        );
        await _shareFile(
          exported,
          successMessage: 'JSA image ready to share.',
        );
      } else {
        await _saveImageToPhotos(draft);
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

  Future<void> _saveImageToPhotos(JsaDraft draft) async {
    final imageBytes = await _captureExportImageBytes(draft);
    if (imageBytes == null) {
      throw StateError('Unable to capture JSA image.');
    }

    final now = DateTime.now();
    final name =
        'wellwerks_jsa_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final result = await ImageGallerySaver.saveImage(
      imageBytes,
      quality: 100,
      name: name,
    );

    final map = result is Map ? result : <String, dynamic>{};
    final dynamic raw = map['isSuccess'] ?? map['success'];
    final success = raw == true || raw == 1 || raw?.toString() == 'true';
    if (!success) {
      throw StateError('Unable to save image to Photos.');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('JSA image saved to Photos.')),
    );
  }

  Future<void> _shareFile(
    ExportedJsaFile exported, {
    required String successMessage,
  }) async {
    final box = context.findRenderObject() as RenderBox?;
    final shareOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);

    final lowerName = exported.fileName.toLowerCase();
    final mimeType = lowerName.endsWith('.png')
        ? 'image/png'
        : (lowerName.endsWith('.pdf') ? 'application/pdf' : null);
    final isImage = mimeType == 'image/png';
    final fileToShare = mimeType == null
        ? XFile(exported.filePath)
        : XFile(exported.filePath, mimeType: mimeType);

    await Share.shareXFiles(
      [fileToShare],
      subject: isImage ? null : 'WellWerks JSA',
      text: isImage ? null : 'JSA exported from WellWerks.',
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
    final timeText = _time.format(context);

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
              icon: const Icon(Icons.copy),
              tooltip: 'Copy GPS Coordinates',
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
                    'Built-in JSA template structure. Final approved safety content will be added in a future build.',
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
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              Material(
                color: Theme.of(context).colorScheme.surface,
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
          Positioned(
            left: -5000,
            top: 0,
            child: IgnorePointer(
              child: RepaintBoundary(
                key: _exportImageKey,
                child: SizedBox(
                  width: 900,
                  child: _exportPreviewCard(_exportPreviewDraft),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exportPreviewCard(JsaDraft? draft) {
    final selectedType = _currentJsaTypeLabel;
    final exportDraft = draft ??
        JsaDraft(
          activeJobId: _activeJob?.id ?? '',
          templateId: _selectedTemplateId,
          templateName: _selectedTemplateName,
          company: _company,
          date: _draftDateKey,
          time:
              '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
          location: _location.text.trim(),
          county: _county.text.trim(),
          cityState: _cityState.text.trim(),
          gpsCoordinates: _gpsCoordinates.text.trim(),
          task: selectedType,
          tasks: <String>[selectedType],
          steps: _steps,
          hazards: _hazards,
          recommendations: _recommendations,
          employees: const [],
          notes: _notes.text.trim(),
          weatherTemperature: _weatherTemperature.text.trim(),
          weatherConditions: _weatherConditions.text.trim(),
          weatherWind: _weatherWind.text.trim(),
        );

    return Material(
      color: const Color(0xFF111111),
      child: Container(
        padding: const EdgeInsets.all(24),
        color: const Color(0xFF111111),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WellWerks JSA',
              style: TextStyle(
                color: gold,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              exportDraft.company.trim(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            _exportPreviewSection('Job Information', [
              _previewLine('Date', exportDraft.date),
              _previewLine('Time', exportDraft.time),
              _previewLine(
                'JSA Type',
                exportDraft.templateName.trim().isEmpty
                    ? (exportDraft.task.trim().isEmpty
                        ? 'General'
                        : exportDraft.task.trim())
                    : exportDraft.templateName.trim(),
              ),
              _previewLine('Company', exportDraft.company),
              _previewLine('Location / Pad', exportDraft.location),
              _previewLine('County', exportDraft.county),
              _previewLine('City, State', exportDraft.cityState),
              _previewLine('GPS Coordinates', exportDraft.gpsCoordinates),
              _previewLine('Temperature', exportDraft.weatherTemperature),
              _previewLine('Wind', exportDraft.weatherWind),
              _previewLine('Conditions', exportDraft.weatherConditions),
            ]),
            _exportPreviewSection(
                'Selected Steps', _previewBullets(exportDraft.tasks)),
            _exportPreviewSection(
                'Basic Steps', _previewBullets(exportDraft.steps)),
            _exportPreviewSection(
                'Hazards', _previewBullets(exportDraft.hazards)),
            _exportPreviewSection(
              'Recommendations',
              _previewBullets(exportDraft.recommendations),
            ),
            _exportPreviewSection('Employees & Signatures', [
              if (exportDraft.employees
                  .where((employee) =>
                      employee.name.trim().isNotEmpty ||
                      employee.company.trim().isNotEmpty ||
                      (employee.signaturePngBase64 ?? '').trim().isNotEmpty)
                  .isEmpty)
                const Text(
                  'No employees entered.',
                  style: TextStyle(color: Colors.white70),
                ),
              for (final employee in exportDraft.employees)
                if (employee.name.trim().isNotEmpty ||
                    employee.company.trim().isNotEmpty ||
                    (employee.signaturePngBase64 ?? '').trim().isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.name.trim().isEmpty
                              ? 'Unnamed employee'
                              : employee.name.trim(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          employee.company.trim().isEmpty
                              ? 'Company not entered'
                              : employee.company.trim(),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        if ((employee.signaturePngBase64 ?? '')
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            height: 90,
                            width: 220,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: _signatureImage(employee.signaturePngBase64),
                          ),
                        ],
                      ],
                    ),
                  ),
            ]),
            _exportPreviewSection('Notes / Comments', [
              Text(
                exportDraft.notes.trim(),
                style: const TextStyle(color: Colors.white70),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _exportPreviewSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF17130E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: gold,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  List<Widget> _previewBullets(List<String> items) {
    final visibleItems = items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (visibleItems.isEmpty) {
      return const [
        Text('None entered.', style: TextStyle(color: Colors.white70)),
      ];
    }
    return visibleItems
        .map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child:
                Text('• $item', style: const TextStyle(color: Colors.white70)),
          ),
        )
        .toList();
  }

  Widget _previewLine(String label, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: gold,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: trimmed,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signatureImage(String? base64Value) {
    try {
      final bytes = base64Decode(base64Value ?? '');
      return Image.memory(bytes, fit: BoxFit.contain);
    } catch (_) {
      return const SizedBox.shrink();
    }
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
                      backgroundColor: const Color(0xFF111111)),
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
