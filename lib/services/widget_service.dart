import 'package:home_widget/home_widget.dart';
import 'package:mobile_app/services/app_log_service.dart';

class WidgetService {
  static const _androidWidgetName = 'CanteenWidgetProvider';

  static Future<void> updateWidget({
    required double balance,
    required int? estimatedDays,
  }) async {
    try {
      await HomeWidget.saveWidgetData('widget_balance', balance.toStringAsFixed(2));
      await HomeWidget.saveWidgetData(
        'widget_estimated_days',
        estimatedDays?.toString() ?? '--',
      );
      await HomeWidget.updateWidget(
        androidName: _androidWidgetName,
      );
      AppLogService.instance.info(
        'widget updated: balance=$balance estimatedDays=$estimatedDays',
        tag: 'WIDGET',
      );
    } catch (e) {
      AppLogService.instance.info('widget update failed: $e', tag: 'WIDGET');
    }
  }
}
