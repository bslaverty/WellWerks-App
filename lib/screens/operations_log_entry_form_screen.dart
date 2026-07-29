import 'package:flutter/material.dart';

import '../models/job_setup.dart';
import '../services/operations_log_service.dart';

class OperationsLogEntryFormScreen extends StatefulWidget {
  const OperationsLogEntryFormScreen({
    super.key,
    required this.workflow,
    required this.title,
    required this.activeJob,
    required this.defaultWells,
    required this.initialSelectedWellId,
    required this.initialSelectedWellName,
    required this.initialStage,
    required this.initialReadingTimestamp,
    required this.stageOptions,
    required this.enabledFieldIds,
    required this.logService,
  });

  final OperationsLogWorkflow workflow;
  final String title;
  final JobSetup activeJob;
  final List<JobSetupWell> defaultWells;
  final String initialSelectedWellId;
  final String initialSelectedWellName;
  final String initialStage;
  final DateTime initialReadingTimestamp;
  final List<String> stageOptions;
  final Set<String> enabledFieldIds;
  final OperationsLogService logService;

  @override
  State<OperationsLogEntryFormScreen> createState() =>
      _OperationsLogEntryFormScreenState();
}

class _OperationsLogEntryFormScreenState
    extends State<OperationsLogEntryFormScreen> {
  late final TextEditingController _pumpRateController;
  late final TextEditingController _casingPressureController;
  late final TextEditingController _tubingPressureController;
  late final TextEditingController _pumpPressureController;
  late final TextEditingController _returnsRateController;
  late final TextEditingController _waterRateController;
  late final TextEditingController _flowRateController;
  late final TextEditingController _tankLevelController;
  late final TextEditingController _chokeController;
  late final TextEditingController _sweepInformationController;
  late final TextEditingController _sandOrSolidsController;
  late final TextEditingController _equipmentStatusController;
  late final TextEditingController _downtimeController;
  late final TextEditingController _notesController;

  late DateTime _readingTimestamp;
  late String _selectedWellId;
  String _selectedStage = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pumpRateController = TextEditingController();
    _casingPressureController = TextEditingController();
    _tubingPressureController = TextEditingController();
    _pumpPressureController = TextEditingController();
    _returnsRateController = TextEditingController();
    _waterRateController = TextEditingController();
    _flowRateController = TextEditingController();
    _tankLevelController = TextEditingController();
    _chokeController = TextEditingController();
    _sweepInformationController = TextEditingController();
    _sandOrSolidsController = TextEditingController();
    _equipmentStatusController = TextEditingController();
    _downtimeController = TextEditingController();
    _notesController = TextEditingController();
    _readingTimestamp = widget.initialReadingTimestamp;
    final trimmedInitialStage = widget.initialStage.trim();
    _selectedStage = widget.stageOptions.contains(trimmedInitialStage)
        ? trimmedInitialStage
        : '';

    final availableWellIds = widget.defaultWells.map((item) => item.id).toSet();
    final requestedId = widget.initialSelectedWellId.trim();
    if (requestedId.isNotEmpty && availableWellIds.contains(requestedId)) {
      _selectedWellId = requestedId;
    } else if (widget.defaultWells.isNotEmpty) {
      _selectedWellId = widget.defaultWells.first.id;
    } else {
      _selectedWellId = '';
    }
  }

  @override
  void dispose() {
    _pumpRateController.dispose();
    _casingPressureController.dispose();
    _tubingPressureController.dispose();
    _pumpPressureController.dispose();
    _returnsRateController.dispose();
    _waterRateController.dispose();
    _flowRateController.dispose();
    _tankLevelController.dispose();
    _chokeController.dispose();
    _sweepInformationController.dispose();
    _sandOrSolidsController.dispose();
    _equipmentStatusController.dispose();
    _downtimeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool _isEnabled(String fieldId) => widget.enabledFieldIds.contains(fieldId);

  String get _formTitle {
    final workflowLabel = widget.workflow == OperationsLogWorkflow.drillout
        ? 'Drillout'
        : 'Cleanout';
    return 'Add $workflowLabel Reading';
  }

  String get _selectedWellName {
    for (final item in widget.defaultWells) {
      if (item.id == _selectedWellId) return item.name;
    }
    return widget.initialSelectedWellName.trim();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _readingTimestamp,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (selected == null) return;
    setState(() {
      _readingTimestamp = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _readingTimestamp.hour,
        _readingTimestamp.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_readingTimestamp),
    );
    if (selected == null) return;
    setState(() {
      _readingTimestamp = DateTime(
        _readingTimestamp.year,
        _readingTimestamp.month,
        _readingTimestamp.day,
        selected.hour,
        selected.minute,
      );
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final job = widget.activeJob;
      final entry = await widget.logService.createLocalEntry(
        workflow: widget.workflow,
        jobId: job.id,
        wellId: _selectedWellId,
        wellName: _selectedWellName,
        readingTimestamp: _readingTimestamp,
        operationStage:
            _isEnabled('operationStage') ? _selectedStage.trim() : '',
        choke: _isEnabled('choke') ? _chokeController.text.trim() : '',
        pumpRate: _pumpRateController.text.trim(),
        casingPressure: _casingPressureController.text.trim(),
        tubingPressure: _isEnabled('tubingPressure')
            ? _tubingPressureController.text.trim()
            : '',
        pumpPressure: _isEnabled('pumpPressure')
            ? _pumpPressureController.text.trim()
            : '',
        returnsRate:
            _isEnabled('returnsRate') ? _returnsRateController.text.trim() : '',
        waterRate:
            _isEnabled('waterRate') ? _waterRateController.text.trim() : '',
        flowRate: _isEnabled('flowRate') ? _flowRateController.text.trim() : '',
        tankLevel:
            _isEnabled('tankLevel') ? _tankLevelController.text.trim() : '',
        sweepInformation: _isEnabled('sweepInformation')
            ? _sweepInformationController.text.trim()
            : '',
        sandOrSolids: _isEnabled('sandOrSolids')
            ? _sandOrSolidsController.text.trim()
            : '',
        equipmentStatus: _isEnabled('equipmentStatus')
            ? _equipmentStatusController.text.trim()
            : '',
        downtime: _isEnabled('downtime') ? _downtimeController.text.trim() : '',
        notes: _notesController.text.trim(),
      );
      await widget.logService.upsertEntry(
        workflow: widget.workflow,
        jobId: job.id,
        entry: entry,
      );
      if (!mounted) return;
      Navigator.of(context).pop(entry);
    } catch (error, stackTrace) {
      debugPrint(
        '[OperationsLog] Failed to save reading form for ${widget.workflow.name}: $error\n$stackTrace',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save this reading.')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = MaterialLocalizations.of(context).formatCompactDate(
      _readingTimestamp,
    );
    final timeLabel = TimeOfDay.fromDateTime(_readingTimestamp).format(context);

    return Scaffold(
      appBar: AppBar(title: Text(_formTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Job',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.activeJob.padName.trim().isEmpty
                        ? widget.activeJob.company
                        : widget.activeJob.padName,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('operations-log-form-well-dropdown'),
            initialValue: _selectedWellId.isEmpty ? null : _selectedWellId,
            decoration: const InputDecoration(labelText: 'Well'),
            items: [
              for (final item in widget.defaultWells)
                DropdownMenuItem<String>(
                  value: item.id,
                  child: Text(item.name),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedWellId = value);
            },
          ),
          const SizedBox(height: 12),
          if (_isEnabled('operationStage')) ...[
            DropdownButtonFormField<String>(
              key: const Key('operations-log-form-stage-field'),
              initialValue: _selectedStage,
              decoration: const InputDecoration(labelText: 'Stage'),
              items: [
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('Select stage'),
                ),
                for (final stage in widget.stageOptions)
                  DropdownMenuItem<String>(
                    value: stage,
                    child: Text(stage),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _selectedStage = (value ?? '').trim()),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('operations-log-form-date-button'),
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text('Date: $dateLabel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('operations-log-form-time-button'),
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time),
                  label: Text('Time: $timeLabel'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isEnabled('pumpRate')) ...[
            TextFormField(
              key: const Key('operations-log-form-pump-rate-field'),
              controller: _pumpRateController,
              decoration: const InputDecoration(labelText: 'Rate Override'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('casingPressure')) ...[
            TextFormField(
              key: const Key('operations-log-form-csg-field'),
              controller: _casingPressureController,
              decoration: const InputDecoration(labelText: 'Casing PSI'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('pumpPressure')) ...[
            TextFormField(
              key: const Key('operations-log-form-pump-pressure-field'),
              controller: _pumpPressureController,
              decoration: const InputDecoration(labelText: 'Pump PSI'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('tubingPressure')) ...[
            TextFormField(
              key: const Key('operations-log-form-tbg-field'),
              controller: _tubingPressureController,
              decoration: const InputDecoration(labelText: 'Manifold PSI'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('returnsRate')) ...[
            TextFormField(
              key: const Key('operations-log-form-returns-rate-field'),
              controller: _returnsRateController,
              decoration: const InputDecoration(labelText: 'Returns Rate'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('waterRate')) ...[
            TextFormField(
              key: const Key('operations-log-form-water-rate-field'),
              controller: _waterRateController,
              decoration: const InputDecoration(labelText: 'Water Rate'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('flowRate')) ...[
            TextFormField(
              key: const Key('operations-log-form-flow-rate-field'),
              controller: _flowRateController,
              decoration: const InputDecoration(labelText: 'Flow Rate'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('tankLevel')) ...[
            TextFormField(
              key: const Key('operations-log-form-tank-level-field'),
              controller: _tankLevelController,
              decoration: const InputDecoration(labelText: 'Tank Level'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('choke')) ...[
            TextFormField(
              key: const Key('operations-log-form-choke-field'),
              controller: _chokeController,
              decoration: const InputDecoration(labelText: 'Choke'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('sweepInformation')) ...[
            TextFormField(
              key: const Key('operations-log-form-sweep-field'),
              controller: _sweepInformationController,
              decoration: const InputDecoration(labelText: 'Sweep Information'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('sandOrSolids')) ...[
            TextFormField(
              key: const Key('operations-log-form-sand-field'),
              controller: _sandOrSolidsController,
              decoration: const InputDecoration(labelText: 'Sand / Solids'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('equipmentStatus')) ...[
            TextFormField(
              key: const Key('operations-log-form-equipment-field'),
              controller: _equipmentStatusController,
              decoration: const InputDecoration(labelText: 'Equipment Issues'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('downtime')) ...[
            TextFormField(
              key: const Key('operations-log-form-downtime-field'),
              controller: _downtimeController,
              decoration: const InputDecoration(labelText: 'Downtime'),
            ),
            const SizedBox(height: 12),
          ],
          if (_isEnabled('notes')) ...[
            TextFormField(
              key: const Key('operations-log-form-notes-field'),
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('operations-log-form-cancel-button'),
                  onPressed:
                      _saving ? null : () => Navigator.of(context).maybePop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('operations-log-form-save-button'),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Reading'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
