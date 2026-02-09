import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _repoUrl = 'https://github.com/imbrby/nnez-canteen-mobile';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
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
          ),
        ],
      ),
    );
  }
}
