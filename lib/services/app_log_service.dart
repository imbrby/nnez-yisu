import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class AppLogService {
  AppLogService._();

  static final AppLogService instance = AppLogService._();

  static const int _maxLogFileBytes = 1024 * 1024;
  static const int _flushIntervalMs = 500;

  File? _logFile;
  bool _initialized = false;
  final StringBuffer _buffer = StringBuffer();
  bool _flushScheduled = false;

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
    await _appendAndFlush('===== New Session =====', level: 'INFO', tag: 'BOOT');
  }

  Future<void> info(String message, {String tag = 'APP'}) {
    return _append(level: 'INFO', tag: tag, message: message);
  }

  Future<void> warn(String message, {String tag = 'APP'}) {
    return _append(level: 'WARN', tag: tag, message: message);
  }

  Future<void> error(
    String message, {
    String tag = 'APP',
    Object? error,
    StackTrace? stackTrace,
  }) {
    final buf = StringBuffer(message);
    if (error != null) {
      buf
        ..write('\nerror: ')
        ..write(error);
    }
    if (stackTrace != null) {
      buf
        ..write('\nstack:\n')
        ..write(stackTrace);
    }
    return _append(level: 'ERROR', tag: tag, message: buf.toString());
  }

  Future<void> clear() async {
    await flush();
    final file = _logFile;
    if (file != null) {
      await file.writeAsString('', flush: true);
    }
    await _appendAndFlush('日志已清空', level: 'INFO', tag: 'LOG');
  }

  Future<String> readRecent({int maxLines = 300}) async {
    await flush();
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

  Future<void> _append({
    required String level,
    required String tag,
    required String message,
  }) async {
    final now = DateTime.now().toIso8601String();
    final normalized = message.replaceAll('\r\n', '\n');
    _buffer.write('[$now][$level][$tag] $normalized\n');
    _scheduleFlush();
  }

  Future<void> _appendAndFlush(
    String message, {
    required String level,
    required String tag,
  }) async {
    final now = DateTime.now().toIso8601String();
    final normalized = message.replaceAll('\r\n', '\n');
    _buffer.write('[$now][$level][$tag] $normalized\n');
    await flush();
  }

  void _scheduleFlush() {
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: _flushIntervalMs), () {
      _flushScheduled = false;
      flush();
    });
  }

  Future<void> flush() async {
    final file = _logFile;
    if (file == null || _buffer.isEmpty) {
      return;
    }
    final data = _buffer.toString();
    _buffer.clear();
    try {
      await file.writeAsString(data, mode: FileMode.append, flush: true);
      await _rotateIfNeeded();
    } catch (_) {
      // Silently drop log data on write failure to avoid cascading errors.
    }
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
}
