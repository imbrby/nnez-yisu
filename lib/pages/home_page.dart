import 'package:flutter/material.dart';
import 'package:mobile_app/core/time_utils.dart';
import 'package:mobile_app/models/home_summary.dart';
import 'package:mobile_app/models/transaction_record.dart';
import 'package:mobile_app/widgets/spending_calendar.dart';

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
    if (data == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: <Widget>[
          _SectionCard(
            child: Text(
              hasCredential ? '已初始化。请点右下角“刷新”加载数据。' : '请先到设置页初始化账号。',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      );
    }

    final activeDays = data.daily.where((item) => item.totalAmount > 0).length;
    final avgByActiveDay = activeDays > 0 ? data.totalAmount / activeDays : 0.0;
    final avgByTxn = data.transactionCount > 0
        ? data.totalAmount / data.transactionCount
        : 0.0;

    DailySpending peak = const DailySpending(
      day: '-',
      totalAmount: 0,
      txnCount: 0,
    );
    for (final item in data.daily) {
      if (item.totalAmount > peak.totalAmount) {
        peak = item;
      }
    }

    final monthOptions = data.availableMonths.reversed.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: <Widget>[
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              status,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('当前余额', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                data.currentBalance == null
                    ? '-'
                    : _money(data.currentBalance!),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                data.balanceUpdatedAt == null
                    ? '未同步余额'
                    : '更新于 ${formatDateTime(data.balanceUpdatedAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '当月消费汇总',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: data.selectedMonth,
                      decoration: const InputDecoration(
                        labelText: '选择月份',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: monthOptions
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item.month,
                              child: Text(
                                '${monthLabel(item.month)}${item.hasData ? '' : '（无消费）'}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: isSyncing
                          ? null
                          : (value) {
                              if (value != null && value.isNotEmpty) {
                                onMonthChanged(value);
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${data.startDate} ~ ${data.endDate}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _StatTile(
                    title: '总消费',
                    value: _money(data.totalAmount),
                    hint: '当月',
                  ),
                  _StatTile(
                    title: '总笔数',
                    value: '${data.transactionCount}',
                    hint: '消费记录数',
                  ),
                  _StatTile(
                    title: '活跃日均',
                    value: _money(avgByActiveDay),
                    hint: '总额 / 活跃天数',
                  ),
                  _StatTile(title: '活跃天数', value: '$activeDays', hint: '当日有消费'),
                  _StatTile(
                    title: '单笔平均消费',
                    value: _money(avgByTxn),
                    hint: '总额 / 笔数',
                  ),
                  _StatTile(
                    title: '单日峰值',
                    value: _money(peak.totalAmount),
                    hint: peak.day == '-' ? '无消费峰值' : peak.day,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('每日花费日历', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              SpendingCalendar(daily: data.daily),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('每日明细', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              _DailyTable(daily: data.daily.reversed.toList()),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('近 20 条消费', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              _RecentTable(recent: data.recent),
            ],
          ),
        ),
      ],
    );
  }

  String _money(double value) => '¥${value.toStringAsFixed(2)}';
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.title,
    required this.value,
    required this.hint,
  });

  final String title;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyTable extends StatelessWidget {
  const _DailyTable({required this.daily});

  final List<DailySpending> daily;

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) {
      return const Text('暂无数据');
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const <DataColumn>[
          DataColumn(label: Text('日期')),
          DataColumn(label: Text('消费总额')),
          DataColumn(label: Text('笔数')),
        ],
        rows: daily
            .map(
              (item) => DataRow(
                cells: <DataCell>[
                  DataCell(Text(item.day)),
                  DataCell(Text('¥${item.totalAmount.toStringAsFixed(2)}')),
                  DataCell(Text('${item.txnCount}')),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _RecentTable extends StatelessWidget {
  const _RecentTable({required this.recent});

  final List<TransactionRecord> recent;

  @override
  Widget build(BuildContext context) {
    if (recent.isEmpty) {
      return const Text('暂无数据');
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const <DataColumn>[
          DataColumn(label: Text('时间')),
          DataColumn(label: Text('消费点')),
          DataColumn(label: Text('金额')),
        ],
        rows: recent
            .map(
              (item) => DataRow(
                cells: <DataCell>[
                  DataCell(Text(formatDateTime(item.occurredAt))),
                  DataCell(Text(item.itemName)),
                  DataCell(Text('¥${item.amount.toStringAsFixed(2)}')),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}
