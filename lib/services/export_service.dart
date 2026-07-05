import 'package:package_info_plus/package_info_plus.dart';

import 'file_writer_service.dart';
import 'job_serializer.dart';

class ExportedJobPackage {
  const ExportedJobPackage({
    required this.filePath,
    required this.fileName,
  });

  final String filePath;
  final String fileName;
}

class ExportService {
  ExportService({
    JobSerializer? serializer,
    FileWriterService? fileWriter,
  })  : _serializer = serializer ?? const JobSerializer(),
        _fileWriter = fileWriter ?? const FileWriterService();

  static const schemaVersion = '1.0';

  final JobSerializer _serializer;
  final FileWriterService _fileWriter;

  Future<ExportedJobPackage> exportJobPackage(
      JobExportSnapshot snapshot) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final now = DateTime.now();
    final package = _serializer.serialize(
      snapshot: snapshot,
      appVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
      schemaVersion: schemaVersion,
      exportDate: now,
    );

    final fileName = _buildFileName(snapshot, now);
    final written = await _fileWriter.writeJsonPackage(
      fileName: fileName,
      package: package,
    );
    return ExportedJobPackage(
      filePath: written.file.path,
      fileName: written.fileName,
    );
  }

  String _buildFileName(JobExportSnapshot snapshot, DateTime now) {
    final base = [snapshot.company, snapshot.pad, snapshot.well]
        .where((item) => item.trim().isNotEmpty)
        .join('_');
    final safeBase = (base.isEmpty ? 'job_package' : base)
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final stamp = now.toIso8601String().replaceAll(':', '-');
    return '${safeBase.isEmpty ? 'job_package' : safeBase}_$stamp.wwjob.json';
  }
}
