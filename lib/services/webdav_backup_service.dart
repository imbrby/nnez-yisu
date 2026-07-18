import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nnez_yisu/services/app_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum WebDavBackupMode { overwrite, createNew }

class WebDavConfig {
  const WebDavConfig({
    this.url = '',
    this.username = '',
    this.password = '',
    this.autoBackupEnabled = false,
    this.mode = WebDavBackupMode.overwrite,
    this.lastBackupAt,
  });

  final String url;
  final String username;
  final String password;
  final bool autoBackupEnabled;
  final WebDavBackupMode mode;
  final DateTime? lastBackupAt;

  bool get isConfigured =>
      url.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  WebDavConfig copyWith({
    String? url,
    String? username,
    String? password,
    bool? autoBackupEnabled,
    WebDavBackupMode? mode,
    DateTime? lastBackupAt,
  }) {
    return WebDavConfig(
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      mode: mode ?? this.mode,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
    );
  }
}

class WebDavBackupResult {
  const WebDavBackupResult({required this.fileName, required this.savedAt});

  final String fileName;
  final DateTime savedAt;
}

class WebDavBackupService {
  WebDavBackupService._();

  static final WebDavBackupService instance = WebDavBackupService._();

  static const _urlKey = 'webdav_url';
  static const _usernameKey = 'webdav_username';
  static const _passwordKey = 'webdav_password';
  static const _autoKey = 'webdav_auto_backup_enabled';
  static const _modeKey = 'webdav_backup_mode';
  static const _lastBackupKey = 'webdav_last_backup_at';

  bool _automaticBackupRunning = false;

