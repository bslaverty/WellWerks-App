import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentityService {
  static const _prefsKey = 'wellwerks_device_identity_v1';
  static final DeviceIdentityService instance = DeviceIdentityService._();

  DeviceIdentityService._();

  final Random _random = Random.secure();
  String? _cached;

  Future<String> load() async {
    if (_cached != null && _cached!.trim().isNotEmpty) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        final id =
            decoded is Map ? (decoded['deviceId'] as String? ?? '').trim() : '';
        if (id.isNotEmpty) {
          _cached = id;
          return id;
        }
      } catch (_) {
        // Fall through to generate.
      }
    }

    final next = _generateDeviceId();
    _cached = next;
    await prefs.setString(_prefsKey, jsonEncode({'deviceId': next}));
    return next;
  }

  String _generateDeviceId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = _random.nextInt(1 << 31).toRadixString(36);
    return 'dev_$now$salt';
  }
}
