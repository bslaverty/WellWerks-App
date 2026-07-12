import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/job_setup.dart';
import 'app_settings_service.dart';
import 'job_box_inventory_service.dart';
import 'job_profile_defaults_service.dart';
import 'job_storage_service.dart';
import 'production_shift_service.dart';

enum ActiveCompanyChangeStatus {
  unchanged,
  changed,
}

class ActiveCompanyService {
  ActiveCompanyService._();

  static final ActiveCompanyService instance = ActiveCompanyService._();

  final AppSettingsService _settingsService = AppSettingsService();
  final JobStorageService _jobStorage = JobStorageService();
  final ProductionShiftService _shiftService = ProductionShiftService();
  final JobBoxInventoryService _jobBoxService = JobBoxInventoryService();
  final JobProfileDefaultsService _defaults = JobProfileDefaultsService();

  final ValueNotifier<String> activeCompany =
      ValueNotifier<String>(JobProfileDefaultsService.companyNone);

  bool _loaded = false;

  List<String> get companyOptions =>
      JobProfileDefaultsService.sharedCompanyOptionsAlphabetized;

  String normalize(String value) {
    final normalized = _defaults.normalizeCompany(value.trim());
    if (companyOptions.contains(normalized)) {
      return normalized;
    }
    return JobProfileDefaultsService.companyNone;
  }

  bool isValid(String value) => companyOptions.contains(normalize(value));

  bool isNone(String value) =>
      normalize(value) == JobProfileDefaultsService.companyNone;

  Future<String> ensureLoaded() async {
    if (_loaded) return activeCompany.value;

    final settings = await _settingsService.load();
    final saved = normalize(settings.activeCompany);
    if (saved != JobProfileDefaultsService.companyNone) {
      activeCompany.value = saved;
      _loaded = true;
      return saved;
    }

    final fromActiveJob = await _jobStorage.loadActiveJob();
    final jobCompany = normalize(fromActiveJob?.company ?? '');
    if (jobCompany != JobProfileDefaultsService.companyNone) {
      activeCompany.value = jobCompany;
      _loaded = true;
      await _persist(jobCompany);
      return jobCompany;
    }

    final shift = await _shiftService.loadActiveShift();
    final shiftCompany = normalize(shift.header.company);
    if (shiftCompany != JobProfileDefaultsService.companyNone) {
      activeCompany.value = shiftCompany;
      _loaded = true;
      await _persist(shiftCompany);
      return shiftCompany;
    }

    activeCompany.value = JobProfileDefaultsService.companyNone;
    _loaded = true;
    await _persist(JobProfileDefaultsService.companyNone);
    return JobProfileDefaultsService.companyNone;
  }

  Future<void> setActiveCompany(
    String company, {
    bool syncActiveJob = true,
    bool syncActiveShift = true,
  }) async {
    await ensureLoaded();

    final normalized = normalize(company);
    final next = normalized;
    if (next == activeCompany.value) return;

    activeCompany.value = next;
    await _persist(next);

    if (next == JobProfileDefaultsService.companyNone) return;

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
    if (normalized == JobProfileDefaultsService.companyNone) return;
    await setActiveCompany(normalized);
  }

  Future<ActiveCompanyChangeStatus> setActiveCompanyWithFreshStart(
    String company,
  ) async {
    await ensureLoaded();
    final next = normalize(company);
    if (next == activeCompany.value) {
      return ActiveCompanyChangeStatus.unchanged;
    }

    await clearCurrentSetupForCompanyChange();
    await setActiveCompany(next, syncActiveJob: false, syncActiveShift: false);
    return ActiveCompanyChangeStatus.changed;
  }

  Future<void> clearCurrentSetupForCompanyChange() async {
    await _settingsService.clearActiveData();
    await _jobBoxService.clearWorkingDraft();
    await _clearDrilloutSavedSetup();
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
        jsaCompanyDefault: company == JobProfileDefaultsService.companyNone
            ? settings.jsaCompanyDefault
            : company,
      ),
    );
  }

  Future<void> _clearDrilloutSavedSetup() async {
    const drilloutPrefix = 'wellwerks_drillout_shift_change_v1';
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (key == drilloutPrefix || key.startsWith('$drilloutPrefix:')) {
        await prefs.remove(key);
      }
    }
  }

  @visibleForTesting
  void resetForTest() {
    _loaded = false;
    activeCompany.value = JobProfileDefaultsService.companyNone;
  }
}
