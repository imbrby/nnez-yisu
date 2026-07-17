import 'package:nnez_yisu/services/app_log_service.dart';
import 'package:nnez_yisu/services/canteen_repository.dart';
import 'package:nnez_yisu/services/widget_service.dart';

const backgroundSyncTaskName = 'com.brby.yisu.backgroundSync';

Future<bool> backgroundSyncCallback() async {
  CanteenRepository? repository;
  try {
    await AppLogService.instance.init();
    AppLogService.instance.info('background 30-day sync start', tag: 'BG');

    repository = await CanteenRepository.create();
    if (!repository.hasCredential) {
      AppLogService.instance.info(
        'background sync skipped: no credentials',
        tag: 'BG',
      );
      return true;
    }

    await repository.syncNow();
    final transactionsByMonth = await repository.loadTransactions();
    final rechargesByMonth = await repository.loadRecharges();
    final estimatedDays = WidgetService.estimateDays(
      repository.balance,
      transactionsByMonth,
    );
    await WidgetService.updateFromData(
      balance: repository.balance ?? 0,
      transactionsByMonth: transactionsByMonth,
      rechargesByMonth: rechargesByMonth,
      estimatedDays: estimatedDays,
      studentName: repository.profile?.studentName,
      updatedAt: DateTime.tryParse(repository.balanceUpdatedAt ?? ''),
    );

    AppLogService.instance.info('background 30-day sync done', tag: 'BG');
    return true;
  } catch (error, stackTrace) {
    AppLogService.instance.error(
      'background 30-day sync failed',
      tag: 'BG',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  } finally {
    await repository?.close();
  }
}
