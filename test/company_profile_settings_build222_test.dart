import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/services/job_profile_defaults_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    JobProfileDefaultsService.resetCustomProfilesForTest();
  });

  test('custom company profile persists and resolves defaults', () async {
    final service = JobProfileDefaultsService();
    await service.ensureCustomProfilesLoaded();

    await service.saveCustomProfiles(const [
      CompanyProfileSettings(
        name: 'Acme Operations',
        templateCompany: JobProfileDefaultsService.companyMach,
        defaultActiveSections: ['VRU', 'Gas Cooler'],
      ),
    ]);

    JobProfileDefaultsService.resetCustomProfilesForTest();
    final reload = JobProfileDefaultsService();
    await reload.ensureCustomProfilesLoaded();

    expect(reload.companyOptions, contains('Acme Operations'));

    final profile = reload.profileForCompany('Acme Operations');
    expect(profile.company, 'Acme Operations');
    expect(profile.wellFieldKeys, contains('chk'));
    expect(profile.defaultActiveSections, contains('VRU'));
    expect(profile.defaultActiveSections, contains('Gas Cooler'));
  });

  test('normalizeCompany resolves custom profile names case-insensitively',
      () async {
    final service = JobProfileDefaultsService();
    await service.saveCustomProfiles(const [
      CompanyProfileSettings(
        name: 'Delta Field Services',
        templateCompany: JobProfileDefaultsService.companyContinental,
        defaultActiveSections: [],
      ),
    ]);

    expect(
      service.normalizeCompany('delta field services'),
      'Delta Field Services',
    );
  });
}
