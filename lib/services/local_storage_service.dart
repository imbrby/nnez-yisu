import 'dart:convert';
import 'dart:io';

import 'package:mobile_app/models/campus_profile.dart';
import 'package:mobile_app/models/transaction_record.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class LocalStorageService {
  LocalStorageService._(
    this._stateFile,
    this._stateCache,
    this._transactionsFile,
    this._transactionsBySid,
  );

  final File _stateFile;
  final Map<String, dynamic> _stateCache;
  final File _transactionsFile;
  final Map<String, dynamic> _transactionsBySid;

  static const _sidKey = 'campus_sid';
  static const _passwordKey = 'campus_password';
  static const _profileKey = 'campus_profile';
  static const _balanceKey = 'current_balance';
  static const _balanceUpdatedAtKey = 'balance_updated_at';
  static const _lastSyncAtKey = 'last_sync_at';
  static const _lastSyncDayKey = 'last_sync_day';
  static const _selectedMonthKey = 'selected_month';
  // Legacy key kept for migration from older versions.
  static const _transactionsBySidKey = 'transactions_by_sid';

  static Future<LocalStorageService> create() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final stateFile = File(path.join(baseDir.path, 'app_state.json'));
    final transactionsFile = File(
      path.join(baseDir.path, 'transactions_by_sid.json'),
    );
    final stateCache = await _readMapFromFile(stateFile);
    final transactionsBySid = await _readMapFromFile(transactionsFile);

    final service = LocalStorageService._(
      stateFile,
      stateCache,
      transactionsFile,
      transactionsBySid,
    );
    await service._migrateLegacyTransactionsIfNeeded();
    return service;
  }

  bool get hasCredential {
    return campusSid.isNotEmpty && campusPassword.isNotEmpty;
  }

  String get campusSid {
    return (_stateCache[_sidKey] ?? '').toString();
  }

  String get campusPassword {
    return (_stateCache[_passwordKey] ?? '').toString();
  }

  String get selectedMonth {
    return (_stateCache[_selectedMonthKey] ?? '').toString();
  }

  Future<void> saveSelectedMonth(String month) {
    _stateCache[_selectedMonthKey] = month;
    return _persistState();
  }

  Future<void> saveCredentials({
    required String sid,
    required String password,
  }) async {
    _stateCache[_sidKey] = sid.trim();
    _stateCache[_passwordKey] = password;
    await _persistState();
  }

  Future<void> saveProfile(CampusProfile profile) async {
    _stateCache[_profileKey] = profile.toJson();
    await _persistState();
  }

  CampusProfile? get profile {
    final value = _stateCache[_profileKey];
    if (value == null) {
      return null;
    }
    try {
      if (value is Map<String, dynamic>) {
        return CampusProfile.fromJson(value);
      }
      if (value is String && value.isNotEmpty) {
        final parsed = jsonDecode(value);
        if (parsed is Map<String, dynamic>) {
          return CampusProfile.fromJson(parsed);
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  double? _readDouble(String key) {
    final value = _stateCache[key];
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    final parsed = double.tryParse(value.toString());
    return parsed;
  }

  String? _readNonEmptyString(String key) {
    final value = _stateCache[key];
    if (value == null) {
      return null;
    }
    final text = value.toString();
    if (text.isEmpty) {
      return null;
    }
    return text;
  }

  Future<void> _persistState() async {
    await _writeJsonAtomic(_stateFile, _stateCache);
  }

  Future<void> _persistTransactions() async {
    await _writeJsonAtomic(_transactionsFile, _transactionsBySid);
  }

  static Future<void> _writeJsonAtomic(
    File target,
    Map<String, dynamic> payload,
  ) async {
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(jsonEncode(payload), flush: true);
    if (await target.exists()) {
      await target.delete();
    }
    await temp.rename(target.path);
  }

  static Future<Map<String, dynamic>> _readMapFromFile(File file) async {
    if (!await file.exists()) {
      return <String, dynamic>{};
    }
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return <String, dynamic>{};
      }
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        return Map<String, dynamic>.from(parsed);
      }
      if (parsed is Map) {
        return Map<String, dynamic>.from(parsed);
      }
    } catch (_) {
      return <String, dynamic>{};
    }
    return <String, dynamic>{};
  }

  Future<void> _migrateLegacyTransactionsIfNeeded() async {
    if (_transactionsBySid.isNotEmpty) {
      return;
    }
    final legacy = _stateCache[_transactionsBySidKey];
    final migrated = _parseMapLike(legacy);
    if (migrated.isEmpty) {
      return;
    }
    _transactionsBySid
      ..clear()
      ..addAll(migrated);
    _stateCache.remove(_transactionsBySidKey);
    await _persistTransactions();
    await _persistState();
  }

  static Map<String, dynamic> _parseMapLike(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map<String, dynamic>) {
          return Map<String, dynamic>.from(parsed);
        }
        if (parsed is Map) {
          return Map<String, dynamic>.from(parsed);
        }
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }

  double? get currentBalance {
    return _readDouble(_balanceKey);
  }

  String? get balanceUpdatedAt {
    return _readNonEmptyString(_balanceUpdatedAtKey);
  }

  String? get lastSyncAt {
    return _readNonEmptyString(_lastSyncAtKey);
  }

  String? get lastSyncDay {
    return _readNonEmptyString(_lastSyncDayKey);
  }

  Future<void> saveSyncMeta({
    required double balance,
    required String balanceUpdatedAt,
    required String lastSyncAt,
    required String lastSyncDay,
  }) async {
    _stateCache[_balanceKey] = balance;
    _stateCache[_balanceUpdatedAtKey] = balanceUpdatedAt;
    _stateCache[_lastSyncAtKey] = lastSyncAt;
    _stateCache[_lastSyncDayKey] = lastSyncDay;
    await _persistState();
  }

  Future<void> saveTransactions(
    String sid,
    List<TransactionRecord> rows,
  ) async {
    final key = sid.trim();
    if (key.isEmpty) {
      return;
    }
    _transactionsBySid[key] = rows.map((item) => item.toJson()).toList();
    await _persistTransactions();
  }

  List<TransactionRecord> loadTransactions(String sid) {
    final key = sid.trim();
    if (key.isEmpty) {
      return <TransactionRecord>[];
    }
    final raw = _transactionsBySid[key];
    if (raw is! List) {
      return <TransactionRecord>[];
    }
    final out = <TransactionRecord>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      try {
        out.add(TransactionRecord.fromJsonMap(Map<String, dynamic>.from(item)));
      } catch (_) {
        // skip malformed row
      }
    }
    return out;
  }

  Future<void> clearAll() async {
    _stateCache
      ..remove(_sidKey)
      ..remove(_passwordKey)
      ..remove(_profileKey)
      ..remove(_balanceKey)
      ..remove(_balanceUpdatedAtKey)
      ..remove(_lastSyncAtKey)
      ..remove(_lastSyncDayKey)
      ..remove(_selectedMonthKey)
      ..remove(_transactionsBySidKey);
    _transactionsBySid.clear();
    await _persistState();
    await _persistTransactions();
  }
}
