import 'dart:async';

import 'package:mobile_app/core/time_utils.dart';
import 'package:mobile_app/models/campus_profile.dart';
import 'package:mobile_app/models/home_summary.dart';
import 'package:mobile_app/models/transaction_record.dart';
import 'package:mobile_app/services/app_log_service.dart';
import 'package:mobile_app/services/campus_api_client.dart';
import 'package:mobile_app/services/local_storage_service.dart';

class CanteenRepository {
  CanteenRepository._(this._storage, this._apiClient);

  static const int _initCheckLookbackDays = 3;
  static const int _autoSyncLookbackDays = 1;
  static final Map<String, List<TransactionRecord>> _volatileRowsBySid =
      <String, List<TransactionRecord>>{};

  final LocalStorageService _storage;
  final CampusApiClient _apiClient;
  CampusProfile? _volatileProfile;
  double? _volatileBalance;
  String? _volatileBalanceUpdatedAt;
  String? _volatileLastSyncAt;
  String? _volatileLastSyncDay;

  static Future<CanteenRepository> create() async {
    final storage = await LocalStorageService.create();
    final apiClient = CampusApiClient();
    return CanteenRepository._(storage, apiClient);
  }

  bool get hasCredential => _storage.hasCredential;

  CampusProfile? get profile => _volatileProfile ?? _storage.profile;

  String? get lastSyncAt => _volatileLastSyncAt ?? _storage.lastSyncAt;

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
      _volatileProfile = placeholder;
      await _runTimed(() => _storage.saveProfile(placeholder), '保存用户信息超时');
      await _runTimed(() {
        return _storage.saveSyncMeta(
          balance: 0,
          balanceUpdatedAt: '',
          lastSyncAt: '',
          lastSyncDay: '',
        );
      }, '保存同步状态超时');
      _volatileBalance = 0;
      _volatileBalanceUpdatedAt = '';
      _volatileLastSyncAt = '';
      _volatileLastSyncDay = '';
      await _runTimed(
        () => _storage.saveTransactions(normalizedSid, <TransactionRecord>[]),
        '清理本地消费缓存超时',
      );
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
    _volatileProfile = payload.profile;
    _volatileBalance = payload.balance;
    _volatileBalanceUpdatedAt = payload.balanceUpdatedAt.toIso8601String();
    _volatileLastSyncAt = '';
    _volatileLastSyncDay = '';
    unawaited(_saveProfileBestEffort(payload.profile));
    unawaited(
      _saveSyncMetaBestEffort(
        balance: payload.balance,
        balanceUpdatedAt: payload.balanceUpdatedAt.toIso8601String(),
        lastSyncAt: '',
        lastSyncDay: '',
      ),
    );
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

    _logInfo('sync.fetchAll start');
    final payload = await _apiClient
        .fetchAll(
          sid: sid,
          plainPassword: password,
          startDate: range.startDate,
          endDate: range.endDate,
          includeTransactions: includeTransactions,
          onProgress: onProgress,
        )
        .timeout(
          const Duration(seconds: 50),
          onTimeout: () {
            throw TimeoutException('同步接口超时，请稍后重试。');
          },
        );
    _logInfo('sync.fetchAll ok');

