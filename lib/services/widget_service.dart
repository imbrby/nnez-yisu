import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:nnez_yisu/core/expense_classifier.dart';
import 'package:nnez_yisu/models/recharge_record.dart';
import 'package:nnez_yisu/models/transaction_record.dart';
import 'package:nnez_yisu/services/app_log_service.dart';

enum CanteenWidgetTheme { pine, grain, ink }

enum CanteenWidgetKind { balance, overview, endurance }

class CanteenWidgetPreferences {
  const CanteenWidgetPreferences({
    this.theme = CanteenWidgetTheme.pine,
    this.hideBalance = false,
    this.showStudentName = true,
    this.showTodaySpend = true,
  });

  final CanteenWidgetTheme theme;
  final bool hideBalance;
  final bool showStudentName;
  final bool showTodaySpend;

  CanteenWidgetPreferences copyWith({
    CanteenWidgetTheme? theme,
    bool? hideBalance,
    bool? showStudentName,
    bool? showTodaySpend,
  }) {
    return CanteenWidgetPreferences(
      theme: theme ?? this.theme,
      hideBalance: hideBalance ?? this.hideBalance,
      showStudentName: showStudentName ?? this.showStudentName,
      showTodaySpend: showTodaySpend ?? this.showTodaySpend,
    );
  }
}

class CanteenWidgetSnapshot {
  const CanteenWidgetSnapshot({
    required this.balance,
    required this.todaySpend,
    required this.studentName,
    required this.updatedAt,
    this.estimatedDays,
  });

  final String balance;
  final String todaySpend;
  final String studentName;
  final String updatedAt;
  final int? estimatedDays;
}

class WidgetActivityRecord {
  const WidgetActivityRecord({
    required this.occurredAt,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.isRecharge,
    required this.category,
  });

  final String occurredAt;
  final String title;
  final String subtitle;
  final double amount;
  final bool isRecharge;
  final ExpenseCategory category;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'subtitle': subtitle,
    'amount': amount.toStringAsFixed(2),
    'isRecharge': isRecharge,
    'category': category.name,
  };
}

class WidgetService {
  static const _androidWidgetNames = <String>[
    'CanteenWidgetProvider',
    'CanteenOverviewWidgetProvider',
    'CanteenEnduranceWidgetProvider',
  ];
  static Future<void> _preferenceWriteQueue = Future<void>.value();

