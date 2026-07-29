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
  final OperationsLogService logService;

  @override
  State<OperationsLogEntryFormScreen> createState() =>
      _OperationsLogEntryFormScreenState();
}

class _OperationsLogEntryFormScreenState
    extends State<OperationsLogEntryFormScreen> {
  late final TextEditingController _stageController;
  late final TextEditingController _pumpRateController;
  late final TextEditingController _casingPressureController;
  late final TextEditingController _tubingPressureController;
  late final TextEditingController _notesController;

  late DateTime _readingTimestamp;
  late String _selectedWellId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _stageController = TextEditingController(text: widget.initialStage.trim());
    _pumpRateController = TextEditingController();
    _casingPressureController = TextEditingController();
    _tubingPressureController = TextEditingController();
    _notesController = TextEditingController();
    _readingTimestamp = widget.initialReadingTimestamp;

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
    _stageController.dispose();
    _pumpRateController.dispose();
    _casingPressureController.dispose();
    _tubingPressureController.dispose();
    _notesController.dispose();
    super.dispose();
  }

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
        operationStage: _stageController.text.trim(),
        pumpRate: _pumpRateController.text.trim(),
        casingPressure: _casingPressureController.text.trim(),
        tubingPressure: _tubingPressureController.text.trim(),
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
          TextFormField(
            key: const Key('operations-log-form-stage-field'),
            controller: _stageController,
            decoration: const InputDecoration(labelText: 'Stage'),
          ),
          const SizedBox(height: 12),
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
          TextFormField(
            key: const Key('operations-log-form-pump-rate-field'),
            controller: _pumpRateController,
            decoration: const InputDecoration(labelText: 'Pump Rate'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('operations-log-form-csg-field'),
            controller: _casingPressureController,
            decoration: const InputDecoration(labelText: 'Casing Pressure'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('operations-log-form-tbg-field'),
            controller: _tubingPressureController,
            decoration: const InputDecoration(labelText: 'Tubing Pressure'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('operations-log-form-notes-field'),
            controller: _notesController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
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
