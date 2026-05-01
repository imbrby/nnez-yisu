import 'package:flutter/material.dart';

class AccountOperationPage extends StatefulWidget {
  const AccountOperationPage({
    super.key,
    required this.onReportLoss,
    required this.onCancelLoss,
  });

  final Future<String> Function() onReportLoss;
  final Future<String> Function() onCancelLoss;

  @override
  State<AccountOperationPage> createState() => _AccountOperationPageState();
}

class _AccountOperationPageState extends State<AccountOperationPage> {
  bool _busy = false;

  Future<void> _confirmAndExecute({
    required String title,
    required String content,
    required Future<String> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final msg = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg.isNotEmpty ? msg : '操作成功')));
    } catch (e) {
      if (!mounted) return;
      final text = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作失败：$text')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('账户操作')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.lock_outline, color: colorScheme.error),
                  title: const Text('挂失'),
                  subtitle: const Text('挂失后校园卡将无法使用'),
                  trailing: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _busy
                      ? null
                      : () => _confirmAndExecute(
                          title: '确认挂失',
                          content: '挂失后校园卡将被冻结，无法进行任何消费操作。\n\n确定要挂失吗？',
                          action: widget.onReportLoss,
                        ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(
                    Icons.lock_open_outlined,
                    color: colorScheme.primary,
                  ),
                  title: const Text('解挂'),
                  subtitle: const Text('解除挂失恢复校园卡使用'),
                  trailing: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _busy
                      ? null
                      : () => _confirmAndExecute(
                          title: '确认解挂',
                          content: '解挂后校园卡将恢复正常使用。\n\n确定要解挂吗？',
                          action: widget.onCancelLoss,
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
