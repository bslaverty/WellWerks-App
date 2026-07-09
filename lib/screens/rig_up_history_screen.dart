import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/recovery_state_service.dart';
import '../services/rig_up_inventory_service.dart';
import '../widgets/app_header.dart';
import 'rig_up_inventory_screen.dart';

class RigUpHistoryScreen extends StatefulWidget {
  const RigUpHistoryScreen({super.key});

  @override
  State<RigUpHistoryScreen> createState() => _RigUpHistoryScreenState();
}

class _RigUpHistoryScreenState extends State<RigUpHistoryScreen> {
  Color get _gold => Theme.of(context).colorScheme.primary;

  final _recoveryState = RecoveryStateService();
  final _inventoryService = RigUpInventoryService();

  bool _loading = true;
  List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _recoveryState.saveLastModule(RecoveryModules.rigUpHistory);
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final list = await _inventoryService.loadAllRecords();
    if (!mounted) return;
    setState(() {
      _records = list;
      _loading = false;
    });
  }

  Future<void> _openRecord(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RigUpInventoryScreen(initialRecordId: id),
      ),
    );
    await _loadRecords();
  }

  Future<void> _shareRecord(Map<String, dynamic> record) async {
    final text = record['inventoryText']?.toString().trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preview/save inventory text first.')),
      );
      return;
    }
    await Share.share(text, subject: 'Rig-Up Inventory');
  }

  Future<void> _deleteRecord(Map<String, dynamic> record) async {
    final id = record['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rig-Up Record?'),
        content: const Text('This record will be removed from Rig-Up History.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await _inventoryService.deleteRecord(id);
    await _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Rig-Up History', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Rig-Up History', showBack: true),
      body: _records.isEmpty
          ? const Center(
              child: Text(
                'No rig-up inventory records saved yet.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(18),
              itemCount: _records.length,
              itemBuilder: (context, index) {
                final record = _records[index];
                final id = record['id']?.toString() ?? '';
                final customer = (record['customer']?.toString() ?? '').trim();
                final company = (record['company']?.toString() ?? '').trim();
                final pad = (record['pad']?.toString() ??
                        record['jobPad']?.toString() ??
                        '')
                    .trim();
                final date = (record['date']?.toString() ?? '').trim();
                final wells = List<String>.from(
                  record['wells'] as List? ?? const <String>[],
                );

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onTap: id.isEmpty ? null : () => _openRecord(id),
                    leading: Icon(Icons.inventory_2_outlined, color: _gold),
                    title: Text(
                      customer.isNotEmpty
                          ? customer
                          : (company.isEmpty ? 'Not entered' : company),
                      style: TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pad: ${pad.isEmpty ? '-' : pad}'),
                        Text('Date: ${date.isEmpty ? '-' : date}'),
                        Text('Wells: ${wells.length}'),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'open' && id.isNotEmpty) {
                          _openRecord(id);
                          return;
                        }
                        if (value == 'share') {
                          _shareRecord(record);
                          return;
                        }
                        if (value == 'delete') {
                          _deleteRecord(record);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                            value: 'open', child: Text('Open / Edit')),
                        PopupMenuItem(
                            value: 'share', child: Text('Share / Send')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
