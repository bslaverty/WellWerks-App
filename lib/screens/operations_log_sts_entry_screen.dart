import 'package:flutter/material.dart';

import '../widgets/sts_date_time_selector_sheet.dart';

class OperationsLogStsEntryResult {
  const OperationsLogStsEntryResult({
    required this.pumpRate,
    required this.averageReturnRate,
    required this.estimatedSts,
    required this.actualSts,
    required this.notes,
  });

  final String pumpRate;
  final double averageReturnRate;
  final DateTime estimatedSts;
  final DateTime actualSts;
  final String notes;
}

class OperationsLogStsEntryScreen extends StatefulWidget {
  const OperationsLogStsEntryScreen({
    super.key,
    this.title = 'Add STS',
    this.initialPumpRate = '',
    this.initialAverageReturnRate,
    this.initialEstimatedSts,
    this.initialActualSts,
    this.initialNotes = '',
  });

  final String title;
  final String initialPumpRate;
  final double? initialAverageReturnRate;
  final DateTime? initialEstimatedSts;
  final DateTime? initialActualSts;
  final String initialNotes;

  @override
  State<OperationsLogStsEntryScreen> createState() =>
      _OperationsLogStsEntryScreenState();
}

class _OperationsLogStsEntryScreenState
    extends State<OperationsLogStsEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pumpRateController;
  late final TextEditingController _averageReturnRateController;
  DateTime? _actualSts;
  DateTime? _estimatedSts;
  late final TextEditingController _notesController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pumpRateController = TextEditingController(text: widget.initialPumpRate);
    _averageReturnRateController = TextEditingController(
      text: widget.initialAverageReturnRate == null
          ? ''
          : widget.initialAverageReturnRate!.toStringAsFixed(2),
    );
    _estimatedSts = widget.initialEstimatedSts;
    _actualSts = widget.initialActualSts;
    _notesController = TextEditingController(text: widget.initialNotes);
  }

  @override
  void dispose() {
    _pumpRateController.dispose();
    _averageReturnRateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final dateLabel =
        MaterialLocalizations.of(context).formatCompactDate(local);
    final timeLabel = TimeOfDay.fromDateTime(local).format(context);
    return '$dateLabel $timeLabel';
  }

  Future<void> _pickEstimatedSts() async {
    final selection = await showStsDateTimeSelectorSheet(
      context,
      title: 'Estimated STS',
      helperText: 'Select estimated sweep-to-surface time.',
      readingTimestamp: _estimatedSts ?? DateTime.now(),
      initialValue: _estimatedSts ?? DateTime.now(),
    );
    if (!mounted || selection == null || selection.cleared) return;
    if (selection.value == null) return;
    setState(() => _estimatedSts = selection.value);
  }

  Future<void> _pickActualSts() async {
    final selection = await showStsDateTimeSelectorSheet(
      context,
      title: 'Actual STS',
      helperText: 'Select actual sweep-to-surface time.',
      readingTimestamp: _estimatedSts ?? DateTime.now(),
      initialValue: _actualSts ?? DateTime.now(),
    );
    if (!mounted || selection == null || selection.cleared) return;
    if (selection.value == null) return;
    setState(() => _actualSts = selection.value);
  }

  double? _parseAverageReturnRate() {
    final parsed = double.tryParse(_averageReturnRateController.text.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  String? _validatePumpRate(String? value) {
    if ((value ?? '').trim().isEmpty) {
      return 'Pump Rate is required.';
    }
    return null;
  }

  String? _validateAverageReturnRate(String? value) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null || parsed <= 0) {
      return 'Average Return Rate must be greater than 0.';
    }
    return null;
  }

  void _save() {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_estimatedSts == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estimated STS is required.')),
      );
      return;
    }
    if (_actualSts == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Actual STS is required.')),
      );
      return;
    }
    final averageReturnRate = _parseAverageReturnRate();
    if (averageReturnRate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Average Return Rate must be greater than 0.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    Navigator.of(context).pop(
      OperationsLogStsEntryResult(
        pumpRate: _pumpRateController.text.trim(),
        averageReturnRate: averageReturnRate,
        estimatedSts: _estimatedSts!,
        actualSts: _actualSts!,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const wwGold = Color(0xFFD9A63C);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _pumpRateController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
              decoration: const InputDecoration(labelText: 'Pump Rate'),
              validator: _validatePumpRate,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _averageReturnRateController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
              decoration: const InputDecoration(
                labelText: 'Average Return Rate',
                helperText: 'bbl/min',
              ),
              validator: _validateAverageReturnRate,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('Estimated STS'),
              subtitle: Text(
                _estimatedSts == null
                    ? 'Not set'
                    : _formatDateTime(_estimatedSts!),
              ),
              trailing: FilledButton(
                onPressed: _pickEstimatedSts,
                style: FilledButton.styleFrom(
                  backgroundColor: wwGold,
                  foregroundColor: Colors.black,
                ),
                child: Text(_estimatedSts == null ? 'Set' : 'Change'),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Actual STS'),
              subtitle: Text(
                _actualSts == null ? 'Not set' : _formatDateTime(_actualSts!),
              ),
              trailing: FilledButton(
                onPressed: _pickActualSts,
                style: FilledButton.styleFrom(
                  backgroundColor: wwGold,
                  foregroundColor: Colors.black,
                ),
                child: Text(_actualSts == null ? 'Set' : 'Change'),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes (Optional)',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: wwGold,
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                icon: const Icon(Icons.save_outlined),
                label: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save STS'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
