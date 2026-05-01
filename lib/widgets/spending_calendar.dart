import 'package:flutter/material.dart';
import 'package:nnez_yisu/models/home_summary.dart';

class SpendingCalendar extends StatelessWidget {
  const SpendingCalendar({super.key, required this.daily});

  final List<DailySpending> daily;

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }

    final first = daily.first.day;
    final offset = _weekdayIndex(first);
    final cells = <Widget>[
      for (final item in const <String>['日', '一', '二', '三', '四', '五', '六'])
        Center(
          child: Text(
            item,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      for (int i = 0; i < offset; i += 1) const SizedBox(height: 48),
      for (final item in daily) _DayCell(day: item),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('少 ¥15', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 10,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                  gradient: LinearGradient(
                    colors: <Color>[
                      Color(0xFF32A852),
                      Color(0xFFF4D03F),
                      Color(0xFFD93025),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('多 ¥30+', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 7,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cells,
        ),
      ],
    );
  }

  int _weekdayIndex(String day) {
    final parts = day.split('-');
    if (parts.length != 3) {
      return 0;
    }
    final year = int.tryParse(parts[0]) ?? 1970;
    final month = int.tryParse(parts[1]) ?? 1;
    final date = int.tryParse(parts[2]) ?? 1;
    if (year < 1970 || month < 1 || month > 12 || date < 1 || date > 31) {
      return 0;
    }
    return DateTime.utc(year, month, date, 12).weekday % 7;
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day});

  final DailySpending day;

  @override
  Widget build(BuildContext context) {
    final amount = day.totalAmount;
    final textColor = amount >= 24 ? Colors.white : const Color(0xFF2F2A25);
    final background = _amountToColor(amount);
    final dayText = day.day.length >= 10
        ? day.day.substring(8, 10).replaceFirst(RegExp(r'^0'), '')
        : '-';
    final amountText = amount > 0 ? amount.toStringAsFixed(2) : '-';

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x1A2F2A25)),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            dayText,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              amountText,
              style: TextStyle(
                color: amount > 0
                    ? textColor
                    : textColor.withValues(alpha: 0.45),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _amountToColor(double amount) {
    if (!amount.isFinite || amount <= 0) {
      return const Color(0xFFF3EFE8);
    }
    final ratio = (amount / 30).clamp(0.0, 1.0);
    if (ratio <= 0.5) {
      return Color.lerp(
            const Color(0xFF32A852),
            const Color(0xFFF4D03F),
            ratio / 0.5,
          ) ??
          const Color(0xFFF4D03F);
    }
    return Color.lerp(
          const Color(0xFFF4D03F),
          const Color(0xFFD93025),
          (ratio - 0.5) / 0.5,
        ) ??
        const Color(0xFFD93025);
  }
}
