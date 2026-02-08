import 'package:flutter/material.dart';
import 'package:mobile_app/core/time_utils.dart';
import 'package:mobile_app/services/canteen_repository.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.status,
  });

  final CanteenRepository? repository;
  final String status;

  @override
  Widget build(BuildContext context) {
    final repo = repository;
    final balance = repo?.balance;
    final balanceUpdatedAt = repo?.balanceUpdatedAt;

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
                  balance == null ? '-' : '¥${balance.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  balanceUpdatedAt == null || balanceUpdatedAt.isEmpty
                      ? '未同步'
                      : '更新于 ${formatDateTime(balanceUpdatedAt)}',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
