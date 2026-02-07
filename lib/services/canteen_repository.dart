import 'dart:async';

import 'package:mobile_app/core/time_utils.dart';
import 'package:mobile_app/models/campus_profile.dart';
import 'package:mobile_app/models/home_summary.dart';
import 'package:mobile_app/services/app_log_service.dart';
import 'package:mobile_app/services/campus_api_client.dart';
import 'package:mobile_app/services/local_database_service.dart';
import 'package:mobile_app/services/local_storage_service.dart';

class CanteenRepository {
  CanteenRepository._(this._storage, this._database, this._apiClient);

  static const int _initCheckLookbackDays = 3;
  static const int _autoSyncLookbackDays = 1;

  final LocalStorageService _storage;
  final LocalDatabaseService _database;
  final CampusApiClient _apiClient;

  static Future<CanteenRepository> create() async {
    final storage = await LocalStorageService.create();
    final database = LocalDatabaseService();
    final apiClient = CampusApiClient();
    return CanteenRepository._(storage, database, apiClient);
  }

  bool get hasCredential => _storage.hasCredential;

  CampusProfile? get profile => _storage.profile;

  String? get lastSyncAt => _storage.lastSyncAt;

  Future<void> initializeAccount({
    required String sid,
    required String password,
    void Function(String message)? onProgress,
    bool localOnly = true,
  }) async {
    final normalizedSid = sid.trim();
    if (normalizedSid.isEmpty || password.isEmpty) {
      throw Exception('请输入食堂账号和密码。');
    }

    onProgress?.call('正在保存账号信息...');
    await _runTimed(
      () => _storage.saveCredentials(sid: normalizedSid, password: password),
      '保存账号信息超时',
    );
    if (localOnly) {
      final placeholder = CampusProfile(
        sid: normalizedSid,
        idCode: normalizedSid,
        studentName: '未同步用户',
        gradeName: '',
        className: '',
        academyName: '',
        specialityName: '',
      );
      await _runTimed(() => _storage.saveProfile(placeholder), '保存用户信息超时');
      await _runTimed(() {
        return _storage.saveSyncMeta(
          balance: 0,
          balanceUpdatedAt: '',
          lastSyncAt: '',
          lastSyncDay: '',
        );
      }, '保存同步状态超时');
      return;
    }

    final range = _buildSyncRange(_initCheckLookbackDays);
    final payload = await _apiClient.fetchAll(
      sid: normalizedSid,
      plainPassword: password,
      startDate: range.startDate,
      endDate: range.endDate,
      includeTransactions: false,
      onProgress: onProgress,
    );
    await _runTimed(() => _storage.saveProfile(payload.profile), '保存用户信息超时');
    await _runTimed(() {
      return _storage.saveSyncMeta(
        balance: payload.balance,
        balanceUpdatedAt: payload.balanceUpdatedAt.toIso8601String(),
        lastSyncAt: '',
        lastSyncDay: '',
      );
    }, '保存同步状态超时');
  }

