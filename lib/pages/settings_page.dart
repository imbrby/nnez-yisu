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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: data == null
                ? const Text('尚未初始化账号。请先完成账号绑定。')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        data.studentName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('账号: ${data.sid}'),
                      if (data.gradeName.isNotEmpty)
                        Text('年级: ${data.gradeName}'),
                      if (data.className.isNotEmpty)
                        Text('班级: ${data.className}'),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.tonalIcon(
          onPressed: (data == null || isBusy) ? null : onLogout,
          icon: const Icon(Icons.logout),
          label: const Text('退出登录'),
        ),
      ],
    );
  }
}
