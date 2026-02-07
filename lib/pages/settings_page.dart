import 'package:flutter/material.dart';
import 'package:mobile_app/core/time_utils.dart';
import 'package:mobile_app/models/campus_profile.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.profile,
    required this.lastSyncAt,
    required this.onLogout,
    required this.isBusy,
  });

  final CampusProfile? profile;
  final String? lastSyncAt;
  final VoidCallback onLogout;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final data = profile;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: data == null
                ? Text(
                    '尚未初始化账号。请先完成账号绑定。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            child: Icon(
                              Icons.person,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  data.studentName,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'IDcode: ${data.idCode.isEmpty ? data.sid : data.idCode}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _InfoLine(label: '年级', value: data.gradeName),
                      _InfoLine(label: '班级', value: data.className),
                      _InfoLine(label: '学校', value: data.academyName),
                      _InfoLine(label: '类型', value: data.specialityName),
                      const SizedBox(height: 10),
                      Text(
                        lastSyncAt == null
                            ? '尚未同步'
                            : '上次同步：${formatDateTime(lastSyncAt)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: (data == null || isBusy) ? null : onLogout,
          icon: const Icon(Icons.logout),
          label: const Text('退出登录并清空本地数据'),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 48,
            child: Text(
              '$label：',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
