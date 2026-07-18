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
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enterDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 320);
    final exitDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return AnimatedBuilder(
      animation: Listenable.merge([notifications, updates]),
      builder: (context, _) {
        final hasUpdate =
            updates.downloadState.phase != UpdateDownloadPhase.idle;
        final notification = notifications.current;
        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UpdateDownloadBanner(service: updates, applySafeArea: false),
                  if (hasUpdate && notification != null)
                    const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: enterDuration,
                    reverseDuration: exitDuration,
                    switchInCurve: Curves.easeOutQuart,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previousChildren, ?currentChild],
                    ),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -0.08),
                          end: Offset.zero,
                        ).animate(animation),
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.985,
                            end: 1,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                    ),
                    child: notification == null
                        ? const SizedBox.shrink(
                            key: ValueKey('notification-idle'),
                          )
                        : _AppNotificationBanner(
                            key: const ValueKey('notification-visible'),
                            notification: notification,
                            duration: enterDuration,
                          ),
                  ),
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
  const _AppNotificationBanner({
    super.key,
    required this.notification,
    required this.duration,
  });

  final AppNotification notification;
  final Duration duration;

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
              AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutQuart,
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBackground,
                  shape: BoxShape.circle,
                ),
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: Curves.easeOutQuart,
                  switchOutCurve: Curves.easeInCubic,
                  child: Icon(
                    icon,
                    key: ValueKey(icon),
                    color: iconColor,
                    size: 21,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: Curves.easeOutQuart,
                      switchOutCurve: Curves.easeInCubic,
                      child: Text(
                        notification.title,
                        key: ValueKey(notification.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: Curves.easeOutQuart,
                      switchOutCurve: Curves.easeInCubic,
                      child: Text(
                        notification.message,
                        key: ValueKey(notification.message),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: duration,
                      curve: Curves.easeOutQuart,
                      alignment: Alignment.topCenter,
                      child: notification.showProgress
                          ? Padding(
                              padding: const EdgeInsets.only(top: 9),
                              child: LinearProgressIndicator(
                                minHeight: 5,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
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
