import 'dart:io';

import 'package:home_widget/home_widget.dart';
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
}
