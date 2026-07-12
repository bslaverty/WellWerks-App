import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/job_setup.dart';
import '../services/active_company_service.dart';
import '../services/job_profile_defaults_service.dart';
import '../services/job_storage_service.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

class JobSetupScreen extends StatefulWidget {
  const JobSetupScreen({
    super.key,
    this.startFreshJob = false,
    this.editActiveOnOpen = false,
  });

  final bool startFreshJob;
  final bool editActiveOnOpen;

  @override
  State<JobSetupScreen> createState() => _JobSetupScreenState();
}

class _JobSetupScreenState extends State<JobSetupScreen> {
  final _storage = JobStorageService();
  final _profileDefaults = JobProfileDefaultsService();
  final _activeCompanyService = ActiveCompanyService.instance;
  final _page = PageController();
  Timer? _autoSaveTimer;

  int _step = 0;
  bool _loading = true;
  bool _editing = false;
  bool _startingFreshJob = false;
  JobSetup? _activeJob;

  String company = 'Mach Energy';
  String jobType = JobProfileDefaultsService.jobTypeSingleWell;
  List<String> wellFieldKeys = const [];
  List<String> activeEquipmentSections = const [];
  final selectedChemicals = <String>[];
  String shift = 'Day';
  final padName = TextEditingController();
  final notes = TextEditingController();
  final leaseName = TextEditingController();
  final county = TextEditingController();
  final state = TextEditingController(text: 'Oklahoma');
  final dateStarted = TextEditingController(
    text: DateFormat('MM/dd/yyyy').format(DateTime.now()),
  );
  final wellEntry = TextEditingController();
  final wells = <String>[];
  final wellIds = <String>[];

  final sandSeparators = TextEditingController(text: '2');
  final plugCatchers = TextEditingController(text: '1');
  final chokeManifolds = TextEditingController(text: '1');
  final lineHeaters = TextEditingController(text: '1');
  final testUnits = TextEditingController(text: '1');
  final ecds = TextEditingController(text: '1');
  final vrus = TextEditingController(text: '1');
  final flares = TextEditingController(text: '1');
  final transferPumps = TextEditingController(text: '1');

  final oilTanks = TextEditingController(text: '4');
  final oilTankCapacity = TextEditingController(text: '400');
  final waterTanks = TextEditingController(text: '6');
  final waterTankCapacity = TextEditingController(text: '500');
  final productionTankFactor = TextEditingController(text: '1.67');

  int _i(TextEditingController controller) {
    return int.tryParse(controller.text.trim()) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _attachAutoSaveListeners();
    _load();
  }

  List<TextEditingController> get _autoSaveControllers => [
        padName,
        notes,
        leaseName,
        county,
        state,
        dateStarted,
        wellEntry,
        sandSeparators,
        plugCatchers,
        chokeManifolds,
        lineHeaters,
        testUnits,
        ecds,
        vrus,
        flares,
        transferPumps,
        oilTanks,
        oilTankCapacity,
        waterTanks,
        waterTankCapacity,
        productionTankFactor,
      ];

  void _attachAutoSaveListeners() {
    for (final controller in _autoSaveControllers) {
      controller.addListener(_scheduleAutoSave);
    }
  }

  Future<void> _load() async {
    await _activeCompanyService.ensureLoaded();
    final active = await _storage.loadActiveJob();
    if (active != null) {
      _applyJobToForm(active);
    } else {
      final globalCompany = _activeCompanyService.activeCompany.value;
      if (globalCompany.trim().isNotEmpty) {
        company = globalCompany;
      }
    }

    if (!mounted) return;
    setState(() {
      _activeJob = active;
      _startingFreshJob = widget.startFreshJob;
      _editing =
          widget.startFreshJob || (widget.editActiveOnOpen && active != null);
      _loading = false;
    });

    if (widget.startFreshJob) {
      _resetFormForNewJob();
      if (mounted) {
        setState(() {
          _activeJob = null;
          _startingFreshJob = true;
          _editing = true;
          _step = 0;
        });
      }
      if (_page.hasClients) {
        _page.jumpToPage(0);
      }
      return;
    }

    if (widget.editActiveOnOpen && active != null) {
      if (_page.hasClients) {
        _page.jumpToPage(0);
      }
    }
  }