    onProgress?.call('网络数据处理完成，正在更新界面...');
    _volatileProfile = payload.profile;
    _volatileBalance = payload.balance;
    _volatileBalanceUpdatedAt = payload.balanceUpdatedAt.toIso8601String();
    _logInfo('syncNow fetched payload txns=${payload.transactions.length}');
    unawaited(_saveProfileBestEffort(payload.profile));
    if (includeTransactions) {
      _logInfo('syncNow about to notify progress: 写入本地数据');
      onProgress?.call('正在写入本地数据...');
      _logInfo('syncNow progress callback returned: 写入本地数据');
      await _saveTransactionsBestEffort(sid, payload.transactions);
    }
    onProgress?.call('正在保存同步信息...');
    final nowIso = DateTime.now().toIso8601String();
    final today = formatShanghaiDay(shanghaiNow());
    _volatileLastSyncAt = nowIso;
    _volatileLastSyncDay = today;
    await _withTimeout(
      () => _saveSyncMetaBestEffort(
        balance: payload.balance,
        balanceUpdatedAt: payload.balanceUpdatedAt.toIso8601String(),
        lastSyncAt: nowIso,
        lastSyncDay: today,
      ),
      step: 'sync.saveSyncMeta.bestEffort',
      timeout: const Duration(seconds: 5),
    );
    _logInfo('syncNow done');
  }

  bool shouldAutoSyncToday() {
    if (!hasCredential) {
      return false;
    }
    final today = formatShanghaiDay(shanghaiNow());
    final lastSyncDay = _volatileLastSyncDay ?? _storage.lastSyncDay;
    return lastSyncDay != today;
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

      _logInfo(
        'loadSummary window selected=$selectedStart~$selectedEnd history=$historyStart~$historyEnd',
      );
      unawaited(_saveSelectedMonthNonBlocking(selectedMonth));

      final allRows = _storage.loadTransactions(sid);
      final effectiveRows = allRows.isNotEmpty
          ? allRows
          : (_volatileRowsBySid[sid] ?? <TransactionRecord>[]);
      _logInfo(
        'allRows loaded from storage: ${allRows.length}, volatile: ${(_volatileRowsBySid[sid] ?? <TransactionRecord>[]).length}',
      );
      final selectedRows = effectiveRows
          .where(
            (row) => _dayInRange(row.occurredDay, selectedStart, selectedEnd),
          )
          .toList();
      _logInfo('selectedRows loaded: ${selectedRows.length}');

      final dayMap = <String, DailySpending>{};
      for (final row in selectedRows) {
        final day = row.occurredDay;
        final current = dayMap[day];
        if (current == null) {
          dayMap[day] = DailySpending(
            day: day,
            totalAmount: row.amount.abs(),
            txnCount: 1,
          );
          continue;
        }
        dayMap[day] = DailySpending(
          day: day,
          totalAmount: current.totalAmount + row.amount.abs(),
          txnCount: current.txnCount + 1,
        );
      }
      _logInfo('dayMap aggregated: ${dayMap.length}');

      final fullDays = daysBetween(selectedStart, selectedEnd);
      final daily = fullDays
          .map(
            (day) =>
                dayMap[day] ??
                DailySpending(day: day, totalAmount: 0, txnCount: 0),
          )
          .toList();
      _logInfo('daily series built: ${daily.length}');

      final historyRows = effectiveRows
          .where(
            (row) => _dayInRange(row.occurredDay, historyStart, historyEnd),
          )
          .toList();
      _logInfo('historyRows loaded: ${historyRows.length}');
      final monthMap = <String, MonthOverview>{};
      for (final row in historyRows) {
        if (row.occurredDay.length < 7) {
          continue;
        }
        final month = row.occurredDay.substring(0, 7);
        final current = monthMap[month];
        if (current == null) {
          monthMap[month] = MonthOverview(
            month: month,
            totalAmount: row.amount.abs(),
            txnCount: 1,
            hasData: true,
          );
          continue;
        }
        monthMap[month] = MonthOverview(
          month: month,
          totalAmount: current.totalAmount + row.amount.abs(),
          txnCount: current.txnCount + 1,
          hasData: true,
        );
      }
      _logInfo('monthMap aggregated: ${monthMap.length}');

      final recent = historyRows.toList()
        ..sort((a, b) {
          final byTime = b.occurredAt.compareTo(a.occurredAt);
          if (byTime != 0) {
            return byTime;
          }
          return b.txnId.compareTo(a.txnId);
        });
      final recentTop20 = recent.take(20).toList();
      _logInfo('recentTop20 built: ${recentTop20.length}');

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
        'summary totals: totalAmount=${totalAmount.toStringAsFixed(2)} txnCount=$transactionCount',
      );

      _logInfo(
        'loadSummary done month=$selectedMonth daily=${daily.length} recent=${recentTop20.length} history=${historyRows.length}',
      );
      return HomeSummary(
        selectedMonth: selectedMonth,
        startDate: selectedStart,
        endDate: selectedEnd,
        days: monthDays(selectedMonth),
        availableMonths: availableMonths,
        daily: daily,
        recent: recentTop20,
        totalAmount: totalAmount,
        transactionCount: transactionCount,
        currentBalance: _volatileBalance ?? _storage.currentBalance,
        balanceUpdatedAt:
            _volatileBalanceUpdatedAt ?? _storage.balanceUpdatedAt,
        lastSyncAt: _volatileLastSyncAt ?? _storage.lastSyncAt,
      );
    } catch (error, stackTrace) {
      _logError('loadSummary failed', error, stackTrace);
      rethrow;
    }
  }

  Future<void> logout() async {
    _volatileProfile = null;
    _volatileBalance = null;
    _volatileBalanceUpdatedAt = null;
    _volatileLastSyncAt = null;
    _volatileLastSyncDay = null;
    await _storage.clearAll();
  }

  Future<void> close() async {
    return;
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
    _logInfo('$step start');
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

  Future<void> _saveTransactionsBestEffort(
    String sid,
    List<TransactionRecord> rows,
  ) async {
    _volatileRowsBySid[sid] = List<TransactionRecord>.from(rows);
    try {
      await _withTimeout(
        () => _storage.saveTransactions(sid, rows),
        step: 'sync.storage.saveTransactions',
        timeout: const Duration(seconds: 3),
      );
      _logInfo('saveTransactions persisted rows=${rows.length}');
    } catch (error, stackTrace) {
      _logError(
        'saveTransactions fallback to volatile cache',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _saveProfileBestEffort(CampusProfile profile) async {
    try {
      await _storage
          .saveProfile(profile)
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              throw TimeoutException('saveProfile 超时');
            },
          );
      _logInfo('saveProfile persisted');
    } catch (error, stackTrace) {
      _logError('saveProfile best-effort failed', error, stackTrace);
    }
  }

  Future<void> _saveSyncMetaBestEffort({
    required double balance,
    required String balanceUpdatedAt,
    required String lastSyncAt,
    required String lastSyncDay,
  }) async {
    try {
      await _storage
          .saveSyncMeta(
            balance: balance,
            balanceUpdatedAt: balanceUpdatedAt,
            lastSyncAt: lastSyncAt,
            lastSyncDay: lastSyncDay,
          )
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              throw TimeoutException('saveSyncMeta 超时');
            },
          );
      _logInfo('saveSyncMeta persisted');
    } catch (error, stackTrace) {
      _logError('saveSyncMeta best-effort failed', error, stackTrace);
    }
  }

  bool _dayInRange(String day, String startDay, String endDay) {
    if (day.length != 10) {
      return false;
    }
    return day.compareTo(startDay) >= 0 && day.compareTo(endDay) <= 0;
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
