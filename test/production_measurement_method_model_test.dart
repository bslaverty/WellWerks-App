import 'package:flutter_test/flutter_test.dart';
import 'package:wellwerks/models/production_shift.dart';
import 'package:wellwerks/models/job_setup.dart';
import 'package:wellwerks/services/job_profile_defaults_service.dart';

void main() {
  test('Build 104 defaults measurement methods to tank for legacy data', () {
    final data = ProductionWellCheckData.fromJson(const <String, dynamic>{});

    expect(
      data.waterMeasurementMethod,
      ProductionWellCheckData.measurementTank,
    );
    expect(
      data.oilMeasurementMethod,
      ProductionWellCheckData.measurementTank,
    );
    expect(data.waterMeterReading, '');
    expect(data.oilMeterReading, '');
  });

  test('Build 104 report row preserves meter method and meter values', () {
    final row = ProductionReportRow.fromJson(const <String, dynamic>{
      'hourIndex': 2,
      'time': '8 PM',
      'well': 'Horse 16-2H',
      'choke': '32/64"',
      'tbg': '1200',
      'csg': '900',
      'waterProduction': 15,
      'oilProduction': 9,
      'hourlyGas': 75,
      'gas24HourRate': 1800,
      'gasStatic': '100',
      'gasDifferential': '20',
      'gasTemp': '82',
      'sandRate': '.2',
      'waterGaugeText': 'Meter: 1234',
      'oilGaugeText': 'Meter: 4321',
      'currentWaterBbl': -1,
      'currentOilBbl': -1,
      'currentWaterMeter': 1234,
      'currentOilMeter': 4321,
      'waterMeasurementMethod': 'meter',
      'oilMeasurementMethod': 'meter',
      'currentGasAccum': 6000,
      'hoursSincePrevious': 2,
      'waterHauled': 0,
      'oilHauled': 0,
      'waterPumped': 0,
      'oilPumped': 0,
      'notes': 'meter mode row',
    });

    expect(
      row.waterMeasurementMethod,
      ProductionWellCheckData.measurementMeter,
    );
    expect(row.oilMeasurementMethod, ProductionWellCheckData.measurementMeter);
    expect(row.currentWaterMeter, 1234);
    expect(row.currentOilMeter, 4321);
  });

  test('Build 300 defaults legacy jobs to tank gauging and persists CTB', () {
    final legacy = JobSetup.fromJson(const <String, dynamic>{});
    expect(legacy.productionMeasurementMethod,
        JobSetup.productionMeasurementTankGauging);

    final ctb = legacy.copyWith(
      productionMeasurementMethod: JobSetup.productionMeasurementCtbMetered,
    );
    expect(ctb.usesCentralTankBattery, isTrue);
    expect(JobSetup.fromJson(ctb.toJson()).usesCentralTankBattery, isTrue);
  });

  test('Build 300 includes Validus in the shared Production profile list', () {
    final defaults = JobProfileDefaultsService();
    expect(defaults.companyOptions,
        contains(JobProfileDefaultsService.companyValidus));
    expect(defaults.normalizeCompany('validus'),
        JobProfileDefaultsService.companyValidus);
    expect(defaults.profileForCompany('Validus').company,
        JobProfileDefaultsService.companyValidus);
  });
}
