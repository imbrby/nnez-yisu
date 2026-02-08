import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mobile_app/models/campus_profile.dart';
import 'package:mobile_app/models/campus_sync_payload.dart';
import 'package:mobile_app/models/transaction_record.dart';
import 'package:mobile_app/services/app_log_service.dart';

class CampusApiClient {
  static const _baseUrl = 'http://xfxt.nnez.cn:455';
  static const Duration _stepTimeout = Duration(seconds: 18);

  Future<CampusSyncPayload> fetchAll({
    required String sid,
    required String plainPassword,
    required String startDate,
    required String endDate,
    bool includeTransactions = true,
    void Function(String message)? onProgress,
  }) async {
    _logInfo(
      'fetchAll start sid=$sid includeTransactions=$includeTransactions range=$startDate~$endDate',
    );

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 3);
    final session = _CampusSession();

    try {
      _emitProgress(onProgress, '正在建立会话...');
      await _bootstrapSession(client, session);
      _logInfo('session bootstrap ok cookies=${session.cookieCount}');

      _emitProgress(onProgress, '正在初始化验证码会话...');
      final authTypeResp = await _postForm(
        client: client,
        session: session,
        path: '/interface/index',
        payload: <String, String>{'method': 'loginauthtype'},
        refererPath: '/mobile/login',
      );
      _logInfo('POST loginauthtype done status=${authTypeResp.statusCode}');

      final verifyResp = await _get(
        client: client,
        session: session,
        path: '/interface/getVerifyCode?${Random().nextDouble()}',
        refererPath: '/mobile/login',
        accept:
            'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
        readText: false,
      );
      if (verifyResp.statusCode != 200) {
        throw Exception('验证码会话初始化失败 (${verifyResp.statusCode})');
      }
      _logInfo('GET verify code done');

      _emitProgress(onProgress, '正在登录账号...');
      final loginResp = await _postForm(
        client: client,
        session: session,
        path: '/interface/login',
        payload: <String, String>{
          'sid': sid,
          'passWord': base64Encode(utf8.encode(plainPassword)),
          'verifycode': '',
          'ismobile': '1',
        },
        refererPath: '/mobile/login',
      );
      final loginJson = _decodeJson(loginResp.body);
      if (loginResp.statusCode != 200) {
        throw Exception('登录请求失败 (${loginResp.statusCode})');
      }
      if (!_isSuccess(loginJson)) {
        throw Exception('登录失败：${_extractMessage(loginJson)}');
      }
      _logInfo('login success');

      List<dynamic> rawData = <dynamic>[];
      if (includeTransactions) {
        _emitProgress(onProgress, '正在拉取消费流水...');
        final recordsResp = await _postForm(
          client: client,
          session: session,
          path: '/interface/index',
          payload: <String, String>{
            'method': 'getecardxfmx',
            'stuid': '1',
            'carno': sid,
            'starttime': startDate,
            'endtime': endDate,
          },
          refererPath: '/mobile/yktxfjl',
        );
        final recordsJson = _decodeJson(recordsResp.body);
        if (recordsResp.statusCode != 200) {
          throw Exception('查询流水失败 (${recordsResp.statusCode})');
        }
        final parsed = recordsJson['data'];
        if (!_isSuccess(recordsJson) || parsed is! List) {
          throw Exception('查询流水失败：${_extractMessage(recordsJson)}');
        }
        rawData = parsed;
        _logInfo('transactions fetched rows=${rawData.length}');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      _emitProgress(onProgress, '正在查询余额...');
      final balance = await _fetchBalance(client, session, sid);
      _logInfo('balance fetched value=${balance.toStringAsFixed(2)}');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      _emitProgress(onProgress, '正在获取个人信息...');
      final profile = await _fetchProfile(client, session);
      _logInfo(
        'profile fetched sid=${profile.sid} name=${profile.studentName}',
      );

      _emitProgress(onProgress, '正在整理数据...');
      final rows = includeTransactions
          ? await _toRecords(sid: sid, rawList: rawData)
          : <TransactionRecord>[];
      _logInfo('records normalized rows=${rows.length}');

      final payload = CampusSyncPayload(
        profile: profile,
        transactions: rows,
        balance: balance,
        balanceUpdatedAt: DateTime.now(),
      );
      _logInfo('fetchAll return payload ready');
      return payload;
    } on TimeoutException catch (error, stackTrace) {
      _logError('fetchAll timeout', error, stackTrace);
      AppLogService.instance.flush();
      throw Exception('校园接口超时，请稍后重试。');
    } on SocketException catch (error, stackTrace) {
      _logError('fetchAll socket error', error, stackTrace);
      AppLogService.instance.flush();
      throw Exception('网络连接失败，请检查网络后重试。');
    } on HttpException catch (error, stackTrace) {
      _logError('fetchAll http error', error, stackTrace);
      AppLogService.instance.flush();
      throw Exception('校园接口请求失败，请稍后重试。');
    } on FormatException catch (error, stackTrace) {
      _logError('fetchAll format error', error, stackTrace);
      AppLogService.instance.flush();
      throw Exception('服务器返回数据格式异常，请稍后重试。');
    } catch (error, stackTrace) {
      _logError('fetchAll unexpected error', error, stackTrace);
      AppLogService.instance.flush();
      rethrow;
    } finally {
      client.close(force: true);
      _logInfo('http client closed');
    }
  }

