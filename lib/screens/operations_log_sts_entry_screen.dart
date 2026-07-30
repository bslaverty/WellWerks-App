import 'package:flutter/material.dart';

import '../widgets/sts_date_time_selector_sheet.dart';

class OperationsLogStsEntryResult {
  const OperationsLogStsEntryResult({
    required this.actualSts,
    required this.notes,
  });

  final DateTime actualSts;
  final String notes;
}

class OperationsLogStsEntryScreen extends StatefulWidget {
  const OperationsLogStsEntryScreen({
    super.key,
    required this.estimatedSts,
    required this.pumpRate,
    required this.averageReturnRate,
    this.initialActualSts,
    this.initialNotes = '',
  });

  final DateTime estimatedSts;
  final String pumpRate;
  final double? averageReturnRate;
  final DateTime? initialActualSts;
  final String initialNotes;

  @override
  State<OperationsLogStsEntryScreen> createState() =>
      _OperationsLogStsEntryScreenState();
}

class _OperationsLogStsEntryScreenState extends State<OperationsLogStsEntryScreen> {
  DateTime? _actualSts;
  late final TextEditingController _notesController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _actualSts = widget.initialActualSts;
    _notesController = TextEditingController(text: widget.initialNotes);
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final dateLabel = MaterialLocalizations.of(context).formatCompactDate(local);
    final timeLabel = TimeOfDay.fromDateTime(local).format(context);
    return '$dateLabel $timeLabel';
  }

  Future<void> _pickActualSts() async {
    final selection = await showStsDateTimeSelectorSheet(
      context,
      title: 'Actual STS',
      helperText: 'Select actual sweep-to-surface time.',
      readingTimestamp: widget.estimatedSts,
      initialValue: _actualSts ?? DateTime.now(),
    );
    if (!mounted || selection == null || selection.cleared) return;
    if (selection.value == null) return;
    setState(() => _actualSts = selection.value);
  }

  void _save() {
    if (_saving || _actualSts == null) return;
    setState(() => _saving = true);
    Navigator.of(context).pop(
      OperationsLogStsEntryResult(
        actualSts: _actualSts!,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const wwGold = Color(0xFFD9A63C);

    return Scaffold(
      appBar: AppBar(title: const Text('Add STS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'STS Snapshot',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text('Current Pump Rate: ${widget.pumpRate.trim().isEmpty ? '--' : widget.pumpRate.trim()}'),
                  const SizedBox(height: 6),
                  Text(
                    'Most Recent Avg Returns: ${widget.averageReturnRate == null ? '--' : widget.averageReturnRate!.toStringAsFixed(2)} bbl/min',
                  ),
                  const SizedBox(height: 6),
                  Text('Estimated STS: ${_formatDateTime(widget.estimatedSts)}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
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
              onPressed: _actualSts == null ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: wwGold,
                foregroundColor: Colors.black,
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
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
    );
  }
}
