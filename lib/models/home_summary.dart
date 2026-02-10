import 'package:nnez_yisu/models/transaction_record.dart';

class DailySpending {
  const DailySpending({
    required this.day,
    required this.totalAmount,
    required this.txnCount,
  });

  final String day;
  final double totalAmount;
  final int txnCount;
}

class MonthOverview {
  const MonthOverview({
    required this.month,
    required this.totalAmount,
    required this.txnCount,
    required this.hasData,
  });

  final String month;
  final double totalAmount;
  final int txnCount;
  final bool hasData;
}

class HomeSummary {
  const HomeSummary({
    required this.selectedMonth,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.availableMonths,
    required this.daily,
    required this.recent,
    required this.totalAmount,
    required this.transactionCount,
    required this.currentBalance,
    required this.balanceUpdatedAt,
    required this.lastSyncAt,
  });

  final String selectedMonth;
  final String startDate;
  final String endDate;
  final int days;
  final List<MonthOverview> availableMonths;
  final List<DailySpending> daily;
  final List<TransactionRecord> recent;
  final double totalAmount;
  final int transactionCount;
  final double? currentBalance;
  final String? balanceUpdatedAt;
  final String? lastSyncAt;
}
