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

    final client = CampusApiClient();
    final payload = await client.fetchAll(
      sid: sid,
      plainPassword: password,
      startDate: dateStr,
      endDate: dateStr,
      includeTransactions: true,
    );

    // Calculate today's spending
    double todaySpent = 0;
    for (final txn in payload.transactions) {
      if (txn.occurredDay == dateStr) {
        todaySpent += txn.amount.abs();
      }
    }

    // Update widget data
    await HomeWidget.saveWidgetData('widget_balance', payload.balance.toStringAsFixed(2));
    await HomeWidget.saveWidgetData('widget_today_spent', todaySpent.toStringAsFixed(2));
    await HomeWidget.updateWidget(androidName: 'CanteenWidgetProvider');

    // Update balance in SharedPreferences
    await prefs.setDouble('user_${sid}_balance', payload.balance);
    await prefs.setString('user_${sid}_balance_updated_at', payload.balanceUpdatedAt.toIso8601String());

    AppLogService.instance.info(
      'background sync done: balance=${payload.balance} todaySpent=$todaySpent',
      tag: 'BG',
    );
    return true;
  } catch (e) {
    AppLogService.instance.info('background sync failed: $e', tag: 'BG');
    return false;
  }
}
