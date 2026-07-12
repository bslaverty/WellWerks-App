import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/job_setup.dart';
import '../models/production_shift.dart';

class JobStorageService {
  static const _activeJobKey = 'wellwerks_active_job';
  static const _lastEndedJobKey = 'wellwerks_last_ended_job';
  static const _lastActiveJobIdKey = 'wellwerks_last_active_job_id_v1';
  static const _jobsKey = 'wellwerks_jobs_list_v1';
  static final ValueNotifier<JobSetup?> _activeJobNotifier =
      ValueNotifier<JobSetup?>(null);
  static bool _activeJobHydrated = false;

  ValueListenable<JobSetup?> get activeJobListenable => _activeJobNotifier;

  Future<JobSetup> saveActiveJob(JobSetup job) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizeActiveJob(job);
    await prefs.setString(_activeJobKey, jsonEncode(normalized.toJson()));
    await prefs.setString(_lastActiveJobIdKey, normalized.id);
    await _upsertJobInList(normalized);
    _activeJobHydrated = true;
    _publishActiveJob(normalized);
    return normalized;
  }

  Future<JobSetup?> ensureActiveJobLoaded() async {
    if (_activeJobHydrated) {
      return _activeJobNotifier.value;
    }
    return loadActiveJob();
  }

  Future<List<JobSetup>> loadJobs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_jobsKey);
    if (raw == null || raw.isEmpty) return const <JobSetup>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final jobs = decoded
          .map((item) =>
              JobSetup.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      jobs.sort((a, b) {
        final aStarted = a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bStarted = b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bStarted.compareTo(aStarted);
      });
      return jobs;
    } catch (_) {
      await prefs.remove(_jobsKey);
      return const <JobSetup>[];
    }
  }

  Future<void> saveJobs(List<JobSetup> jobs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _jobsKey,
      jsonEncode(jobs.map((item) => item.toJson()).toList()),
    );
  }

  Future<JobSetup?> loadActiveJob() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeJobKey);
    if (raw == null || raw.isEmpty) {
      _activeJobHydrated = true;
      _publishActiveJob(null);
      return null;
    }
    try {
      final decoded =
          JobSetup.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final normalized = _normalizeActiveJob(decoded);
      if (!_jobsEqual(decoded, normalized)) {
        await prefs.setString(_activeJobKey, jsonEncode(normalized.toJson()));
      }
      _activeJobHydrated = true;
      _publishActiveJob(normalized);
      return normalized;
    } catch (_) {
      await prefs.remove(_activeJobKey);
      await prefs.remove(_lastActiveJobIdKey);
      _activeJobHydrated = true;
      _publishActiveJob(null);
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

  Future<JobSetup?> loadJobById(String jobId) async {
    final targetId = jobId.trim();
    if (targetId.isEmpty) return null;
    final jobs = await loadJobs();
    for (final job in jobs) {
      if (job.id == targetId) {
        return job;
      }
    }
    return null;
  }

  Future<JobSetup?> resolveProductionActiveJob(ProductionShift shift) async {
    final activeJob = await loadActiveJob();
    if (activeJob != null) {
      return activeJob;
    }
    return loadJobById(shift.activeJobId);
  }

  Future<JobSetup> updateActiveJob(JobSetup job) async {
    return saveActiveJob(job);
  }

  Future<void> setActiveJobById(String jobId) async {
    final targetId = jobId.trim();
    if (targetId.isEmpty) return;
    final jobs = await loadJobs();
    final match = jobs.where((item) => item.id == targetId).toList();
    if (match.isEmpty) return;
    await saveActiveJob(match.first);
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
    await _upsertJobInList(endedJob);
    _activeJobHydrated = true;
    _publishActiveJob(null);
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

  Future<JobSetup?> archiveJobById(String jobId) async {
    final targetId = jobId.trim();
    if (targetId.isEmpty) return null;
    final jobs = await loadJobs();
    final index = jobs.indexWhere((item) => item.id == targetId);
    if (index == -1) return null;
    final archived = jobs[index].copyWith(
      status: 'archived',
      endedAt: jobs[index].endedAt ?? DateTime.now(),
    );
    jobs[index] = archived;
    await saveJobs(jobs);

    final active = await loadActiveJob();
    if (active != null && active.id == targetId) {
      await clearActiveJob();
    }
    return archived;
  }

  Future<JobSetup?> deleteJobById(String jobId) async {
    final targetId = jobId.trim();
    if (targetId.isEmpty) return null;

    final jobs = await loadJobs();
    final index = jobs.indexWhere((item) => item.id == targetId);
    if (index == -1) return null;
    final deleted = jobs.removeAt(index);
    await saveJobs(jobs);

    final active = await loadActiveJob();
    if (active != null && active.id == targetId) {
      await clearActiveJob();
    }

    final ended = await loadLastEndedJob();
    if (ended != null && ended.id == targetId) {
      await clearLastEndedJob();
    }

    return deleted;
  }

  Future<void> deleteJob() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeJobKey);
    await prefs.remove(_lastEndedJobKey);
    await prefs.remove(_lastActiveJobIdKey);
    await prefs.remove(_jobsKey);
  }

  Future<void> clearActiveJob() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeJobKey);
    await prefs.remove(_lastActiveJobIdKey);
    _activeJobHydrated = true;
    _publishActiveJob(null);
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
    final resolvedEntries = job.resolvedWellEntries;
    return job.copyWith(
      id: id,
      status: 'active',
      startedAt: startedAt,
      endedAt: null,
      wells: resolvedEntries.map((entry) => entry.name).toList(),
      wellEntries: resolvedEntries,
    );
  }

  bool _jobsEqual(JobSetup? a, JobSetup? b) {
    if (a == null || b == null) {
      return a == b;
    }
    return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
  }

  void _publishActiveJob(JobSetup? next) {
    if (_jobsEqual(_activeJobNotifier.value, next)) {
      return;
    }
    _activeJobNotifier.value = next;
  }

  Future<void> _upsertJobInList(JobSetup job) async {
    final jobs = List<JobSetup>.from(await loadJobs());
    final index = jobs.indexWhere((item) => item.id == job.id);
    if (index == -1) {
      jobs.insert(0, job);
    } else {
      jobs[index] = job;
    }
    await saveJobs(jobs);
  }
}
