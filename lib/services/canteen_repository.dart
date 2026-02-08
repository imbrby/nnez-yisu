import 'dart:async';

import 'package:mobile_app/models/campus_profile.dart';
import 'package:mobile_app/services/app_log_service.dart';
import 'package:mobile_app/services/campus_api_client.dart';
import 'package:mobile_app/services/local_storage_service.dart';

class CanteenRepository {
  CanteenRepository._(this._storage, this._apiClient);

  final LocalStorageService _storage;
  final CampusApiClient _apiClient;
  CampusProfile? _volatileProfile;
  double? _volatileBalance;
  String? _volatileBalanceUpdatedAt;

  static Future<CanteenRepository> create() async {
    final storage = await LocalStorageService.create();
    final apiClient = CampusApiClient();
    final repo = CanteenRepository._(storage, apiClient);
    return repo;
  }

  bool get hasCredential => _storage.hasCredential;

  CampusProfile? get profile => _volatileProfile ?? _storage.profile;

  double? get balance => _volatileBalance ?? _storage.balance;

  String? get balanceUpdatedAt =>
      _volatileBalanceUpdatedAt ?? _storage.balanceUpdatedAt;

  Future<void> initializeAccount({
    required String sid,
    required String password,
    void Function(String message)? onProgress,
  }) async {
    final normalizedSid = sid.trim();
    if (normalizedSid.isEmpty || password.isEmpty) {
      throw Exception('请输入食堂账号和密码。');
    }

    onProgress?.call('正在保存账号信息...');
    await _storage.saveCredentials(sid: normalizedSid, password: password);

    final placeholder = CampusProfile(
      sid: normalizedSid,
      idCode: normalizedSid,
      studentName: '未同步用户',
      gradeName: '',
      className: '',
      academyName: '',
      specialityName: '',
    );
    _volatileProfile = placeholder;
    await _storage.saveProfile(placeholder);
    await _storage.saveSyncMeta(
      balance: 0,
      balanceUpdatedAt: '',
    );
    _volatileBalance = 0;
    _volatileBalanceUpdatedAt = '';
  }

  Future<void> syncNow({
    void Function(String message)? onProgress,
  }) async {
    if (!hasCredential) {
      throw Exception('请先在设置中初始化账号。');
    }
    final sid = _storage.campusSid;
    final password = _storage.campusPassword;

    _logInfo('sync.fetchAll start');
    final payload = await _apiClient
        .fetchAll(
          sid: sid,
          plainPassword: password,
          startDate: '2026-01-01',
          endDate: '2026-12-31',
          includeTransactions: false,
          onProgress: onProgress,
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('同步接口超时，请稍后重试。');
          },
        );
    _logInfo('sync.fetchAll ok');

    _volatileProfile = payload.profile;
    _volatileBalance = payload.balance;
    _volatileBalanceUpdatedAt = payload.balanceUpdatedAt.toIso8601String();

    await _storage.saveProfile(payload.profile);
    await _storage.saveSyncMeta(
      balance: payload.balance,
      balanceUpdatedAt: payload.balanceUpdatedAt.toIso8601String(),
    );
    _logInfo('syncNow done');
  }

  Future<void> logout() async {
    _logInfo('logout start');
    _volatileProfile = null;
    _volatileBalance = null;
    _volatileBalanceUpdatedAt = null;
    await _storage.clearAll();
    _logInfo('logout done');
  }

  Future<void> close() async {
    _logInfo('close start');
    _logInfo('close done');
  }

  void _logInfo(String message) {
    AppLogService.instance.info(message, tag: 'REPO');
  }
}
