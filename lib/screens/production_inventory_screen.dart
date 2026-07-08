import 'package:flutter/material.dart';

import '../models/production_shift.dart';
import '../services/app_settings_service.dart';
import '../services/job_history_service.dart';
import '../services/production_shift_service.dart';
import '../services/report_profile_service.dart';
import '../widgets/app_header.dart';
import '../widgets/ww_number_field.dart';

class ProductionInventoryScreen extends StatefulWidget {
  const ProductionInventoryScreen({
    super.key,
    this.embedded = false,
    this.showManageLayoutsButton = true,
  });

  final bool embedded;
  final bool showManageLayoutsButton;

  @override
  State<ProductionInventoryScreen> createState() =>
      _ProductionInventoryScreenState();
}

class _ProductionInventoryScreenState extends State<ProductionInventoryScreen> {
  final _service = ProductionShiftService();
  final _historyService = JobHistoryService();
  final _settingsService = AppSettingsService();
  final _layoutService = ReportProfileService();

  final _company = TextEditingController();
  final _pad = TextEditingController();
  final _date = TextEditingController();
  String _gaugeEntryType = 'inches';
  String _gasUnit = 'mcfd';
  String _gasCalculationMethod = 'accumulator';
  String _layoutProfileId = 'default';
  final _startingGasAccum = TextEditingController();
  final _waterHauledBeforeRound = TextEditingController();
  final _oilHauledBeforeRound = TextEditingController();
  final _waterPumpedBeforeRound = TextEditingController();
  final _oilPumpedBeforeRound = TextEditingController();

