import 'package:flutter/material.dart';
import 'package:nnez_yisu/services/app_notification_service.dart';
import 'package:nnez_yisu/services/canteen_repository.dart';
import 'package:nnez_yisu/services/webdav_backup_service.dart';

class DataManagementPage extends StatefulWidget {
  const DataManagementPage({
    super.key,
    required this.onExport,
    required this.onImport,
    required this.onCreateBackupJson,
    required this.onMergeCloudBackup,
    required this.onCloudDataChanged,
    required this.isBusy,
  });

  final VoidCallback onExport;
  final VoidCallback onImport;
  final Future<String> Function() onCreateBackupJson;
  final Future<BackupMergeResult> Function(String json, {bool apply})
  onMergeCloudBackup;
  final Future<void> Function() onCloudDataChanged;
  final bool isBusy;

  @override
  State<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends State<DataManagementPage> {
  final _webDav = WebDavBackupService.instance;
  WebDavConfig? _config;
  bool _operating = false;

  bool get _busy => widget.isBusy || _operating;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await _webDav.loadConfig();
    if (mounted) setState(() => _config = config);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final config = _config;
    return Scaffold(
      appBar: AppBar(title: const Text('数据管理')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_operating) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 14),
          ],
          Text('本地文件', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.upload_outlined,
                    color: colorScheme.primary,
                  ),
                  title: const Text('导出完整备份'),
                  subtitle: const Text('包含消费、充值、余额与个人资料'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : widget.onExport,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(
                    Icons.download_outlined,
                    color: colorScheme.primary,
                  ),
                  title: const Text('导入备份'),
                  subtitle: const Text('从 JSON 文件恢复本地数据'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : widget.onImport,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'WebDAV 云端备份',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (config?.lastBackupAt != null)
                Text(
                  '上次 ${_formatTime(config!.lastBackupAt!)}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.cloud_outlined,
                    color: colorScheme.primary,
                  ),
                  title: const Text('WebDAV 配置'),
                  subtitle: Text(
                    config?.isConfigured == true
                        ? '${config!.username} · ${_modeLabel(config.mode)}'
                        : '尚未配置服务器、用户名和密码',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _configure,
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: Icon(Icons.autorenew, color: colorScheme.primary),
                  title: const Text('手动同步后自动备份'),
                  subtitle: const Text('仅点击首页同步按钮时执行，自动同步不会触发备份'),
                  value: config?.autoBackupEnabled ?? false,
                  onChanged: _busy ? null : _toggleAutoBackup,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(
                    Icons.wifi_tethering,
                    color: colorScheme.primary,
                  ),
                  title: const Text('测试连接'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy || config?.isConfigured != true
                      ? null
                      : _testConnection,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(
                    Icons.cloud_upload_outlined,
                    color: colorScheme.primary,
                  ),
                  title: const Text('立即备份到云端'),
                  subtitle: Text(
                    config?.mode == WebDavBackupMode.createNew
                        ? '创建带时间戳的新文件'
                        : '覆盖固定的 yisu_backup.json',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy || config?.isConfigured != true
                      ? null
                      : _manualBackup,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(
                    Icons.compare_arrows,
                    color: colorScheme.primary,
                  ),
                  title: const Text('比较并补充缺失记录'),
                  subtitle: const Text('只插入云端独有记录，不覆盖本地已有内容'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy || config?.isConfigured != true
                      ? null
                      : _compareAndMerge,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _configure() async {
    final initial = _config ?? await _webDav.loadConfig();
    if (!mounted) return;
    final result = await showDialog<WebDavConfig>(
      context: context,
      builder: (_) => _WebDavConfigDialog(initial: initial),
    );
    if (result == null) return;
    await _run('配置已保存', () async {
      await _webDav.saveConfig(result);
      await _loadConfig();
    });
  }

  Future<void> _toggleAutoBackup(bool enabled) async {
    final config = _config ?? await _webDav.loadConfig();
    if (enabled && !config.isConfigured) {
      await _configure();
      return;
    }
    await _run(enabled ? '已开启手动同步后备份' : '已关闭手动同步后备份', () async {
      await _webDav.saveConfig(config.copyWith(autoBackupEnabled: enabled));
      await _loadConfig();
    });
  }

  Future<void> _testConnection() {
    return _run('WebDAV 连接成功', () => _webDav.testConnection(_config!));
  }

  Future<void> _manualBackup() async {
    await _run('云端备份完成', () async {
      final result = await _webDav.uploadBackup(
        await widget.onCreateBackupJson(),
        config: _config,
      );
      await _loadConfig();
      if (mounted) _showMessage('已上传 ${result.fileName}');
    }, showSuccess: false);
  }

  Future<void> _compareAndMerge() async {
    setState(() => _operating = true);
    AppNotificationService.instance.showProgress(
      '正在比较云端备份',
      '正在读取云端文件并检查本地缺失记录...',
    );
    try {
      final cloudJson = await _webDav.downloadLatestBackup(config: _config);
      final preview = await widget.onMergeCloudBackup(cloudJson, apply: false);
      if (!mounted) return;
      if (preview.totalCount == 0) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('数据已完整'),
            content: const Text('云端备份没有本地缺失的消费或充值记录。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('发现缺失记录'),
              content: Text(
                '云端比本地多 ${preview.transactionCount} 条消费记录、'
                '${preview.rechargeCount} 条充值记录。\n\n'
                '合并只会补充这些记录，不会修改本地已有内容。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('补充记录'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
      final merged = await widget.onMergeCloudBackup(cloudJson, apply: true);
      await widget.onCloudDataChanged();
      if (mounted) _showMessage('已补充 ${merged.totalCount} 条记录');
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _run(
    String successMessage,
    Future<void> Function() action, {
    bool showSuccess = true,
  }) async {
    setState(() => _operating = true);
    AppNotificationService.instance.showProgress('正在处理', '请稍候，操作完成后会自动提示。');
    try {
      await action();
      if (mounted && showSuccess) _showMessage(successMessage);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  void _showMessage(String message) {
    AppNotificationService.instance.showSuccess(message);
  }

  void _showError(Object error) {
    final message = error
        .toString()
        .replaceFirst(RegExp(r'^(?:Format)?Exception:\s*'), '')
        .trim();
    AppNotificationService.instance.showError(
      message.isEmpty ? '操作失败，请稍后重试。' : message,
    );
  }

  static String _modeLabel(WebDavBackupMode mode) {
    return mode == WebDavBackupMode.overwrite ? '覆盖固定文件' : '每次创建新文件';
  }

  static String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.month)}/${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

class _WebDavConfigDialog extends StatefulWidget {
  const _WebDavConfigDialog({required this.initial});

  final WebDavConfig initial;

  @override
  State<_WebDavConfigDialog> createState() => _WebDavConfigDialogState();
}

class _WebDavConfigDialogState extends State<_WebDavConfigDialog> {
  late final TextEditingController _urlController = TextEditingController(
    text: widget.initial.url,
  );
  late final TextEditingController _usernameController = TextEditingController(
    text: widget.initial.username,
  );
  late final TextEditingController _passwordController = TextEditingController(
    text: widget.initial.password,
  );
  late WebDavBackupMode _mode = widget.initial.mode;
  late bool _autoBackup = widget.initial.autoBackupEnabled;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('WebDAV 配置'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'WebDAV 地址',
                hintText: 'https://dav.example.com/dav/（自动创建 yisu 目录）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '密码或应用专用密码',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '自动备份文件策略',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            RadioGroup<WebDavBackupMode>(
              groupValue: _mode,
              onChanged: (value) {
                if (value != null) setState(() => _mode = value);
              },
              child: const Column(
                children: [
                  RadioListTile<WebDavBackupMode>(
                    contentPadding: EdgeInsets.zero,
                    value: WebDavBackupMode.overwrite,
                    title: Text('覆盖固定文件'),
                    subtitle: Text('始终更新 yisu_backup.json，不产生历史副本'),
                  ),
                  RadioListTile<WebDavBackupMode>(
                    contentPadding: EdgeInsets.zero,
                    value: WebDavBackupMode.createNew,
                    title: Text('每次创建新文件'),
                    subtitle: Text('使用时间戳保留每一次备份'),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('手动同步后自动备份'),
              subtitle: const Text('自动同步和后台同步不会触发云端备份'),
              value: _autoBackup,
              onChanged: (value) => setState(() => _autoBackup = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              WebDavConfig(
                url: _urlController.text.trim(),
                username: _usernameController.text.trim(),
                password: _passwordController.text,
                autoBackupEnabled: _autoBackup,
                mode: _mode,
                lastBackupAt: widget.initial.lastBackupAt,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
