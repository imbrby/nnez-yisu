import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mobile_app/core/time_utils.dart';
import 'package:mobile_app/models/campus_profile.dart';
import 'package:mobile_app/models/home_summary.dart';
import 'package:mobile_app/pages/home_page.dart';
import 'package:mobile_app/pages/settings_page.dart';
import 'package:mobile_app/services/app_log_service.dart';
import 'package:mobile_app/services/canteen_repository.dart';
import 'package:mobile_app/services/local_database_service.dart';
import 'package:mobile_app/services/local_storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await AppLogService.instance.init();
    await AppLogService.instance.info('应用启动', tag: 'BOOT');
  } catch (_) {
    // Keep app startup resilient even if log file initialization fails.
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      AppLogService.instance.error(
        'FlutterError: ${details.exceptionAsString()}',
        tag: 'CRASH',
        stackTrace: details.stack,
      ),
    );
  };

  ui.PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(
      AppLogService.instance.error(
        'PlatformDispatcher 未捕获异常',
        tag: 'CRASH',
        error: error,
        stackTrace: stackTrace,
      ),
    );
    return false;
  };

  await runZonedGuarded(
    () async {
      runApp(const CanteenApp());
    },
    (error, stackTrace) {
      unawaited(
        AppLogService.instance.error(
          'runZonedGuarded 未捕获异常',
          tag: 'CRASH',
          error: error,
          stackTrace: stackTrace,
        ),
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

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const bool _safeModeDisableAutoTasks = false;

  final TextEditingController _sidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  CanteenRepository? _repository;
  HomeSummary? _summary;
  CampusProfile? _profile;

  Timer? _bootWatchdog;
  bool _booting = true;
  bool _syncing = false;
  bool _settingUp = false;
  int _tabIndex = 0;
  String _status = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _logInfo('AppShell initState');
    _startBootWatchdog();
    _bootstrap();
  }

  @override
  void dispose() {
    _logInfo('AppShell dispose');
    WidgetsBinding.instance.removeObserver(this);
    _bootWatchdog?.cancel();
    _sidController.dispose();
    _passwordController.dispose();
    _repository?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logInfo('Lifecycle: $state');
    if (state == AppLifecycleState.resumed && !_safeModeDisableAutoTasks) {
      _autoSyncIfNeeded();
    }
  }

  bool get _needsSetup {
    final repo = _repository;
    return repo != null && !repo.hasCredential;
  }

  void _startBootWatchdog() {
    _bootWatchdog?.cancel();
    _logInfo('启动看门狗已开启 (25s)');
    _bootWatchdog = Timer(const Duration(seconds: 25), () {
      if (!mounted || !_booting) {
        return;
      }
      _logWarn('启动看门狗触发超时');
      setState(() {
        _booting = false;
        _status = '启动超时，请点击重试。';
      });
    });
  }

  Future<void> _bootstrap() async {
    _logInfo('开始 bootstrap');
    try {
      final repo = await CanteenRepository.create().timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('本地数据初始化超时。'),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _repository = repo;
        _profile = repo.profile;
        if (repo.lastSyncAt != null && _status.isEmpty) {
          _status = '上次同步：${formatDateTime(repo.lastSyncAt)}';
        }
      });
      _logInfo('bootstrap 完成，hasCredential=${repo.hasCredential}');
    } catch (error, stackTrace) {
      _logError('bootstrap 失败', error, stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '初始化失败：${_formatError(error)}';
      });
    } finally {
      _bootWatchdog?.cancel();
      _logInfo('bootstrap 结束，开始加载摘要与自动刷新检查');
      if (mounted) {
        setState(() {
          _booting = false;
        });
      }
      unawaited(_reloadSummarySafe());
      if (!_safeModeDisableAutoTasks) {
        unawaited(_autoSyncIfNeeded(showLastSyncWhenNoAction: true));
      }
    }
  }

  Future<void> _retryBootstrap() async {
    if (_syncing || _settingUp) {
      return;
    }
    _logInfo('手动重试启动');
    await _repository?.close();
    if (!mounted) {
      return;
    }
    setState(() {
      _repository = null;
      _summary = null;
      _profile = null;
      _booting = true;
      _status = '';
    });
    _startBootWatchdog();
    await _bootstrap();
  }

  Future<void> _clearLocalAndRetry() async {
    if (_syncing || _settingUp) {
      return;
    }
    _logWarn('用户触发清空本地数据并重试');
    setState(() {
      _booting = true;
      _status = '正在清理本地数据...';
    });

    try {
      await _repository?.close();
      final storage = await LocalStorageService.create();
      await storage.clearAll();
      await LocalDatabaseService.deleteDatabaseFile();
    } catch (error, stackTrace) {
      _logError('清理本地数据失败（已忽略）', error, stackTrace);
      // ignore cleanup error and continue retry.
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _repository = null;
      _summary = null;
      _profile = null;
      _status = '';
    });
    _startBootWatchdog();
    await _bootstrap();
  }

  Future<void> _reloadSummary({String? month}) async {
    final repo = _repository;
    if (repo == null) {
      return;
    }
    _logInfo('加载摘要 month=${month ?? "(current)"}');
    final summary = await repo
        .loadSummary(requestedMonth: month)
        .timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw TimeoutException('加载本地数据超时。'),
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _summary = summary;
    });
    final hasData =
        summary != null && summary.daily.any((item) => item.txnCount > 0);
    _logInfo('摘要加载完成 hasData=$hasData month=${summary?.selectedMonth ?? "-"}');
  }

  Future<void> _reloadSummarySafe({String? month}) async {
    try {
      await _reloadSummary(month: month);
    } catch (error, stackTrace) {
      _logError('加载摘要失败', error, stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '加载摘要失败：${_formatError(error)}';
      });
    }
  }

  Future<void> _autoSyncIfNeeded({
    bool showLastSyncWhenNoAction = false,
  }) async {
    if (_safeModeDisableAutoTasks) {
      return;
    }
    final repo = _repository;
    if (repo == null || !repo.hasCredential || _settingUp || _syncing) {
      return;
    }
    _logInfo('自动刷新检查，lastSyncDay=${repo.lastSyncAt ?? "-"}');
    if (!repo.shouldAutoSyncToday()) {
      if (showLastSyncWhenNoAction &&
          repo.lastSyncAt != null &&
          _status.isEmpty) {
        setState(() {
          _status = '上次同步：${formatDateTime(repo.lastSyncAt)}';
        });
      }
      return;
    }
    _logInfo('触发自动刷新');
    await _syncNow(auto: true, includeTransactions: true, lookbackDays: 2);
  }

  Future<void> _syncNow({
    required bool auto,
    bool includeTransactions = false,
    int? lookbackDays,
  }) async {
    final repo = _repository;
    if (repo == null || !repo.hasCredential || _settingUp || _syncing) {
      return;
    }
    _logInfo(
      '开始刷新 auto=$auto includeTransactions=$includeTransactions lookbackDays=${lookbackDays ?? "-"}',
    );

    setState(() {
      _syncing = true;
      _status = auto
          ? (includeTransactions ? '今日首次进入，正在自动刷新...' : '今日首次进入，正在快速刷新...')
          : '正在刷新...';
    });

    try {
      await repo
          .syncNow(
            includeTransactions: includeTransactions,
            lookbackDays: lookbackDays,
            onProgress: (message) {
              if (!mounted) {
                return;
              }
              _logInfo('刷新进度: $message');
              setState(() {
                _status = message;
              });
            },
          )
          .timeout(
            Duration(seconds: includeTransactions ? 120 : 40),
            onTimeout: () {
              throw TimeoutException(auto ? '自动刷新超时，稍后可手动重试。' : '刷新超时，请稍后重试。');
            },
          );
      if (!mounted) {
        return;
      }
      _profile = repo.profile;
      await _reloadSummarySafe(month: _summary?.selectedMonth);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '刷新完成。';
      });
      _logInfo('刷新完成');
    } catch (error, stackTrace) {
      _logError('刷新失败', error, stackTrace);
      if (!mounted) {
        return;
      }
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
    if (repo == null || _settingUp || _syncing) {
      return;
    }

    final sid = _sidController.text.trim();
    final password = _passwordController.text;
    if (sid.isEmpty || password.isEmpty) {
      setState(() {
        _status = '请输入食堂账号和密码。';
      });
      return;
    }
    _logInfo('开始初始化账号 sid=$sid');

    setState(() {
      _settingUp = true;
      _status = '正在初始化账号...';
    });

    try {
      await repo
          .initializeAccount(
            sid: sid,
            password: password,
            localOnly: true,
            onProgress: (message) {
              if (!mounted) {
                return;
              }
              _logInfo('初始化进度: $message');
              setState(() {
                _status = message;
              });
            },
          )
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              throw TimeoutException('初始化超时，请检查网络后重试。');
            },
          );
      if (!mounted) {
        return;
      }
      _profile = repo.profile;
      if (!mounted) {
        return;
      }
      _sidController.clear();
      _passwordController.clear();
      setState(() {
        _status = '初始化完成（已跳过远程校验）。请进入主页后点右下角刷新同步。';
      });
      _logInfo('初始化账号完成');
    } catch (error, stackTrace) {
      _logError('初始化账号失败', error, stackTrace);
      if (!mounted) {
        return;
      }
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
    if (repo == null || _syncing || _settingUp) {
      return;
    }

    setState(() {
      _syncing = true;
      _status = '正在退出...';
    });
    _logInfo('开始退出登录');

    try {
      await repo.logout();
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = null;
        _summary = null;
        _status = '已退出并清空本地数据。';
        _tabIndex = 1;
      });
      _logInfo('退出登录完成');
    } catch (error, stackTrace) {
      _logError('退出登录失败', error, stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '退出失败：${_formatError(error)}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
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

  void _logInfo(String message) {
    unawaited(AppLogService.instance.info(message, tag: 'APP'));
  }

  void _logWarn(String message) {
    unawaited(AppLogService.instance.warn(message, tag: 'APP'));
  }

  void _logError(String context, Object error, StackTrace stackTrace) {
    unawaited(
      AppLogService.instance.error(
        context,
        tag: 'APP',
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 14),
                  Text(
                    _status.isEmpty ? '正在启动...' : _status,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

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
                    onPressed: _retryBootstrap,
                    child: const Text('重试启动'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _clearLocalAndRetry,
                    child: const Text('清空本地数据后重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final body = IndexedStack(
      index: _tabIndex,
      children: <Widget>[
        HomePage(
          summary: _summary,
          hasCredential: _repository?.hasCredential ?? false,
          isSyncing: _syncing || _settingUp,
          status: _status,
          onMonthChanged: (month) {
            _reloadSummarySafe(month: month);
          },
        ),
        SettingsPage(
          profile: _profile,
          lastSyncAt: _summary?.lastSyncAt ?? _repository?.lastSyncAt,
          onLogout: _logout,
          isBusy: _syncing || _settingUp,
        ),
      ],
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: <Widget>[
            body,
            if (_needsSetup)
              Positioned.fill(
                child: _SetupOverlay(
                  sidController: _sidController,
                  passwordController: _passwordController,
                  submitting: _settingUp,
                  statusMessage: _status,
                  onSubmit: _setupAccount,
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: _tabIndex == 0 && !_needsSetup
          ? FloatingActionButton.extended(
              onPressed: (_syncing || _settingUp)
                  ? null
                  : () => _syncNow(auto: false, includeTransactions: true),
              icon: _syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_syncing ? '刷新中' : '刷新'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '主页',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
        onDestinationSelected: (index) {
          setState(() {
            _tabIndex = index;
          });
        },
      ),
    );
  }
}

class _SetupOverlay extends StatelessWidget {
  const _SetupOverlay({
    required this.sidController,
    required this.passwordController,
    required this.submitting,
    required this.statusMessage,
    required this.onSubmit,
  });

  final TextEditingController sidController;
  final TextEditingController passwordController;
  final bool submitting;
  final String statusMessage;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              margin: const EdgeInsets.all(24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '初始化账号',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '首次使用请填写食堂账号和原密码。当前版本初始化仅保存本地账号，远程同步请在主页手动刷新。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (statusMessage.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      Builder(
                        builder: (context) {
                          final isError =
                              statusMessage.contains('失败') ||
                              statusMessage.contains('超时') ||
                              statusMessage.contains('错误');
                          return Text(
                            statusMessage,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: isError
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context).colorScheme.primary,
                                ),
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: sidController,
                      enabled: !submitting,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '食堂账号',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      enabled: !submitting,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '食堂密码',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: submitting ? null : onSubmit,
                        icon: submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(submitting ? '初始化中...' : '初始化并登录'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
