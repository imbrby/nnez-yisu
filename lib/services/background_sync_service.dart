import 'package:home_widget/home_widget.dart';
import 'package:mobile_app/services/app_log_service.dart';
import 'package:mobile_app/services/campus_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

const backgroundSyncTaskName = 'com.brby.yisu.backgroundSync';

Future<bool> backgroundSyncCallback() async {
  try {
    await AppLogService.instance.init();
    AppLogService.instance.info('background sync start', tag: 'BG');

    final prefs = await SharedPreferences.getInstance();
    final sid = (prefs.getString('campus_sid') ?? '').trim();
    final password = prefs.getString('campus_password') ?? '';
    if (sid.isEmpty || password.isEmpty) {
      AppLogService.instance.info('background sync skipped: no credentials', tag: 'BG');
      return true;
    }

    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Fetch last month range for estimated days calculation
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0);
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final client = CampusApiClient();
    final payload = await client.fetchAll(
      sid: sid,
      plainPassword: password,
      startDate: fmt(lastMonth),
      endDate: dateStr,
      includeTransactions: true,
    );

    // Calculate estimated days from last month's data
    final lastMonthStart = fmt(lastMonth);
    final lastMonthEndStr = fmt(lastMonthEnd);
    final lastMonthTxns = payload.transactions.where(
      (t) => t.occurredDay.compareTo(lastMonthStart) >= 0 &&
             t.occurredDay.compareTo(lastMonthEndStr) <= 0,
    );
    final dailyTotals = <String, double>{};
    for (final txn in lastMonthTxns) {
      dailyTotals[txn.occurredDay] =
          (dailyTotals[txn.occurredDay] ?? 0) + txn.amount.abs();
    }
    int? estimatedDays;
    if (dailyTotals.isNotEmpty) {
      final totalSpent = dailyTotals.values.fold<double>(0, (a, b) => a + b);
      final avgPerActiveDay = totalSpent / dailyTotals.length;
      if (avgPerActiveDay > 0) {
        estimatedDays = (payload.balance / avgPerActiveDay).floor();
      }
    }

    // Update widget data
    await HomeWidget.saveWidgetData('widget_balance', payload.balance.toStringAsFixed(2));
    await HomeWidget.saveWidgetData(
      'widget_estimated_days',
      estimatedDays?.toString() ?? '--',
    );
    await HomeWidget.updateWidget(androidName: 'CanteenWidgetProvider');

    // Update balance in SharedPreferences
    await prefs.setDouble('user_${sid}_balance', payload.balance);
    await prefs.setString('user_${sid}_balance_updated_at', payload.balanceUpdatedAt.toIso8601String());

    AppLogService.instance.info(
      'background sync done: balance=${payload.balance} estimatedDays=$estimatedDays',
      tag: 'BG',
    );
    return true;
  } catch (e) {
    AppLogService.instance.info('background sync failed: $e', tag: 'BG');
    return false;
  }
}
