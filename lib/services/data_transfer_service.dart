import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class DataTransferService {
  static Future<void> exportAndShare(String jsonContent, String sid) async {
    final dir = await getTemporaryDirectory();
    final fileName = 'yisu_backup_${sid}_${DateTime.now().millisecondsSinceEpoch}.json';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonContent);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: '一粟数据备份',
    );
  }

  static Future<String?> pickAndReadJsonFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) return null;
    return File(path).readAsString();
  }
}
