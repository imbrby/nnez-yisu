import 'dart:async';
import 'dart:convert';

import 'package:mobile_app/models/campus_profile.dart';
import 'package:mobile_app/models/recharge_record.dart';
import 'package:mobile_app/models/transaction_record.dart';
import 'package:mobile_app/services/app_log_service.dart';
import 'package:mobile_app/services/campus_api_client.dart';
import 'package:mobile_app/services/local_database_service.dart';
import 'package:mobile_app/services/local_storage_service.dart';

class CanteenRepository {
  CanteenRepository._(this._storage, this._db, this._apiClient);

  final LocalStorageService _storage;
  final LocalDatabaseService _db;
  final CampusApiClient _apiClient;
  CampusProfile? _volatileProfile;
  double? _volatileBalance;
  String? _volatileBalanceUpdatedAt;

  static Future<CanteenRepository> create() async {
    final storage = await LocalStorageService.create();
    final db = LocalDatabaseService();
    await db.init();
    final apiClient = CampusApiClient();
    final repo = CanteenRepository._(storage, db, apiClient);
    // Migrate legacy data
    await storage.migrateToPerUser();
    await repo._migrateLegacyTransactions();
    return repo;
  }

  bool get hasCredential => _storage.hasCredential;

  String get currentSid => _storage.campusSid;

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
    await _storage.setActiveSid(normalizedSid);

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

  Future<List<TransactionRecord>> syncNow({
    void Function(String message)? onProgress,
  }) async {
    if (!hasCredential) {
      throw Exception('请先在设置中初始化账号。');
    }
    final sid = _storage.campusSid;
    final password = _storage.campusPassword;

    // 获取近30天的起止日期
    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 30));
    final endDate = now;

    _logInfo('sync.fetchAll start');
    final payload = await _apiClient
        .fetchAll(
          sid: sid,
          plainPassword: password,
          startDate: '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
          endDate: '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}',
          includeTransactions: true,
          onProgress: onProgress,
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('同步接口超时，请稍后重试。');
          },
        );
    _logInfo('sync.fetchAll ok, got ${payload.transactions.length} transactions');

    _volatileProfile = payload.profile;
    _volatileBalance = payload.balance;
    _volatileBalanceUpdatedAt = payload.balanceUpdatedAt.toIso8601String();

    await _storage.saveProfile(payload.profile);
    await _storage.saveSyncMeta(
      balance: payload.balance,
      balanceUpdatedAt: payload.balanceUpdatedAt.toIso8601String(),
    );

    // Save transactions to SQLite with sid
    final stamped = payload.transactions.map((t) => t.withSid(sid)).toList();
    await _db.upsertTransactions(sid, stamped);

    // Save recharges to SQLite with sid
    final stampedRecharges = payload.recharges.map((r) => r.withSid(sid)).toList();
    await _db.upsertRecharges(sid, stampedRecharges);

    _logInfo('syncNow done');

    return stamped;
  }

  Future<Map<String, List<TransactionRecord>>> loadTransactions() async {
    final sid = currentSid;
    if (sid.isEmpty) return {};
    // Query all transactions for this user from SQLite
    final rows = await _db.queryByDayRange(
      sid: sid,
      startDate: '2000-01-01',
      endDate: '2099-12-31',
    );
    final byMonth = <String, List<TransactionRecord>>{};
    for (final txn in rows) {
      final key = txn.occurredDay.substring(0, 7);
      (byMonth[key] ??= []).add(txn);
    }
    return byMonth;
  }

  Future<void> logout() async {
    _logInfo('logout start');
    _volatileProfile = null;
    _volatileBalance = null;
    _volatileBalanceUpdatedAt = null;
    await _storage.clearActiveSession();
    _logInfo('logout done');
  }

  Future<void> close() async {
    _logInfo('close start');
    await _db.close();
    _logInfo('close done');
  }

  Future<String> exportToJson() async {
    final sid = currentSid;
    if (sid.isEmpty) throw Exception('没有登录的账号。');
    final profileData = profile;
    final rows = await _db.queryByDayRange(
      sid: sid,
      startDate: '2000-01-01',
      endDate: '2099-12-31',
    );
    final data = <String, dynamic>{
      'version': 1,
      'sid': sid,
      'exportedAt': DateTime.now().toIso8601String(),
      if (profileData != null) 'profile': profileData.toJson(),
      'balance': balance,
      'balanceUpdatedAt': balanceUpdatedAt,
      'transactions': rows.map((t) => t.toJson()).toList(),
    };
    return jsonEncode(data);
  }

  Future<int> importFromJson(String jsonString) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final sid = currentSid;
    if (sid.isEmpty) throw Exception('请先登录账号再导入数据。');

    // Import profile if present
    if (data['profile'] != null) {
      final importedProfile = CampusProfile.fromJson(
        data['profile'] as Map<String, dynamic>,
      );
      await _storage.saveProfile(importedProfile, sid: sid);
      _volatileProfile = importedProfile;
    }

    // Import balance if present
    if (data['balance'] != null) {
      await _storage.saveSyncMeta(
        balance: (data['balance'] as num).toDouble(),
        balanceUpdatedAt: (data['balanceUpdatedAt'] ?? '').toString(),
        sid: sid,
      );
      _volatileBalance = (data['balance'] as num).toDouble();
      _volatileBalanceUpdatedAt = (data['balanceUpdatedAt'] ?? '').toString();
    }

    // Import transactions
    final txnList = data['transactions'] as List<dynamic>? ?? [];
    final records = txnList
        .map((e) => TransactionRecord.fromJsonMap(e as Map<String, dynamic>))
        .map((t) => t.withSid(sid))
        .toList();
    if (records.isNotEmpty) {
      await _db.upsertTransactions(sid, records);
    }
    _logInfo('importFromJson done: ${records.length} transactions');
    return records.length;
  }

  Future<List<RechargeRecord>> loadRecentRecharges({int limit = 20}) async {
    final sid = currentSid;
    if (sid.isEmpty) return [];
    return _db.queryRecentRecharges(sid: sid, limit: limit);
  }

  Future<String> reportLoss() async {
    if (!hasCredential) throw Exception('请先登录账号。');
    final sid = _storage.campusSid;
    final password = _storage.campusPassword;
    return _apiClient.reportLoss(sid: sid, plainPassword: password);
  }

  Future<String> cancelLoss() async {
    if (!hasCredential) throw Exception('请先登录账号。');
    final sid = _storage.campusSid;
    final password = _storage.campusPassword;
    return _apiClient.cancelLoss(sid: sid, plainPassword: password);
  }

  Future<void> _migrateLegacyTransactions() async {
    final sid = currentSid;
    if (sid.isEmpty) return;
    final legacy = _storage.loadTransactionsLegacy();
    if (legacy.isEmpty) return;
    _logInfo('migrating legacy transactions for sid=$sid');
    final all = legacy.values.expand((list) => list).toList();
    final stamped = all.map((t) => t.sid.isEmpty ? t.withSid(sid) : t).toList();
    await _db.upsertTransactions(sid, stamped);
    await _storage.removeLegacyTransactions();
    _logInfo('legacy transactions migrated: ${stamped.length} rows');
  }

  void _logInfo(String message) {
    AppLogService.instance.info(message, tag: 'REPO');
  }
}
