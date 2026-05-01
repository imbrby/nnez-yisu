import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class DataTransferService {
  static Future<String?> exportWithSystemFileManager(
    String jsonContent,
    String sid,
  ) async {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final fileName = 'yisu_backup_${sid}_$stamp.json';
    final bytes = Uint8List.fromList(utf8.encode(jsonContent));
    return FilePicker.platform.saveFile(
      dialogTitle: '保存导出数据',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: <String>['json'],
      bytes: bytes,
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
