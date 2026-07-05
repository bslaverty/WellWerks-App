import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/job_setup.dart';

class JobStorageService {
  static const _activeJobKey = 'wellwerks_active_job';
  static const _lastEndedJobKey = 'wellwerks_last_ended_job';

  Future<JobSetup> saveActiveJob(JobSetup job) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizeActiveJob(job);
    await prefs.setString(_activeJobKey, jsonEncode(normalized.toJson()));
    return normalized;
  }

  Future<JobSetup?> loadActiveJob() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeJobKey);
    if (raw == null || raw.isEmpty) return null;
    return JobSetup.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<JobSetup?> loadLastEndedJob() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastEndedJobKey);
    if (raw == null || raw.isEmpty) return null;
    return JobSetup.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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
    return endedJob;
  }

  Future<JobSetup> duplicateJobForNewJob(JobSetup job) async {
    final duplicated = job.copyWith(
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
  }

  Future<void> clearActiveJob() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeJobKey);
  }

  JobSetup _normalizeActiveJob(JobSetup job) {
    return job.copyWith(
      status: 'active',
      startedAt: job.startedAt ?? DateTime.now(),
      endedAt: null,
    );
  }
}
