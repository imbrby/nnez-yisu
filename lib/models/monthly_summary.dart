class MonthlySummary {
  const MonthlySummary({
    required this.totalSpent,
    required this.transactionCount,
    required this.activeDays,
    required this.avgPerActiveDay,
    required this.avgPerTransaction,
    required this.maxDailySpent,
  });

  final double totalSpent;
  final int transactionCount;
  final int activeDays;
  final double avgPerActiveDay;
  final double avgPerTransaction;
  final double maxDailySpent;

  static MonthlySummary fromTransactions(List<dynamic> transactions) {
    if (transactions.isEmpty) {
      return const MonthlySummary(
        totalSpent: 0,
        transactionCount: 0,
        activeDays: 0,
        avgPerActiveDay: 0,
        avgPerTransaction: 0,
        maxDailySpent: 0,
      );
    }

    double totalSpent = 0;
    final dailySpending = <String, double>{};

    for (final txn in transactions) {
      if (txn is Map<String, dynamic>) {
        final amount = (double.tryParse(txn['Money']?.toString() ?? '0') ?? 0)
            .abs();
        totalSpent += amount;

        final timeStr = txn['Time']?.toString() ?? '';
        final match = RegExp(
          r'^(\d{4})/(\d{1,2})/(\d{1,2})',
        ).firstMatch(timeStr);
        if (match != null) {
          String pad(String v) => v.padLeft(2, '0');
          final day =
              '${match.group(1)}-${pad(match.group(2)!)}-${pad(match.group(3)!)}';
          dailySpending[day] = (dailySpending[day] ?? 0) + amount;
        }
      }
    }

    final activeDays = dailySpending.length;
    final avgPerActiveDay = activeDays > 0 ? totalSpent / activeDays : 0.0;
    final avgPerTransaction = transactions.isNotEmpty
        ? totalSpent / transactions.length
        : 0.0;
    final maxDailySpent = dailySpending.values.isEmpty
        ? 0.0
        : dailySpending.values.reduce((a, b) => a > b ? a : b);

    return MonthlySummary(
      totalSpent: totalSpent,
      transactionCount: transactions.length,
      activeDays: activeDays,
      avgPerActiveDay: avgPerActiveDay,
      avgPerTransaction: avgPerTransaction,
      maxDailySpent: maxDailySpent,
    );
  }
}
