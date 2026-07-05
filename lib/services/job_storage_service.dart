import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/job_setup.dart';

class JobStorageService {
  static const _activeJobKey = 'wellwerks_active_job';
  static const _lastEndedJobKey = 'wellwerks_last_ended_job';
  static const _lastActiveJobIdKey = 'wellwerks_last_active_job_id_v1';

  Future<JobSetup> saveActiveJob(JobSetup job) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizeActiveJob(job);
    await prefs.setString(_activeJobKey, jsonEncode(normalized.toJson()));
    await prefs.setString(_lastActiveJobIdKey, normalized.id);
    return normalized;
  }

  Future<JobSetup?> loadActiveJob() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeJobKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return JobSetup.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await prefs.remove(_activeJobKey);
      await prefs.remove(_lastActiveJobIdKey);
      return null;
    }
  }

  Future<JobSetup?> loadLastEndedJob() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastEndedJobKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return JobSetup.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await prefs.remove(_lastEndedJobKey);
      return null;
    }
  }

  Future<String> loadLastActiveJobId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastActiveJobIdKey) ?? '';
  }

  Future<JobSetup> updateActiveJob(JobSetup job) async {
    return saveActiveJob(job);
  }

  Future<JobSetup?> endActiveJob() async {
    final prefs = await SharedPreferences.getInstance();
    final activeJob = await loadActiveJob();
    if (activeJob == null) return null;

    final endedJob = activeJob.copyWith(
      status: 'ended',
      startedAt: activeJob.startedAt ?? DateTime.now(),
      endedAt: DateTime.now(),
    );

    await prefs.setString(_lastEndedJobKey, jsonEncode(endedJob.toJson()));
    await prefs.remove(_activeJobKey);
    await prefs.remove(_lastActiveJobIdKey);
    return endedJob;
  }

  Future<JobSetup> duplicateJobForNewJob(JobSetup job) async {
    final duplicated = job.copyWith(
      id: '',
      status: 'active',
      startedAt: DateTime.now(),
      endedAt: null,
    );
    return saveActiveJob(duplicated);
  }

  Future<void> deleteJob() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeJobKey);
    await prefs.remove(_lastEndedJobKey);
    await prefs.remove(_lastActiveJobIdKey);
  }

  Future<void> clearActiveJob() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeJobKey);
    await prefs.remove(_lastActiveJobIdKey);
  }

  Future<void> clearLastEndedJob() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastEndedJobKey);
  }

  JobSetup _normalizeActiveJob(JobSetup job) {
    final startedAt = job.startedAt ?? DateTime.now();
    final id = job.id.trim().isEmpty
        ? startedAt.microsecondsSinceEpoch.toString()
        : job.id;
    return job.copyWith(
      id: id,
      status: 'active',
      startedAt: startedAt,
      endedAt: null,
    );
  }
}
