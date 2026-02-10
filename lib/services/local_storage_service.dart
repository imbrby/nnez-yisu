import 'dart:convert';

import 'package:nnez_yisu/models/campus_profile.dart';
import 'package:nnez_yisu/models/transaction_record.dart';
import 'package:nnez_yisu/services/app_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  LocalStorageService._(this._prefs);

  final SharedPreferences _prefs;
  Future<void> _writeQueue = Future<void>.value();

  // Active session keys
  static const _sidKey = 'campus_sid';
  static const _passwordKey = 'campus_password';
  static const _activeSidKey = 'active_sid';

  // Legacy flat keys (for migration only)
  static const _legacyProfileKey = 'campus_profile';
  static const _legacyBalanceKey = 'current_balance';
  static const _legacyBalanceUpdatedAtKey = 'balance_updated_at';
  static const _legacyTransactionsKey = 'transactions_by_month';

  // Per-user key helpers
  static String _userProfileKey(String sid) => 'user_${sid}_profile';
  static String _userBalanceKey(String sid) => 'user_${sid}_balance';
  static String _userBalanceUpdatedAtKey(String sid) =>
      'user_${sid}_balance_updated_at';

  static Future<LocalStorageService> create() async {
    final watch = Stopwatch()..start();
    final prefs = await SharedPreferences.getInstance();
    final service = LocalStorageService._(prefs);
    service._logInfo('create done in ${watch.elapsedMilliseconds}ms');
    return service;
  }

  // --- Active session ---

  bool get hasCredential => campusSid.isNotEmpty && campusPassword.isNotEmpty;

  String get campusSid => (_prefs.getString(_sidKey) ?? '').trim();

  String get campusPassword => _prefs.getString(_passwordKey) ?? '';

  String? get activeSid => _prefs.getString(_activeSidKey);

  Future<void> setActiveSid(String? sid) async {
    await _enqueueWrite('setActiveSid', () async {
      if (sid == null) {
        await _prefs.remove(_activeSidKey);
      } else {
        await _prefs.setString(_activeSidKey, sid);
      }
    });
  }

  Future<void> saveCredentials({
    required String sid,
    required String password,
  }) async {
    await _enqueueWrite('saveCredentials', () async {
      await _prefs.setString(_sidKey, sid.trim());
      await _prefs.setString(_passwordKey, password);
    });
  }

  // --- Per-user profile ---

  Future<void> saveProfile(CampusProfile profile, {String? sid}) async {
    final key = _userProfileKey(sid ?? campusSid);
    await _enqueueWrite('saveProfile', () async {
      await _prefs.setString(key, jsonEncode(profile.toJson()));
    });
  }

  CampusProfile? getProfile({String? sid}) {
    final key = _userProfileKey(sid ?? campusSid);
    final raw = _prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return CampusProfile.fromJson(decoded);
      }
      if (decoded is Map) {
        return CampusProfile.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (error) {
      _logInfo('profile parse failed: $error');
    }
    return null;
  }

  CampusProfile? get profile => getProfile();

  // --- Per-user balance ---

  Future<void> saveSyncMeta({
    required double balance,
    required String balanceUpdatedAt,
    String? sid,
  }) async {
    final s = sid ?? campusSid;
    await _enqueueWrite('saveSyncMeta', () async {
      await _prefs.setDouble(_userBalanceKey(s), balance);
      await _prefs.setString(_userBalanceUpdatedAtKey(s), balanceUpdatedAt);
    });
  }

  double? getBalance({String? sid}) =>
      _prefs.getDouble(_userBalanceKey(sid ?? campusSid));
  double? get balance => getBalance();

  String? getBalanceUpdatedAt({String? sid}) {
    final value = _prefs.getString(_userBalanceUpdatedAtKey(sid ?? campusSid));
    return (value == null || value.isEmpty) ? null : value;
  }

  String? get balanceUpdatedAt => getBalanceUpdatedAt();

  // --- Logout (preserve per-user data) ---

  Future<void> clearActiveSession() async {
    await _enqueueWrite('clearActiveSession', () async {
      await _prefs.remove(_sidKey);
      await _prefs.remove(_passwordKey);
      await _prefs.remove(_activeSidKey);
    });
  }

  // --- Legacy migration ---

  Future<void> migrateToPerUser() async {
    final sid = campusSid;
    if (sid.isEmpty) return;
    // Already migrated if active_sid exists
    if (_prefs.containsKey(_activeSidKey)) return;
    _logInfo('migrateToPerUser start sid=$sid');

    final oldProfile = _prefs.getString(_legacyProfileKey);
    if (oldProfile != null && !_prefs.containsKey(_userProfileKey(sid))) {
      await _prefs.setString(_userProfileKey(sid), oldProfile);
    }
    final oldBalance = _prefs.getDouble(_legacyBalanceKey);
    if (oldBalance != null && !_prefs.containsKey(_userBalanceKey(sid))) {
      await _prefs.setDouble(_userBalanceKey(sid), oldBalance);
    }
    final oldUpdatedAt = _prefs.getString(_legacyBalanceUpdatedAtKey);
    if (oldUpdatedAt != null &&
        !_prefs.containsKey(_userBalanceUpdatedAtKey(sid))) {
      await _prefs.setString(_userBalanceUpdatedAtKey(sid), oldUpdatedAt);
    }
    await _prefs.setString(_activeSidKey, sid);
    // Clean old flat keys
    await _prefs.remove(_legacyProfileKey);
    await _prefs.remove(_legacyBalanceKey);
    await _prefs.remove(_legacyBalanceUpdatedAtKey);
    _logInfo('migrateToPerUser done');
  }

  Map<String, List<TransactionRecord>> loadTransactionsLegacy() {
    final raw = _prefs.getString(_legacyTransactionsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, List<TransactionRecord>>{};
      for (final entry in decoded.entries) {
        final list = (entry.value as List)
            .map(
              (e) => TransactionRecord.fromJsonMap(e as Map<String, dynamic>),
            )
            .toList();
        result[entry.key] = list;
      }
      return result;
    } catch (error) {
      _logInfo('loadTransactionsLegacy parse failed: $error');
      return {};
    }
  }

  Future<void> removeLegacyTransactions() async {
    await _enqueueWrite('removeLegacyTransactions', () async {
      await _prefs.remove(_legacyTransactionsKey);
    });
  }

  // --- Write queue ---

  Future<void> _enqueueWrite(String step, Future<void> Function() action) {
    final watch = Stopwatch()..start();
    final run = _writeQueue.catchError((_) {}).then((_) async {
      _logInfo('$step start');
      await action();
      _logInfo('$step done ${watch.elapsedMilliseconds}ms');
    });
    _writeQueue = run.catchError((error, stackTrace) {
      _logError('$step failed', error, stackTrace);
    });
    return run;
  }

  void _logInfo(String message) {
    AppLogService.instance.info(message, tag: 'STORE');
  }

  void _logError(String context, Object error, StackTrace stackTrace) {
    AppLogService.instance.error(
      context,
      tag: 'STORE',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
