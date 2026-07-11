import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/services/job_profile_defaults_service.dart';
import 'package:wellwerks/services/report_profile_service.dart';
import 'package:wellwerks/utils/flywheel_text_update_formatter.dart';

void main() {
  test('flywheel formatter preserves required field order and labels', () {
    final text = buildFlywheelTextUpdate(
      updateLine: '6:00pm update',
      locationLine: 'Sylvan Pad',
      wells: const [
        FlywheelWellLineData(
          wellName: 'Sylvan 2',
          tubing: '1777',
          csg: '1218',
          choke: '36/128',
          oil: '110',
          water: '64',
          diff: '168',
          stat: '127',
          temp: '126',
          mcf: '3949',
          sand: '0',
        ),
      ],
    );

    final expected = [
      '6:00pm update',
      'Sylvan Pad',
      '',
      'Sylvan 2',
      'Tubing 1777',
      'CSG- 1218',
      'Ck- 36/128',
      'Oil- 110',
      'Wtr- 64',
      'Diff- 168',
      'Stat- 127',
      'Temp- 126',
      'MCF- 3949',
      'Sand 0 cup/hr',
    ].join('\n');

    expect(text, expected);
  });

  test('flywheel formatter keeps one blank line between wells', () {
    final text = buildFlywheelTextUpdate(
      updateLine: '6:00pm update',
      locationLine: 'Sylvan Pad',
      wells: const [
        FlywheelWellLineData(
          wellName: 'Well A',
          tubing: '1',
          csg: '2',
          choke: '3',
          oil: '4',
          water: '5',
          diff: '6',
          stat: '7',
          temp: '8',
          mcf: '9',
          sand: '10',
        ),
        FlywheelWellLineData(
          wellName: 'Well B',
          tubing: '1',
          csg: '2',
          choke: '3',
          oil: '4',
          water: '5',
          diff: '6',
          stat: '7',
          temp: '8',
          mcf: '9',
          sand: '10',
        ),
      ],
    );

    expect(text.contains('Sand 10 cup/hr\n\nWell B'), isTrue);
  });

  test('flywheel company normalizes and profile exists', () {
    final defaults = JobProfileDefaultsService();
    final profileService = ReportProfileService();

    expect(
      defaults.normalizeCompany('flywheel'),
      JobProfileDefaultsService.companyFlywheel,
    );

    final hasFlywheel = profileService
        .systemProfiles()
        .any((profile) => profile.id == ReportProfileService.flywheelProfileId);
    expect(hasFlywheel, isTrue);
  });
}
