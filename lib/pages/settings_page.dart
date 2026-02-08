import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_app/models/campus_profile.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.profile,
    required this.onLogout,
    required this.isBusy,
  });

  final CampusProfile? profile;
  final VoidCallback onLogout;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final data = profile;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const SizedBox(height: 40),
                  // User Profile Card
                  if (data != null) ...[
                    Card(
                      elevation: 0,
                      color: colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: colorScheme.primaryContainer,
                              child: Icon(
                                Icons.person,
                                size: 30,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data.studentName,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ID: ${data.idCode}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      color: colorScheme.surfaceContainerHighest,
                      child: Column(
                        children: [
                          if (data.academyName.isNotEmpty)
                            ListTile(
                              leading: Icon(Icons.account_balance_outlined, color: colorScheme.primary),
                              title: const Text('学校'),
                              trailing: Text(data.academyName, style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant)),
                            ),
                          if (data.academyName.isNotEmpty && data.specialityName.isNotEmpty)
                            const Divider(height: 1, indent: 56),
                          if (data.specialityName.isNotEmpty)
                            ListTile(
                              leading: Icon(Icons.location_on_outlined, color: colorScheme.primary),
                              title: const Text('校区'),
                              trailing: Text(data.specialityName, style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant)),
                            ),
                          if (data.specialityName.isNotEmpty && data.gradeName.isNotEmpty)
                            const Divider(height: 1, indent: 56),
                          if (data.gradeName.isNotEmpty)
                            ListTile(
                              leading: Icon(Icons.school_outlined, color: colorScheme.primary),
                              title: const Text('年级'),
                              trailing: Text(data.gradeName, style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant)),
                            ),
                          if (data.gradeName.isNotEmpty && data.className.isNotEmpty)
                            const Divider(height: 1, indent: 56),
                          if (data.className.isNotEmpty)
                            ListTile(
                              leading: Icon(Icons.class_outlined, color: colorScheme.primary),
                              title: const Text('班级'),
                              trailing: Text(data.className, style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Logout Button
                    FilledButton.tonal(
                      onPressed: isBusy ? null : onLogout,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.logout,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text('退出登录'),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Not initialized state
                    Card(
                      elevation: 0,
                      color: colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            Icon(
                              Icons.account_circle_outlined,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '尚未初始化账号',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '请先完成账号绑定',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
          const SizedBox(height: 24),
          // About Card
          const _AboutCard(),
        ],
      ),
    );
  }
}

const _repoUrl = 'https://github.com/imbrby/nnez-canteen-mobile';

class _AboutCard extends StatefulWidget {
  const _AboutCard();

  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  String _version = '';
  String? _updateInfo;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

  Future<void> _checkUpdate() async {
    setState(() { _checking = true; _updateInfo = null; });
    try {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('https://api.github.com/repos/imbrby/nnez-canteen-mobile/releases/latest'),
      );
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      final response = await request.close().timeout(const Duration(seconds: 10));
      final body = await response.transform(utf8.decoder).join();
      client.close();
      if (response.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final tagName = (data['tag_name'] ?? '').toString();
        final remoteVersion = tagName.replaceFirst('v', '').replaceAll(RegExp(r'\+.*'), '');
        if (remoteVersion.compareTo(_version) > 0) {
          if (mounted) setState(() => _updateInfo = '发现新版本: $tagName');
          final htmlUrl = (data['html_url'] ?? '').toString();
          if (htmlUrl.isNotEmpty && mounted) {
            _showUpdateDialog(tagName, htmlUrl);
          }
        } else {
          if (mounted) setState(() => _updateInfo = '已是最新版本');
        }
      } else {
        if (mounted) setState(() => _updateInfo = '检查失败 (${response.statusCode})');
      }
    } catch (e) {
      if (mounted) setState(() => _updateInfo = '检查失败');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _showUpdateDialog(String tag, String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新版本'),
        content: Text('最新版本: $tag\n当前版本: v$_version'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('稍后')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            child: const Text('前往下载'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.info_outline, color: colorScheme.primary),
            title: const Text('关于'),
            trailing: Text('v$_version', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: Icon(Icons.update_outlined, color: colorScheme.primary),
            title: const Text('检查更新'),
            trailing: _checking
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : _updateInfo != null
                    ? Text(_updateInfo!, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant))
                    : const Icon(Icons.chevron_right),
            onTap: _checking ? null : _checkUpdate,
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: Icon(Icons.code_outlined, color: colorScheme.primary),
            title: const Text('GitHub'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(Uri.parse(_repoUrl), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
    );
  }
}
