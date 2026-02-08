import 'package:flutter/material.dart';
import 'package:mobile_app/core/time_utils.dart';
import 'package:mobile_app/models/home_summary.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.summary,
    required this.hasCredential,
    required this.isSyncing,
    required this.status,
    required this.onMonthChanged,
  });

  final HomeSummary? summary;
  final bool hasCredential;
  final bool isSyncing;
  final String status;
  final ValueChanged<String> onMonthChanged;

  @override
  Widget build(BuildContext context) {
    final data = summary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(status),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('当前余额'),
                const SizedBox(height: 8),
                Text(
                  data?.currentBalance == null
                      ? '-'
                      : '¥${data!.currentBalance!.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  data?.balanceUpdatedAt == null
                      ? '未同步'
                      : '更新于 ${formatDateTime(data!.balanceUpdatedAt)}',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
