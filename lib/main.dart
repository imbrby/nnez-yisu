import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nnez_yisu/models/campus_profile.dart';
import 'package:nnez_yisu/models/monthly_summary.dart';
import 'package:nnez_yisu/models/recharge_record.dart';
import 'package:nnez_yisu/models/transaction_record.dart';
import 'package:nnez_yisu/pages/detail_page.dart';
import 'package:nnez_yisu/pages/home_page.dart';
import 'package:nnez_yisu/pages/settings_page.dart';
import 'package:nnez_yisu/services/app_log_service.dart';
import 'package:nnez_yisu/services/app_notification_service.dart';
import 'package:nnez_yisu/services/app_theme_service.dart';
import 'package:nnez_yisu/services/app_update_service.dart';
import 'package:nnez_yisu/services/background_sync_service.dart';
import 'package:nnez_yisu/services/canteen_repository.dart';
import 'package:nnez_yisu/services/campus_api_client.dart';
import 'package:nnez_yisu/services/data_transfer_service.dart';
import 'package:nnez_yisu/services/widget_service.dart';
import 'package:nnez_yisu/services/webdav_backup_service.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void _workmanagerCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == backgroundSyncTaskName ||
        task == Workmanager.iOSBackgroundTask) {
      return await backgroundSyncCallback();
    }
    return true;
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppThemeService.instance.init();
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

  final isMobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (isMobile) {
    try {
      await Workmanager().initialize(_workmanagerCallbackDispatcher);
      await Workmanager().registerPeriodicTask(
        backgroundSyncTaskName,
        backgroundSyncTaskName,
        frequency: const Duration(hours: 3),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (error, stackTrace) {
      AppLogService.instance.error(
        'Workmanager 初始化失败',
        tag: 'BOOT',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

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
    final themeService = AppThemeService.instance;
    return AnimatedBuilder(
      animation: themeService,
      builder: (context, _) => MaterialApp(
        title: '一粟',
        debugShowCheckedModeBanner: false,
        theme: themeService.buildTheme(),
        home: const AppShell(),
        builder: (context, child) => Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AppNotificationHost(),
            ),
          ],
        ),
      ),
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
  String _status = '正在初始化本地数据...';
  bool _syncing = false;
  bool _settingUp = false;
  Timer? _autoSyncTimer;
  bool _autoUpdateChecked = false;
  int _tabIndex = 0;
  final Map<String, List<TransactionRecord>> _transactionsByMonth = {};
  final Map<String, List<RechargeRecord>> _rechargesByMonth = {};
  List<RechargeRecord> _recentRecharges = [];
  int? _estimatedDays;
  late String _selectedMonth = _currentMonthKey();

  @override
  void initState() {
    super.initState();
    _logInfo('AppShell initState');
    unawaited(AppUpdateService.instance.cleanupPendingPackages());
    _startAutoSyncTimer();
    _bootstrap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoCheckUpdateOnLaunch();
    });
  }

  @override
  void dispose() {
    _sidController.dispose();
    _passwordController.dispose();
    _autoSyncTimer?.cancel();
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
      final saved = await repo.loadTransactions();
      final savedRecharges = await repo.loadRecharges();
      final recentRecharges = await repo.loadRecentRecharges();
      if (!mounted) return;
      setState(() {
        _repository = repo;
        _profile = repo.profile;
        _transactionsByMonth
          ..clear()
          ..addAll(saved);
        _rechargesByMonth
          ..clear()
          ..addAll(savedRecharges);
        _recentRecharges = recentRecharges;
        _estimatedDays = _calcEstimatedDays(repo.balance, saved);
        _status = '';
      });
      _updateHomeWidgets(repo, saved);
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
      AppNotificationService.instance.showError(
        _formatError(error),
        title: '启动失败',
      );
    }
  }

  void _startAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(hours: 3), (_) {
      _logInfo('触发3小时自动刷新定时任务');
      _syncNow();
    });
  }

  Future<void> _maybeAutoCheckUpdateOnLaunch() async {
    if (_autoUpdateChecked) return;
    _autoUpdateChecked = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      final enabled = await AppUpdateService.instance.isAutoCheckEnabled();
      if (!enabled) return;
      final result = await AppUpdateService.instance.checkForUpdate();
      if (!mounted || !result.hasUpdate) return;
      await AppUpdateService.instance.showUpdateDialog(context, result);
    } catch (error, stackTrace) {
      _logError('自动检查更新失败', error, stackTrace);
    }
  }

  Future<void> _syncNow({bool manual = false}) async {
    _logInfo('syncNow entry settingUp=$_settingUp syncing=$_syncing');
    final repo = _repository;
    if (repo == null || !repo.hasCredential || _settingUp || _syncing) {
      _logInfo('syncNow skipped: precondition not met');
      return;
    }
    _logInfo('开始刷新');

    var retry = false;
    setState(() {
      _syncing = true;
    });
    AppNotificationService.instance.showProgress(
      manual ? '正在手动同步' : '正在自动同步',
      '正在获取校园卡余额和最近流水...',
    );

    try {
      final transactions = await repo.syncNow();

      if (!mounted) return;
      _profile = repo.profile;
      // Reload all transactions from SQLite (already persisted by syncNow)
      _transactionsByMonth.clear();
      final fresh = await repo.loadTransactions();
      _transactionsByMonth.addAll(fresh);
      _rechargesByMonth.clear();
      final freshRecharges = await repo.loadRecharges();
      _rechargesByMonth.addAll(freshRecharges);
      _selectedMonth = _currentMonthKey();
      // Load recent recharges
      _recentRecharges = await repo.loadRecentRecharges();
      // Calculate estimated days
      _estimatedDays = _calcEstimatedDays(repo.balance, fresh);
      // Update home screen widgets
      _updateHomeWidgets(repo, fresh);
      final backupCompleted = manual
          ? await WebDavBackupService.instance.backupIfEnabled(
              repo.exportToJson,
            )
          : false;
      AppNotificationService.instance.showSuccess(
        backupCompleted
            ? '校园卡数据已同步，并已备份到云端。'
            : '已获取 ${transactions.length} 条最近流水。',
        title: '同步完成',
      );
      _logInfo('刷新完成，获取到 ${transactions.length} 条流水');
    } catch (error, stackTrace) {
      _logError('刷新失败', error, stackTrace);
      if (!mounted) return;
      AppNotificationService.instance.showError(
        _formatError(error),
        title: '同步失败',
      );
      retry = await _showSyncErrorDialog(_formatError(error));
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
    if (retry && mounted) unawaited(_syncNow(manual: manual));
  }

  Future<bool> _showSyncErrorDialog(String message) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('刷新失败'),
            content: SelectableText(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('关闭'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _updateCampusBaseUrl(String? customBaseUrl) async {
    final repo = _repository;
    if (repo == null) throw Exception('应用尚未初始化完成。');
    await repo.updateCampusBaseUrl(customBaseUrl);
    if (mounted) setState(() {});
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
    _logInfo('开始初始化账号');

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
      AppNotificationService.instance.showSuccess(
        '账号已保存，请手动同步一次以获取最新数据。',
        title: '初始化完成',
      );
      _logInfo('初始化账号完成');
    } catch (error, stackTrace) {
      _logError('初始化账号失败', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _status = '初始化失败：${_formatError(error)}';
      });
      AppNotificationService.instance.showError(
        _formatError(error),
        title: '初始化失败',
      );
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
        _rechargesByMonth.clear();
        _recentRecharges = [];
        _estimatedDays = null;
      });
      AppNotificationService.instance.showSuccess('校园卡账号已从本机退出。', title: '已登出');
      _logInfo('登出完成');
    } catch (error, stackTrace) {
      _logError('登出失败', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _status = '登出失败：${_formatError(error)}';
      });
      AppNotificationService.instance.showError(
        _formatError(error),
        title: '登出失败',
      );
    }
  }

  Future<void> _exportData() async {
    final repo = _repository;
    if (repo == null || !repo.hasCredential) return;
    AppNotificationService.instance.showProgress('正在导出', '正在生成完整本地备份...');
    try {
      final json = await repo.exportToJson();
      final savedPath = await DataTransferService.exportWithSystemFileManager(
        json,
      );
      if (!mounted) return;
      if (savedPath == null) {
        AppNotificationService.instance.showInfo('未选择保存位置。', title: '已取消导出');
      } else {
        AppNotificationService.instance.showSuccess('完整备份已保存。', title: '导出完成');
      }
    } catch (error, stackTrace) {
      _logError('导出失败', error, stackTrace);
      if (!mounted) return;
      AppNotificationService.instance.showError(
        _formatError(error),
        title: '导出失败',
      );
    }
  }

  Future<void> _importData() async {
    final repo = _repository;
    if (repo == null || !repo.hasCredential) return;
    try {
      final jsonString = await DataTransferService.pickAndReadJsonFile();
      if (jsonString == null) return;
      if (!mounted) return;
      AppNotificationService.instance.showProgress('正在导入', '正在校验并写入备份数据...');
      final count = await repo.importFromJson(jsonString);
      if (!mounted) return;
      await _reloadRepositoryData();
      AppNotificationService.instance.showSuccess(
        '已导入 $count 条记录。',
        title: '导入完成',
      );
    } catch (error, stackTrace) {
      _logError('导入失败', error, stackTrace);
      if (!mounted) return;
      AppNotificationService.instance.showError(
        _formatError(error),
        title: '导入失败',
      );
    }
  }

  Future<String> _createBackupJson() async {
    final repo = _repository;
    if (repo == null || !repo.hasCredential) {
      throw Exception('请先初始化校园卡账号。');
    }
    return repo.exportToJson();
  }

  Future<BackupMergeResult> _mergeCloudBackup(
    String json, {
    bool apply = false,
  }) async {
    final repo = _repository;
    if (repo == null || !repo.hasCredential) {
      throw Exception('请先初始化校园卡账号。');
    }
    return repo.mergeMissingFromJson(json, apply: apply);
  }

  Future<void> _reloadRepositoryData() async {
    final repo = _repository;
    if (repo == null) return;
    final fresh = await repo.loadTransactions();
    final freshRecharges = await repo.loadRecharges();
    final recentRecharges = await repo.loadRecentRecharges();
    if (!mounted) return;
    _transactionsByMonth
      ..clear()
      ..addAll(fresh);
    _rechargesByMonth
      ..clear()
      ..addAll(freshRecharges);
    _profile = repo.profile;
    _recentRecharges = recentRecharges;
    _estimatedDays = _calcEstimatedDays(repo.balance, fresh);
    _updateHomeWidgets(repo, fresh);
    setState(() {});
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
    final totalSpent = dailyTotals.values.fold<double>(0, (a, b) => a + b);
    final avgPerActiveDay = totalSpent / dailyTotals.length;
    if (avgPerActiveDay <= 0) return null;
    return (balance / avgPerActiveDay).floor();
  }

  void _updateHomeWidgets(
    CanteenRepository repo,
    Map<String, List<TransactionRecord>> transactionsByMonth,
  ) {
    final updatedAt = DateTime.tryParse(repo.balanceUpdatedAt ?? '');
    unawaited(
      WidgetService.updateFromData(
        balance: repo.balance ?? 0,
        transactionsByMonth: transactionsByMonth,
        rechargesByMonth: _rechargesByMonth,
        estimatedDays: _estimatedDays,
        studentName: repo.profile?.studentName,
        updatedAt: updatedAt,
      ),
    );
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
    final isWindowsDesktop =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
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
      dailyCounts[txn.occurredDay] = (dailyCounts[txn.occurredDay] ?? 0) + 1;
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
    final allTransactions =
        _transactionsByMonth.values.expand((list) => list).toList()
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
        DetailPage(
          balance: _repository?.balance,
          transactionsByMonth: _transactionsByMonth,
          rechargesByMonth: _rechargesByMonth,
        ),
        SettingsPage(
          profile: _profile,
          onLogout: _logout,
          onExport: _exportData,
          onImport: _importData,
          onCreateBackupJson: _createBackupJson,
          onMergeCloudBackup: _mergeCloudBackup,
          onCloudDataChanged: _reloadRepositoryData,
          onReportLoss: _reportLoss,
          onCancelLoss: _cancelLoss,
          usesCustomBaseUrl: _repository?.usesCustomCampusBaseUrl ?? false,
          campusBaseUrl: _repository?.campusBaseUrl ?? defaultCampusBaseUrl,
          onBaseUrlChanged: _updateCampusBaseUrl,
          isBusy: _syncing || _settingUp,
        ),
      ],
    );

    final hasCredential = _repository?.hasCredential ?? false;
    final scaffoldBody = isWindowsDesktop
        ? Row(
            children: <Widget>[
              SafeArea(
                child: NavigationRail(
                  selectedIndex: _tabIndex,
                  onDestinationSelected: (index) {
                    setState(() {
                      _tabIndex = index;
                    });
                  },
                  groupAlignment: 0,
                  labelType: NavigationRailLabelType.all,
                  destinations: const <NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Icon(Icons.home_outlined),
                      ),
                      selectedIcon: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Icon(Icons.home),
                      ),
                      label: Text('首页'),
                    ),
                    NavigationRailDestination(
                      icon: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Icon(Icons.receipt_long_outlined),
                      ),
                      selectedIcon: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Icon(Icons.receipt_long),
                      ),
                      label: Text('细目'),
                    ),
                    NavigationRailDestination(
                      icon: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Icon(Icons.settings_outlined),
                      ),
                      selectedIcon: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Icon(Icons.settings),
                      ),
                      label: Text('设置'),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: body,
                  ),
                ),
              ),
            ],
          )
        : body;

    return Stack(
      children: <Widget>[
        Scaffold(
          body: scaffoldBody,
          bottomNavigationBar: isWindowsDesktop
              ? null
              : NavigationBar(
                  selectedIndex: _tabIndex,
                  onDestinationSelected: (index) {
                    setState(() {
                      _tabIndex = index;
                    });
                  },
                  destinations: const <NavigationDestination>[
                    NavigationDestination(icon: Icon(Icons.home), label: '首页'),
                    NavigationDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      label: '细目',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings),
                      label: '设置',
                    ),
                  ],
                ),
          floatingActionButton: hasCredential && _tabIndex == 0
              ? FloatingActionButton(
                  onPressed: _syncing || _settingUp
                      ? null
                      : () => _syncNow(manual: true),
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
