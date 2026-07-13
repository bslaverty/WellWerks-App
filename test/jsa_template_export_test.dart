import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellwerks/models/jsa_draft.dart';
import 'package:wellwerks/models/jsa_template.dart';
import 'package:wellwerks/services/jsa_export_service.dart';
import 'package:wellwerks/services/jsa_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory =
        await Directory.systemTemp.createTemp('wellwerks_jsa_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      switch (methodCall.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getApplicationSupportDirectory':
        case 'getTemporaryDirectory':
          return tempDirectory.path;
        default:
          return tempDirectory.path;
      }
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  JsaDraft buildTemplateDraft() {
    final production = JsaBuiltInTemplates.byId('production')!;
    return JsaDraft(
      activeJobId: 'job-1',
      templateId: production.id,
      templateName: production.name,
      company: 'Mach Energy',
      date: '2026-07-12',
      time: '06:00',
      location: 'Pad A',
      wellName: 'Alpha 12H',
      county: 'County A',
      cityState: 'Midland, TX',
      gpsCoordinates: '12.34567, -98.76543',
      task: production.name,
      tasks: <String>[production.name],
      steps: List<String>.from(production.basicJobSteps),
      hazards: List<String>.from(production.hazards),
      recommendations: List<String>.from(production.recommendedActions),
      employees: List.generate(6, (_) => JsaEmployee()),
      notes: 'Template export coverage',
      weatherTemperature: '75 F',
      weatherConditions: 'Clear',
      weatherWind: '5 mph',
    );
  }

  test('PDF export contains expected document/table tokens', () async {
    final service = JsaExportService();
    final draft = buildTemplateDraft();

    final exported = await service.exportPdf(draft: draft);
    final file = File(exported.filePath);

    expect(await file.exists(), isTrue);
    final bytes = await file.readAsBytes();
    expect(bytes.length, greaterThan(1000));

    final text = latin1.decode(bytes, allowInvalid: true);
    expect(text, contains('[(WellWerks)]TJ'));
    expect(text, contains('[(JSA)]TJ'));
    expect(text, contains('[(Job)]TJ'));
    expect(text, contains('[(Information)]TJ'));
    expect(text, contains('[(Basic)]TJ'));
    expect(text, contains('[(Hazard)]TJ'));
    expect(text, contains('[(Recommended)]TJ'));
    expect(text, contains('[(Well)]TJ'));
    expect(text, contains('[(Name)]TJ'));
    expect(text, contains('[(Page)]TJ'));
  });

  test('Template-driven row export writes step, hazard, and action tokens',
      () async {
    final service = JsaExportService();
    final draft = buildTemplateDraft();
    final exported = await service.exportPdf(draft: draft);
    final bytes = await File(exported.filePath).readAsBytes();
    final text = latin1.decode(bytes, allowInvalid: true);

    expect(text, contains('[(Conduct)]TJ'));
    expect(text, contains('[(Unfamiliar)]TJ'));
    expect(text, contains('[(Review)]TJ'));
    expect(text, contains('[(Inspect)]TJ'));
    expect(text, contains('[(High-pressure)]TJ'));
  });

  test('Current JSA edits export and removed template rows are omitted',
      () async {
    final service = JsaExportService();
    final draft = JsaDraft(
      activeJobId: 'job-edit',
      templateId: 'production',
      templateName: 'Production',
      company: 'Mach Energy',
      date: '2026-07-12',
      time: '6:00 PM',
      location: 'Pad B',
      wellName: 'Edited Well',
      county: 'County B',
      cityState: 'Odessa, TX',
      gpsCoordinates: '1, 2',
      task: 'Production',
      tasks: const <String>['Production'],
      steps: const <String>[
        'Operator edited step one',
        'Operator edited step two',
      ],
      hazards: const <String>[
        'STEP 1',
        '• Operator hazard one',
        '• Operator hazard two',
        'STEP 2',
        '• Operator hazard three',
      ],
      recommendations: const <String>[
        'STEP 1',
        '• Operator action one',
        'STEP 2',
        '• Operator action two',
      ],
      employees: List.generate(6, (_) => JsaEmployee()),
      notes: 'Edited note',
    );

    final editedBytes =
        await File((await service.exportPdf(draft: draft)).filePath)
            .readAsBytes();
    final templateBytes = await File(
      (await service.exportPdf(draft: buildTemplateDraft())).filePath,
    ).readAsBytes();

    expect(latin1.decode(editedBytes, allowInvalid: true),
        contains('[(Operator)]TJ'));
    expect(editedBytes.length, isNot(templateBytes.length));
  });

  test('PDF includes page numbering on long exports', () async {
    final service = JsaExportService();
    final draft = buildTemplateDraft();
    final longNotes =
        List<String>.generate(200, (index) => 'Long note $index').join('\n');

    final exported = await service.exportPdf(
      draft: draft,
      baseFileName: 'long_jsa',
    );
    final file = File(exported.filePath);
    final firstBytes = await file.readAsBytes();
    final firstText = latin1.decode(firstBytes, allowInvalid: true);
    expect(firstText, contains('[(Page)]TJ'));

    final exportedLong = await service.exportPdf(
      draft: JsaDraft(
        activeJobId: draft.activeJobId,
        templateId: draft.templateId,
        templateName: draft.templateName,
        company: draft.company,
        date: draft.date,
        time: draft.time,
        location: draft.location,
        wellName: draft.wellName,
        county: draft.county,
        cityState: draft.cityState,
        gpsCoordinates: draft.gpsCoordinates,
        task: draft.task,
        tasks: draft.tasks,
        steps: draft.steps,
        hazards: draft.hazards,
        recommendations: draft.recommendations,
        employees: draft.employees,
        notes: longNotes,
      ),
      baseFileName: 'long_jsa_multi',
    );
    final longText = latin1.decode(
      await File(exportedLong.filePath).readAsBytes(),
      allowInvalid: true,
    );
    expect(longText, contains('[(Page)]TJ'));
  });

  test('Page image export writes one file per page with sequential names',
      () async {
    final service = JsaExportService(
      rasterizer: (pdfBytes) async => <Uint8List>[
        Uint8List.fromList(List<int>.filled(64, 1)),
        Uint8List.fromList(List<int>.filled(64, 2)),
      ],
    );
    final draft = buildTemplateDraft();

    final exported = await service.exportPageImages(
      draft: draft,
      baseFileName: 'Custom_JSA.pdf',
    );

    expect(exported, hasLength(2));
    expect(exported.first.fileName, 'Custom_JSA_Page-1.png');
    expect(exported.last.fileName, 'Custom_JSA_Page-2.png');
    expect(await File(exported.first.filePath).exists(), isTrue);
    expect(await File(exported.last.filePath).exists(), isTrue);
  });

  test('Old JSA records remain compatible without template identifiers', () {
    final legacyJson = <String, dynamic>{
      'activeJobId': 'legacy-job',
      'company': 'Legacy Co',
      'date': '2026-07-10',
      'time': '12:00',
      'location': 'Legacy Pad',
      'task': 'Flowback',
      'steps': <String>['Legacy Step'],
      'hazards': <String>['Legacy Hazard'],
      'recommendations': <String>['Legacy Action'],
      'employees': <Map<String, dynamic>>[],
      'notes': '',
    };

    final draft = JsaDraft.fromJson(legacyJson);
    expect(draft.templateId, '');
    expect(draft.templateName, '');
    expect(draft.task, 'Flowback');
    expect(draft.steps, const <String>['Legacy Step']);
  });

  test('Template content persists for current JSA and JSA history', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = JsaStorageService();
    final rigUp = JsaBuiltInTemplates.byId('rig_up')!;

    final draft = JsaDraft(
      activeJobId: 'job-history',
      templateId: rigUp.id,
      templateName: rigUp.name,
      company: 'Mach Energy',
      date: '2026-07-12',
      time: '07:00',
      location: 'History Pad',
      task: rigUp.name,
      tasks: <String>[rigUp.name],
      steps: List<String>.from(rigUp.basicJobSteps),
      hazards: List<String>.from(rigUp.hazards),
      recommendations: List<String>.from(rigUp.recommendedActions),
      employees: List.generate(6, (_) => JsaEmployee()),
      notes: '',
    );

    await storage.saveDraft(draft);
    final current = await storage.loadDraft(
      activeJobId: 'job-history',
      date: '2026-07-12',
    );
    final history = await storage.loadAllDrafts();

    expect(current, isNotNull);
    expect(current!.templateName, 'Rig Up');
    expect(current.steps.length, 10);
    expect(
        current.steps.first, 'Conduct pre-job meeting and review rig-up plan');
    expect(current.steps.last, 'Conduct final rig-up inspection and handoff');
    expect(history.any((item) => item.templateName == 'Rig Up'), isTrue);
  });
}