  final List<TextEditingController> _wellControllers = [];
  final List<String> _wellChokeTypes = [];
  final List<_TankControllers> _waterTanks = [];
  final List<_TankControllers> _oilTanks = [];
  final List<_OilInventoryControllers> _oilInventoryWells = [];
  List<ReportLayoutProfile> _layoutProfiles = const [];
  String _defaultBblPerInch = '1.67';
  String _defaultChokeDisplay = 'ADJ';

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _company,
      _pad,
      _date,
      _startingGasAccum,
      _waterHauledBeforeRound,
      _oilHauledBeforeRound,
      _waterPumpedBeforeRound,
      _oilPumpedBeforeRound,
    ]) {
      controller.dispose();
    }
    for (final controller in _wellControllers) {
      controller.dispose();
    }
    for (final tank in _waterTanks) {
      tank.dispose();
    }
    for (final tank in _oilTanks) {
      tank.dispose();
    }
    for (final well in _oilInventoryWells) {
      well.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final shift = await _service.loadActiveShift();
    final settings = await _settingsService.load();
    _layoutProfiles = await _layoutService.loadProfiles();
    final activeLayoutId = await _layoutService.loadActiveProfileId();
    _setFromShift(shift);
    _defaultBblPerInch = settings.defaultBblPerInch;
    _defaultChokeDisplay = settings.defaultChokeDisplay;
    if (_isEffectivelyEmptyShift(shift)) {
      _gaugeEntryType = settings.defaultGaugeType;
      _gasUnit = settings.defaultGasUnit;
      _gasCalculationMethod = settings.defaultGasCalculationMethod;
      for (var i = 0; i < _wellChokeTypes.length; i++) {
        _wellChokeTypes[i] = settings.defaultChokeDisplay;
      }
      for (final tank in [..._waterTanks, ..._oilTanks]) {
        tank.bblPerInch.text = settings.defaultBblPerInch;
      }
    }
    final requested = shift.header.layoutProfileId;
    _layoutProfileId = _layoutProfiles.any((p) => p.id == requested)
        ? requested
        : (_layoutProfiles.any((p) => p.id == activeLayoutId)
            ? activeLayoutId
            : _layoutProfiles.first.id);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  bool _isEffectivelyEmptyShift(ProductionShift shift) {
    return shift.header.company.trim().isEmpty &&
        shift.header.pad.trim().isEmpty &&
        shift.header.date.trim().isEmpty &&
        shift.savedRows.isEmpty &&
        shift.hourlyChecks.isEmpty &&
        shift.inventory.startingGasAccum.trim().isEmpty &&
        shift.inventory.oilInventoryWells.every((well) =>
            well.wellName.trim().isEmpty &&
            well.beginningOilInventory.trim().isEmpty &&
            well.currentOilInventory.trim().isEmpty &&
            well.expectedOilInventory.trim().isEmpty &&
            well.currentCushion.trim().isEmpty &&
            well.maximumCushion.trim().isEmpty);
  }

  void _setFromShift(ProductionShift shift) {
    _company.text = shift.header.company;
    _pad.text = shift.header.pad;
    _date.text =
        shift.header.date.trim().isEmpty ? _todayDateText() : shift.header.date;
    _gaugeEntryType = shift.inventory.gaugeEntryType;
    _gasUnit = shift.inventory.gasUnit;
    _gasCalculationMethod = shift.inventory.gasCalculationMethod;
    final requestedLayout = shift.header.layoutProfileId;
    if (_layoutProfiles.isNotEmpty) {
      _layoutProfileId = _layoutProfiles.any((p) => p.id == requestedLayout)
          ? requestedLayout
          : _layoutProfiles.first.id;
    }
    _startingGasAccum.text = shift.inventory.startingGasAccum;
    _waterHauledBeforeRound.text = shift.inventory.waterHauledBeforeRound;
    _oilHauledBeforeRound.text = shift.inventory.oilHauledBeforeRound;
    _waterPumpedBeforeRound.text = shift.inventory.waterPumpedBeforeRound;
    _oilPumpedBeforeRound.text = shift.inventory.oilPumpedBeforeRound;

    for (final controller in _wellControllers) {
      controller.dispose();
    }
    _wellControllers
      ..clear()
      ..addAll(
          (shift.header.wells.isEmpty ? const ['Well 1'] : shift.header.wells)
              .map((well) => TextEditingController(text: well)));
    _wellChokeTypes
      ..clear()
      ..addAll(
        (shift.header.wells.isEmpty ? const ['Well 1'] : shift.header.wells)
            .map(
          (well) => shift.header.wellChokeTypes[well] ?? shift.header.chokeType,
        ),
      );
    _defaultChokeDisplay = shift.header.chokeType;

    for (final tank in _waterTanks) {
      tank.dispose();
    }
    _waterTanks
      ..clear()
      ..addAll(shift.inventory.waterTanks.map(_TankControllers.fromTank));

    for (final tank in _oilTanks) {
      tank.dispose();
    }
    _oilTanks
      ..clear()
      ..addAll(shift.inventory.oilTanks.map(_TankControllers.fromTank));

    for (final well in _oilInventoryWells) {
      well.dispose();
    }
    _oilInventoryWells
      ..clear()
      ..addAll(
          _buildOilInventoryControllers(shift.inventory.oilInventoryWells));
  }

  List<_OilInventoryControllers> _buildOilInventoryControllers(
    List<ProductionOilInventoryWell> existing,
  ) {
    return [
      for (int i = 0; i < _wellControllers.length; i++)
        _OilInventoryControllers.fromWell(
          existing: i < existing.length ? existing[i] : null,
        ),
    ];
  }

  ProductionShiftHeader _headerFromControllers() {
    final wells = _wellControllers
        .map((controller) => controller.text.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return ProductionShiftHeader(
      company: _company.text.trim(),
      pad: _pad.text.trim(),
      date: _date.text.trim(),
      layoutProfileId: _layoutProfileId,
      chokeType: _defaultChokeDisplay,
      wellChokeTypes: {
        for (int i = 0; i < _wellControllers.length; i++)
          _wellControllers[i].text.trim().isEmpty
              ? 'Well ${i + 1}'
              : _wellControllers[i].text.trim(): _wellChokeTypes[i]
      },
      wells: wells.isEmpty ? const ['Well 1'] : wells,
    );
  }

  Future<void> _manageLayouts() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Manage layouts in Text/Report Layouts.'),
      ),
    );
  }

  String _todayDateText() {
    final now = DateTime.now();
    final local = DateTime(now.year, now.month, now.day);
    return local.toIso8601String().split('T').first;
  }

  ProductionInventoryBaseline _inventoryFromControllers() {
    return ProductionInventoryBaseline(
      waterTanks:
          _waterTanks.map((tank) => tank.toTank(_gaugeEntryType)).toList(),
      oilTanks: _oilTanks.map((tank) => tank.toTank(_gaugeEntryType)).toList(),
      oilInventoryWells: [
        for (int i = 0; i < _wellControllers.length; i++)
          _oilInventoryWells[i].toWell(
            _wellControllers[i].text.trim().isEmpty
                ? 'Well ${i + 1}'
                : _wellControllers[i].text.trim(),
          ),
      ],
      gaugeEntryType: _gaugeEntryType,
      gasUnit: _gasUnit,
      gasCalculationMethod: _gasCalculationMethod,
      startingGasAccum: _startingGasAccum.text.trim(),
      waterHauledBeforeRound: _waterHauledBeforeRound.text.trim(),
      oilHauledBeforeRound: _oilHauledBeforeRound.text.trim(),
      waterPumpedBeforeRound: _waterPumpedBeforeRound.text.trim(),
      oilPumpedBeforeRound: _oilPumpedBeforeRound.text.trim(),
    );
  }

  Future<void> _saveInventory() async {
    final active = await _service.loadActiveShift();
    final updated = active.copyWith(
      header: _headerFromControllers(),
      inventory: _inventoryFromControllers(),
    );
    await _service.saveActiveShift(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Production Inventory saved.')),
    );
  }

  Future<void> _clearInventory() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear Inventory?'),
            content: const Text(
              'This clears the shift header, starting inventory, starting gas, and pre-round adjustments.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear Inventory'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final active = await _service.loadActiveShift();
    final cleared = active.copyWith(
      header: const ProductionShiftHeader(),
      inventory: ProductionInventoryBaseline.empty(),
    );
    await _service.saveActiveShift(cleared);
    _setFromShift(cleared);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Production Inventory cleared.')),
    );
  }

  Future<void> _newDay() async {
    final action = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Start New Day?'),
            content: const Text(
              'Choose whether to archive the current job/shift before clearing the active production shift.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop('cancel'),
                child: const Text('Cancel'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop('clearOnly'),
                child: const Text('Clear Without Archive'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop('archiveClear'),
                child: const Text('Archive then Clear'),
              ),
            ],
          ),
        ) ??
        'cancel';
    if (action == 'cancel') return;

    if (action == 'archiveClear') {
      await _saveInventory();
      await _historyService.archiveCurrentJobOrShift();
    }

    await _service.clearActiveShift();
    _setFromShift(ProductionShift.empty());
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(action == 'archiveClear'
            ? 'Active production shift archived and cleared.'
            : 'Active production shift cleared.'),
      ),
    );
  }

  Future<void> _archiveYesterday() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Archive Current Job / Shift?'),
            content: const Text(
              'This saves the current active job and production shift into local History without clearing active data.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Archive Current Job / Shift'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    await _saveInventory();
    await _historyService.archiveCurrentJobOrShift();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Current job/shift archived to local History.')),
    );
  }

  void _addWell() {
    setState(() {
      _wellControllers.add(
        TextEditingController(text: 'Well ${_wellControllers.length + 1}'),
      );
      _wellChokeTypes.add(_defaultChokeDisplay);
      _oilInventoryWells.add(_OilInventoryControllers.blank());
    });
  }

  void _removeWell(int index) {
    if (_wellControllers.length == 1) return;
    setState(() {
      final controller = _wellControllers.removeAt(index);
      controller.dispose();
      _wellChokeTypes.removeAt(index);
      final oilInventory = _oilInventoryWells.removeAt(index);
      oilInventory.dispose();
    });
  }

  void _addTank(List<_TankControllers> list, String label) {
    setState(() {
      list.add(_TankControllers(
        name: TextEditingController(text: '$label ${list.length + 1}'),
        gaugeInches: TextEditingController(),
        gaugeFeet: TextEditingController(),
        gaugeInchesPart: TextEditingController(),
        gaugeDecimalFeet: TextEditingController(),
        bblPerInch: TextEditingController(text: _defaultBblPerInch),
      ));
    });
  }

  void _removeTank(List<_TankControllers> list, int index) {
    if (list.length == 1) return;
    setState(() {
      final tank = list.removeAt(index);
      tank.dispose();
    });
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFFCDA56A),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _textField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  List<Widget> _gaugeInputFields(_TankControllers tank) {
    if (_gaugeEntryType == 'feetInches') {
      return [
        WwNumberField(
          label: 'Gauge Feet',
          controller: tank.gaugeFeet,
          onChanged: (_) => setState(() {}),
        ),
        WwNumberField(
          label: 'Gauge Inches',
          controller: tank.gaugeInchesPart,
          onChanged: (_) => setState(() {}),
        ),
      ];
    }
    if (_gaugeEntryType == 'decimalFeet') {
      return [
        WwNumberField(
          label: 'Gauge (decimal feet)',
          controller: tank.gaugeDecimalFeet,
          onChanged: (_) => setState(() {}),
        ),
      ];
    }
    return [
      WwNumberField(
        label: 'Gauge (inches)',
        controller: tank.gaugeInches,
        onChanged: (_) => setState(() {}),
      ),
    ];
  }

  Widget _tankSection({
    required String title,
    required List<_TankControllers> tanks,
    required String tankLabel,
  }) {
    return _section(title, [
      for (int i = 0; i < tanks.length; i++)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$tankLabel ${i + 1}',
                        style: const TextStyle(
                          color: Color(0xFFCDA56A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: tanks.length == 1
                          ? null
                          : () => _removeTank(tanks, i),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
                _textField('Tank Name', tanks[i].name),
                ..._gaugeInputFields(tanks[i]),
                WwNumberField(
                  label: 'BBL per inch',
                  controller: tanks[i].bblPerInch,
                  helperText: 'Default 1.67',
                  onChanged: (_) => setState(() {}),
                ),
                Text(
                  'Entered: ${tanks[i].gaugeEntryText(_gaugeEntryType)}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 2),
                Text(
                  'Converted Gauge: ${tanks[i].convertedGaugeText(_gaugeEntryType)} in',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 2),
                Text(
                  'Starting BBL: ${tanks[i].calculatedBbl(_gaugeEntryType).toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFFCDA56A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _addTank(tanks, tankLabel),
          icon: const Icon(Icons.add),
          label: Text('Add $tankLabel'),
        ),
      ),
    ]);
  }

  Widget _oilInventorySection() {
    return _section('Oil Inventory Foundation', [
      const Text(
        'Track per-well oil inventory and cushion values for the active shift.',
        style: TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 10),
      for (int i = 0; i < _wellControllers.length; i++)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _wellControllers[i].text.trim().isEmpty
                      ? 'Well ${i + 1}'
                      : _wellControllers[i].text.trim(),
                  style: const TextStyle(
                    color: Color(0xFFCDA56A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                WwNumberField(
                  label: 'Beginning Oil Inventory',
                  controller: _oilInventoryWells[i].beginningOilInventory,
                  helperText: 'BBL',
                  onChanged: (_) => setState(() {}),
                ),
                WwNumberField(
                  label: 'Current Oil Inventory',
                  controller: _oilInventoryWells[i].currentOilInventory,
                  helperText: 'BBL',
                  onChanged: (_) => setState(() {}),
                ),
                WwNumberField(
                  label: 'Expected Oil Inventory',
                  controller: _oilInventoryWells[i].expectedOilInventory,
                  helperText: 'BBL',
                  onChanged: (_) => setState(() {}),
                ),
                WwNumberField(
                  label: 'Current Cushion',
                  controller: _oilInventoryWells[i].currentCushion,
                  helperText: 'BBL',
                  onChanged: (_) => setState(() {}),
                ),
                WwNumberField(
                  label: 'Maximum Cushion',
                  controller: _oilInventoryWells[i].maximumCushion,
                  helperText: 'BBL',
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
        ),
      if (_wellControllers.isEmpty)
        const Text(
          'Add at least one well to begin oil inventory tracking.',
          style: TextStyle(color: Colors.white70),
        ),
    ]);
  }

  Widget _wellChokeField(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: _wellChokeTypes[index],
        decoration: InputDecoration(labelText: 'Well ${index + 1} Choke Type'),
        items: const [
          DropdownMenuItem(value: 'ADJ', child: Text('ADJ')),
          DropdownMenuItem(value: 'POS', child: Text('POS')),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() => _wellChokeTypes[index] = value);
        },
      ),
    );
  }

  Widget _content() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _section('Shift Header', [
          _textField('Company', _company),
          _textField('Pad Name', _pad),
          _textField('Date', _date),
          DropdownButtonFormField<String>(
            initialValue: _gaugeEntryType,
            decoration: const InputDecoration(labelText: 'Gauge Entry Type'),
            items: const [
              DropdownMenuItem(value: 'inches', child: Text('Inches')),
              DropdownMenuItem(
                  value: 'feetInches', child: Text('Feet + Inches')),
              DropdownMenuItem(
                  value: 'decimalFeet', child: Text('Decimal Feet')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _gaugeEntryType = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _gasUnit,
            decoration: const InputDecoration(labelText: 'Gas Unit'),
            items: const [
              DropdownMenuItem(value: 'mcfd', child: Text('MCF/D')),
              DropdownMenuItem(value: 'mmcfd', child: Text('MMCF/D')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _gasUnit = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _gasCalculationMethod,
            decoration:
                const InputDecoration(labelText: 'Gas Calculation Method'),
            items: const [
              DropdownMenuItem(
                value: 'accumulator',
                child: Text('Gas Accumulator'),
              ),
              DropdownMenuItem(
                value: 'manual',
                child: Text('Manual Sales Gas Rate'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _gasCalculationMethod = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _layoutProfileId,
            decoration: const InputDecoration(labelText: 'Layout Profile'),
            items: [
              for (final profile in _layoutProfiles)
                DropdownMenuItem(
                  value: profile.id,
                  child: Text(profile.name),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _layoutProfileId = value);
            },
          ),
          if (widget.showManageLayoutsButton) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _manageLayouts,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Manage Report/Text Layouts'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const SizedBox(height: 4),
          const Text(
            'Wells on Location',
            style: TextStyle(
              color: Color(0xFFCDA56A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < _wellControllers.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _textField('Well ${i + 1}', _wellControllers[i]),
                      _wellChokeField(i),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _wellControllers.length == 1
                      ? null
                      : () => _removeWell(i),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addWell,
              icon: const Icon(Icons.add),
              label: const Text('Add Well'),
            ),
          ),
        ]),
        _tankSection(
          title: 'Starting Inventory • Water Tanks',
          tanks: _waterTanks,
          tankLabel: 'Water Tank',
        ),
        _tankSection(
          title: 'Starting Inventory • Oil Tanks',
          tanks: _oilTanks,
          tankLabel: 'Oil Tank',
        ),
        _oilInventorySection(),
        if (_gasCalculationMethod == 'accumulator')
          _section('Starting Gas', [
            WwNumberField(
              label: 'Starting Gas Accum',
              controller: _startingGasAccum,
              onChanged: (_) => setState(() {}),
            ),
          ]),
        _section('Pre-Round Adjustments', [
          WwNumberField(
            label: 'Water Hauled Before Round',
            controller: _waterHauledBeforeRound,
            onChanged: (_) => setState(() {}),
          ),
          WwNumberField(
            label: 'Oil Hauled Before Round',
            controller: _oilHauledBeforeRound,
            onChanged: (_) => setState(() {}),
          ),
          WwNumberField(
            label: 'Water Pumped Before Round',
            controller: _waterPumpedBeforeRound,
            onChanged: (_) => setState(() {}),
          ),
          WwNumberField(
            label: 'Oil Pumped Before Round',
            controller: _oilPumpedBeforeRound,
            onChanged: (_) => setState(() {}),
          ),
        ]),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saveInventory,
            icon: const Icon(Icons.save),
            label: const Text('Save Inventory'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _clearInventory,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Clear Inventory'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _newDay,
            icon: const Icon(Icons.refresh),
            label: const Text('New Day'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _archiveYesterday,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Archive Current Job / Shift'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      if (widget.embedded) {
        return const Center(child: CircularProgressIndicator());
      }
      return const Scaffold(
        appBar: AppHeader(title: 'Production Inventory', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (widget.embedded) {
      return _content();
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Production Inventory', showBack: true),
      body: _content(),
    );
  }
}

class _TankControllers {
  _TankControllers({
    required this.name,
    required this.gaugeInches,
    required this.gaugeFeet,
    required this.gaugeInchesPart,
    required this.gaugeDecimalFeet,
    required this.bblPerInch,
  });

  factory _TankControllers.fromTank(ProductionTank tank) {
    final entry = tank.gaugeEntry;
    return _TankControllers(
      name: TextEditingController(text: tank.name),
      gaugeInches: TextEditingController(
        text: entry.mode == 'inches' ? entry.inches : tank.gauge,
      ),
      gaugeFeet: TextEditingController(text: entry.feet),
      gaugeInchesPart: TextEditingController(text: entry.inchesPart),
      gaugeDecimalFeet: TextEditingController(text: entry.decimalFeet),
      bblPerInch: TextEditingController(text: tank.bblPerInch),
    );
  }

  final TextEditingController name;
  final TextEditingController gaugeInches;
  final TextEditingController gaugeFeet;
  final TextEditingController gaugeInchesPart;
  final TextEditingController gaugeDecimalFeet;
  final TextEditingController bblPerInch;

  ProductionGaugeEntry gaugeEntry(String mode) => ProductionGaugeEntry(
        mode: mode,
        inches: gaugeInches.text.trim(),
        feet: gaugeFeet.text.trim(),
        inchesPart: gaugeInchesPart.text.trim(),
        decimalFeet: gaugeDecimalFeet.text.trim(),
      );

  String convertedGaugeText(String mode) {
    final value = gaugeEntry(mode).asInches();
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  String gaugeEntryText(String mode) => gaugeEntry(mode).entryText();

  double calculatedBbl(String mode) {
    final gaugeValue = gaugeEntry(mode).asInches();
    final factor = double.tryParse(bblPerInch.text.trim()) ?? 1.67;
    final safeFactor = factor <= 0 ? 1.67 : factor;
    return gaugeValue * safeFactor;
  }

  ProductionTank toTank(String gaugeEntryType) {
    final factor = double.tryParse(bblPerInch.text.trim()) ?? 1.67;
    final safeFactor = factor <= 0 ? 1.67 : factor;
    final entry = gaugeEntry(gaugeEntryType);
    return ProductionTank(
      name: name.text.trim().isEmpty ? 'Tank' : name.text.trim(),
      gauge: convertedGaugeText(gaugeEntryType),
      gaugeEntry: entry,
      bblPerInch: safeFactor.toStringAsFixed(2),
    );
  }

  void dispose() {
    name.dispose();
    gaugeInches.dispose();
    gaugeFeet.dispose();
    gaugeInchesPart.dispose();
    gaugeDecimalFeet.dispose();
    bblPerInch.dispose();
  }
}

class _OilInventoryControllers {
  _OilInventoryControllers({
    required this.beginningOilInventory,
    required this.currentOilInventory,
    required this.expectedOilInventory,
    required this.currentCushion,
    required this.maximumCushion,
  });

  factory _OilInventoryControllers.blank() {
    return _OilInventoryControllers(
      beginningOilInventory: TextEditingController(),
      currentOilInventory: TextEditingController(),
      expectedOilInventory: TextEditingController(),
      currentCushion: TextEditingController(),
      maximumCushion: TextEditingController(),
    );
  }

  factory _OilInventoryControllers.fromWell({
    ProductionOilInventoryWell? existing,
  }) {
    return _OilInventoryControllers(
      beginningOilInventory: TextEditingController(
        text: existing?.beginningOilInventory ?? '',
      ),
      currentOilInventory: TextEditingController(
        text: existing?.currentOilInventory ?? '',
      ),
      expectedOilInventory: TextEditingController(
        text: existing?.expectedOilInventory ?? '',
      ),
      currentCushion: TextEditingController(
        text: existing?.currentCushion ?? '',
      ),
      maximumCushion: TextEditingController(
        text: existing?.maximumCushion ?? '',
      ),
    );
  }

  final TextEditingController beginningOilInventory;
  final TextEditingController currentOilInventory;
  final TextEditingController expectedOilInventory;
  final TextEditingController currentCushion;
  final TextEditingController maximumCushion;

  ProductionOilInventoryWell toWell(String wellName) {
    return ProductionOilInventoryWell(
      wellName: wellName,
      beginningOilInventory: beginningOilInventory.text.trim(),
      currentOilInventory: currentOilInventory.text.trim(),
      expectedOilInventory: expectedOilInventory.text.trim(),
      currentCushion: currentCushion.text.trim(),
      maximumCushion: maximumCushion.text.trim(),
    );
  }

  void dispose() {
    beginningOilInventory.dispose();
    currentOilInventory.dispose();
    expectedOilInventory.dispose();
    currentCushion.dispose();
    maximumCushion.dispose();
  }
}
