import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:mobile_app/models/campus_profile.dart';
import 'package:mobile_app/models/campus_sync_payload.dart';
import 'package:mobile_app/models/transaction_record.dart';

class CampusApiClient {
  static const _baseUrl = 'http://xfxt.nnez.cn:455';

  Future<CampusSyncPayload> fetchAll({
    required String sid,
    required String plainPassword,
    required String startDate,
    required String endDate,
  }) async {
    try {
      final cookieJar = CookieJar();
      final dio = Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          responseType: ResponseType.plain,
        ),
      );
      dio.interceptors.add(CookieManager(cookieJar));

      await dio.get<void>(
        '/mobile/login',
        options: Options(
          headers: <String, String>{
            'accept': 'text/html,application/xhtml+xml',
          },
        ),
      );

      final bootCookies = await cookieJar.loadForRequest(
        Uri.parse('$_baseUrl/mobile/login'),
      );
      final hasSession = bootCookies.any(
        (cookie) => cookie.name == 'ASP.NET_SessionId',
      );
      if (!hasSession) {
        throw Exception('未获取到 ASP.NET_SessionId，会话初始化失败。');
      }

      await _waitRandom(280, 760);

      await _postForm(dio, '/interface/index', <String, String>{
        'method': 'loginauthtype',
      }, refererPath: '/mobile/login');

      await _waitRandom(500, 1200);

      final verifyResp = await _get(
        dio,
        '/interface/getVerifyCode?${Random().nextDouble()}',
        refererPath: '/mobile/login',
        accept:
            'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      );
      if (verifyResp.statusCode != 200) {
        throw Exception('验证码会话初始化失败 (${verifyResp.statusCode ?? 0})');
      }

      final encodedPassword = base64Encode(utf8.encode(plainPassword));

      final loginResp = await _postForm(
        dio,
        '/interface/login',
        <String, String>{
          'sid': sid,
          'passWord': encodedPassword,
          'verifycode': '',
          'ismobile': '1',
        },
        refererPath: '/mobile/login',
      );
      final loginJson = _decodeJson(loginResp.data);
      if (loginResp.statusCode != 200) {
        throw Exception('登录请求失败 (${loginResp.statusCode ?? 0})');
      }
      if (!_isSuccess(loginJson)) {
        throw Exception('登录失败：${_extractMessage(loginJson)}');
      }

      await _waitRandom(600, 1500);

      final recordsResp =
          await _postForm(dio, '/interface/index', <String, String>{
            'method': 'getecardxfmx',
            'stuid': '1',
            'carno': sid,
            'starttime': startDate,
            'endtime': endDate,
          }, refererPath: '/mobile/yktxfjl');
      final recordsJson = _decodeJson(recordsResp.data);
      if (recordsResp.statusCode != 200) {
        throw Exception('查询流水失败 (${recordsResp.statusCode ?? 0})');
      }
      final rawData = recordsJson['data'];
      if (!_isSuccess(recordsJson) || rawData is! List) {
        throw Exception('查询流水失败：${_extractMessage(recordsJson)}');
      }

      await _waitRandom(180, 500);

      final balance = await _fetchBalance(dio, sid);
      final profile = await _fetchProfile(dio);
      final rows = _toRecords(sid: sid, rawList: rawData);

      return CampusSyncPayload(
        profile: profile,
        transactions: rows,
        balance: balance,
        balanceUpdatedAt: DateTime.now(),
      );
    } on DioException catch (error) {
      throw Exception(_formatDioError(error));
    } on FormatException {
      throw Exception('服务器返回数据格式异常，请稍后重试。');
    }
  }

  Future<Response<String>> _postForm(
    Dio dio,
    String path,
    Map<String, String> payload, {
    required String refererPath,
  }) {
    final body = payload.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');

    return dio.post<String>(
      path,
      data: body,
      options: Options(
        headers: <String, String>{
          'accept': 'application/json, text/javascript, */*; q=0.01',
          'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'x-requested-with': 'XMLHttpRequest',
          'referer': '$_baseUrl$refererPath',
        },
        responseType: ResponseType.plain,
      ),
    );
  }

  Future<Response<String>> _get(
    Dio dio,
    String path, {
    required String refererPath,
    String accept = '*/*',
  }) {
    return dio.get<String>(
      path,
      options: Options(
        headers: <String, String>{
          'accept': accept,
          'referer': '$_baseUrl$refererPath',
        },
        responseType: ResponseType.plain,
      ),
    );
  }

  Future<double> _fetchBalance(Dio dio, String sid) async {
    final response = await _postForm(dio, '/interface/index', <String, String>{
      'method': 'getecardyue',
      'carno': sid,
    }, refererPath: '/mobile/yktzxcz');
    final payload = _decodeJson(response.data);
    if (response.statusCode != 200 || !_isSuccess(payload)) {
      throw Exception('查询余额失败：${_extractMessage(payload)}');
    }
    final value = double.tryParse(payload['data']?.toString() ?? '');
    if (value == null) {
      throw Exception('查询余额失败：余额格式异常。');
    }
    return value;
  }

  Future<CampusProfile> _fetchProfile(Dio dio) async {
    final response = await _postForm(dio, '/interface/index', <String, String>{
      'method': 'getinfo',
      'stuid': '1',
    }, refererPath: '/mobile/stuinfo');
    final payload = _decodeJson(response.data);
    if (response.statusCode != 200 || !_isSuccess(payload)) {
      throw Exception('获取用户信息失败：${_extractMessage(payload)}');
    }
    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('获取用户信息失败：返回数据格式错误。');
    }
    return CampusProfile.fromRemote(data);
  }

  List<TransactionRecord> _toRecords({
    required String sid,
    required List<dynamic> rawList,
  }) {
    final records = <TransactionRecord>[];
    for (final row in rawList) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final normalized = _normalizeRow(sid, row);
      if (normalized != null) {
        records.add(normalized);
      }
    }
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
      rawPayload: jsonEncode(row),
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
}
