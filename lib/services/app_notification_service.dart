import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nnez_yisu/services/app_update_service.dart';

enum AppNotificationKind { info, success, error }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.kind,
    this.showProgress = false,
  });

  final int id;
  final String title;
  final String message;
  final AppNotificationKind kind;
  final bool showProgress;
}

class AppNotificationService extends ChangeNotifier {
  AppNotificationService._();

  static final AppNotificationService instance = AppNotificationService._();

  AppNotification? _current;
  Timer? _dismissTimer;
  int _nextId = 0;

  AppNotification? get current => _current;

  void showInfo(
    String message, {
    String title = '提示',
    Duration duration = const Duration(seconds: 5),
  }) {
    _show(title, message, AppNotificationKind.info, duration: duration);
  }

  void showSuccess(
    String message, {
    String title = '操作完成',
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(title, message, AppNotificationKind.success, duration: duration);
  }

  void showError(
    String message, {
    String title = '操作失败',
    Duration duration = const Duration(seconds: 8),
  }) {
    _show(title, message, AppNotificationKind.error, duration: duration);
  }

  void showProgress(String title, String message) {
    _show(title, message, AppNotificationKind.info, showProgress: true);
  }

  void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  void clear() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _current = null;
  }

  void _show(
    String title,
    String message,
    AppNotificationKind kind, {
    bool showProgress = false,
    Duration? duration,
  }) {
    _dismissTimer?.cancel();
    final notification = AppNotification(
      id: ++_nextId,
      title: title,
      message: message,
      kind: kind,
      showProgress: showProgress,
    );
    _current = notification;
    notifyListeners();
    if (duration != null) {
      _dismissTimer = Timer(duration, () {
        if (_current?.id == notification.id) dismiss();
      });
    }
  }
}

class AppNotificationHost extends StatefulWidget {
  const AppNotificationHost({super.key});

  @override
  State<AppNotificationHost> createState() => _AppNotificationHostState();
}

class _AppNotificationHostState extends State<AppNotificationHost> {
  @override
  void dispose() {
    AppNotificationService.instance.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = AppNotificationService.instance;
    final updates = AppUpdateService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([notifications, updates]),
      builder: (context, _) {
        final hasUpdate =
            updates.downloadState.phase != UpdateDownloadPhase.idle;
        final notification = notifications.current;
        if (!hasUpdate && notification == null) {
          return const SizedBox.shrink();
        }
        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasUpdate)
                    UpdateDownloadBanner(
                      service: updates,
                      applySafeArea: false,
                    ),
                  if (hasUpdate && notification != null)
                    const SizedBox(height: 8),
                  if (notification != null)
                    _AppNotificationBanner(notification: notification),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AppNotificationBanner extends StatelessWidget {
  const _AppNotificationBanner({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, iconColor, iconBackground) = switch (notification.kind) {
      AppNotificationKind.success => (
        Icons.check_circle_outline,
        colorScheme.primary,
        colorScheme.primaryContainer,
      ),
      AppNotificationKind.error => (
        Icons.error_outline,
        colorScheme.error,
        colorScheme.errorContainer,
      ),
      AppNotificationKind.info => (
        notification.showProgress
            ? Icons.sync_rounded
            : Icons.info_outline_rounded,
        colorScheme.tertiary,
        colorScheme.tertiaryContainer,
      ),
    };
    return Semantics(
      liveRegion: true,
      label: '${notification.title}，${notification.message}',
      child: Material(
        elevation: 8,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notification.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (notification.showProgress) ...[
                      const SizedBox(height: 9),
                      LinearProgressIndicator(
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: AppNotificationService.instance.dismiss,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