  void _scheduleAutoSave() {
    if (!_editing) return;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 500), () async {
      final saved = await _storage.saveActiveJob(_buildJobFromForm());
      if (!mounted) return;
      _activeJob = saved;
    });
  }

  void _applyJobToForm(JobSetup job) {
    company = _profileDefaults.normalizeCompany(job.company);
    jobType = _profileDefaults.normalizeJobType(job.jobType);
    final defaults = _profileDefaults.profileForCompany(company);
    wellFieldKeys = job.wellFieldKeys.isEmpty
        ? List<String>.from(defaults.wellFieldKeys)
        : List<String>.from(job.wellFieldKeys);
    activeEquipmentSections = job.activeEquipmentSections.isEmpty
        ? List<String>.from(defaults.defaultActiveSections)
        : List<String>.from(job.activeEquipmentSections);
    selectedChemicals
      ..clear()
      ..addAll(job.selectedChemicals);
    shift = job.shift;
    padName.text = job.padName;
    notes.text = job.notes;
    leaseName.text = job.leaseName;
    county.text = job.county;
    state.text = job.state;
    dateStarted.text = job.dateStarted.trim().isEmpty
        ? DateFormat('MM/dd/yyyy').format(DateTime.now())
        : job.dateStarted;
    wells
      ..clear()
      ..addAll(job.wells);
    wellIds
      ..clear()
      ..addAll(job.wellIds);
    while (wellIds.length < wells.length) {
      wellIds.add(JobSetup.generateWellId());
    }
    if (jobType == JobProfileDefaultsService.jobTypeSingleWell &&
        wells.length > 1) {
      wells.removeRange(1, wells.length);
      wellIds.removeRange(1, wellIds.length);
    }
    sandSeparators.text = job.sandSeparators.toString();
    plugCatchers.text = job.plugCatchers.toString();
    chokeManifolds.text = job.chokeManifolds.toString();
    lineHeaters.text = job.lineHeaters.toString();
    testUnits.text = job.testUnits.toString();
    ecds.text = job.ecds.toString();
    vrus.text = job.vrus.toString();
    flares.text = job.flares.toString();
    transferPumps.text = job.transferPumps.toString();
    oilTanks.text = job.oilTanks.toString();
    oilTankCapacity.text = job.oilTankCapacity;
    waterTanks.text = job.waterTanks.toString();
    waterTankCapacity.text = job.waterTankCapacity;
    productionTankFactor.text = job.productionTankFactor;
  }

  void _resetFormForNewJob() {
    final globalCompany = _activeCompanyService.activeCompany.value.trim();
    company = globalCompany.isEmpty ? 'Mach Energy' : globalCompany;
    jobType = JobProfileDefaultsService.jobTypeSingleWell;
    final defaults = _profileDefaults.profileForCompany(company);
    wellFieldKeys = List<String>.from(defaults.wellFieldKeys);
    activeEquipmentSections = List<String>.from(defaults.defaultActiveSections);
    selectedChemicals
      ..clear()
      ..addAll(JobSetup.chemicalOptions);
    shift = 'Day';
    padName.clear();
    notes.clear();
    leaseName.clear();
    county.clear();
    state.text = 'Oklahoma';
    dateStarted.text = DateFormat('MM/dd/yyyy').format(DateTime.now());
    wellEntry.clear();
    wells.clear();
    wellIds.clear();
    sandSeparators.text = '2';
    plugCatchers.text = '1';
    chokeManifolds.text = '1';
    lineHeaters.text = '1';
    testUnits.text = '1';
    ecds.text = '1';
    vrus.text = '1';
    flares.text = '1';
    transferPumps.text = '1';
    oilTanks.text = '4';
    oilTankCapacity.text = '400';
    waterTanks.text = '6';
    waterTankCapacity.text = '500';
    productionTankFactor.text = '1.67';
  }

  JobSetup _buildJobFromForm() {
    final normalizedPairs = <MapEntry<String, String>>[];
    for (int i = 0; i < wells.length; i++) {
      final name = wells[i].trim();
      if (name.isEmpty) continue;
      final id = i < wellIds.length && wellIds[i].trim().isNotEmpty
          ? wellIds[i].trim()
          : JobSetup.generateWellId();
      normalizedPairs.add(MapEntry(id, name));
    }
    final safePairs = jobType == JobProfileDefaultsService.jobTypeSingleWell
        ? (normalizedPairs.isEmpty
            ? const <MapEntry<String, String>>[]
            : <MapEntry<String, String>>[normalizedPairs.first])
        : normalizedPairs;
    final safeWells = [for (final item in safePairs) item.value];
    final safeWellEntries = [
      for (final item in safePairs)
        JobSetupWell(
          id: item.key,
          name: item.value,
        ),
    ];

    return JobSetup(
      company: company,
      jobType: jobType,
      customer: safeWells.isEmpty ? '' : safeWells.first,
      padName: padName.text.trim(),
      notes: notes.text.trim(),
      leaseName: leaseName.text.trim(),
      county: county.text.trim(),
      state: state.text.trim(),
      shift: shift,
      dateStarted: dateStarted.text.trim(),
      status: _activeJob?.status ?? 'active',
      id: _activeJob?.id ?? '',
      startedAt: _activeJob?.startedAt,
      endedAt: _activeJob?.endedAt,
      wells: safeWells,
      wellEntries: safeWellEntries,
      wellFieldKeys: List<String>.from(wellFieldKeys),
      activeEquipmentSections: List<String>.from(activeEquipmentSections),
      sandSeparators: _i(sandSeparators),
      plugCatchers: _i(plugCatchers),
      chokeManifolds: _i(chokeManifolds),
      lineHeaters: _i(lineHeaters),
      testUnits: _i(testUnits),
      ecds: _i(ecds),
      vrus: _i(vrus),
      flares: _i(flares),
      transferPumps: _i(transferPumps),
      oilTanks: _i(oilTanks),
      oilTankCapacity: oilTankCapacity.text.trim(),
      waterTanks: _i(waterTanks),
      waterTankCapacity: waterTankCapacity.text.trim(),
      productionTankFactor: productionTankFactor.text.trim().isEmpty
          ? '1.67'
          : productionTankFactor.text.trim(),
      selectedChemicals: List<String>.from(selectedChemicals),
    );
  }

  void _next() {
    if (_step >= 4) return;
    setState(() => _step++);
    _page.animateToPage(
      _step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _backStep() {
    if (_step == 0) return;
    setState(() => _step--);
    _page.animateToPage(
      _step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _startJobSetup() {
    _resetFormForNewJob();
    setState(() {
      _activeJob = null;
      _startingFreshJob = true;
      _editing = true;
      _step = 0;
    });
    if (_page.hasClients) {
      _page.jumpToPage(0);
    }
  }

  void _editActiveJob() {
    final active = _activeJob;
    if (active == null) return;

    _applyJobToForm(active);
    setState(() {
      _startingFreshJob = false;
      _editing = true;
      _step = 0;
    });
    if (_page.hasClients) {
      _page.jumpToPage(0);
    }
  }

  Future<void> _save() async {
    final isStartingNewJob = _startingFreshJob || _activeJob == null;
    final job = _buildJobFromForm();
    final saved = isStartingNewJob
        ? await _storage.saveActiveJob(job)
        : await _storage.updateActiveJob(job);

    if (!mounted) return;
    setState(() {
      _activeJob = saved;
      _startingFreshJob = false;
      _editing = false;
      _step = 0;
    });
    if (_page.hasClients) {
      _page.jumpToPage(0);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            isStartingNewJob ? 'Active job started' : 'Active job updated'),
      ),
    );
  }

  Future<void> _confirmEndJob() async {
    final active = _activeJob;
    if (active == null) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('End Active Job?'),
            content: Text(
              'This will mark ${active.primaryWell.isEmpty ? 'the current job' : active.primaryWell} as ended and remove it from Active Job.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('End Job'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    final ended = await _storage.endActiveJob();
    if (!mounted || ended == null) return;

    _applyJobToForm(ended);
    setState(() {
      _activeJob = null;
      _startingFreshJob = false;
      _editing = false;
      _step = 0;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Active job ended')));
  }

  Widget _navButtons({bool finish = false}) {
    return Row(
      children: [
        if (_step > 0)
          Expanded(
            child: OutlinedButton(
              onPressed: _backStep,
              child: const Text('Back'),
            ),
          ),
        if (_step > 0) const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: finish ? _save : _next,
            child: Text(
              finish
                  ? (_startingFreshJob ? 'Start Job' : 'Save Active Job')
                  : 'Next',
            ),
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime? value) {
    if (value == null) return 'Not started';
    return DateFormat('MM/dd/yyyy h:mm a').format(value);
  }

  String _displayValue(String value, {String fallback = 'Not entered'}) {
    return value.trim().isEmpty ? fallback : value.trim();
  }

  Widget _buildOverviewValue(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFCDA56A),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 17)),
        ],
      ),
    );
  }

  Widget _buildNoActiveJobView() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No Active Job',
                  style: TextStyle(
                    color: Color(0xFFCDA56A),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Start a job to keep the current company, pad, well, shift, and notes active on this device.',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _startJobSetup,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Job'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveJobView(JobSetup job) {
    final defaults = _profileDefaults.profileForCompany(job.company);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Active Job',
                        style: TextStyle(
                          color: Color(0xFFCDA56A),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Chip(label: Text(job.status.toUpperCase())),
                  ],
                ),
                const SizedBox(height: 16),
                _buildOverviewValue('Company', _displayValue(job.company)),
                _buildOverviewValue(
                  'Job Type',
                  _profileDefaults.jobTypeLabel(job.jobType),
                ),
                _buildOverviewValue('Pad', _displayValue(job.padName)),
                _buildOverviewValue(
                  'Well(s)',
                  job.wells.isEmpty ? 'Not entered' : job.wells.join(', '),
                ),
                _buildOverviewValue(
                  'Chemicals',
                  job.selectedChemicals.isEmpty
                      ? 'Not selected'
                      : job.selectedChemicals.join(', '),
                ),
                _buildOverviewValue(
                  'Active Sections',
                  job.activeEquipmentSections.isEmpty
                      ? defaults.defaultActiveSections.join(', ')
                      : job.activeEquipmentSections.join(', '),
                ),
                _buildOverviewValue('Shift', _displayValue(job.shift)),
                _buildOverviewValue('Date', _displayValue(job.dateStarted)),
                _buildOverviewValue('Started', _formatTimestamp(job.startedAt)),
                _buildOverviewValue('Notes', _displayValue(job.notes)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _editActiveJob,
                    icon: const Icon(Icons.edit),
                    label: const Text('Update Active Job'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _confirmEndJob,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('End Job'),
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
  void dispose() {
    _autoSaveTimer?.cancel();
    _page.dispose();
    for (final controller in _autoSaveControllers) {
      controller.removeListener(_scheduleAutoSave);
    }
    for (final controller in _autoSaveControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Job Setup', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppHeader(
        title: _editing
            ? (_startingFreshJob ? 'Start Job' : 'Edit Active Job')
            : (_activeJob == null ? 'Job Setup' : 'Active Job'),
        showBack: true,
      ),
      body: _editing
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                  child: LinearProgressIndicator(value: (_step + 1) / 5),
                ),
                Expanded(
                  child: PageView(
                    controller: _page,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _StepPage(title: '1. Company', children: [
                        InputDecorator(
                          decoration:
                              const InputDecoration(labelText: 'Company'),
                          child:
                              Text(company.trim().isEmpty ? 'None' : company),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: jobType,
                          decoration:
                              const InputDecoration(labelText: 'Job Type'),
                          items: const [
                            DropdownMenuItem(
                              value:
                                  JobProfileDefaultsService.jobTypeSingleWell,
                              child: Text('Single Well'),
                            ),
                            DropdownMenuItem(
                              value:
                                  JobProfileDefaultsService.jobTypeMultiWellPad,
                              child: Text('Multi-Well / Pad'),
                            ),
                          ],
                          onChanged: (value) {
                            final nextType = _profileDefaults.normalizeJobType(
                                value ??
                                    JobProfileDefaultsService
                                        .jobTypeSingleWell);
                            setState(() {
                              jobType = nextType;
                              if (jobType ==
                                      JobProfileDefaultsService
                                          .jobTypeSingleWell &&
                                  wells.length > 1) {
                                wells.removeRange(1, wells.length);
                                if (wellIds.length > 1) {
                                  wellIds.removeRange(1, wellIds.length);
                                }
                              }
                            });
                            _scheduleAutoSave();
                          },
                        ),
                        const SizedBox(height: 14),
                        const SizedBox(height: 20),
                        const Text(
                          'Company controls default labels/sections. Job Type controls one well vs multiple wells. Select active chemicals for Quick Round and reports.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 14),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Chemicals',
                            style: TextStyle(
                              color: Color(0xFFCDA56A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...JobSetup.chemicalOptions.map(
                          (chemical) => CheckboxListTile(
                            value: selectedChemicals.contains(chemical),
                            title: Text(chemical),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (enabled) {
                              setState(() {
                                if (enabled ?? false) {
                                  if (!selectedChemicals.contains(chemical)) {
                                    selectedChemicals.add(chemical);
                                  }
                                } else {
                                  selectedChemicals.remove(chemical);
                                }
                                if (selectedChemicals.isEmpty) {
                                  selectedChemicals.add('Biocide');
                                }
                              });
                              _scheduleAutoSave();
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Well Fields',
                            style: TextStyle(
                              color: Color(0xFFCDA56A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final field in wellFieldKeys)
                              Chip(
                                label: Text(field.toUpperCase()),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Active Equipment Sections',
                            style: TextStyle(
                              color: Color(0xFFCDA56A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._profileDefaults
                            .profileForCompany(company)
                            .optionalSections
                            .map(
                              (section) => CheckboxListTile(
                                value:
                                    activeEquipmentSections.contains(section),
                                title: Text(section),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                onChanged: (enabled) {
                                  setState(() {
                                    if (enabled ?? false) {
                                      if (!activeEquipmentSections
                                          .contains(section)) {
                                        activeEquipmentSections.add(section);
                                      }
                                    } else {
                                      activeEquipmentSections.remove(section);
                                    }
                                  });
                                  _scheduleAutoSave();
                                },
                              ),
                            ),
                        const SizedBox(height: 24),
                        _navButtons(),
                      ]),
                      _StepPage(title: '2. Job Info', children: [
                        TextField(
                          controller: padName,
                          decoration:
                              const InputDecoration(labelText: 'Pad Name'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: notes,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Notes (Optional)',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: leaseName,
                          decoration:
                              const InputDecoration(labelText: 'Lease Name'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: county,
                          decoration:
                              const InputDecoration(labelText: 'County'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: state,
                          decoration: const InputDecoration(labelText: 'State'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: shift,
                          decoration: const InputDecoration(labelText: 'Shift'),
                          items: const [
                            DropdownMenuItem(
                              value: 'Day',
                              child: Text('Day'),
                            ),
                            DropdownMenuItem(
                              value: 'Night',
                              child: Text('Night'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => shift = value ?? 'Day');
                            _scheduleAutoSave();
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: dateStarted,
                          decoration: const InputDecoration(labelText: 'Date'),
                        ),
                        const SizedBox(height: 24),
                        _navButtons(),
                      ]),
                      _StepPage(title: '3. Wells', children: [
                        if (jobType ==
                            JobProfileDefaultsService.jobTypeSingleWell)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text(
                              'Single Well selected. Add one well name.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text(
                              'Multi-Well / Pad selected. Add all well names for this pad.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: wellEntry,
                                decoration: const InputDecoration(
                                  labelText: 'Well Name',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton.filled(
                              onPressed: () {
                                final name = wellEntry.text.trim();
                                if (name.isEmpty) return;
                                if (jobType ==
                                        JobProfileDefaultsService
                                            .jobTypeSingleWell &&
                                    wells.isNotEmpty) {
                                  setState(() {
                                    wells[0] = name;
                                    if (wellIds.isEmpty) {
                                      wellIds.add(JobSetup.generateWellId());
                                    }
                                    wellEntry.clear();
                                  });
                                  _scheduleAutoSave();
                                  return;
                                }
                                setState(() {
                                  wells.add(name);
                                  wellIds.add(JobSetup.generateWellId());
                                  wellEntry.clear();
                                });
                                _scheduleAutoSave();
                              },
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (wells.isEmpty)
                          Text(
                            jobType ==
                                    JobProfileDefaultsService.jobTypeSingleWell
                                ? 'Add the active well name.'
                                : 'Add each well on this pad.',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        for (int i = 0; i < wells.length; i++)
                          Card(
                            child: ListTile(
                              title: Text(wells[i]),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () {
                                  setState(() {
                                    wells.removeAt(i);
                                    if (i < wellIds.length) {
                                      wellIds.removeAt(i);
                                    }
                                  });
                                  _scheduleAutoSave();
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                        _navButtons(),
                      ]),
                      _StepPage(title: '4. Equipment', children: [
                        _countField('Sand Separators', sandSeparators),
                        _countField('Plug Catchers', plugCatchers),
                        _countField('Choke Manifolds', chokeManifolds),
                        _countField('Line Heaters', lineHeaters),
                        _countField('Test Units', testUnits),
                        _countField('ECDs', ecds),
                        _countField('VRUs', vrus),
                        _countField('Flares', flares),
                        _countField('Transfer Pumps', transferPumps),
                        const SizedBox(height: 24),
                        _navButtons(),
                      ]),
                      _StepPage(title: '5. Tanks', children: [
                        _countField('Oil Tanks', oilTanks),
                        WwNumberField(
                          label: 'Oil Tank Capacity',
                          controller: oilTankCapacity,
                        ),
                        _countField('Water Tanks', waterTanks),
                        WwNumberField(
                          label: 'Water Tank Capacity',
                          controller: waterTankCapacity,
                        ),
                        WwNumberField(
                          label: 'Production Tank Factor (BBL/In)',
                          controller: productionTankFactor,
                          allowDecimal: true,
                        ),
                        const Text(
                          'Default tank factor stays 1.67 unless you change it.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 18),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              'Summary\n$company\n${_profileDefaults.jobTypeLabel(jobType)}\n${padName.text.trim().isEmpty ? 'No pad entered' : padName.text.trim()}\n${wells.length} well(s)\nChemicals: ${selectedChemicals.join(', ')}\nSections: ${activeEquipmentSections.isEmpty ? 'None' : activeEquipmentSections.join(', ')}\n${_i(sandSeparators) + _i(plugCatchers) + _i(chokeManifolds) + _i(lineHeaters) + _i(testUnits) + _i(ecds) + _i(vrus) + _i(flares) + _i(transferPumps)} equipment item(s)\n${_i(oilTanks) + _i(waterTanks)} tank(s)',
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _navButtons(finish: true),
                      ]),
                    ],
                  ),
                ),
              ],
            )
          : (_activeJob == null
              ? _buildNoActiveJobView()
              : _buildActiveJobView(_activeJob!)),
    );
  }

  Widget _countField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WwNumberField(
        label: label,
        controller: controller,
        allowDecimal: false,
        onChanged: (_) => _scheduleAutoSave(),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFCDA56A),
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}
