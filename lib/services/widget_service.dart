import 'package:home_widget/home_widget.dart';
import 'package:nnez_yisu/services/app_log_service.dart';

class WidgetService {
  static const _androidWidgetName = 'CanteenWidgetProvider';

  static Future<void> updateWidget({required double balance}) async {
    try {
      await HomeWidget.saveWidgetData(
        'widget_balance',
        balance.toStringAsFixed(2),
      );
      await HomeWidget.updateWidget(androidName: _androidWidgetName);
      AppLogService.instance.info(
        'widget updated: balance=$balance',
        tag: 'WIDGET',
      );
    } catch (e) {
      AppLogService.instance.info('widget update failed: $e', tag: 'WIDGET');
    }
  }
}
