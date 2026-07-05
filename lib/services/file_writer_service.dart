import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class WrittenJobExport {
  const WrittenJobExport({
    required this.file,
    required this.fileName,
  });

  final File file;
  final String fileName;
}

class FileWriterService {
  const FileWriterService();

  Future<WrittenJobExport> writeJsonPackage({
    required String fileName,
    required Map<String, dynamic> package,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final exportDirectory = Directory('${directory.path}/wellwerks_exports');
    if (!await exportDirectory.exists()) {
      await exportDirectory.create(recursive: true);
    }
    final file = File('${exportDirectory.path}/$fileName');
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(package));
    return WrittenJobExport(file: file, fileName: fileName);
  }
}
