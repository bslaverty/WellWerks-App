import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/operator_profile_service.dart';
import '../widgets/app_header.dart';

class OperatorProfileScreen extends StatefulWidget {
  const OperatorProfileScreen({super.key});

  @override
  State<OperatorProfileScreen> createState() => _OperatorProfileScreenState();
}

class _OperatorProfileScreenState extends State<OperatorProfileScreen> {
  final _service = OperatorProfileService.instance;
  final _imagePicker = ImagePicker();
  final _nameController = TextEditingController();
  final _initialsController = TextEditingController();
  final _companyController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  bool _loading = true;
  String _operatorId = '';
  String _photoBase64 = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _initialsController.dispose();
    _companyController.dispose();
    _jobTitleController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _service.load();
    if (!mounted) return;
    setState(() {
      _operatorId = profile.operatorId;
      _nameController.text = profile.name;
      _initialsController.text = profile.initials;
      _companyController.text = profile.company;
      _jobTitleController.text = profile.jobTitle;
      _phoneController.text = profile.phone;
      _emailController.text = profile.email;
      _photoBase64 = profile.photoBase64;
      _loading = false;
    });
  }

  Future<void> _pickPhoto() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _photoBase64 = base64Encode(bytes));
  }

  void _removePhoto() {
    setState(() => _photoBase64 = '');
  }

  Uint8List? get _photoBytes {
    final raw = _photoBase64.trim();
    if (raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final initials = _initialsController.text.trim();
    final next = await _service.updateProfile(
      name: name,
      initials: initials,
      company: _companyController.text,
      jobTitle: _jobTitleController.text,
      phone: _phoneController.text,
      email: _emailController.text,
      photoBase64: _photoBase64,
    );
    if (!mounted) return;
    setState(() {
      _operatorId = next.operatorId;
      _initialsController.text = next.initials;
      _photoBase64 = next.photoBase64;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Operator profile saved.')),
    );
  }

  Widget _profilePhotoCard() {
    final scheme = Theme.of(context).colorScheme;
    final photoBytes = _photoBytes;
    final initials = _initialsController.text.trim().isEmpty
        ? _service.suggestInitials(_nameController.text)
        : _initialsController.text.trim().toUpperCase();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: scheme.primaryContainer,
              backgroundImage:
                  photoBytes == null ? null : MemoryImage(photoBytes),
              child: photoBytes == null
                  ? Text(
                      initials.isEmpty ? 'OP' : initials,
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              _nameController.text.trim().isEmpty
                  ? 'Operator Profile'
                  : _nameController.text.trim(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            if (_jobTitleController.text.trim().isNotEmpty ||
                _companyController.text.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                [
                  _jobTitleController.text.trim(),
                  _companyController.text.trim()
                ].where((value) => value.isNotEmpty).join(' • '),
                style: TextStyle(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label:
                      Text(photoBytes == null ? 'Add Photo' : 'Change Photo'),
                ),
                if (photoBytes != null)
                  OutlinedButton.icon(
                    onPressed: _removePhoto,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove Photo'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileField(
    TextEditingController controller,
    String label, {
    TextInputAction? textInputAction,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        textInputAction: textInputAction,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        onChanged: (_) => setState(() {}),
      ),
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
                _profilePhotoCard(),
                const SizedBox(height: 12),
                const Text(
                  'Profile Details',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                _profileField(
                  _nameController,
                  'Name',
                  textInputAction: TextInputAction.next,
                ),
                _profileField(
                  _initialsController,
                  'Initials',
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                ),
                _profileField(
                  _companyController,
                  'Company',
                  textInputAction: TextInputAction.next,
                ),
                _profileField(
                  _jobTitleController,
                  'Job Title',
                  textInputAction: TextInputAction.next,
                ),
                _profileField(
                  _phoneController,
                  'Phone',
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                ),
                _profileField(
                  _emailController,
                  'Email',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 4),
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
