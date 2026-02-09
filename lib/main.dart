import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mobile_app/models/campus_profile.dart';
import 'package:mobile_app/models/monthly_summary.dart';
import 'package:mobile_app/models/recharge_record.dart';
import 'package:mobile_app/models/transaction_record.dart';
import 'package:mobile_app/pages/home_page.dart';
import 'package:mobile_app/pages/settings_page.dart';
import 'package:mobile_app/services/app_log_service.dart';
import 'package:mobile_app/services/background_sync_service.dart';
import 'package:mobile_app/services/canteen_repository.dart';
import 'package:mobile_app/services/data_transfer_service.dart';
import 'package:mobile_app/services/widget_service.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void _workmanagerCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == backgroundSyncTaskName || task == Workmanager.iOSBackgroundTask) {
      return await backgroundSyncCallback();
    }
    return true;
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await AppLogService.instance.init();
    AppLogService.instance.info('应用启动', tag: 'BOOT');
  } catch (_) {}

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogService.instance.error(
      'FlutterError: ${details.exceptionAsString()}',
      tag: 'CRASH',
      stackTrace: details.stack,
    );
  };

  ui.PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogService.instance.error(
      'PlatformDispatcher 未捕获异常',
      tag: 'CRASH',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  };

  // Initialize Workmanager for background sync
  await Workmanager().initialize(_workmanagerCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    backgroundSyncTaskName,
    backgroundSyncTaskName,
    frequency: const Duration(hours: 3),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );

  await runZonedGuarded(
    () async {
      runApp(const CanteenApp());
    },
    (error, stackTrace) {
      AppLogService.instance.error(
        'runZonedGuarded 未捕获异常',
        tag: 'CRASH',
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}

class CanteenApp extends StatelessWidget {
  const CanteenApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1F6F5B),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: '一粟',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF5F0E6),
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
        ),
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final TextEditingController _sidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  CanteenRepository? _repository;
  CampusProfile? _profile;
  String _status = '';
  bool _syncing = false;
  bool _settingUp = false;
  Timer? _statusClearTimer;
  int _tabIndex = 0;
  final Map<String, List<TransactionRecord>> _transactionsByMonth = {};
  List<RechargeRecord> _recentRecharges = [];
  int? _estimatedDays;
  late String _selectedMonth = _currentMonthKey();

  @override
  void initState() {
    super.initState();
    _logInfo('AppShell initState');
    _bootstrap();
  }

  @override
  void dispose() {
    _sidController.dispose();
    _passwordController.dispose();
    _statusClearTimer?.cancel();
    _repository?.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _logInfo('开始 bootstrap');
    try {
      final repo = await CanteenRepository.create().timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('本地数据初始化超时。'),
      );
      if (!mounted) return;
      setState(() {
        _repository = repo;
        _profile = repo.profile;
      });
      // Restore persisted transactions from SQLite
      final saved = await repo.loadTransactions();
      if (saved.isNotEmpty) {
        _transactionsByMonth.addAll(saved);
      }
      // Load recent recharges
      _recentRecharges = await repo.loadRecentRecharges();
      // Calculate estimated days
      _estimatedDays = _calcEstimatedDays(repo.balance, saved);
      _logInfo('bootstrap 完成，hasCredential=${repo.hasCredential}');
      // Auto-sync if not synced today
      if (repo.hasCredential) {
        final updatedAt = repo.balanceUpdatedAt ?? '';
        final today = _currentDayKey();
        if (!updatedAt.startsWith(today)) {
          _logInfo('今日未刷新，自动触发同步');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncNow();
          });
        }
      }
    } catch (error, stackTrace) {
      _logError('bootstrap 失败', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _status = 'bootstrap 失败：${_formatError(error)}';
      });
    }
  }

  Future<void> _syncNow() async {
    _logInfo('syncNow entry settingUp=$_settingUp syncing=$_syncing');
    final repo = _repository;
    if (repo == null || !repo.hasCredential || _settingUp || _syncing) {
      _logInfo('syncNow skipped: precondition not met');
      return;
    }
    _logInfo('开始刷新');

    setState(() {
      _syncing = true;
      _status = '正在刷新...';
    });

    try {
      final transactions = await repo.syncNow();

      if (!mounted) return;
      _profile = repo.profile;
      // Reload all transactions from SQLite (already persisted by syncNow)
      _transactionsByMonth.clear();
      final fresh = await repo.loadTransactions();
      _transactionsByMonth.addAll(fresh);
      _selectedMonth = _currentMonthKey();
      // Load recent recharges
      _recentRecharges = await repo.loadRecentRecharges();
      // Calculate estimated days
      _estimatedDays = _calcEstimatedDays(repo.balance, fresh);
      // Update home screen widget
      WidgetService.updateWidget(
        balance: repo.balance ?? 0,
        estimatedDays: _estimatedDays,
      );
      setState(() {
        _status = '刷新成功';
      });
      _statusClearTimer?.cancel();
      _statusClearTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _status = '');
      });
      _logInfo('刷新完成，获取到 ${transactions.length} 条流水');
    } catch (error, stackTrace) {
      _logError('刷新失败', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _status = '刷新失败：${_formatError(error)}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  Future<void> _setupAccount() async {
    final repo = _repository;
    if (repo == null || _settingUp || _syncing) return;

    final sid = _sidController.text.trim();
    final password = _passwordController.text;
    if (sid.isEmpty || password.isEmpty) {
      setState(() {
        _status = '请输入食堂账号和密码';
      });
      return;
    }
    _logInfo('开始初始化账号 sid=$sid');

    setState(() {
      _settingUp = true;
      _status = '正在初始化账号...';
    });

    try {
      await repo.initializeAccount(
        sid: sid,
        password: password,
        onProgress: (message) {
          if (!mounted) return;
          _logInfo('初始化进度: $message');
          setState(() {
            _status = message;
          });
        },
      );
      if (!mounted) return;
      _profile = repo.profile;
      _sidController.clear();
      _passwordController.clear();
      // Load any existing data for this user from SQLite
      _transactionsByMonth.clear();
      final saved = await repo.loadTransactions();
      _transactionsByMonth.addAll(saved);
      setState(() {
        _status = '初始化完成，请点右下角刷新同步余额';
      });
      _logInfo('初始化账号完成');
    } catch (error, stackTrace) {
      _logError('初始化账号失败', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _status = '初始化失败：${_formatError(error)}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _settingUp = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final repo = _repository;
    if (repo == null || _syncing || _settingUp) return;

    setState(() {
      _status = '正在登出...';
    });

    try {
      await repo.logout();
      if (!mounted) return;
      setState(() {
        _profile = null;
        _status = '已登出';
        _tabIndex = 0;
        _transactionsByMonth.clear();
        _recentRecharges = [];
        _estimatedDays = null;
      });
      _logInfo('登出完成');
    } catch (error, stackTrace) {
      _logError('登出失败', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _status = '登出失败：${_formatError(error)}';
      });
    }
  }

  Future<void> _exportData() async {
    final repo = _repository;
    if (repo == null || !repo.hasCredential) return;
    setState(() => _status = '正在导出...');
    try {
      final json = await repo.exportToJson();
      await DataTransferService.exportAndShare(json, repo.currentSid);
      if (!mounted) return;
      setState(() => _status = '导出完成');
      _statusClearTimer?.cancel();
      _statusClearTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _status = '');
      });
    } catch (error, stackTrace) {
      _logError('导出失败', error, stackTrace);
      if (!mounted) return;
      setState(() => _status = '导出失败：${_formatError(error)}');
    }
  }

  Future<void> _importData() async {
    final repo = _repository;
    if (repo == null || !repo.hasCredential) return;
    try {
      final jsonString = await DataTransferService.pickAndReadJsonFile();
      if (jsonString == null) return;
      if (!mounted) return;
      setState(() => _status = '正在导入...');
      final count = await repo.importFromJson(jsonString);
      if (!mounted) return;
      // Reload transactions from SQLite
      _transactionsByMonth.clear();
      final fresh = await repo.loadTransactions();
      _transactionsByMonth.addAll(fresh);
      _profile = repo.profile;
      _recentRecharges = await repo.loadRecentRecharges();
      _estimatedDays = _calcEstimatedDays(repo.balance, fresh);
      setState(() => _status = '导入完成，共 $count 条记录');
      _statusClearTimer?.cancel();
      _statusClearTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _status = '');
      });
    } catch (error, stackTrace) {
      _logError('导入失败', error, stackTrace);
      if (!mounted) return;
      setState(() => _status = '导入失败：${_formatError(error)}');
    }
  }

  Future<String> _reportLoss() async {
    final repo = _repository;
    if (repo == null) throw Exception('未初始化');
    return repo.reportLoss();
  }

  Future<String> _cancelLoss() async {
    final repo = _repository;
    if (repo == null) throw Exception('未初始化');
    return repo.cancelLoss();
  }

  static int? _calcEstimatedDays(
    double? balance,
    Map<String, List<TransactionRecord>> txnByMonth,
  ) {
    if (balance == null || balance <= 0) return null;
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final lastMonthKey =
        '${lastMonth.year}-${lastMonth.month.toString().padLeft(2, '0')}';
    final lastMonthTxns = txnByMonth[lastMonthKey];
    if (lastMonthTxns == null || lastMonthTxns.isEmpty) return null;
    final dailyTotals = <String, double>{};
    for (final txn in lastMonthTxns) {
      dailyTotals[txn.occurredDay] =
          (dailyTotals[txn.occurredDay] ?? 0) + txn.amount.abs();
    }
    if (dailyTotals.isEmpty) return null;
    final totalSpent =
        dailyTotals.values.fold<double>(0, (a, b) => a + b);
    final avgPerActiveDay = totalSpent / dailyTotals.length;
    if (avgPerActiveDay <= 0) return null;
    return (balance / avgPerActiveDay).floor();
  }

  String _formatError(Object error) {
    final text = error.toString();
    final cleanedTimeout = text.replaceFirst(
      RegExp(r'^TimeoutException(?: after [^:]+)?:\s*'),
      '',
    );
    final cleaned = cleanedTimeout.replaceFirst(RegExp(r'^Exception:\s*'), '');
    return cleaned.trim().isEmpty ? '未知错误' : cleaned.trim();
  }

  static String _currentMonthKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static String _currentDayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String _monthLabel(String key) {
    final parts = key.split('-');
    if (parts.length == 2) return '${parts[0]}年${int.parse(parts[1])}月';
    return key;
  }

  void _switchMonth(int delta) {
    final parts = _selectedMonth.split('-');
    if (parts.length != 2) return;
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final d = DateTime(year, month + delta, 1);
    final newKey = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    // Don't go beyond current month
    if (newKey.compareTo(_currentMonthKey()) > 0) return;
    setState(() {
      _selectedMonth = newKey;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_repository == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _status.isEmpty ? '初始化失败。' : _status,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _bootstrap,
                    child: const Text('重试启动'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 计算月度统计
    final selectedTransactions = _transactionsByMonth[_selectedMonth] ?? [];
    final dailyTotals = <String, double>{};
    final dailyCounts = <String, int>{};
    for (final txn in selectedTransactions) {
      dailyTotals[txn.occurredDay] =
          (dailyTotals[txn.occurredDay] ?? 0.0) + txn.amount.abs();
      dailyCounts[txn.occurredDay] =
          (dailyCounts[txn.occurredDay] ?? 0) + 1;
    }
    MonthlySummary? monthlySummary;
    if (selectedTransactions.isNotEmpty) {
      final totalExpense = selectedTransactions.fold<double>(
        0.0,
        (sum, txn) => sum + txn.amount.abs(),
      );
      final totalCount = selectedTransactions.length;

      final activeDays = selectedTransactions
          .map((txn) => txn.occurredDay)
          .toSet()
          .length;

      final peakDaily = dailyTotals.values.isEmpty
          ? 0.0
          : dailyTotals.values.reduce((a, b) => a > b ? a : b);

      monthlySummary = MonthlySummary(
        totalSpent: totalExpense,
        transactionCount: totalCount,
        activeDays: activeDays,
        avgPerTransaction: totalCount > 0 ? totalExpense / totalCount : 0.0,
        avgPerActiveDay: activeDays > 0 ? totalExpense / activeDays : 0.0,
        maxDailySpent: peakDaily,
      );
    }

    // 最近20条消费记录
    final allTransactions = _transactionsByMonth.values.expand((list) => list).toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final recentTransactions = allTransactions.take(20).toList();

    final body = IndexedStack(
      index: _tabIndex,
      children: <Widget>[
        HomePage(
          repository: _repository,
          monthlySummary: monthlySummary,
          monthLabel: _monthLabel(_selectedMonth),
          selectedMonth: _selectedMonth,
          dailyTotals: dailyTotals,
          dailyCounts: dailyCounts,
          recentTransactions: recentTransactions,
          recentRecharges: _recentRecharges,
          estimatedDays: _estimatedDays,
          canGoNext: _selectedMonth.compareTo(_currentMonthKey()) < 0,
          onPrevMonth: () => _switchMonth(-1),
          onNextMonth: () => _switchMonth(1),
        ),
        SettingsPage(
          profile: _profile,
          onLogout: _logout,
          onExport: _exportData,
          onImport: _importData,
          onReportLoss: _reportLoss,
          onCancelLoss: _cancelLoss,
          isBusy: _syncing || _settingUp,
        ),
      ],
    );

    final hasCredential = _repository?.hasCredential ?? false;

    return Stack(
      children: <Widget>[
        Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tabIndex,
            onDestinationSelected: (index) {
              setState(() {
                _tabIndex = index;
              });
            },
            destinations: const <NavigationDestination>[
              NavigationDestination(icon: Icon(Icons.home), label: '首页'),
              NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
            ],
          ),
          floatingActionButton: hasCredential && _tabIndex == 0
              ? _status.isNotEmpty && !_syncing
                  ? FloatingActionButton.extended(
                      onPressed: _settingUp ? null : _syncNow,
                      icon: const Icon(Icons.check),
                      label: Text(_status),
                    )
                  : FloatingActionButton(
                      onPressed: _syncing || _settingUp ? null : _syncNow,
                      child: _syncing
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                    )
              : null,
        ),
        if (!hasCredential)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(20),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text(
                          '初始化账号',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _sidController,
                          decoration: const InputDecoration(
                            labelText: '食堂账号',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !_settingUp,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: '密码',
                            border: OutlineInputBorder(),
                          ),
                          obscureText: true,
                          enabled: !_settingUp,
                        ),
                        const SizedBox(height: 20),
                        if (_status.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              _status,
                              style: TextStyle(
                                color: _status.contains('失败')
                                    ? Colors.red
                                    : null,
                              ),
                            ),
                          ),
                        FilledButton(
                          onPressed: _settingUp ? null : _setupAccount,
                          child: _settingUp
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('初始化'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _logInfo(String message) {
    AppLogService.instance.info(message, tag: 'APP');
  }

  void _logError(String context, Object error, StackTrace stackTrace) {
    AppLogService.instance.error(
      context,
      tag: 'APP',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