  static Future<void> updateWidget({
    required double balance,
    double? todaySpend,
    double? monthExpense,
    double? monthRecharge,
    int? monthRecordCount,
    String? monthLabel,
    double? mealAmount,
    double? drinkAmount,
    double? snackAmount,
    List<WidgetActivityRecord>? recentRecords,
    int? estimatedDays,
    bool replaceEstimatedDays = false,
    String? studentName,
    DateTime? updatedAt,
  }) async {
    try {
      await HomeWidget.saveWidgetData(
        'widget_balance',
        balance.toStringAsFixed(2),
      );
      if (todaySpend != null) {
        await HomeWidget.saveWidgetData(
          'widget_today_spend',
          todaySpend.toStringAsFixed(2),
        );
      }
      if (monthExpense != null) {
        await HomeWidget.saveWidgetData(
          'widget_month_expense',
          monthExpense.toStringAsFixed(2),
        );
      }
      if (monthRecharge != null) {
        await HomeWidget.saveWidgetData(
          'widget_month_recharge',
          monthRecharge.toStringAsFixed(2),
        );
      }
      if (monthRecordCount != null) {
        await HomeWidget.saveWidgetData(
          'widget_month_record_count',
          monthRecordCount,
        );
      }
      if (monthLabel != null) {
        await HomeWidget.saveWidgetData('widget_month_label', monthLabel);
      }
      if (mealAmount != null) {
        await HomeWidget.saveWidgetData(
          'widget_meal_amount',
          mealAmount.toStringAsFixed(2),
        );
      }
      if (drinkAmount != null) {
        await HomeWidget.saveWidgetData(
          'widget_drink_amount',
          drinkAmount.toStringAsFixed(2),
        );
      }
      if (snackAmount != null) {
        await HomeWidget.saveWidgetData(
          'widget_snack_amount',
          snackAmount.toStringAsFixed(2),
        );
      }
      if (recentRecords != null) {
        await HomeWidget.saveWidgetData(
          'widget_recent_records',
          jsonEncode(
            recentRecords.take(4).map((record) => record.toJson()).toList(),
          ),
        );
      }
      if (estimatedDays != null) {
        await HomeWidget.saveWidgetData('widget_estimated_days', estimatedDays);
      } else if (replaceEstimatedDays) {
        await HomeWidget.saveWidgetData<int>('widget_estimated_days', null);
      }
      if (studentName != null) {
        await HomeWidget.saveWidgetData('widget_student_name', studentName);
      }
      if (updatedAt != null) {
        await HomeWidget.saveWidgetData(
          'widget_updated_at',
          _formatUpdatedAt(updatedAt),
        );
      }
      await refreshAllWidgets();
      AppLogService.instance.info(
        'widgets updated: balance=$balance todaySpend=$todaySpend',
        tag: 'WIDGET',
      );
    } catch (error, stackTrace) {
      AppLogService.instance.error(
        'widget update failed',
        tag: 'WIDGET',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> updateFromData({
    required double balance,
    required Map<String, List<TransactionRecord>> transactionsByMonth,
    required Map<String, List<RechargeRecord>> rechargesByMonth,
    required int? estimatedDays,
    String? studentName,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final todayKey = '$monthKey-${now.day.toString().padLeft(2, '0')}';
    final monthTransactions = transactionsByMonth[monthKey] ?? const [];
    final monthRecharges = rechargesByMonth[monthKey] ?? const [];
    final todaySpend = monthTransactions
        .where((transaction) => transaction.occurredDay == todayKey)
        .fold<double>(0, (sum, transaction) => sum + transaction.amount.abs());
    final categoryTotals = <ExpenseCategory, double>{
      ExpenseCategory.meal: 0,
      ExpenseCategory.drink: 0,
      ExpenseCategory.snack: 0,
    };
    for (final transaction in monthTransactions) {
      final category = ExpenseClassifier.classify(
        transaction.itemName,
      ).category;
      if (categoryTotals.containsKey(category)) {
        categoryTotals[category] =
            (categoryTotals[category] ?? 0) + transaction.amount.abs();
      }
    }
    final recentRecords = <WidgetActivityRecord>[
      for (final transaction in transactionsByMonth.values.expand(
        (rows) => rows,
      ))
        WidgetActivityRecord(
          occurredAt: transaction.occurredAt,
          title: transaction.itemName,
          subtitle: _formatActivityTime(
            transaction.occurredDay,
            transaction.occurredAt,
          ),
          amount: transaction.amount.abs(),
          isRecharge: false,
          category: ExpenseClassifier.classify(transaction.itemName).category,
        ),
      for (final recharge in rechargesByMonth.values.expand((rows) => rows))
        WidgetActivityRecord(
          occurredAt: recharge.occurredAt,
          title: recharge.channel.isEmpty ? '校园卡充值' : recharge.channel,
          subtitle: _formatActivityTime(
            recharge.occurredDay,
            recharge.occurredAt,
          ),
          amount: recharge.amount.abs(),
          isRecharge: true,
          category: ExpenseCategory.unknown,
        ),
    ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    return updateWidget(
      balance: balance,
      todaySpend: todaySpend,
      monthExpense: monthTransactions.fold<double>(
        0,
        (sum, transaction) => sum + transaction.amount.abs(),
      ),
      monthRecharge: monthRecharges.fold<double>(
        0,
        (sum, recharge) => sum + recharge.amount.abs(),
      ),
      monthRecordCount: monthTransactions.length + monthRecharges.length,
      monthLabel: '${now.year}年${now.month}月记录',
      mealAmount: categoryTotals[ExpenseCategory.meal] ?? 0,
      drinkAmount: categoryTotals[ExpenseCategory.drink] ?? 0,
      snackAmount: categoryTotals[ExpenseCategory.snack] ?? 0,
      recentRecords: recentRecords,
      estimatedDays: estimatedDays,
      replaceEstimatedDays: true,
      studentName: studentName,
      updatedAt: updatedAt,
    );
  }

  static int? estimateDays(
    double? balance,
    Map<String, List<TransactionRecord>> transactionsByMonth,
  ) {
    if (balance == null || balance <= 0) return null;
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final lastMonthKey =
        '${lastMonth.year}-${lastMonth.month.toString().padLeft(2, '0')}';
    final rows = transactionsByMonth[lastMonthKey];
    if (rows == null || rows.isEmpty) return null;
    final dailyTotals = <String, double>{};
    for (final transaction in rows) {
      dailyTotals[transaction.occurredDay] =
          (dailyTotals[transaction.occurredDay] ?? 0) +
          transaction.amount.abs();
    }
    if (dailyTotals.isEmpty) return null;
    final total = dailyTotals.values.fold<double>(0, (a, b) => a + b);
    final average = total / dailyTotals.length;
    return average <= 0 ? null : (balance / average).floor();
  }

  static Future<CanteenWidgetPreferences> loadPreferences() async {
    final themeKey = await HomeWidget.getWidgetData<String>(
      'widget_theme',
      defaultValue: CanteenWidgetTheme.pine.name,
    );
    return CanteenWidgetPreferences(
      theme: CanteenWidgetTheme.values.firstWhere(
        (theme) => theme.name == themeKey,
        orElse: () => CanteenWidgetTheme.pine,
      ),
      hideBalance:
          await HomeWidget.getWidgetData<bool>(
            'widget_hide_balance',
            defaultValue: false,
          ) ??
          false,
      showStudentName:
          await HomeWidget.getWidgetData<bool>(
            'widget_show_student_name',
            defaultValue: true,
          ) ??
          true,
      showTodaySpend:
          await HomeWidget.getWidgetData<bool>(
            'widget_show_today_spend',
            defaultValue: true,
          ) ??
          true,
    );
  }

  static Future<void> savePreferences(CanteenWidgetPreferences preferences) {
    final write = _preferenceWriteQueue.catchError((_) {}).then((_) async {
      await HomeWidget.saveWidgetData('widget_theme', preferences.theme.name);
      await HomeWidget.saveWidgetData(
        'widget_hide_balance',
        preferences.hideBalance,
      );
      await HomeWidget.saveWidgetData(
        'widget_show_student_name',
        preferences.showStudentName,
      );
      await HomeWidget.saveWidgetData(
        'widget_show_today_spend',
        preferences.showTodaySpend,
      );
      await refreshAllWidgets();
    });
    _preferenceWriteQueue = write.catchError((_) {});
    return write;
  }

  static Future<CanteenWidgetSnapshot> loadSnapshot() async {
    return CanteenWidgetSnapshot(
      balance:
          await HomeWidget.getWidgetData<String>(
            'widget_balance',
            defaultValue: '--',
          ) ??
          '--',
      todaySpend:
          await HomeWidget.getWidgetData<String>(
            'widget_today_spend',
            defaultValue: '0.00',
          ) ??
          '0.00',
      estimatedDays: await HomeWidget.getWidgetData<int>(
        'widget_estimated_days',
      ),
      studentName:
          await HomeWidget.getWidgetData<String>(
            'widget_student_name',
            defaultValue: '',
          ) ??
          '',
      updatedAt:
          await HomeWidget.getWidgetData<String>(
            'widget_updated_at',
            defaultValue: '等待同步',
          ) ??
          '等待同步',
    );
  }

  static Future<void> refreshAllWidgets() async {
    for (final name in _androidWidgetNames) {
      await HomeWidget.updateWidget(androidName: name);
    }
  }

  static Future<bool> canPinWidgets() async {
    if (!Platform.isAndroid) return false;
    return await HomeWidget.isRequestPinWidgetSupported() ?? false;
  }

  static Future<void> requestPin(CanteenWidgetKind kind) {
    final name = switch (kind) {
      CanteenWidgetKind.balance => 'CanteenWidgetProvider',
      CanteenWidgetKind.overview => 'CanteenOverviewWidgetProvider',
      CanteenWidgetKind.endurance => 'CanteenEnduranceWidgetProvider',
    };
    return HomeWidget.requestPinWidget(androidName: name);
  }

  static String _formatUpdatedAt(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.month}月${value.day}日 $hour:$minute';
  }

  static String _formatActivityTime(String occurredDay, String occurredAt) {
    final day = occurredDay.length >= 10
        ? occurredDay.substring(5).replaceFirst('-', '/')
        : '--/--';
    final time = occurredAt.length >= 16
        ? occurredAt.substring(11, 16)
        : '--:--';
    return '$day $time';
  }
}
