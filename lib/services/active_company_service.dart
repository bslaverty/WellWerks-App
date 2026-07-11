import 'package:flutter/foundation.dart';

import '../models/job_setup.dart';
import 'app_settings_service.dart';
import 'job_profile_defaults_service.dart';
import 'job_storage_service.dart';
import 'production_shift_service.dart';

class ActiveCompanyService {
  ActiveCompanyService._();

  static final ActiveCompanyService instance = ActiveCompanyService._();

  final AppSettingsService _settingsService = AppSettingsService();
  final JobStorageService _jobStorage = JobStorageService();
  final ProductionShiftService _shiftService = ProductionShiftService();
  final JobProfileDefaultsService _defaults = JobProfileDefaultsService();

  final ValueNotifier<String> activeCompany = ValueNotifier<String>('');

  bool _loaded = false;

  List<String> get companyOptions =>
      JobProfileDefaultsService.sharedCompanyOptionsAlphabetized;

  String normalize(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final normalized = _defaults.normalizeCompany(trimmed);
    if (companyOptions.contains(normalized)) {
      return normalized;
    }
    return '';
  }

  bool isValid(String value) => normalize(value).isNotEmpty;

  Future<String> ensureLoaded() async {
    if (_loaded) return activeCompany.value;

    final settings = await _settingsService.load();
    final saved = normalize(settings.activeCompany);
    if (saved.isNotEmpty) {
      activeCompany.value = saved;
      _loaded = true;
      return saved;
    }

    final fromActiveJob = await _jobStorage.loadActiveJob();
    final jobCompany = normalize(fromActiveJob?.company ?? '');
    if (jobCompany.isNotEmpty) {
      activeCompany.value = jobCompany;
      _loaded = true;
      await _persist(jobCompany);
      return jobCompany;
    }

    final shift = await _shiftService.loadActiveShift();
    final shiftCompany = normalize(shift.header.company);
    if (shiftCompany.isNotEmpty) {
      activeCompany.value = shiftCompany;
      _loaded = true;
      await _persist(shiftCompany);
      return shiftCompany;
    }

    activeCompany.value = '';
    _loaded = true;
    await _persist('');
    return '';
  }

  Future<void> setActiveCompany(
    String company, {
    bool syncActiveJob = true,
    bool syncActiveShift = true,
  }) async {
    await ensureLoaded();

    final normalized = normalize(company);
    final next = company.trim().isEmpty ? '' : normalized;
    if (next == activeCompany.value) return;

    activeCompany.value = next;
    await _persist(next);

    if (next.isEmpty) return;

    if (syncActiveJob) {
      final activeJob = await _jobStorage.loadActiveJob();
      if (activeJob != null) {
        final updatedJob = _applyCompanyToJob(activeJob, next);
        await _jobStorage.saveActiveJob(updatedJob);
      }
    }

    if (syncActiveShift) {
      final shift = await _shiftService.loadActiveShift();
      final updatedShift = shift.copyWith(
        header: shift.header.copyWith(company: next),
      );
      await _shiftService.saveActiveShift(updatedShift);
    }
  }

  Future<void> setIfValidCandidate(String candidate) async {
    final normalized = normalize(candidate);
    if (normalized.isEmpty) return;
    await setActiveCompany(normalized);
  }

  JobSetup _applyCompanyToJob(JobSetup job, String company) {
    final nextCustomer = job.customer.trim().isEmpty ? company : job.customer;
    return job.copyWith(company: company, customer: nextCustomer);
  }

  Future<void> _persist(String company) async {
    final settings = await _settingsService.load();
    await _settingsService.save(
      settings.copyWith(
        activeCompany: company,
        jsaCompanyDefault:
            company.isEmpty ? settings.jsaCompanyDefault : company,
      ),
    );
  }

  @visibleForTesting
  void resetForTest() {
    _loaded = false;
    activeCompany.value = '';
  }
}
