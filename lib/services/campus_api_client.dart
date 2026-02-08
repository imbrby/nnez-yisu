import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:mobile_app/models/campus_profile.dart';
import 'package:mobile_app/models/campus_sync_payload.dart';
import 'package:mobile_app/models/transaction_record.dart';
import 'package:mobile_app/services/app_log_service.dart';

// ---------------------------------------------------------------------------
// Types for isolate boundary
// ---------------------------------------------------------------------------

typedef _FetchAllParams = ({
  String sid,
  String plainPassword,
  String startDate,
  String endDate,
  bool includeTransactions,
});

class _IsolateResult {
  const _IsolateResult({required this.payload, required this.logs});
  final CampusSyncPayload payload;
  final List<String> logs;
}

// ---------------------------------------------------------------------------
// Top-level isolate entry point
// ---------------------------------------------------------------------------

const String _baseUrl = 'http://xfxt.nnez.cn:455';
const Duration _stepTimeout = Duration(seconds: 18);

Future<_IsolateResult> _fetchAllInIsolate(_FetchAllParams params) async {
  final logs = <String>[];
  void logInfo(String msg) => logs.add('[INFO][API] $msg');
  void logError(String ctx, Object err, StackTrace st) {
    logs.add('[ERROR][API] $ctx\nerror: $err\nstack:\n$st');
  }

  logInfo(
    'fetchAll start sid=${params.sid}'
    ' includeTransactions=${params.includeTransactions}'
    ' range=${params.startDate}~${params.endDate}',
  );

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 3);
  final session = _CampusSession();

  try {
    await _bootstrapSession(client, session, logInfo);
    logInfo('session bootstrap ok cookies=${session.cookieCount}');

    final authTypeResp = await _postForm(
      client: client,
      session: session,
      path: '/interface/index',
      payload: <String, String>{'method': 'loginauthtype'},
      refererPath: '/mobile/login',
      logInfo: logInfo,
    );
    logInfo('POST loginauthtype done status=${authTypeResp.statusCode}');

    final verifyResp = await _getRequest(
      client: client,
      session: session,
      path: '/interface/getVerifyCode?${Random().nextDouble()}',
      refererPath: '/mobile/login',
      accept:
          'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      readText: false,
      logInfo: logInfo,
    );
    if (verifyResp.statusCode != 200) {
      throw Exception('验证码会话初始化失败 (${verifyResp.statusCode})');
    }
    logInfo('GET verify code done');

    final loginResp = await _postForm(
      client: client,
      session: session,
      path: '/interface/login',
      payload: <String, String>{
        'sid': params.sid,
        'passWord': base64Encode(utf8.encode(params.plainPassword)),
        'verifycode': '',
        'ismobile': '1',
      },
      refererPath: '/mobile/login',
      logInfo: logInfo,
    );
    final loginJson = _decodeJson(loginResp.body);
    if (loginResp.statusCode != 200) {
      throw Exception('登录请求失败 (${loginResp.statusCode})');
    }
    if (!_isSuccess(loginJson)) {
      throw Exception('登录失败：${_extractMessage(loginJson)}');
    }
    logInfo('login success');

    final balance =
        await _fetchBalance(client, session, params.sid, logInfo);
    logInfo('balance fetched value=${balance.toStringAsFixed(2)}');

    final profile = await _fetchProfile(client, session, logInfo);
    logInfo(
      'profile fetched sid=${profile.sid} name=${profile.studentName}',
    );

    final payload = CampusSyncPayload(
      profile: profile,
      transactions: <TransactionRecord>[],
      balance: balance,
      balanceUpdatedAt: DateTime.now(),
    );
    logInfo('fetchAll return payload ready');
    return _IsolateResult(payload: payload, logs: logs);
  } on TimeoutException catch (err, st) {
    logError('fetchAll timeout', err, st);
    throw Exception('校园接口超时，请稍后重试。');
  } on SocketException catch (err, st) {
    logError('fetchAll socket error', err, st);
    throw Exception('网络连接失败，请检查网络后重试。');
  } on HttpException catch (err, st) {
    logError('fetchAll http error', err, st);
    throw Exception('校园接口请求失败，请稍后重试。');
  } on FormatException catch (err, st) {
    logError('fetchAll format error', err, st);
    throw Exception('服务器返回数据格式异常，请稍后重试。');
  } catch (err, st) {
    logError('fetchAll unexpected error', err, st);
    rethrow;
  } finally {
    client.close(force: true);
    logInfo('http client closed');
  }
}

