import 'package:flutter/material.dart';
import 'package:nnez_yisu/models/campus_profile.dart';
import 'package:nnez_yisu/pages/about_page.dart';
import 'package:nnez_yisu/pages/account_operation_page.dart';
import 'package:nnez_yisu/pages/data_management_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.profile,
    required this.onLogout,
    required this.onExport,
    required this.onImport,
    required this.onReportLoss,
    required this.onCancelLoss,
    required this.isBusy,
  });

  final CampusProfile? profile;
  final VoidCallback onLogout;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final Future<String> Function() onReportLoss;
  final Future<String> Function() onCancelLoss;
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

  void _pushAbout(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _LazyAboutPage()),
    );
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
