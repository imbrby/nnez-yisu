import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class AppLogService {
  AppLogService._();

  static final AppLogService instance = AppLogService._();

  static const int _maxLogFileBytes = 1024 * 1024;

  File? _logFile;
  bool _initialized = false;
  Future<void> _queue = Future<void>.value();

  String? get logPath => _logFile?.path;

  Future<void> init() async {
    if (_initialized) {
      return;
    }
    final logsDir = await _resolveLogDirectory();
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }
    _logFile = File(path.join(logsDir.path, 'app.log'));
    _initialized = true;
    await _rotateIfNeeded();
    await info('===== New Session =====', tag: 'BOOT');
  }

  Future<void> info(String message, {String tag = 'APP'}) {
    return _write(level: 'INFO', tag: tag, message: message);
  }

  Future<void> warn(String message, {String tag = 'APP'}) {
    return _write(level: 'WARN', tag: tag, message: message);
  }

  Future<void> error(
    String message, {
    String tag = 'APP',
    Object? error,
    StackTrace? stackTrace,
  }) {
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer
        ..write('\nerror: ')
        ..write(error);
    }
    if (stackTrace != null) {
      buffer
        ..write('\nstack:\n')
        ..write(stackTrace);
    }
    return _write(level: 'ERROR', tag: tag, message: buffer.toString());
  }

  Future<void> clear() async {
    await _enqueue(() async {
      final file = _logFile;
      if (file == null) {
        return;
      }
      await file.writeAsString('', flush: true);
    });
    await info('日志已清空', tag: 'LOG');
  }

  Future<String> readRecent({int maxLines = 300}) async {
    final file = _logFile;
    if (file == null || !await file.exists()) {
      return '';
    }
    final raw = await file.readAsString();
    if (raw.isEmpty) {
      return '';
    }
    final lines = raw.split('\n');
    if (lines.length <= maxLines) {
      return raw;
    }
    final start = lines.length - maxLines;
    return lines.sublist(start).join('\n');
  }

  Future<void> _write({
    required String level,
    required String tag,
    required String message,
  }) {
    return _enqueue(() async {
      final file = _logFile;
      if (file == null) {
        return;
      }
      await _rotateIfNeeded();
      final now = DateTime.now().toIso8601String();
      final normalized = message.replaceAll('\r\n', '\n');
      final entry = '[$now][$level][$tag] $normalized\n';
      await file.writeAsString(entry, mode: FileMode.append, flush: true);
    });
  }

  Future<void> _rotateIfNeeded() async {
    final file = _logFile;
    if (file == null || !await file.exists()) {
      return;
    }
    final size = await file.length();
    if (size < _maxLogFileBytes) {
      return;
    }
    final backup = File('${file.path}.1');
    if (await backup.exists()) {
      await backup.delete();
    }
    await file.rename(backup.path);
  }

  Future<Directory> _resolveLogDirectory() async {
    final external = await getExternalStorageDirectory();
    if (external == null) {
      throw StateError('无法获取外部私有目录。');
    }
    return Directory(path.join(external.path, 'logs'));
  }

  Future<void> _enqueue(Future<void> Function() action) {
    _queue = _queue.then((_) => action()).catchError((_) {});
    return _queue;
  }
}