// ---------------------------------------------------------------------------
// Top-level HTTP helpers (callable from isolate)
// ---------------------------------------------------------------------------

Future<void> _bootstrapSession(
  HttpClient client,
  _CampusSession session,
  void Function(String) logInfo,
) async {
  final response = await _request(
    client: client,
    session: session,
    method: 'GET',
    path: '/mobile/login',
    headers: <String, String>{'accept': 'text/html,application/xhtml+xml'},
    logInfo: logInfo,
  );
  if (response.statusCode != 200) {
    throw Exception('会话初始化失败 (${response.statusCode})');
  }
  if (!session.has('ASP.NET_SessionId')) {
    throw Exception('未获取到 ASP.NET_SessionId，会话初始化失败。');
  }
  logInfo('GET /mobile/login done');
}

Future<_HttpResponse> _postForm({
  required HttpClient client,
  required _CampusSession session,
  required String path,
  required Map<String, String> payload,
  required String refererPath,
  required void Function(String) logInfo,
}) {
  final body = payload.entries
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
      )
      .join('&');
  return _request(
    client: client,
    session: session,
    method: 'POST',
    path: path,
    headers: <String, String>{
      'accept': 'application/json, text/javascript, */*; q=0.01',
      'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'x-requested-with': 'XMLHttpRequest',
      'referer': '$_baseUrl$refererPath',
    },
    body: body,
    logInfo: logInfo,
  );
}
// PLACEHOLDER_MORE_HELPERS

Future<_HttpResponse> _getRequest({
  required HttpClient client,
  required _CampusSession session,
  required String path,
  required String refererPath,
  required String accept,
  bool readText = true,
  required void Function(String) logInfo,
}) {
  return _request(
    client: client,
    session: session,
    method: 'GET',
    path: path,
    headers: <String, String>{
      'accept': accept,
      'referer': '$_baseUrl$refererPath',
    },
    readText: readText,
    logInfo: logInfo,
  );
}

Future<_HttpResponse> _request({
  required HttpClient client,
  required _CampusSession session,
  required String method,
  required String path,
  required void Function(String) logInfo,
  Map<String, String>? headers,
  String? body,
  bool readText = true,
}) async {
  final uri = Uri.parse('$_baseUrl$path');
  logInfo('$method $path openUrl');

  Future<_HttpResponse> doRequest() async {
    final request = await client.openUrl(method, uri);
    if (headers != null) {
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
    }
    session.applyTo(request.headers);
    if (body != null) {
      final bytes = utf8.encode(body);
      request.headers.set(HttpHeaders.contentLengthHeader, bytes.length);
      request.add(bytes);
    }
    logInfo('$method $path close');
    final response = await request.close();
    session.absorb(response.headers);
    if (!readText) {
      await response.drain<List<int>>(<int>[]);
      logInfo('$method $path drained');
      return _HttpResponse(statusCode: response.statusCode, body: '');
    }
    logInfo('$method $path reading body');
    final text = await const Utf8Decoder(
      allowMalformed: true,
    ).bind(response).join();
    logInfo('$method $path done status=${response.statusCode}');
    return _HttpResponse(statusCode: response.statusCode, body: text);
  }

  return doRequest().timeout(_stepTimeout);
}
// PLACEHOLDER_DOMAIN_HELPERS

Future<double> _fetchBalance(
  HttpClient client,
  _CampusSession session,
  String sid,
  void Function(String) logInfo,
) async {
  logInfo('fetchBalance start sid=$sid');
  final response = await _postForm(
    client: client,
    session: session,
    path: '/interface/index',
    payload: <String, String>{'method': 'getecardyue', 'carno': sid},
    refererPath: '/mobile/yktzxcz',
    logInfo: logInfo,
  );
  final payload = _decodeJson(response.body);
  final rawPreview = response.body.length > 300
      ? response.body.substring(0, 300)
      : response.body;
  logInfo('fetchBalance raw=$rawPreview');
  if (response.statusCode != 200 || !_isSuccess(payload)) {
    throw Exception('查询余额失败：${_extractMessage(payload)}（raw=$rawPreview）');
  }
  final value = double.tryParse(payload['data']?.toString() ?? '');
  if (value == null) {
    throw Exception('查询余额失败：余额格式异常。');
  }
  logInfo('fetchBalance done');
  return value;
}

