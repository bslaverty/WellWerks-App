import 'dart:convert';
import 'dart:io';

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
      county: 'County A',
      cityState: 'City, ST',
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

  test('PDF export contains loaded template content and supports long content',
      () async {
    const service = JsaExportService();
    final draft = buildTemplateDraft();

    final exported = await service.exportPdf(draft: draft);
    final file = File(exported.filePath);

    expect(await file.exists(), isTrue);
    final bytes = await file.readAsBytes();
    expect(bytes.length, greaterThan(1000));

    final text = latin1.decode(bytes, allowInvalid: true);
    expect(text, contains('[(STEP)]TJ'));
    expect(text, contains('[(10)]TJ'));
    expect(text, contains('[(unnecessary)]TJ'));
    expect(text, contains('[(restrictions)]TJ'));
  });

  test('Image export writes provided bytes and preserves long content payload',
      () async {
    const service = JsaExportService();
    final draft = buildTemplateDraft();
    final pngBytes =
        Uint8List.fromList(List<int>.generate(2048, (i) => i % 255));

    final exported = await service.exportImage(
      draft: draft,
      pngBytes: pngBytes,
    );
    final file = File(exported.filePath);

    expect(await file.exists(), isTrue);
    final stored = await file.readAsBytes();
    expect(stored.length, pngBytes.length);
    expect(stored, pngBytes);
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
