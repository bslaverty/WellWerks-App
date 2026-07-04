import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/job_setup.dart';

class JobStorageService {
  static const _activeJobKey = 'wellwerks_active_job';

  Future<void> saveActiveJob(JobSetup job) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeJobKey, jsonEncode(job.toJson()));
  }

  Future<JobSetup?> loadActiveJob() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeJobKey);
    if (raw == null || raw.isEmpty) return null;
    return JobSetup.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> clearActiveJob() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeJobKey);
  }
}
