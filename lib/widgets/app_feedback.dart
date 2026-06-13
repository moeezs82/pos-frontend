import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

enum AppFeedbackType { success, error, warning, info }

class AppFeedback {
  AppFeedback._();

  static OverlayEntry? _currentEntry;

  static void success(BuildContext context, String message) => show(
        context,
        message,
        type: AppFeedbackType.success,
      );

  static void error(BuildContext context, String message) => show(
        context,
        message,
        type: AppFeedbackType.error,
      );

  static void warning(BuildContext context, String message) => show(
        context,
        message,
        type: AppFeedbackType.warning,
      );

  static void info(BuildContext context, String message) => show(
        context,
        message,
        type: AppFeedbackType.info,
      );

  static void show(
    BuildContext context,
    String message, {
    AppFeedbackType type = AppFeedbackType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final color = _color(type);
    final icon = _icon(type);

    _currentEntry?.remove();
    _currentEntry = null;

    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _FeedbackOverlay(
        message: message,
        color: color,
        icon: icon,
        onClose: () {
          if (entry.mounted) entry.remove();
          if (_currentEntry == entry) _currentEntry = null;
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
    Future.delayed(duration, () {
      if (entry.mounted) entry.remove();
      if (_currentEntry == entry) _currentEntry = null;
    });
  }

  static Color _color(AppFeedbackType type) {
    switch (type) {
      case AppFeedbackType.success:
        return AppTheme.success;
      case AppFeedbackType.error:
        return AppTheme.danger;
      case AppFeedbackType.warning:
        return AppTheme.warning;
      case AppFeedbackType.info:
        return AppTheme.primary;
    }
  }

  static IconData _icon(AppFeedbackType type) {
    switch (type) {
      case AppFeedbackType.success:
        return Icons.check_circle_rounded;
      case AppFeedbackType.error:
        return Icons.error_rounded;
      case AppFeedbackType.warning:
        return Icons.warning_amber_rounded;
      case AppFeedbackType.info:
        return Icons.info_rounded;
    }
  }
}

class _FeedbackOverlay extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;
  final VoidCallback onClose;

  const _FeedbackOverlay({
    required this.message,
    required this.color,
    required this.icon,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final right = width >= 800 ? 24.0 : 12.0;
    final top = MediaQuery.of(context).padding.top + 14;
    final maxWidth = width >= 800 ? 430.0 : width - 24;

    return Positioned(
      top: top,
      right: right,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, -8 * (1 - value)),
                child: child,
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.navy.withOpacity(.12),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 34,
                      width: 34,
                      decoration: BoxDecoration(
                        color: color.withOpacity(.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 19),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.navy,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Dismiss',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