  Future<WebDavConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final modeName = prefs.getString(_modeKey);
    final lastBackupRaw = prefs.getString(_lastBackupKey);
    return WebDavConfig(
      url: prefs.getString(_urlKey) ?? '',
      username: prefs.getString(_usernameKey) ?? '',
      password: prefs.getString(_passwordKey) ?? '',
      autoBackupEnabled: prefs.getBool(_autoKey) ?? false,
      mode: WebDavBackupMode.values.firstWhere(
        (mode) => mode.name == modeName,
        orElse: () => WebDavBackupMode.overwrite,
      ),
      lastBackupAt: DateTime.tryParse(lastBackupRaw ?? ''),
    );
  }

  Future<void> saveConfig(WebDavConfig config) async {
    _collectionUri(config.url);
    if (config.username.trim().isEmpty || config.password.isEmpty) {
      throw const FormatException('请输入 WebDAV 用户名和密码。');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, config.url.trim());
    await prefs.setString(_usernameKey, config.username.trim());
    await prefs.setString(_passwordKey, config.password);
    await prefs.setBool(_autoKey, config.autoBackupEnabled);
    await prefs.setString(_modeKey, config.mode.name);
  }

  Future<void> testConnection(WebDavConfig config) async {
    _validateConfigured(config);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final response = await _send(
        client: client,
        config: config,
        method: 'PROPFIND',
        uri: _collectionUri(config.url),
        headers: const <String, String>{'Depth': '0'},
      );
      if (response.statusCode != 200 && response.statusCode != 207) {
        throw Exception(_statusMessage('连接失败', response.statusCode));
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<WebDavBackupResult> uploadBackup(
    String jsonContent, {
    WebDavConfig? config,
  }) async {
    final activeConfig = config ?? await loadConfig();
    _validateConfigured(activeConfig);
    final collection = _collectionUri(activeConfig.url);
    final now = DateTime.now();
    final fileName = activeConfig.mode == WebDavBackupMode.overwrite
        ? 'yisu_backup.json'
        : 'yisu_backup_${_fileTimestamp(now)}.json';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      await _ensureCollection(client, activeConfig, collection);
      final response = await _send(
        client: client,
        config: activeConfig,
        method: 'PUT',
        uri: _childUri(collection, fileName),
        body: utf8.encode(jsonContent),
        headers: const <String, String>{
          HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        },
        timeout: const Duration(seconds: 60),
      );
      if (response.statusCode != 200 &&
          response.statusCode != 201 &&
          response.statusCode != 204) {
        throw Exception(_statusMessage('备份上传失败', response.statusCode));
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastBackupKey, now.toIso8601String());
      return WebDavBackupResult(fileName: fileName, savedAt: now);
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> backupIfEnabled(Future<String> Function() createJson) async {
    if (_automaticBackupRunning) return false;
    final config = await loadConfig();
    if (!config.autoBackupEnabled || !config.isConfigured) return false;
    _automaticBackupRunning = true;
    try {
      await uploadBackup(await createJson(), config: config);
      AppLogService.instance.info('WebDAV auto backup done', tag: 'BACKUP');
      return true;
    } catch (error, stackTrace) {
      AppLogService.instance.error(
        'WebDAV auto backup failed',
        tag: 'BACKUP',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      _automaticBackupRunning = false;
    }
  }

  Future<String> downloadLatestBackup({WebDavConfig? config}) async {
    final activeConfig = config ?? await loadConfig();
    _validateConfigured(activeConfig);
    final collection = _collectionUri(activeConfig.url);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final fileName = await _latestFileName(client, activeConfig, collection);
      final response = await _send(
        client: client,
        config: activeConfig,
        method: 'GET',
        uri: _childUri(collection, fileName),
        timeout: const Duration(seconds: 60),
      );
      if (response.statusCode != 200) {
        throw Exception(_statusMessage('下载云端备份失败', response.statusCode));
      }
      return response.body;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _ensureCollection(
    HttpClient client,
    WebDavConfig config,
    Uri collection,
  ) async {
    final probe = await _send(
      client: client,
      config: config,
      method: 'PROPFIND',
      uri: collection,
      headers: const <String, String>{'Depth': '0'},
    );
    if (probe.statusCode == 200 || probe.statusCode == 207) return;
    if (probe.statusCode != 404) {
      throw Exception(_statusMessage('无法访问 WebDAV 目录', probe.statusCode));
    }
    final parent = _parentCollection(collection);
    if (parent == null) {
      throw Exception('无法访问 WebDAV 服务根目录，请检查备份目录地址。');
    }
    await _ensureCollection(client, config, parent);
    final created = await _send(
      client: client,
      config: config,
      method: 'MKCOL',
      uri: collection,
    );
    if (created.statusCode != 201 && created.statusCode != 405) {
      throw Exception(_statusMessage('创建 WebDAV 目录失败', created.statusCode));
    }
    if (created.statusCode == 405) {
      final verify = await _send(
        client: client,
        config: config,
        method: 'PROPFIND',
        uri: collection,
        headers: const <String, String>{'Depth': '0'},
      );
      if (verify.statusCode != 200 && verify.statusCode != 207) {
        throw Exception(_statusMessage('无法确认 WebDAV 目录', verify.statusCode));
      }
    }
  }

  Future<String> _latestFileName(
    HttpClient client,
    WebDavConfig config,
    Uri collection,
  ) async {
    if (config.mode == WebDavBackupMode.overwrite) {
      return 'yisu_backup.json';
    }
    final response = await _send(
      client: client,
      config: config,
      method: 'PROPFIND',
      uri: collection,
      headers: const <String, String>{'Depth': '1'},
    );
    if (response.statusCode != 200 && response.statusCode != 207) {
      throw Exception(_statusMessage('读取云端备份列表失败', response.statusCode));
    }
    final names =
        RegExp(
              r'<(?:[^:>]+:)?href[^>]*>(.*?)</(?:[^:>]+:)?href>',
              caseSensitive: false,
              dotAll: true,
            )
            .allMatches(response.body)
            .map((match) => _decodeXml(match.group(1) ?? ''))
            .map((href) => Uri.tryParse(href)?.pathSegments.lastOrNull ?? '')
            .map(Uri.decodeComponent)
            .where(
              (name) =>
                  name.startsWith('yisu_backup_') && name.endsWith('.json'),
            )
            .toList()
          ..sort();
    if (names.isEmpty) throw Exception('云端没有可用于比较的备份文件。');
    return names.last;
  }

  Future<_WebDavResponse> _send({
    required HttpClient client,
    required WebDavConfig config,
    required String method,
    required Uri uri,
    Map<String, String> headers = const <String, String>{},
    List<int>? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final request = await client.openUrl(method, uri).timeout(timeout);
    final credentials = base64Encode(
      utf8.encode('${config.username.trim()}:${config.password}'),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Basic $credentials');
    request.headers.set(HttpHeaders.userAgentHeader, 'nnez-yisu-webdav');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (body != null) {
      request.headers.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close().timeout(timeout);
    final responseBody = await const Utf8Decoder(
      allowMalformed: true,
    ).bind(response).join().timeout(timeout);
    return _WebDavResponse(statusCode: response.statusCode, body: responseBody);
  }

  static Uri _collectionUri(String raw) {
    final value = raw.trim();
    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw const FormatException('请输入有效的 HTTP 或 HTTPS WebDAV 目录地址。');
    }
    final path = parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/';
    return parsed.replace(path: path);
  }

  static Uri _childUri(Uri collection, String fileName) {
    return collection.replace(
      pathSegments: <String>[
        ...collection.pathSegments.where((segment) => segment.isNotEmpty),
        fileName,
      ],
    );
  }

  static Uri? _parentCollection(Uri collection) {
    final segments = collection.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) return null;
    segments.removeLast();
    return collection.replace(pathSegments: <String>[...segments, '']);
  }

  static void _validateConfigured(WebDavConfig config) {
    _collectionUri(config.url);
    if (config.username.trim().isEmpty || config.password.isEmpty) {
      throw Exception('请先完成 WebDAV 配置。');
    }
  }

  static String _fileTimestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }

  static String _decodeXml(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();

  static String _statusMessage(String action, int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return '$action：认证失败，请检查用户名和密码。';
    }
    if (statusCode == 404) return '$action：目录或文件不存在。';
    if (statusCode == 507) return '$action：云端空间不足。';
    return '$action（HTTP $statusCode）。';
  }
}

class _WebDavResponse {
  const _WebDavResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