  Future<void> _bootstrapSession(
    HttpClient client,
    _CampusSession session,
  ) async {
    final response = await _request(
      client: client,
      session: session,
      method: 'GET',
      path: '/mobile/login',
      headers: <String, String>{'accept': 'text/html,application/xhtml+xml'},
    );
    if (response.statusCode != 200) {
      throw Exception('会话初始化失败 (${response.statusCode})');
    }
    if (!session.has('ASP.NET_SessionId')) {
      throw Exception('未获取到 ASP.NET_SessionId，会话初始化失败。');
    }
    _logInfo('GET /mobile/login done');
  }

  Future<_HttpResponse> _postForm({
    required HttpClient client,
    required _CampusSession session,
    required String path,
    required Map<String, String> payload,
    required String refererPath,
  }) {
    final body = payload.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
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
    );
  }

  Future<_HttpResponse> _get({
    required HttpClient client,
    required _CampusSession session,
    required String path,
    required String refererPath,
    required String accept,
    bool readText = true,
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
    );
  }

  Future<_HttpResponse> _request({
    required HttpClient client,
    required _CampusSession session,
    required String method,
    required String path,
    Map<String, String>? headers,
    String? body,
    bool readText = true,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    _logInfo('$method $path openUrl');

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

      _logInfo('$method $path close');
      final response = await request.close();
      session.absorb(response.headers);

      if (!readText) {
        await response.drain<List<int>>(<int>[]);
        _logInfo('$method $path drained');
        return _HttpResponse(statusCode: response.statusCode, body: '');
      }

      _logInfo('$method $path reading body');
      final text = await const Utf8Decoder(
        allowMalformed: true,
      ).bind(response).join();
      _logInfo('$method $path done status=${response.statusCode}');
      return _HttpResponse(statusCode: response.statusCode, body: text);
    }

    return doRequest().timeout(_stepTimeout);
  }

  Future<double> _fetchBalance(
    HttpClient client,
    _CampusSession session,
    String sid,
  ) async {
    _logInfo('fetchBalance start sid=$sid');
    final response = await _postForm(
      client: client,
      session: session,
      path: '/interface/index',
      payload: <String, String>{'method': 'getecardyue', 'carno': sid},
      refererPath: '/mobile/yktzxcz',
    );
    final payload = _decodeJson(response.body);
    final rawPreview = response.body.length > 300
        ? response.body.substring(0, 300)
        : response.body;
    _logInfo('fetchBalance raw=$rawPreview');
    _logInfo('fetchBalance keys=${payload.keys.toList()} isSuccess=${_isSuccess(payload)}');
    if (response.statusCode != 200 || !_isSuccess(payload)) {
      throw Exception('查询余额失败：${_extractMessage(payload)}（raw=$rawPreview）');
    }
    final value = double.tryParse(payload['data']?.toString() ?? '');
    if (value == null) {
      throw Exception('查询余额失败：余额格式异常。');
    }
    _logInfo('fetchBalance done');
    return value;
  }

  Future<CampusProfile> _fetchProfile(
    HttpClient client,
    _CampusSession session,
  ) async {
    _logInfo('fetchProfile start');
    final response = await _postForm(
      client: client,
      session: session,
      path: '/interface/index',
      payload: <String, String>{'method': 'getinfo', 'stuid': '1'},
      refererPath: '/mobile/stuinfo',
    );
    final payload = _decodeJson(response.body);
    if (response.statusCode != 200 || !_isSuccess(payload)) {
      throw Exception('获取用户信息失败：${_extractMessage(payload)}');
    }
    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('获取用户信息失败：返回数据格式错误。');
    }
    _logInfo('fetchProfile done');
    return CampusProfile.fromRemote(data);
  }

  Future<List<TransactionRecord>> _toRecords({
    required String sid,
    required List<dynamic> rawList,
  }) async {
    _logInfo('_toRecords start sid=$sid raw=${rawList.length}');
    final records = <TransactionRecord>[];
    var index = 0;
    for (final row in rawList) {
      index += 1;
      if (row is! Map<String, dynamic>) {
        if (index % 100 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        continue;
      }
      final normalized = _normalizeRow(sid, row);
      if (normalized != null) {
        records.add(normalized);
      }
      if (index % 100 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    _logInfo('_toRecords done rows=${records.length}');
    return records;
  }

  TransactionRecord? _normalizeRow(String sid, Map<String, dynamic> row) {
    final txnId = (row['Id'] ?? '').toString().trim();
    if (txnId.isEmpty) {
      return null;
    }

    final amount = double.tryParse((row['Money'] ?? '').toString());
    if (amount == null) {
      return null;
    }

    final balance = double.tryParse((row['Balance'] ?? '').toString());
    final time = _normalizeCampusTime((row['Time'] ?? '').toString());
    if (time == null) {
      return null;
    }

    return TransactionRecord(
      sid: sid,
      txnId: txnId,
      amount: amount.abs(),
      balance: balance,
      occurredAt: time.$2,
      occurredDay: time.$1,
      itemName: (row['ItemName'] ?? '').toString().trim().isEmpty
          ? '未知消费点'
          : (row['ItemName'] ?? '').toString().trim(),
      rawPayload: '{}',
    );
  }

  ({String $1, String $2})? _normalizeCampusTime(String input) {
    final match = RegExp(
      r'^(\d{4})/(\d{1,2})/(\d{1,2})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})$',
    ).firstMatch(input);
    if (match == null) {
      return null;
    }
    String pad(String value) => value.padLeft(2, '0');
    final day =
        '${match.group(1)!}-${pad(match.group(2)!)}-${pad(match.group(3)!)}';
    final datetime =
        '$day ${pad(match.group(4)!)}:${pad(match.group(5)!)}:${pad(match.group(6)!)}';
    return ($1: day, $2: datetime);
  }

  Map<String, dynamic> _decodeJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{'raw': decoded};
  }

  bool _isSuccess(Map<String, dynamic> payload) {
    if (payload['success'] == true) {
      return true;
    }
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

  void _emitProgress(
    void Function(String message)? onProgress,
    String message,
  ) {
    if (onProgress == null) {
      return;
    }
    scheduleMicrotask(() {
      try {
        onProgress(message);
      } catch (error, stackTrace) {
        _logError('progress callback failed', error, stackTrace);
      }
    });
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

class _CampusSession {
  final Map<String, String> _cookies = <String, String>{};

  int get cookieCount => _cookies.length;

  bool has(String key) => _cookies.containsKey(key);

  void applyTo(HttpHeaders headers) {
    if (_cookies.isEmpty) {
      return;
    }
    headers.set(
      HttpHeaders.cookieHeader,
      _cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; '),
    );
  }

  void absorb(HttpHeaders headers) {
    final values = headers[HttpHeaders.setCookieHeader];
    if (values == null || values.isEmpty) {
      return;
    }
    for (final raw in values) {
      final pair = raw.split(';').first.trim();
      if (pair.isEmpty) {
        continue;
      }
      final idx = pair.indexOf('=');
      if (idx <= 0) {
        continue;
      }
      final key = pair.substring(0, idx).trim();
      final value = pair.substring(idx + 1).trim();
      if (key.isNotEmpty) {
        _cookies[key] = value;
      }
    }
  }
}

class _HttpResponse {
  const _HttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
