import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:mobile_app/models/campus_profile.dart';
import 'package:mobile_app/models/campus_sync_payload.dart';
import 'package:mobile_app/models/transaction_record.dart';
import 'package:mobile_app/services/app_log_service.dart';

class CampusApiClient {
  static const _baseUrl = 'http://xfxt.nnez.cn:455';
  static const Duration _stepTimeout = Duration(seconds: 20);

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

    final dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.plain,
      ),
    );
    final session = _CampusSession();

    try {
      onProgress?.call('正在建立会话...');
      await _bootstrapSession(dio, session);
      _logInfo('session bootstrap ok cookies=${session.cookieCount}');

      onProgress?.call('正在初始化验证码会话...');
      await _waitRandom(160, 420);
      final authTypeResp = await _postForm(
        dio: dio,
        session: session,
        path: '/interface/index',
        payload: <String, String>{'method': 'loginauthtype'},
        refererPath: '/mobile/login',
      ).timeout(_stepTimeout);
      _logInfo(
        'POST loginauthtype done status=${authTypeResp.statusCode ?? 0}',
      );

      await _waitRandom(260, 720);
      final verifyResp = await _get(
        dio: dio,
        session: session,
        path: '/interface/getVerifyCode?${Random().nextDouble()}',
        refererPath: '/mobile/login',
        accept:
            'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      ).timeout(_stepTimeout);
      if (verifyResp.statusCode != 200) {
        throw Exception('验证码会话初始化失败 (${verifyResp.statusCode ?? 0})');
      }
      _logInfo('GET verify code done');

      onProgress?.call('正在登录账号...');
      final encodedPassword = base64Encode(utf8.encode(plainPassword));
      final loginResp = await _postForm(
        dio: dio,
        session: session,
        path: '/interface/login',
        payload: <String, String>{
          'sid': sid,
          'passWord': encodedPassword,
          'verifycode': '',
          'ismobile': '1',
        },
        refererPath: '/mobile/login',
      ).timeout(_stepTimeout);
      final loginJson = _decodeJson(loginResp.data);
      if (loginResp.statusCode != 200) {
        throw Exception('登录请求失败 (${loginResp.statusCode ?? 0})');
      }
      if (!_isSuccess(loginJson)) {
        throw Exception('登录失败：${_extractMessage(loginJson)}');
      }
      _logInfo('login success');

      List<dynamic> rawData = <dynamic>[];
      if (includeTransactions) {
        onProgress?.call('正在拉取消费流水...');
        await _waitRandom(280, 840);
        final recordsResp = await _postForm(
          dio: dio,
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
        ).timeout(_stepTimeout);
        final recordsJson = _decodeJson(recordsResp.data);
        if (recordsResp.statusCode != 200) {
          throw Exception('查询流水失败 (${recordsResp.statusCode ?? 0})');
        }
        final parsed = recordsJson['data'];
        if (!_isSuccess(recordsJson) || parsed is! List) {
          throw Exception('查询流水失败：${_extractMessage(recordsJson)}');
        }
        rawData = parsed;
        _logInfo('transactions fetched rows=${rawData.length}');
      }

      onProgress?.call('正在查询余额...');
      final balance = await _fetchBalance(dio, session, sid);
      _logInfo('balance fetched value=${balance.toStringAsFixed(2)}');

      onProgress?.call('正在获取个人信息...');
      final profile = await _fetchProfile(dio, session);
      _logInfo(
        'profile fetched sid=${profile.sid} name=${profile.studentName}',
      );

      onProgress?.call('正在整理数据...');
      final rows = includeTransactions
          ? await _toRecords(sid: sid, rawList: rawData, onProgress: onProgress)
          : <TransactionRecord>[];
      _logInfo('records normalized rows=${rows.length}');

      return CampusSyncPayload(
        profile: profile,
        transactions: rows,
        balance: balance,
        balanceUpdatedAt: DateTime.now(),
      );
    } on TimeoutException catch (error, stackTrace) {
      _logError('fetchAll timeout', error, stackTrace);
      throw Exception('校园接口超时，请稍后重试。');
    } on DioException catch (error) {
      _logError('fetchAll dio error', error, error.stackTrace);
      throw Exception(_formatDioError(error));
    } on FormatException catch (error, stackTrace) {
      _logError('fetchAll format exception', error, stackTrace);
      throw Exception('服务器返回数据格式异常，请稍后重试。');
    } catch (error, stackTrace) {
      _logError('fetchAll unexpected error', error, stackTrace);
      rethrow;
    }
  }

  Future<void> _bootstrapSession(Dio dio, _CampusSession session) async {
    final response = await dio
        .get<String>(
          '/mobile/login',
          options: Options(
            headers: <String, String>{
              'accept': 'text/html,application/xhtml+xml',
            },
          ),
        )
        .timeout(_stepTimeout);

    session.absorb(response.headers);
    if (!session.has('ASP.NET_SessionId')) {
      throw Exception('未获取到 ASP.NET_SessionId，会话初始化失败。');
    }
    _logInfo('GET /mobile/login done');
  }

  Future<Response<String>> _postForm({
    required Dio dio,
    required _CampusSession session,
    required String path,
    required Map<String, String> payload,
    required String refererPath,
  }) async {
    final body = payload.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');

    final headers = <String, String>{
      'accept': 'application/json, text/javascript, */*; q=0.01',
      'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'x-requested-with': 'XMLHttpRequest',
      'referer': '$_baseUrl$refererPath',
    };
    session.applyTo(headers);

    final response = await dio.post<String>(
      path,
      data: body,
      options: Options(headers: headers, responseType: ResponseType.plain),
    );
    session.absorb(response.headers);
    return response;
  }

  Future<Response<String>> _get({
    required Dio dio,
    required _CampusSession session,
    required String path,
    required String refererPath,
    String accept = '*/*',
  }) async {
    final headers = <String, String>{
      'accept': accept,
      'referer': '$_baseUrl$refererPath',
    };
    session.applyTo(headers);

    final response = await dio.get<String>(
      path,
      options: Options(headers: headers, responseType: ResponseType.plain),
    );
    session.absorb(response.headers);
    return response;
  }

  Future<double> _fetchBalance(
    Dio dio,
    _CampusSession session,
    String sid,
  ) async {
    _logInfo('fetchBalance start sid=$sid');
    final response = await _postForm(
      dio: dio,
      session: session,
      path: '/interface/index',
      payload: <String, String>{'method': 'getecardyue', 'carno': sid},
      refererPath: '/mobile/yktzxcz',
    ).timeout(_stepTimeout);
    final payload = _decodeJson(response.data);
    if (response.statusCode != 200 || !_isSuccess(payload)) {
      throw Exception('查询余额失败：${_extractMessage(payload)}');
    }
    final value = double.tryParse(payload['data']?.toString() ?? '');
    if (value == null) {
      throw Exception('查询余额失败：余额格式异常。');
    }
    _logInfo('fetchBalance done');
    return value;
  }

  Future<CampusProfile> _fetchProfile(Dio dio, _CampusSession session) async {
    _logInfo('fetchProfile start');
    final response = await _postForm(
      dio: dio,
      session: session,
      path: '/interface/index',
      payload: <String, String>{'method': 'getinfo', 'stuid': '1'},
      refererPath: '/mobile/stuinfo',
    ).timeout(_stepTimeout);
    final payload = _decodeJson(response.data);
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
    void Function(String message)? onProgress,
  }) async {
    _logInfo('_toRecords start sid=$sid raw=${rawList.length}');
    final records = <TransactionRecord>[];
    final total = rawList.length;
    var index = 0;

    for (final row in rawList) {
      index += 1;
      if (row is! Map<String, dynamic>) {
        if (index % 100 == 0) {
          onProgress?.call('正在整理数据...$index/$total');
          await Future<void>.delayed(Duration.zero);
        }
        continue;
      }

      final normalized = _normalizeRow(sid, row);
      if (normalized != null) {
        records.add(normalized);
      }
      if (index % 100 == 0) {
        onProgress?.call('正在整理数据...$index/$total');
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
    final dynamic decoded = jsonDecode(raw);
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

  Future<void> _waitRandom(int minMs, int maxMs) async {
    final value = minMs + Random().nextInt(maxMs - minMs + 1);
    await Future<void>.delayed(Duration(milliseconds: value));
  }

  String _formatDioError(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout) {
      return '连接超时，请检查网络后重试。';
    }
    if (error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return '请求超时，请稍后重试。';
    }
    if (error.type == DioExceptionType.connectionError) {
      return '网络连接失败，请检查网络后重试。';
    }
    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      return '网络请求失败（HTTP $statusCode）。';
    }
    return '网络请求失败，请稍后重试。';
  }

  void _logInfo(String message) {
    unawaited(AppLogService.instance.info(message, tag: 'API'));
  }

  void _logError(String context, Object error, StackTrace stackTrace) {
    unawaited(
      AppLogService.instance.error(
        context,
        tag: 'API',
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }
}

class _CampusSession {
  final Map<String, String> _cookies = <String, String>{};

  int get cookieCount => _cookies.length;

  bool has(String key) => _cookies.containsKey(key);

  void applyTo(Map<String, String> headers) {
    if (_cookies.isEmpty) {
      return;
    }
    headers['cookie'] = _cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  void absorb(Headers headers) {
    final setCookieValues = headers['set-cookie'];
    if (setCookieValues == null || setCookieValues.isEmpty) {
      return;
    }
    for (final raw in setCookieValues) {
      final firstPart = raw.split(';').first.trim();
      if (firstPart.isEmpty) {
        continue;
      }
      final idx = firstPart.indexOf('=');
      if (idx <= 0) {
        continue;
      }
      final name = firstPart.substring(0, idx).trim();
      final value = firstPart.substring(idx + 1).trim();
      if (name.isNotEmpty) {
        _cookies[name] = value;
      }
    }
  }
}
