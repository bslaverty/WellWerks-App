import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/services/active_company_service.dart';
import 'package:wellwerks/services/app_settings_service.dart';
import 'package:wellwerks/services/job_profile_defaults_service.dart';

void main() {
  final service = ActiveCompanyService.instance;
  final settingsService = AppSettingsService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service.resetForTest();
  });

  test('shared company list includes Flywheel Energy with no duplicates', () {
    final options = service.companyOptions;
    expect(options.first, JobProfileDefaultsService.companyNone);
    expect(options.contains('Custom'), isFalse);
    expect(options.contains(JobProfileDefaultsService.companyFlywheel), isTrue);
    expect(
      options
          .where((name) => name == JobProfileDefaultsService.companyFlywheel)
          .length,
      1,
    );
  });

  test('active company persists through app settings', () async {
    await service.ensureLoaded();
    await service.setActiveCompany('Flywheel Energy',
        syncActiveJob: false, syncActiveShift: false);

    final loadedSettings = await settingsService.load();
    expect(loadedSettings.activeCompany, 'Flywheel Energy');
    expect(service.activeCompany.value, 'Flywheel Energy');
  });

  test('invalid saved active company falls back safely to no selection',
      () async {
    const data = AppSettingsData(
      defaultGasUnit: AppSettingsDefaults.gasUnit,
      defaultGaugeType: AppSettingsDefaults.gaugeType,
      defaultBblPerInch: AppSettingsDefaults.bblPerInch,
      defaultGasCalculationMethod: AppSettingsDefaults.gasCalculationMethod,
      defaultChokeDisplay: AppSettingsDefaults.chokeDisplay,
      defaultOptionalReportSections: AppSettingsDefaults.optionalReportSections,
      activeCompany: 'Invalid Company',
    );
    await settingsService.save(data);

    final loaded = await service.ensureLoaded();
    expect(loaded, JobProfileDefaultsService.companyNone);
    expect(service.activeCompany.value, JobProfileDefaultsService.companyNone);
  });

  test('setIfValidCandidate updates only for valid shared companies', () async {
    await service.ensureLoaded();

    await service.setIfValidCandidate('not-in-list');
    expect(service.activeCompany.value, JobProfileDefaultsService.companyNone);

    await service.setIfValidCandidate('flywheel');
    expect(service.activeCompany.value, 'Flywheel Energy');
  });

  test('legacy Custom in settings migrates to None', () async {
    const data = AppSettingsData(
      defaultGasUnit: AppSettingsDefaults.gasUnit,
      defaultGaugeType: AppSettingsDefaults.gaugeType,
      defaultBblPerInch: AppSettingsDefaults.bblPerInch,
      defaultGasCalculationMethod: AppSettingsDefaults.gasCalculationMethod,
      defaultChokeDisplay: AppSettingsDefaults.chokeDisplay,
      defaultOptionalReportSections: AppSettingsDefaults.optionalReportSections,
      activeCompany: 'Custom',
    );
    await settingsService.save(data);

    final loaded = await service.ensureLoaded();
    expect(loaded, JobProfileDefaultsService.companyNone);
  });

  test('fresh-start company change clears current setup and updates active',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wellwerks_drillout_shift_change_v1', '{"x":1}');

    final status =
        await service.setActiveCompanyWithFreshStart('Continental Resources');

    expect(status, ActiveCompanyChangeStatus.changed);
    expect(service.activeCompany.value, 'Continental Resources');
    expect(
      prefs.getString('wellwerks_drillout_shift_change_v1'),
      isNull,
    );
  });
}
