import 'package:flutter/material.dart';

class DataManagementPage extends StatelessWidget {
  const DataManagementPage({
    super.key,
    required this.onExport,
    required this.onImport,
    required this.isBusy,
  });

  final VoidCallback onExport;
  final VoidCallback onImport;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('数据管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.upload_outlined, color: colorScheme.primary),
                  title: const Text('导出数据'),
                  subtitle: const Text('将消费记录导出为 JSON 文件'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: isBusy ? null : () {
                    onExport();
                    Navigator.pop(context);
                  },
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(Icons.download_outlined, color: colorScheme.primary),
                  title: const Text('导入数据'),
                  subtitle: const Text('从 JSON 文件导入消费记录'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: isBusy ? null : () {
                    onImport();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
