import 'package:flutter/material.dart';
import 'package:mobile_app/core/time_utils.dart';
import 'package:mobile_app/models/monthly_summary.dart';
import 'package:mobile_app/models/recharge_record.dart';
import 'package:mobile_app/models/transaction_record.dart';
import 'package:mobile_app/services/canteen_repository.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.monthlySummary,
    required this.monthLabel,
    required this.selectedMonth,
    required this.dailyTotals,
    required this.dailyCounts,
    required this.recentTransactions,
    required this.recentRecharges,
    required this.estimatedDays,
    required this.canGoNext,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  final CanteenRepository? repository;
  final MonthlySummary? monthlySummary;
  final String monthLabel;
  final String selectedMonth;
  final Map<String, double> dailyTotals;
  final Map<String, int> dailyCounts;
  final List<TransactionRecord> recentTransactions;
  final List<RechargeRecord> recentRecharges;
  final int? estimatedDays;
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

    // Merge recent transactions and recharges into activity list
    final recentActivity = <_ActivityItem>[];
    for (final txn in recentTransactions) {
      recentActivity.add(_ActivityItem(
        occurredAt: txn.occurredAt,
        occurredDay: txn.occurredDay,
        title: txn.itemName,
        amount: txn.amount,
        isRecharge: false,
      ));
    }
    for (final r in recentRecharges) {
      recentActivity.add(_ActivityItem(
        occurredAt: r.occurredAt,
        occurredDay: r.occurredDay,
        title: r.channel.isNotEmpty ? r.channel : '充值',
        amount: r.amount,
        isRecharge: true,
      ));
    }
    recentActivity.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final displayActivity = recentActivity.take(20).toList();

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
                    // PLACEHOLDER_ESTIMATED_DAYS_AND_UPDATED
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            balanceUpdatedAt == null || balanceUpdatedAt.isEmpty
                                ? '点击刷新按钮同步余额'
                                : '更新于 ${formatDateTime(balanceUpdatedAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        if (estimatedDays != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '预计可用 $estimatedDays 天',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (estimatedDays == null && balance != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '预计可用 -- 天',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // PLACEHOLDER_MONTHLY_SUMMARY
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
                        Icon(Icons.calendar_month_outlined, color: colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text('消费汇总', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 20),
                          onPressed: onPrevMonth,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                        Text(monthLabel, style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
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
                      Row(children: [
                        Expanded(child: _StatItem(label: '总消费', value: '¥${summary.totalSpent.toStringAsFixed(2)}', hint: '当月总消费', icon: Icons.payments_outlined, colorScheme: colorScheme)),
                        const SizedBox(width: 12),
                        Expanded(child: _StatItem(label: '总笔数', value: '${summary.transactionCount}', hint: '消费记录数', icon: Icons.receipt_long_outlined, colorScheme: colorScheme)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: _StatItem(label: '活跃日均', value: '¥${summary.avgPerActiveDay.toStringAsFixed(2)}', hint: '总额 / 活跃天数', icon: Icons.trending_up_outlined, colorScheme: colorScheme)),
                        const SizedBox(width: 12),
                        Expanded(child: _StatItem(label: '活跃天数', value: '${summary.activeDays}', hint: '当日有消费', icon: Icons.event_available_outlined, colorScheme: colorScheme)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: _StatItem(label: '单笔均消费', value: '¥${summary.avgPerTransaction.toStringAsFixed(2)}', hint: '总额 / 笔数', icon: Icons.analytics_outlined, colorScheme: colorScheme)),
                        const SizedBox(width: 12),
                        Expanded(child: _StatItem(label: '单日峰值', value: '¥${summary.maxDailySpent.toStringAsFixed(2)}', hint: '单日最高消费', icon: Icons.arrow_upward_outlined, colorScheme: colorScheme)),
                      ]),
                    ],
                    if (summary == null) ...[
                      const SizedBox(height: 16),
                      Center(child: Text('暂无数据，请刷新', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant))),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // PLACEHOLDER_CALENDAR_AND_ACTIVITY
            // Spending Calendar Card
            Card(
              elevation: 2,
              shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _SpendingCalendar(
                  selectedMonth: selectedMonth,
                  dailyTotals: dailyTotals,
                  dailyCounts: dailyCounts,
                ),
              ),
            ),
            if (displayActivity.isNotEmpty) ...[
              const SizedBox(height: 16),
              // Recent Activity Card
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
                          Icon(Icons.receipt_long_outlined, color: colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text('最近余额变动', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...displayActivity.map((item) => _ActivityTile(item: item)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// PLACEHOLDER_HELPER_CLASSES

class _ActivityItem {
  const _ActivityItem({
    required this.occurredAt,
    required this.occurredDay,
    required this.title,
    required this.amount,
    required this.isRecharge,
  });
  final String occurredAt;
  final String occurredDay;
  final String title;
  final double amount;
  final bool isRecharge;
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});

  final _ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final time = item.occurredAt.length >= 16 ? item.occurredAt.substring(11, 16) : '';
    final date = item.occurredDay.length >= 10
        ? '${item.occurredDay.substring(5).replaceFirst('-', '/')} $time'
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: item.isRecharge
                  ? colorScheme.tertiaryContainer
                  : colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              item.isRecharge ? Icons.add_circle_outline : Icons.restaurant_outlined,
              size: 18,
              color: item.isRecharge
                  ? colorScheme.onTertiaryContainer
                  : colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          // PLACEHOLDER_TILE_REST
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  date,
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(
            item.isRecharge
                ? '+¥${item.amount.toStringAsFixed(2)}'
                : '-¥${item.amount.toStringAsFixed(2)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: item.isRecharge
                  ? const Color(0xFF2E7D32)
                  : colorScheme.error,
            ),
          ),
        ],
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
    // PLACEHOLDER_STAT_ITEM_BODY
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

// PLACEHOLDER_SPENDING_CALENDAR

class _SpendingCalendar extends StatelessWidget {
  const _SpendingCalendar({
    required this.selectedMonth,
    required this.dailyTotals,
    required this.dailyCounts,
  });

  final String selectedMonth;
  final Map<String, double> dailyTotals;
  final Map<String, int> dailyCounts;

  static const _warmLight = Color(0xFFFFF3E0);
  static const _warmDark = Color(0xFFE65100);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final parts = selectedMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7;

    final maxSpend = dailyTotals.values.isEmpty
        ? 1.0
        : dailyTotals.values.reduce((a, b) => a > b ? a : b);

    const weekdays = ['日', '一', '二', '三', '四', '五', '六'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.grid_view_outlined, color: colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text('消费日历', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: weekdays.map((d) => Expanded(
            child: Center(
              child: Text(d, style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
            ),
          )).toList(),
        ),
        const SizedBox(height: 4),
        // PLACEHOLDER_CALENDAR_ROWS
        ..._buildRows(context, daysInMonth, startWeekday, year, month, maxSpend, theme, colorScheme),
      ],
    );
  }

  List<Widget> _buildRows(BuildContext context, int daysInMonth, int startWeekday, int year, int month, double maxSpend, ThemeData theme, ColorScheme colorScheme) {
    final rows = <Widget>[];
    var dayCounter = 1;
    final totalCells = startWeekday + daysInMonth;
    final rowCount = (totalCells / 7).ceil();

    for (var row = 0; row < rowCount; row++) {
      final cells = <Widget>[];
      for (var col = 0; col < 7; col++) {
        final cellIndex = row * 7 + col;
        if (cellIndex < startWeekday || dayCounter > daysInMonth) {
          cells.add(const Expanded(child: SizedBox(height: 48)));
        } else {
          final day = dayCounter;
          final dayStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
          final spent = dailyTotals[dayStr] ?? 0.0;
          final count = dailyCounts[dayStr] ?? 0;
          final intensity = maxSpend > 0 ? (spent / maxSpend).clamp(0.0, 1.0) : 0.0;

          final bgColor = spent > 0
              ? Color.lerp(_warmLight, _warmDark, intensity * 0.7)!
              : colorScheme.surfaceContainerHighest;
          final textColor = spent > 0
              ? (intensity > 0.5 ? Colors.white : Colors.brown.shade900)
              : colorScheme.onSurfaceVariant;

          cells.add(Expanded(
            child: GestureDetector(
              onTap: spent > 0 ? () => _showDayDetail(context, dayStr, day, spent, count) : null,
              child: Container(
                height: 48,
                margin: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$day', style: TextStyle(fontSize: 10, color: textColor)),
                    if (spent > 0)
                      Text(
                        '¥${spent.toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor),
                      ),
                  ],
                ),
              ),
            ),
          ));
          dayCounter++;
        }
      }
      rows.add(Row(children: cells));
    }
    return rows;
  }

  void _showDayDetail(BuildContext context, String dayStr, int day, double spent, int count) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$day日消费详情', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(children: [
                  Icon(Icons.payments_outlined, color: colorScheme.primary),
                  const SizedBox(height: 4),
                  Text('¥${spent.toStringAsFixed(2)}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  Text('总消费', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                ]),
                Column(children: [
                  Icon(Icons.receipt_long_outlined, color: colorScheme.primary),
                  const SizedBox(height: 4),
                  Text('$count', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  Text('交易笔数', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                ]),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
