import 'package:flutter/material.dart';

import '../services/operator_profile_service.dart';
import '../widgets/app_header.dart';

class OperatorProfileScreen extends StatefulWidget {
  const OperatorProfileScreen({super.key});

  @override
  State<OperatorProfileScreen> createState() => _OperatorProfileScreenState();
}

class _OperatorProfileScreenState extends State<OperatorProfileScreen> {
  final _service = OperatorProfileService.instance;
  final _nameController = TextEditingController();
  final _initialsController = TextEditingController();
  bool _loading = true;
  String _operatorId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _initialsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _service.load();
    if (!mounted) return;
    setState(() {
      _operatorId = profile.operatorId;
      _nameController.text = profile.name;
      _initialsController.text = profile.initials;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final initials = _initialsController.text.trim();
    final next = await _service.updateProfile(name: name, initials: initials);
    if (!mounted) return;
    setState(() {
      _operatorId = next.operatorId;
      _initialsController.text = next.initials;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Operator profile saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Operator Profile', showBack: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Operator Profile',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _initialsController,
                  decoration: const InputDecoration(
                    labelText: 'Initials',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),
                Text(
                  'Operator ID: $_operatorId',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
              ],
            ),
    );
  }
}