Future<CampusProfile> _fetchProfile(
  HttpClient client,
  _CampusSession session,
  void Function(String) logInfo,
) async {
  logInfo('fetchProfile start');
  final response = await _postForm(
    client: client,
    session: session,
    path: '/interface/index',
    payload: <String, String>{'method': 'getinfo', 'stuid': '1'},
    refererPath: '/mobile/stuinfo',
    logInfo: logInfo,
  );
  final payload = _decodeJson(response.body);
  if (response.statusCode != 200 || !_isSuccess(payload)) {
    throw Exception('获取用户信息失败：${_extractMessage(payload)}');
  }
  final data = payload['data'];
  if (data is! Map<String, dynamic>) {
    throw Exception('获取用户信息失败：返回数据格式错误。');
  }
  logInfo('fetchProfile done');
  return CampusProfile.fromRemote(data);
}

Map<String, dynamic> _decodeJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  return <String, dynamic>{'raw': decoded};
}

bool _isSuccess(Map<String, dynamic> payload) {
  if (payload['success'] == true) return true;
  final state = int.tryParse(payload['state']?.toString() ?? '');
  final code = int.tryParse(payload['code']?.toString() ?? '');
  return state == 200 || code == 200;
}

String _extractMessage(Map<String, dynamic> payload) {
  return (payload['msg'] ??
          payload['message'] ??
          payload['errmsg'] ??
          payload['error'] ??
          payload['info'] ??
          '未知错误')
      .toString();
}

// ---------------------------------------------------------------------------
// Public API — thin wrapper that dispatches to isolate
// ---------------------------------------------------------------------------

class CampusApiClient {
  Future<CampusSyncPayload> fetchAll({
    required String sid,
    required String plainPassword,
    required String startDate,
    required String endDate,
    bool includeTransactions = true,
    void Function(String message)? onProgress,
  }) async {
    _logInfo(
      'fetchAll dispatching to isolate sid=$sid'
      ' range=$startDate~$endDate',
    );
    final params = (
      sid: sid,
      plainPassword: plainPassword,
      startDate: startDate,
      endDate: endDate,
      includeTransactions: includeTransactions,
    );
    try {
      final result = await Isolate.run(
        () => _fetchAllInIsolate(params),
      );
      for (final line in result.logs) {
        _logInfo(line);
      }
      _logInfo('fetchAll isolate returned');
      return result.payload;
    } catch (error, stackTrace) {
      _logError('fetchAll isolate failed', error, stackTrace);
      AppLogService.instance.flush();
      rethrow;
    }
  }

  void _logInfo(String message) {
    AppLogService.instance.info(message, tag: 'API');
  }

  void _logError(String context, Object error, StackTrace stackTrace) {
    AppLogService.instance.error(
      context,
      tag: 'API',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

// ---------------------------------------------------------------------------
// Session & response helpers
// ---------------------------------------------------------------------------

class _CampusSession {
  final Map<String, String> _cookies = <String, String>{};

  int get cookieCount => _cookies.length;

  bool has(String key) => _cookies.containsKey(key);

  void applyTo(HttpHeaders headers) {
    if (_cookies.isEmpty) return;
    headers.set(
      HttpHeaders.cookieHeader,
      _cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; '),
    );
  }

  void absorb(HttpHeaders headers) {
    final values = headers[HttpHeaders.setCookieHeader];
    if (values == null || values.isEmpty) return;
    for (final raw in values) {
      final pair = raw.split(';').first.trim();
      if (pair.isEmpty) continue;
      final idx = pair.indexOf('=');
      if (idx <= 0) continue;
      final key = pair.substring(0, idx).trim();
      final value = pair.substring(idx + 1).trim();
      if (key.isNotEmpty) _cookies[key] = value;
    }
  }
}

class _HttpResponse {
  const _HttpResponse({required this.statusCode, required this.body});
  final int statusCode;
  final String body;
}
