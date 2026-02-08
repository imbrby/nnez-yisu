import 'package:flutter/material.dart';
import 'package:mobile_app/models/campus_profile.dart';

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
                        child: Column(
                          children: [
                            // Avatar
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: colorScheme.primaryContainer,
                              child: Icon(
                                Icons.person,
                                size: 40,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Name
                            Text(
                              data.studentName,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Student ID
                            Text(
                              data.sid,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Info List
                    Card(
                      elevation: 0,
                      color: colorScheme.surfaceContainerHighest,
                      child: Column(
                        children: [
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
        ],
      ),
    );
  }
}