  Future<void> _runTimed(
    Future<void> Function() action,
    String timeoutMessage,
  ) {
    return action().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException(timeoutMessage);
      },
    );
  }

  Future<void> syncNow({
    void Function(String message)? onProgress,
    bool includeTransactions = true,
    int? lookbackDays,
  }) async {
    if (!hasCredential) {
      throw Exception('请先在设置中初始化账号。');
    }
    final sid = _storage.campusSid;
    final password = _storage.campusPassword;
    final range = _buildSyncRange(
      lookbackDays ??
          (includeTransactions
              ? _monthToDateLookbackDays()
              : _autoSyncLookbackDays),
    );

    final payload = await _apiClient.fetchAll(
      sid: sid,
      plainPassword: password,
      startDate: range.startDate,
      endDate: range.endDate,
      includeTransactions: includeTransactions,
      onProgress: onProgress,
    );

    await _storage.saveProfile(payload.profile);
    if (includeTransactions) {
      await _database.init();
      onProgress?.call('正在写入本地数据...');
      await _database.upsertTransactions(
        sid,
        payload.transactions,
        onProgress: onProgress,
      );
    }
    await _storage.saveSyncMeta(
      balance: payload.balance,
      balanceUpdatedAt: payload.balanceUpdatedAt.toIso8601String(),
      lastSyncAt: DateTime.now().toIso8601String(),
      lastSyncDay: formatShanghaiDay(shanghaiNow()),
    );
  }

  bool shouldAutoSyncToday() {
    if (!hasCredential) {
      return false;
    }
    final today = formatShanghaiDay(shanghaiNow());
    return _storage.lastSyncDay != today;
  }

  Future<HomeSummary?> loadSummary({String? requestedMonth}) async {
    _logInfo(
      'loadSummary start requestedMonth=${requestedMonth ?? "(current)"}',
    );
    if (!hasCredential) {
      _logInfo('loadSummary skipped: no credential');
      return null;
    }
    try {
      await _withTimeout(() => _database.init(), step: 'db.init');

      final sid = _storage.campusSid;
      final currentMonth = monthOf(shanghaiNow());
      final earliestMonth = addMonths(currentMonth, -11);
      final selectedMonth = _resolveMonth(
        requestedMonth: requestedMonth,
        fallbackMonth: _storage.selectedMonth,
        minMonth: earliestMonth,
        maxMonth: currentMonth,
      );

      final selectedStart = monthStart(selectedMonth);
      final selectedEnd = monthEnd(selectedMonth);
      final historyStart = monthStart(earliestMonth);
      final historyEnd = monthEnd(currentMonth);

      unawaited(_saveSelectedMonthNonBlocking(selectedMonth));

      final dailyRows = await _withTimeout(
        () => _database.queryDailyTotals(
          sid: sid,
          startDate: selectedStart,
          endDate: selectedEnd,
        ),
        step: 'db.queryDailyTotals',
      );

      final dayMap = <String, DailySpending>{};
      for (final row in dailyRows) {
        final day = (row['day'] ?? '').toString();
        if (day.isEmpty) {
          continue;
        }
        dayMap[day] = DailySpending(
          day: day,
          totalAmount: _toDouble(row['total_amount']).abs(),
          txnCount: _toInt(row['txn_count']),
        );
      }

      final fullDays = daysBetween(selectedStart, selectedEnd);
      final daily = fullDays
          .map(
            (day) =>
                dayMap[day] ??
                DailySpending(day: day, totalAmount: 0, txnCount: 0),
          )
          .toList();

      final recent = await _withTimeout(
        () => _database.queryRecent(sid: sid, limit: 20),
        step: 'db.queryRecent',
      );

      final monthRows = await _withTimeout(
        () => _database.queryMonthlyTotals(
          sid: sid,
          startDate: historyStart,
          endDate: historyEnd,
        ),
        step: 'db.queryMonthlyTotals',
      );
      final monthMap = <String, MonthOverview>{};
      for (final row in monthRows) {
        final month = (row['month'] ?? '').toString();
        if (month.isEmpty) {
          continue;
        }
        final txnCount = _toInt(row['txn_count']);
        monthMap[month] = MonthOverview(
          month: month,
          totalAmount: _toDouble(row['total_amount']).abs(),
          txnCount: txnCount,
          hasData: txnCount > 0,
        );
      }

      final availableMonths = monthsBetween(earliestMonth, currentMonth)
          .map(
            (month) =>
                monthMap[month] ??
                MonthOverview(
                  month: month,
                  totalAmount: 0,
                  txnCount: 0,
                  hasData: false,
                ),
          )
          .toList();

      final totalAmount = daily.fold<double>(
        0,
        (sum, item) => sum + item.totalAmount,
      );
      final transactionCount = daily.fold<int>(
        0,
        (sum, item) => sum + item.txnCount,
      );

      _logInfo(
        'loadSummary done month=$selectedMonth daily=${daily.length} recent=${recent.length} monthRows=${monthRows.length}',
      );
      return HomeSummary(
        selectedMonth: selectedMonth,
        startDate: selectedStart,
        endDate: selectedEnd,
        days: monthDays(selectedMonth),
        availableMonths: availableMonths,
        daily: daily,
        recent: recent,
        totalAmount: totalAmount,
        transactionCount: transactionCount,
        currentBalance: _storage.currentBalance,
        balanceUpdatedAt: _storage.balanceUpdatedAt,
        lastSyncAt: _storage.lastSyncAt,
      );
    } catch (error, stackTrace) {
      _logError('loadSummary failed', error, stackTrace);
      rethrow;
    }
  }

  Future<void> logout() async {
    await _storage.clearAll();
    try {
      await _database.init();
      await _database.clearAll();
    } catch (_) {
      // ignore db clear failure in logout path
    }
  }

  Future<void> close() {
    return _database.close();
  }

  ({String startDate, String endDate}) _buildSyncRange(int lookbackDays) {
    final now = shanghaiNow();
    return (
      startDate: formatShanghaiDay(
        now.subtract(Duration(days: lookbackDays - 1)),
      ),
      endDate: formatShanghaiDay(now),
    );
  }

  int _monthToDateLookbackDays() {
    final day = shanghaiNow().day;
    return day < 1 ? 1 : day;
  }

  double _toDouble(Object? value) {
    if (value is num) {
      final parsed = value.toDouble();
      return parsed.isFinite ? parsed : 0;
    }
    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed == null || !parsed.isFinite) {
      return 0;
    }
    return parsed;
  }

  int _toInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _saveSelectedMonthNonBlocking(String month) async {
    try {
      await _storage
          .saveSelectedMonth(month)
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              throw TimeoutException('saveSelectedMonth 超时');
            },
          );
      _logInfo('saveSelectedMonth ok: $month');
    } catch (error, stackTrace) {
      _logError('saveSelectedMonth failed', error, stackTrace);
    }
  }

  Future<T> _withTimeout<T>(
    Future<T> Function() action, {
    required String step,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final watch = Stopwatch()..start();
    final value = await action().timeout(
      timeout,
      onTimeout: () {
        throw TimeoutException('$step 超时');
      },
    );
    _logInfo('$step ok ${watch.elapsedMilliseconds}ms');
    return value;
  }

  void _logInfo(String message) {
    unawaited(AppLogService.instance.info(message, tag: 'REPO'));
  }

  void _logError(String context, Object error, StackTrace stackTrace) {
    unawaited(
      AppLogService.instance.error(
        context,
        tag: 'REPO',
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  String _resolveMonth({
    required String? requestedMonth,
    required String fallbackMonth,
    required String minMonth,
    required String maxMonth,
  }) {
    final candidate = (requestedMonth ?? fallbackMonth).trim();
    final match = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$').hasMatch(candidate);
    if (!match) {
      return maxMonth;
    }
    if (candidate.compareTo(minMonth) < 0 ||
        candidate.compareTo(maxMonth) > 0) {
      return maxMonth;
    }
    return candidate;
  }
}
