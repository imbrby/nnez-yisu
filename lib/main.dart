import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_app/core/time_utils.dart';
import 'package:mobile_app/models/campus_profile.dart';
import 'package:mobile_app/models/home_summary.dart';
import 'package:mobile_app/pages/home_page.dart';
import 'package:mobile_app/pages/settings_page.dart';
import 'package:mobile_app/services/canteen_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CanteenApp());
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
      title: '食堂消费',
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
  final TextEditingController _sidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  CanteenRepository? _repository;
  HomeSummary? _summary;
  CampusProfile? _profile;

  bool _booting = true;
  bool _syncing = false;
  bool _settingUp = false;
  int _tabIndex = 0;
  String _status = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sidController.dispose();
    _passwordController.dispose();
    _repository?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _autoSyncIfNeeded();
    }
  }

  bool get _needsSetup {
    final repo = _repository;
    return repo != null && !repo.hasCredential;
  }

  Future<void> _bootstrap() async {
    try {
      final repo = await CanteenRepository.create();
      if (!mounted) {
        return;
      }
      _repository = repo;
      _profile = repo.profile;
      await _reloadSummary();
      if (repo.lastSyncAt != null && _status.isEmpty) {
        setState(() {
          _status = '上次同步：${formatDateTime(repo.lastSyncAt)}';
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '初始化失败：${_formatError(error)}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _booting = false;
        });
      }
      unawaited(_autoSyncIfNeeded(showLastSyncWhenNoAction: true));
    }
  }

  Future<void> _reloadSummary({String? month}) async {
    final repo = _repository;
    if (repo == null) {
      return;
    }
    final summary = await repo.loadSummary(requestedMonth: month);
    if (!mounted) {
      return;
    }
    setState(() {
      _summary = summary;
    });
  }

  Future<void> _autoSyncIfNeeded({
    bool showLastSyncWhenNoAction = false,
  }) async {
    final repo = _repository;
    if (repo == null || !repo.hasCredential || _settingUp || _syncing) {
      return;
    }
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
    await _syncNow(auto: true);
  }

  Future<void> _syncNow({required bool auto}) async {
    final repo = _repository;
    if (repo == null || !repo.hasCredential || _settingUp || _syncing) {
      return;
    }

    setState(() {
      _syncing = true;
      _status = auto ? '今日首次进入，正在自动刷新...' : '正在刷新...';
    });

    try {
      await repo.syncNow().timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          throw TimeoutException(auto ? '自动刷新超时，稍后可手动重试。' : '刷新超时，请稍后重试。');
        },
      );
      if (!mounted) {
        return;
      }
      _profile = repo.profile;
      await _reloadSummary(month: _summary?.selectedMonth);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '刷新完成。';
      });
    } catch (error) {
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

    setState(() {
      _settingUp = true;
      _status = '正在初始化并同步数据，请稍候...';
    });

    try {
      await repo
          .initializeAccount(sid: sid, password: password)
          .timeout(
            const Duration(seconds: 90),
            onTimeout: () {
              throw TimeoutException('初始化超时，请检查网络后重试。');
            },
          );
      if (!mounted) {
        return;
      }
      _profile = repo.profile;
      await _reloadSummary();
      if (!mounted) {
        return;
      }
      _sidController.clear();
      _passwordController.clear();
      setState(() {
        _status = '初始化完成。';
      });
    } catch (error) {
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
    } catch (error) {
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
    return text.replaceFirst(RegExp(r'^(Exception|TimeoutException):\s*'), '');
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final body = IndexedStack(
      index: _tabIndex,
      children: <Widget>[
        HomePage(
          summary: _summary,
          isSyncing: _syncing || _settingUp,
          status: _status,
          onMonthChanged: (month) {
            _reloadSummary(month: month);
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
      body: Stack(
        children: <Widget>[
          body,
          if (_needsSetup)
            Positioned.fill(
              child: _SetupOverlay(
                sidController: _sidController,
                passwordController: _passwordController,
                submitting: _settingUp,
                onSubmit: _setupAccount,
              ),
            ),
        ],
      ),
      floatingActionButton: _tabIndex == 0 && !_needsSetup
          ? FloatingActionButton(
              onPressed: (_syncing || _settingUp)
                  ? null
                  : () => _syncNow(auto: false),
              child: _syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
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
    required this.onSubmit,
  });

  final TextEditingController sidController;
  final TextEditingController passwordController;
  final bool submitting;
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
                      '首次使用请填写食堂账号和原密码。应用会自动同步最近一年流水并保存到本地。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
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
