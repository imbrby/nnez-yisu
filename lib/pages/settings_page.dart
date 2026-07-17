import 'package:flutter/material.dart';
import 'package:nnez_yisu/models/campus_profile.dart';
import 'package:nnez_yisu/pages/about_page.dart';
import 'package:nnez_yisu/pages/account_operation_page.dart';
import 'package:nnez_yisu/pages/app_theme_settings_page.dart';
import 'package:nnez_yisu/pages/data_management_page.dart';
import 'package:nnez_yisu/pages/widget_settings_page.dart';
import 'package:nnez_yisu/services/campus_api_client.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.profile,
    required this.onLogout,
    required this.onExport,
    required this.onImport,
    required this.onReportLoss,
    required this.onCancelLoss,
    required this.usesCustomBaseUrl,
    required this.campusBaseUrl,
    required this.onBaseUrlChanged,
    required this.isBusy,
  });

  final CampusProfile? profile;
  final VoidCallback onLogout;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final Future<String> Function() onReportLoss;
  final Future<String> Function() onCancelLoss;
  final bool usesCustomBaseUrl;
  final String campusBaseUrl;
  final Future<void> Function(String? customBaseUrl) onBaseUrlChanged;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final data = profile;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: data != null
          ? _buildLoggedIn(context, data, theme, colorScheme)
          : _buildNotInitialized(context, theme, colorScheme),
    );
  }

  Widget _buildLoggedIn(
    BuildContext context,
    CampusProfile data,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              const SizedBox(height: 40),
              // User avatar card
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
              // User details card
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest,
                child: Column(
                  children: [
                    if (data.academyName.isNotEmpty)
                      ListTile(
                        leading: Icon(
                          Icons.account_balance_outlined,
                          color: colorScheme.primary,
                        ),
                        title: const Text('学校'),
                        trailing: Text(
                          data.academyName,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (data.academyName.isNotEmpty &&
                        data.specialityName.isNotEmpty)
                      const Divider(height: 1, indent: 56),
                    // PLACEHOLDER_MORE_DETAILS
                    if (data.specialityName.isNotEmpty)
                      ListTile(
                        leading: Icon(
                          Icons.location_on_outlined,
                          color: colorScheme.primary,
                        ),
                        title: const Text('校区'),
                        trailing: Text(
                          data.specialityName,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (data.specialityName.isNotEmpty &&
                        data.gradeName.isNotEmpty)
                      const Divider(height: 1, indent: 56),
                    if (data.gradeName.isNotEmpty)
                      ListTile(
                        leading: Icon(
                          Icons.school_outlined,
                          color: colorScheme.primary,
                        ),
                        title: const Text('年级'),
                        trailing: Text(
                          data.gradeName,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (data.gradeName.isNotEmpty && data.className.isNotEmpty)
                      const Divider(height: 1, indent: 56),
                    if (data.className.isNotEmpty)
                      ListTile(
                        leading: Icon(
                          Icons.class_outlined,
                          color: colorScheme.primary,
                        ),
                        title: const Text('班级'),
                        trailing: Text(
                          data.className,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Function list card
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.palette_outlined,
                        color: colorScheme.primary,
                      ),
                      title: const Text('应用主题'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pushAppThemeSettings(context),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(
                        Icons.widgets_outlined,
                        color: colorScheme.primary,
                      ),
                      title: const Text('桌面小组件'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pushWidgetSettings(context),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(
                        Icons.credit_card_outlined,
                        color: colorScheme.primary,
                      ),
                      title: const Text('账户操作'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pushAccountOperation(context),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(
                        Icons.language_outlined,
                        color: colorScheme.primary,
                      ),
                      title: const Text('校园接口根网址'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: isBusy
                          ? null
                          : () => _showCampusBaseUrlDialog(context),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(
                        Icons.folder_outlined,
                        color: colorScheme.primary,
                      ),
                      title: const Text('数据管理'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pushDataManagement(context),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(
                        Icons.info_outline,
                        color: colorScheme.primary,
                      ),
                      title: const Text('关于'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pushAbout(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Logout button at bottom
        // PLACEHOLDER_LOGOUT_BUTTON
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: FilledButton.tonal(
            onPressed: isBusy ? null : onLogout,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout, size: 20),
                const SizedBox(width: 8),
                const Text('退出登录'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotInitialized(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const SizedBox(height: 40),
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
                Text('尚未初始化账号', style: theme.textTheme.titleLarge),
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
    );
  }

  void _pushAccountOperation(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _LazyAccountOperationPage(
          onReportLoss: onReportLoss,
          onCancelLoss: onCancelLoss,
        ),
      ),
    );
  }

  void _pushDataManagement(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _LazyDataManagementPage(
          onExport: onExport,
          onImport: onImport,
          isBusy: isBusy,
        ),
      ),
    );
  }

  void _pushWidgetSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WidgetSettingsPage()),
    );
  }

  void _pushAppThemeSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppThemeSettingsPage()),
    );
  }

  Future<void> _showCampusBaseUrlDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => _CampusBaseUrlDialog(
        usesCustomBaseUrl: usesCustomBaseUrl,
        currentBaseUrl: campusBaseUrl,
        onSave: onBaseUrlChanged,
      ),
    );
  }

  void _pushAbout(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _LazyAboutPage()),
    );
  }
}

class _CampusBaseUrlDialog extends StatefulWidget {
  const _CampusBaseUrlDialog({
    required this.usesCustomBaseUrl,
    required this.currentBaseUrl,
    required this.onSave,
  });

  final bool usesCustomBaseUrl;
  final String currentBaseUrl;
  final Future<void> Function(String? customBaseUrl) onSave;

  @override
  State<_CampusBaseUrlDialog> createState() => _CampusBaseUrlDialogState();
}

class _CampusBaseUrlDialogState extends State<_CampusBaseUrlDialog> {
  late bool _useCustom = widget.usesCustomBaseUrl;
  late final TextEditingController _controller = TextEditingController(
    text: widget.usesCustomBaseUrl
        ? widget.currentBaseUrl
        : defaultCampusBaseUrl,
  );
  bool _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('校园接口根网址'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<bool>(
              groupValue: _useCustom,
              onChanged: (value) {
                if (!_saving && value != null) _selectMode(value);
              },
              child: Column(
                children: [
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    enabled: !_saving,
                    title: const Text('默认'),
                    subtitle: const Text(defaultCampusBaseUrl),
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    enabled: !_saving,
                    title: const Text('自定义'),
                    subtitle: const Text('仅支持以 http:// 或 https:// 开头的根网址'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              enabled: _useCustom && !_saving,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '自定义根网址',
                hintText: 'http://example.com:455',
                errorText: _errorText,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
              onSubmitted: (_) {
                if (_useCustom && !_saving) _save();
              },
            ),
            const SizedBox(height: 12),
            Text(
              '更改后，前台刷新、后台数据同步和账户操作都会使用该网址。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

  void _selectMode(bool useCustom) {
    setState(() {
      _useCustom = useCustom;
      _errorText = null;
    });
  }

  Future<void> _save() async {
    final customBaseUrl = _useCustom ? _controller.text.trim() : null;
    if (_useCustom && customBaseUrl!.isEmpty) {
      setState(() => _errorText = '请输入自定义根网址。');
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await widget.onSave(customBaseUrl);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      final message = error
          .toString()
          .replaceFirst(RegExp(r'^(?:Format)?Exception:\s*'), '')
          .trim();
      setState(() {
        _saving = false;
        _errorText = message.isEmpty ? '保存失败，请检查网址。' : message;
      });
    }
  }
}

// Wrapper widgets for navigation
class _LazyAccountOperationPage extends StatelessWidget {
  const _LazyAccountOperationPage({
    required this.onReportLoss,
    required this.onCancelLoss,
  });
  final Future<String> Function() onReportLoss;
  final Future<String> Function() onCancelLoss;

  @override
  Widget build(BuildContext context) {
    return AccountOperationPage(
      onReportLoss: onReportLoss,
      onCancelLoss: onCancelLoss,
    );
  }
}

class _LazyDataManagementPage extends StatelessWidget {
  const _LazyDataManagementPage({
    required this.onExport,
    required this.onImport,
    required this.isBusy,
  });
  final VoidCallback onExport;
  final VoidCallback onImport;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return DataManagementPage(
      onExport: onExport,
      onImport: onImport,
      isBusy: isBusy,
    );
  }
}

class _LazyAboutPage extends StatelessWidget {
  const _LazyAboutPage();

  @override
  Widget build(BuildContext context) {
    return const AboutPage();
  }
}
