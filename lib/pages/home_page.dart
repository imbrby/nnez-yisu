import 'package:flutter/material.dart';
import 'package:mobile_app/core/time_utils.dart';
import 'package:mobile_app/models/monthly_summary.dart';
import 'package:mobile_app/services/canteen_repository.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.status,
    required this.isSyncing,
    required this.onRefresh,
    required this.monthlySummary,
    required this.monthLabel,
    required this.canGoNext,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  final CanteenRepository? repository;
  final String status;
  final bool isSyncing;
  final VoidCallback onRefresh;
  final MonthlySummary? monthlySummary;
  final String monthLabel;
  final bool canGoNext;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final repo = repository;
    final balance = repo?.balance;
    final balanceUpdatedAt = repo?.balanceUpdatedAt;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final summary = monthlySummary;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Balance Card
            Card(
              elevation: 2,
              shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.primaryContainer,
                      colorScheme.primaryContainer.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.account_balance_wallet_outlined,
                              color: colorScheme.onPrimaryContainer,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '当前余额',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                        // Refresh button with status
                        _RefreshButton(
                          isSyncing: isSyncing,
                          status: status,
                          onRefresh: onRefresh,
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      balance == null
                          ? '¥ --'
                          : '¥ ${balance.toStringAsFixed(2)}',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      balanceUpdatedAt == null || balanceUpdatedAt.isEmpty
                          ? '点击刷新按钮同步余额'
                          : '更新于 ${formatDateTime(balanceUpdatedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Monthly Summary Card
            Card(
              elevation: 2,
              shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '消费汇总',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 20),
                          onPressed: onPrevMonth,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                        Text(
                          monthLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 20),
                          onPressed: canGoNext ? onNextMonth : null,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                    if (summary != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _StatItem(label: '总消费', value: '¥${summary.totalSpent.toStringAsFixed(2)}', icon: Icons.payments_outlined, colorScheme: colorScheme)),
                          const SizedBox(width: 12),
                          Expanded(child: _StatItem(label: '总笔数', value: '${summary.transactionCount}', hint: '消费记录数', icon: Icons.receipt_long_outlined, colorScheme: colorScheme)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _StatItem(label: '活跃日均', value: '¥${summary.avgPerActiveDay.toStringAsFixed(2)}', hint: '总额 / 活跃天数', icon: Icons.trending_up_outlined, colorScheme: colorScheme)),
                          const SizedBox(width: 12),
                          Expanded(child: _StatItem(label: '活跃天数', value: '${summary.activeDays}', hint: '当日有消费', icon: Icons.event_available_outlined, colorScheme: colorScheme)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _StatItem(label: '单笔均消费', value: '¥${summary.avgPerTransaction.toStringAsFixed(2)}', hint: '总额 / 笔数', icon: Icons.analytics_outlined, colorScheme: colorScheme)),
                          const SizedBox(width: 12),
                          Expanded(child: _StatItem(label: '单日峰值', value: '¥${summary.maxDailySpent.toStringAsFixed(2)}', icon: Icons.arrow_upward_outlined, colorScheme: colorScheme)),
                        ],
                      ),
                    ],
                    if (summary == null) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          '暂无数据，请刷新',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            ],
          ),
        ),
      );
    }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({
    required this.isSyncing,
    required this.status,
    required this.onRefresh,
    required this.colorScheme,
  });

  final bool isSyncing;
  final String status;
  final VoidCallback onRefresh;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isSyncing ? null : onRefresh,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.onPrimaryContainer.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSyncing)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onPrimaryContainer,
                ),
              )
            else
              Icon(
                Icons.refresh,
                size: 18,
                color: colorScheme.onPrimaryContainer,
              ),
            if (status.isNotEmpty) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 100),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    this.hint,
    required this.icon,
    required this.colorScheme,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

