import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class OperatorProfile {
  const OperatorProfile({
    required this.operatorId,
    required this.name,
    required this.initials,
    required this.company,
    required this.jobTitle,
    required this.phone,
    required this.email,
    required this.photoBase64,
  });

  final String operatorId;
  final String name;
  final String initials;
  final String company;
  final String jobTitle;
  final String phone;
  final String email;
  final String photoBase64;

  bool get hasName => name.trim().isNotEmpty;

  OperatorProfile copyWith({
    String? operatorId,
    String? name,
    String? initials,
    String? company,
    String? jobTitle,
    String? phone,
    String? email,
    String? photoBase64,
  }) {
    return OperatorProfile(
      operatorId: operatorId ?? this.operatorId,
      name: name ?? this.name,
      initials: initials ?? this.initials,
      company: company ?? this.company,
      jobTitle: jobTitle ?? this.jobTitle,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      photoBase64: photoBase64 ?? this.photoBase64,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'operatorId': operatorId,
        'name': name,
        'initials': initials,
        'company': company,
        'jobTitle': jobTitle,
        'phone': phone,
        'email': email,
        'photoBase64': photoBase64,
      };

  factory OperatorProfile.fromJson(Map<String, dynamic> json) {
    return OperatorProfile(
      operatorId: (json['operatorId'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      initials: (json['initials'] as String? ?? '').trim(),
      company: (json['company'] as String? ?? '').trim(),
      jobTitle: (json['jobTitle'] as String? ?? '').trim(),
      phone: (json['phone'] as String? ?? '').trim(),
      email: (json['email'] as String? ?? '').trim(),
      photoBase64: (json['photoBase64'] as String? ?? '').trim(),
    );
  }
}

class OperatorProfileService {
  static const _prefsKey = 'wellwerks_operator_profile_v1';
  static final OperatorProfileService instance = OperatorProfileService._();

  OperatorProfileService._();

  final Random _random = Random.secure();
  OperatorProfile? _cached;

  Future<OperatorProfile> load() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      final profile = OperatorProfile(
        operatorId: _generateOperatorId(),
        name: '',
        initials: '',
        company: '',
        jobTitle: '',
        phone: '',
        email: '',
        photoBase64: '',
      );
      _cached = profile;
      await save(profile);
      return profile;
    }

    try {
      final profile = OperatorProfile.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      final next = profile.operatorId.trim().isEmpty
          ? profile.copyWith(operatorId: _generateOperatorId())
          : profile;
      _cached = next;
      if (next != profile) {
        await save(next);
      }
      return next;
    } catch (_) {
      final profile = OperatorProfile(
        operatorId: _generateOperatorId(),
        name: '',
        initials: '',
        company: '',
        jobTitle: '',
        phone: '',
        email: '',
        photoBase64: '',
      );
      _cached = profile;
      await save(profile);
      return profile;
    }
  }

  Future<void> save(OperatorProfile profile) async {
    _cached = profile.copyWith(
      operatorId: profile.operatorId.trim().isEmpty
          ? _generateOperatorId()
          : profile.operatorId.trim(),
      name: profile.name.trim(),
      initials: profile.initials.trim().isEmpty
          ? suggestInitials(profile.name)
          : profile.initials.trim().toUpperCase(),
      company: profile.company.trim(),
      jobTitle: profile.jobTitle.trim(),
      phone: profile.phone.trim(),
      email: profile.email.trim(),
      photoBase64: profile.photoBase64.trim(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_cached!.toJson()));
  }

  Future<OperatorProfile> updateProfile({
    required String name,
    required String initials,
    String company = '',
    String jobTitle = '',
    String phone = '',
    String email = '',
    String photoBase64 = '',
  }) async {
    final current = await load();
    final next = current.copyWith(
      name: name.trim(),
      initials: initials.trim().isEmpty
          ? suggestInitials(name)
          : initials.trim().toUpperCase(),
      company: company.trim(),
      jobTitle: jobTitle.trim(),
      phone: phone.trim(),
      email: email.trim(),
      photoBase64: photoBase64.trim(),
    );
    await save(next);
    return _cached!;
  }

  String suggestInitials(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return '';
    final parts =
        cleaned.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    final letters = parts.map((part) => part[0].toUpperCase()).toList();
    return letters.take(3).join();
  }

  String _generateOperatorId() {
    final millis = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = _random.nextInt(1 << 31).toRadixString(36);
    return 'op_$millis$salt';
  }
}
