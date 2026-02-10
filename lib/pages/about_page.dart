import 'package:flutter/material.dart';
import 'package:mobile_app/services/app_update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _repoUrl = 'https://github.com/imbrby/nnez-canteen-mobile';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> with WidgetsBindingObserver {
  String _versionLabel = '';
  String? _updateInfo;
  bool _checking = false;
  bool _autoCheckEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMeta();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMeta();
    }
  }

  Future<void> _loadMeta() async {
    final info = await PackageInfo.fromPlatform();
    final autoCheck = await AppUpdateService.instance.isAutoCheckEnabled();
    if (!mounted) return;
    setState(() {
      _versionLabel = info.buildNumber.isEmpty
          ? 'v${info.version}'
          : 'v${info.version}+${info.buildNumber}';
      _autoCheckEnabled = autoCheck;
    });
  }

  Future<void> _checkUpdate({required bool manual}) async {
    await _loadMeta();
    setState(() {
      _checking = true;
      _updateInfo = null;
    });
    try {
      final result = await AppUpdateService.instance.checkForUpdate(
        ignoreSkippedTag: manual,
      );
      if (!mounted) return;
      setState(() => _updateInfo = result.message);
      if (result.hasUpdate) {
        await AppUpdateService.instance.showUpdateDialog(context, result);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _toggleAutoCheck(bool enabled) async {
    setState(() => _autoCheckEnabled = enabled);
    await AppUpdateService.instance.setAutoCheckEnabled(enabled);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.info_outline, color: colorScheme.primary),
                  title: const Text('应用版本'),
                  trailing: Text(
                    _versionLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: Icon(
                    Icons.auto_awesome_outlined,
                    color: colorScheme.primary,
                  ),
                  title: const Text('启动时自动检查更新'),
                  subtitle: Text(
                    '开启后发现新版本会自动弹窗',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _autoCheckEnabled,
                  onChanged: _toggleAutoCheck,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(
                    Icons.update_outlined,
                    color: colorScheme.primary,
                  ),
                  title: const Text('检查更新'),
                  trailing: _checking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _updateInfo != null
                      ? Text(
                          _updateInfo!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _checking ? null : () => _checkUpdate(manual: true),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(
                    Icons.code_outlined,
                    color: colorScheme.primary,
                  ),
                  title: const Text('GitHub'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => launchUrl(
                    Uri.parse(_repoUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
