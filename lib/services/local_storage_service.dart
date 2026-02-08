import 'dart:convert';

import 'package:mobile_app/models/campus_profile.dart';
import 'package:mobile_app/models/transaction_record.dart';
import 'package:mobile_app/services/app_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  LocalStorageService._(this._prefs);

  final SharedPreferences _prefs;
  Future<void> _writeQueue = Future<void>.value();

  static const _sidKey = 'campus_sid';
  static const _passwordKey = 'campus_password';
  static const _profileKey = 'campus_profile';
  static const _balanceKey = 'current_balance';
  static const _balanceUpdatedAtKey = 'balance_updated_at';
  static const _transactionsKey = 'transactions_by_month';

  static Future<LocalStorageService> create() async {
    final watch = Stopwatch()..start();
    final prefs = await SharedPreferences.getInstance();
    final service = LocalStorageService._(prefs);
    service._logInfo('create done in ${watch.elapsedMilliseconds}ms');
    return service;
  }

  bool get hasCredential {
    return campusSid.isNotEmpty && campusPassword.isNotEmpty;
  }

  String get campusSid {
    return (_prefs.getString(_sidKey) ?? '').trim();
  }

  String get campusPassword {
    return _prefs.getString(_passwordKey) ?? '';
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

  Future<void> saveProfile(CampusProfile profile) async {
    await _enqueueWrite('saveProfile', () async {
      await _prefs.setString(_profileKey, jsonEncode(profile.toJson()));
    });
  }

  CampusProfile? get profile {
    final raw = _prefs.getString(_profileKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
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
      return null;
    }
    return null;
  }

  double? get balance {
    return _prefs.getDouble(_balanceKey);
  }

  String? get balanceUpdatedAt {
    final value = _prefs.getString(_balanceUpdatedAtKey);
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> saveSyncMeta({
    required double balance,
    required String balanceUpdatedAt,
  }) async {
    await _enqueueWrite('saveSyncMeta', () async {
      await _prefs.setDouble(_balanceKey, balance);
      await _prefs.setString(_balanceUpdatedAtKey, balanceUpdatedAt);
    });
  }

  Future<void> saveTransactions(Map<String, List<TransactionRecord>> byMonth) async {
    await _enqueueWrite('saveTransactions', () async {
      final map = <String, dynamic>{};
      for (final entry in byMonth.entries) {
        map[entry.key] = entry.value.map((t) => t.toJson()).toList();
      }
      await _prefs.setString(_transactionsKey, jsonEncode(map));
    });
  }

  Map<String, List<TransactionRecord>> loadTransactions() {
    final raw = _prefs.getString(_transactionsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, List<TransactionRecord>>{};
      for (final entry in decoded.entries) {
        final list = (entry.value as List)
            .map((e) => TransactionRecord.fromJsonMap(e as Map<String, dynamic>))
            .toList();
        result[entry.key] = list;
      }
      return result;
    } catch (error) {
      _logInfo('loadTransactions parse failed: $error');
      return {};
    }
  }

  Future<void> clearAll() async {
    await _enqueueWrite('clearAll', () async {
      await _prefs.remove(_sidKey);
      await _prefs.remove(_passwordKey);
      await _prefs.remove(_profileKey);
      await _prefs.remove(_balanceKey);
      await _prefs.remove(_balanceUpdatedAtKey);
      await _prefs.remove(_transactionsKey);
    });
  }

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
