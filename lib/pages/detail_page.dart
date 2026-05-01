import 'package:flutter/material.dart';
import 'package:nnez_yisu/core/expense_classifier.dart';
import 'package:nnez_yisu/core/time_utils.dart';
import 'package:nnez_yisu/models/recharge_record.dart';
import 'package:nnez_yisu/models/transaction_record.dart';

enum _DetailMode { month, day }

class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.balance,
    required this.transactionsByMonth,
    required this.rechargesByMonth,
  });

  final double? balance;
  final Map<String, List<TransactionRecord>> transactionsByMonth;
  final Map<String, List<RechargeRecord>> rechargesByMonth;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late String _selectedMonth;
  late String _selectedDay;
  _DetailMode _mode = _DetailMode.month;

  @override
  void initState() {
    super.initState();
    _selectedMonth = _currentMonthKey();
    _selectedDay = _currentDayKey();
  }

  @override
  void didUpdateWidget(covariant DetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final today = _currentDayKey();
    if (_selectedDay.compareTo(today) > 0) {
      _selectedDay = today;
      _selectedMonth = today.substring(0, 7);
    }
    final currentMonth = _currentMonthKey();
    if (_selectedMonth.compareTo(currentMonth) > 0) {
      _selectedMonth = currentMonth;
      _selectedDay = _clampDayToMonth(currentMonth, _selectedDay);
    }
  }

  static String _currentMonthKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static String _currentDayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String _dayKey(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  static String _clampDayToMonth(String monthKey, String preferredDay) {
    final monthParts = monthKey.split('-');
    if (monthParts.length != 2) {
      return '$monthKey-01';
    }
    final year = int.tryParse(monthParts[0]) ?? DateTime.now().year;
    final month = int.tryParse(monthParts[1]) ?? DateTime.now().month;
    final maxDay = DateTime(year, month + 1, 0).day;

    final dayParts = preferredDay.split('-');
    final preferred = dayParts.length == 3
        ? (int.tryParse(dayParts[2]) ?? 1)
        : 1;
    final day = preferred.clamp(1, maxDay);
    return '$monthKey-${day.toString().padLeft(2, '0')}';
  }

  void _switchMonth(int delta) {
    final parts = _selectedMonth.split('-');
    if (parts.length != 2) return;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return;

    final target = DateTime(year, month + delta, 1);
    final targetKey =
        '${target.year}-${target.month.toString().padLeft(2, '0')}';
    if (targetKey.compareTo(_currentMonthKey()) > 0) return;

    setState(() {
      _selectedMonth = targetKey;
      _selectedDay = _clampDayToMonth(targetKey, _selectedDay);
    });
  }

  void _shiftDay(int delta) {
    DateTime base;
    try {
      base = DateTime.parse('$_selectedDay 12:00:00');
    } catch (_) {
      base = DateTime.now();
    }
    final next = base.add(Duration(days: delta));
    final dayKey = _dayKey(next);
    if (dayKey.compareTo(_currentDayKey()) > 0) return;
    setState(() {
      _selectedDay = dayKey;
      _selectedMonth = dayKey.substring(0, 7);
    });
  }

  void _selectDayFromCalendar(String dayKey) {
    setState(() {
      _selectedDay = dayKey;
      _selectedMonth = dayKey.substring(0, 7);
      _mode = _DetailMode.day;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final monthTransactions = widget.transactionsByMonth[_selectedMonth] ?? [];
    final monthRecharges = widget.rechargesByMonth[_selectedMonth] ?? [];

    final dailyTotals = <String, double>{};
    final dailyCounts = <String, int>{};
    for (final txn in monthTransactions) {
      dailyTotals[txn.occurredDay] =
          (dailyTotals[txn.occurredDay] ?? 0) + txn.amount.abs();
      dailyCounts[txn.occurredDay] = (dailyCounts[txn.occurredDay] ?? 0) + 1;
    }
    for (final recharge in monthRecharges) {
      dailyTotals[recharge.occurredDay] =
          (dailyTotals[recharge.occurredDay] ?? 0) + recharge.amount.abs();
      dailyCounts[recharge.occurredDay] =
          (dailyCounts[recharge.occurredDay] ?? 0) + 1;
    }

    final monthRecords = <_DetailRecord>[
      ...monthTransactions.map(
        (txn) => _DetailRecord(
          occurredAt: txn.occurredAt,
          occurredDay: txn.occurredDay,
          title: txn.itemName,
          amount: txn.amount.abs(),
          isRecharge: false,
          expense: ExpenseClassifier.classify(txn.itemName),
        ),
      ),
      ...monthRecharges.map(
        (recharge) => _DetailRecord(
          occurredAt: recharge.occurredAt,
          occurredDay: recharge.occurredDay,
          title: recharge.channel.isEmpty ? '充值' : recharge.channel,
          amount: recharge.amount.abs(),
          isRecharge: true,
          expense: null,
        ),
      ),
    ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    final filteredRecords = _mode == _DetailMode.month
        ? monthRecords
        : monthRecords
              .where((record) => record.occurredDay == _selectedDay)
              .toList();
    final rechargeTotal = filteredRecords
        .where((record) => record.isRecharge)
        .fold<double>(0, (sum, record) => sum + record.amount);
    final expenseTotal = filteredRecords
        .where((record) => !record.isRecharge)
        .fold<double>(0, (sum, record) => sum + record.amount);
    final monthCategoryTotals = <ExpenseCategory, double>{
      ExpenseCategory.meal: 0,
      ExpenseCategory.drink: 0,
      ExpenseCategory.snack: 0,
    };
    for (final record in monthRecords) {
      if (record.isRecharge || record.expense == null) {
        continue;
      }
      final category = record.expense!.category;
      if (!monthCategoryTotals.containsKey(category)) {
        continue;
      }
      monthCategoryTotals[category] =
          (monthCategoryTotals[category] ?? 0) + record.amount;
    }

    final canGoNext = _mode == _DetailMode.month
        ? _selectedMonth.compareTo(_currentMonthKey()) < 0
        : _selectedDay.compareTo(_currentDayKey()) < 0;
    final periodLabel = _mode == _DetailMode.month
        ? monthLabel(_selectedMonth)
        : _selectedDay.replaceAll('-', '/');

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.filter_alt_outlined,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '细目筛选',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (widget.balance != null)
                          Text(
                            '余额 ¥${widget.balance!.toStringAsFixed(2)}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: SegmentedButton<_DetailMode>(
                        segments: const <ButtonSegment<_DetailMode>>[
                          ButtonSegment<_DetailMode>(
                            value: _DetailMode.month,
                            icon: Icon(Icons.calendar_view_month_outlined),
                            label: Text('月份'),
                          ),
                          ButtonSegment<_DetailMode>(
                            value: _DetailMode.day,
                            icon: Icon(Icons.today_outlined),
                            label: Text('单日'),
                          ),
                        ],
                        selected: <_DetailMode>{_mode},
                        onSelectionChanged: (selection) {
                          final selected = selection.first;
                          setState(() {
                            _mode = selected;
                            if (_mode == _DetailMode.day &&
                                _selectedDay.substring(0, 7) !=
                                    _selectedMonth) {
                              _selectedDay = _clampDayToMonth(
                                _selectedMonth,
                                _selectedDay,
                              );
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => _mode == _DetailMode.month
                              ? _switchMonth(-1)
                              : _shiftDay(-1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Text(
                            periodLabel,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: canGoNext
                              ? () => _mode == _DetailMode.month
                                    ? _switchMonth(1)
                                    : _shiftDay(1)
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_mode == _DetailMode.day) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _DetailCalendar(
                    selectedMonth: _selectedMonth,
                    selectedDay: _selectedDay,
                    dailyTotals: dailyTotals,
                    dailyCounts: dailyCounts,
                    onDaySelected: _selectDayFromCalendar,
                  ),
                ),
              ),
            ],
            if (_mode == _DetailMode.month) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _MonthlyCategorySummary(
                    mealAmount: monthCategoryTotals[ExpenseCategory.meal] ?? 0,
                    drinkAmount:
                        monthCategoryTotals[ExpenseCategory.drink] ?? 0,
                    snackAmount:
                        monthCategoryTotals[ExpenseCategory.snack] ?? 0,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _mode == _DetailMode.month
                              ? '${monthLabel(_selectedMonth)}记录'
                              : '${_selectedDay.replaceAll('-', '/')}记录',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SummaryChip(
                          icon: Icons.add_card_outlined,
                          label: '充值 ¥${rechargeTotal.toStringAsFixed(2)}',
                          foregroundColor: colorScheme.tertiary,
                          backgroundColor: colorScheme.tertiaryContainer,
                        ),
                        _SummaryChip(
                          icon: Icons.payments_outlined,
                          label: '消费 ¥${expenseTotal.toStringAsFixed(2)}',
                          foregroundColor: colorScheme.error,
                          backgroundColor: colorScheme.errorContainer,
                        ),
                        _SummaryChip(
                          icon: Icons.receipt_outlined,
                          label: '${filteredRecords.length} 条记录',
                          foregroundColor: colorScheme.primary,
                          backgroundColor: colorScheme.primaryContainer,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (filteredRecords.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            '暂无记录',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ...filteredRecords.map(
                      (record) => _DetailRecordTile(record: record),
                    ),
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

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  final IconData icon;
  final String label;
  final Color foregroundColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRecord {
  const _DetailRecord({
    required this.occurredAt,
    required this.occurredDay,
    required this.title,
    required this.amount,
    required this.isRecharge,
    required this.expense,
  });

  final String occurredAt;
  final String occurredDay;
  final String title;
  final double amount;
  final bool isRecharge;
  final ExpenseClassification? expense;
}

class _DetailRecordTile extends StatelessWidget {
  const _DetailRecordTile({required this.record});

  final _DetailRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visualStyle = _recordVisualStyle(record, colorScheme);
    final time = record.occurredAt.length >= 16
        ? record.occurredAt.substring(11, 16)
        : '';
    final machineNumber = record.expense?.machineNumber;
    final machineLabel = machineNumber == null ? '' : ' · $machineNumber号机';
    final date = record.occurredDay.length >= 10
        ? '${record.occurredDay.substring(5).replaceFirst('-', '/')} $time$machineLabel'
        : formatDateTime(record.occurredAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: visualStyle.backgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              visualStyle.icon,
              size: 18,
              color: visualStyle.iconColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  date,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            record.isRecharge
                ? '+¥${record.amount.toStringAsFixed(2)}'
                : '-¥${record.amount.toStringAsFixed(2)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: record.isRecharge
                  ? const Color(0xFF2E7D32)
                  : colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  _RecordVisualStyle _recordVisualStyle(
    _DetailRecord detailRecord,
    ColorScheme colorScheme,
  ) {
    if (detailRecord.isRecharge) {
      return _RecordVisualStyle(
        icon: Icons.add_circle_outline,
        backgroundColor: colorScheme.tertiaryContainer,
        iconColor: colorScheme.onTertiaryContainer,
      );
    }
    switch (detailRecord.expense?.category) {
      case ExpenseCategory.meal:
        return _RecordVisualStyle(
          icon: Icons.restaurant_menu_outlined,
          backgroundColor: colorScheme.primaryContainer,
          iconColor: colorScheme.onPrimaryContainer,
        );
      case ExpenseCategory.drink:
        return _RecordVisualStyle(
          icon: Icons.local_cafe_outlined,
          backgroundColor: colorScheme.tertiaryContainer,
          iconColor: colorScheme.onTertiaryContainer,
        );
      case ExpenseCategory.snack:
        return _RecordVisualStyle(
          icon: Icons.icecream_outlined,
          backgroundColor: colorScheme.secondaryContainer,
          iconColor: colorScheme.onSecondaryContainer,
        );
      case ExpenseCategory.unknown:
      case null:
        return _RecordVisualStyle(
          icon: Icons.receipt_long_outlined,
          backgroundColor: colorScheme.surfaceContainerHighest,
          iconColor: colorScheme.onSurfaceVariant,
        );
    }
  }
}

class _RecordVisualStyle {
  const _RecordVisualStyle({
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
}

class _MonthlyCategorySummary extends StatelessWidget {
  const _MonthlyCategorySummary({
    required this.mealAmount,
    required this.drinkAmount,
    required this.snackAmount,
  });

  final double mealAmount;
  final double drinkAmount;
  final double snackAmount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.category_outlined, color: colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              '地点分类',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _CategoryAmountTile(
                label: '正餐',
                amount: mealAmount,
                icon: Icons.restaurant_menu_outlined,
                foregroundColor: colorScheme.primary,
                backgroundColor: colorScheme.primaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CategoryAmountTile(
                label: '饮品',
                amount: drinkAmount,
                icon: Icons.local_cafe_outlined,
                foregroundColor: colorScheme.tertiary,
                backgroundColor: colorScheme.tertiaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CategoryAmountTile(
                label: '小吃',
                amount: snackAmount,
                icon: Icons.icecream_outlined,
                foregroundColor: colorScheme.secondary,
                backgroundColor: colorScheme.secondaryContainer,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CategoryAmountTile extends StatelessWidget {
  const _CategoryAmountTile({
    required this.label,
    required this.amount,
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  final String label;
  final double amount;
  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foregroundColor),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '¥${amount.toStringAsFixed(2)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailCalendar extends StatelessWidget {
  const _DetailCalendar({
    required this.selectedMonth,
    required this.selectedDay,
    required this.dailyTotals,
    required this.dailyCounts,
    required this.onDaySelected,
  });

  final String selectedMonth;
  final String selectedDay;
  final Map<String, double> dailyTotals;
  final Map<String, int> dailyCounts;
  final ValueChanged<String> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final parts = selectedMonth.split('-');
    final year = int.tryParse(parts.first) ?? DateTime.now().year;
    final month = parts.length > 1
        ? (int.tryParse(parts[1]) ?? DateTime.now().month)
        : DateTime.now().month;

    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7;
    final maxAmount = dailyTotals.values.isEmpty
        ? 1.0
        : dailyTotals.values.reduce((a, b) => a > b ? a : b);

    const weekdays = ['日', '一', '二', '三', '四', '五', '六'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.grid_view_outlined,
              color: colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              '日历定位',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              '点日期切换到单日',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: weekdays
              .map(
                (day) => Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),
        ..._buildRows(
          context: context,
          daysInMonth: daysInMonth,
          startWeekday: startWeekday,
          year: year,
          month: month,
          maxAmount: maxAmount,
        ),
      ],
    );
  }

  List<Widget> _buildRows({
    required BuildContext context,
    required int daysInMonth,
    required int startWeekday,
    required int year,
    required int month,
    required double maxAmount,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rows = <Widget>[];
    var dayCounter = 1;
    final totalCells = startWeekday + daysInMonth;
    final rowCount = (totalCells / 7).ceil();

    for (var row = 0; row < rowCount; row++) {
      final cells = <Widget>[];
      for (var col = 0; col < 7; col++) {
        final index = row * 7 + col;
        if (index < startWeekday || dayCounter > daysInMonth) {
          cells.add(const Expanded(child: SizedBox(height: 52)));
          continue;
        }

        final day = dayCounter;
        final dayKey =
            '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        final amount = dailyTotals[dayKey] ?? 0;
        final count = dailyCounts[dayKey] ?? 0;
        final ratio = maxAmount > 0
            ? (amount / maxAmount).clamp(0.0, 1.0)
            : 0.0;
        final hasData = count > 0;
        final isSelected = selectedDay == dayKey;

        final normalBackground = hasData
            ? Color.lerp(
                colorScheme.secondaryContainer,
                colorScheme.primaryContainer,
                ratio.toDouble(),
              )!
            : colorScheme.surfaceContainerHigh;
        final normalForeground = hasData
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurfaceVariant;

        cells.add(
          Expanded(
            child: GestureDetector(
              onTap: () => onDaySelected(dayKey),
              child: Container(
                height: 52,
                margin: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.primary : normalBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$day',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: isSelected
                            ? colorScheme.onPrimary
                            : normalForeground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      hasData ? '$count笔' : '',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isSelected
                            ? colorScheme.onPrimary.withValues(alpha: 0.9)
                            : normalForeground.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        dayCounter++;
      }
      rows.add(Row(children: cells));
    }
    return rows;
  }
}
