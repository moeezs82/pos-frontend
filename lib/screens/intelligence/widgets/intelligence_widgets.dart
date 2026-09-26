import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> asMapList(dynamic value) {
  if (value is! Iterable) return const [];
  return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false);
}

String money(dynamic value) {
  final n = double.tryParse(value?.toString() ?? '');
  if (n == null) return value?.toString() ?? '0.00';
  return n.toStringAsFixed(2);
}

String qty(dynamic value) {
  final n = double.tryParse(value?.toString() ?? '');
  if (n == null) return value?.toString() ?? '0';
  if ((n - n.round()).abs() < 0.000001) return n.round().toString();
  return n.toStringAsFixed(2);
}

String percent(dynamic value, {int digits = 1, bool signed = false}) {
  final n = double.tryParse(value?.toString() ?? '');
  if (n == null) return '—';
  final formatted = (n * 100).toStringAsFixed(digits);
  if (signed && n > 0) return '+$formatted%';
  return '$formatted%';
}


String confidenceLevel(dynamic basis) {
  final map = asMap(basis);
  return (map['level'] ?? 'none').toString().toLowerCase();
}

bool confidenceHasUsableEstimate(dynamic basis) => confidenceLevel(basis) != 'none';

String titleCase(String value) {
  if (value.trim().isEmpty) return value;
  return value
      .split(RegExp(r'[\s_-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}

Color _confidenceColor(String level) {
  switch (level) {
    case 'high':
      return AppTheme.success;
    case 'medium':
      return AppTheme.info;
    case 'low':
      return AppTheme.warning;
    default:
      return AppTheme.textMuted;
  }
}

String _confidenceLabel(String level) {
  switch (level) {
    case 'high':
      return 'High';
    case 'medium':
      return 'Medium';
    case 'low':
      return 'Low';
    default:
      return 'Collecting data';
  }
}

class IntelligenceMetaBar extends StatelessWidget {
  final String computedAt;
  final bool stale;
  final VoidCallback? onRefresh;
  final bool refreshing;

  const IntelligenceMetaBar({
    super.key,
    required this.computedAt,
    required this.stale,
    this.onRefresh,
    this.refreshing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: stale ? const Color(0xFFFFFBEB) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: stale ? const Color(0xFFFDE68A) : AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(
            stale ? Icons.history_rounded : Icons.schedule_rounded,
            size: 18,
            color: stale ? AppTheme.warning : AppTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              stale
                  ? 'Showing the last successful calculation${computedAt.isEmpty ? '' : ' • $computedAt'}'
                  : computedAt.isEmpty
                      ? 'Calculated from your recorded POS history.'
                      : 'Calculated $computedAt',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onRefresh != null)
            OutlinedButton.icon(
              onPressed: refreshing ? null : onRefresh,
              icon: refreshing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
        ],
      ),
    );
  }
}

class ConfidenceBadge extends StatelessWidget {
  final dynamic basis;
  final bool compact;

  const ConfidenceBadge({super.key, required this.basis, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final map = asMap(basis);
    final level = (map['level'] ?? 'none').toString().toLowerCase();
    final history = map['history_days'];
    final observations = map['observations'];
    final color = _confidenceColor(level);
    final details = [
      if (history != null) '$history history days',
      if (observations != null) '$observations selling days',
    ].join(' • ');
    return Tooltip(
      message: details.isEmpty
          ? 'Confidence ${_confidenceLabel(level)}'
          : '${_confidenceLabel(level)} • $details',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 6),
        decoration: BoxDecoration(
          color: color.withOpacity(.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          _confidenceLabel(level),
          style: TextStyle(
            color: color,
            fontSize: compact ? 10.5 : 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class StockClassBadge extends StatelessWidget {
  final String value;
  const StockClassBadge({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value.toLowerCase();
    final color = switch (v) {
      'running' => AppTheme.success,
      'steady' => AppTheme.info,
      'slow' => AppTheme.warning,
      'dead' => AppTheme.danger,
      'new' => AppTheme.purple,
      _ => AppTheme.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        v.isEmpty ? 'Collecting' : titleCase(v),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class IssueChip extends StatelessWidget {
  final String label;
  final Color color;
  const IssueChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class IntelligenceError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const IntelligenceError({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42, color: AppTheme.danger),
            const SizedBox(height: 12),
            Text(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class IntelligencePageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget>? actions;

  const IntelligencePageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, height: 1.35)),
          ],
        );
        final actionWidgets = actions ?? const <Widget>[];
        if (constraints.maxWidth < 760 || actionWidgets.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              content,
              if (actionWidgets.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: actionWidgets),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: content),
            const SizedBox(width: 16),
            ...actionWidgets,
          ],
        );
      },
    );
  }
}

class IntelligenceInfoBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color color;
  final Color? backgroundColor;
  final Widget? trailing;

  const IntelligenceInfoBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.color = AppTheme.info,
    this.backgroundColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withOpacity(.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(message, style: const TextStyle(color: AppTheme.textMuted, height: 1.4)),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String? caption;
  final String? deltaText;
  final IconData icon;
  final Color color;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    this.caption,
    this.deltaText,
    required this.icon,
    this.color = AppTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 220),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
              if (deltaText != null)
                Text(
                  deltaText!,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.4)),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption!, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.3)),
          ],
        ],
      ),
    );
  }
}

class IntelligenceSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const IntelligenceSectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

class LegendTile extends StatelessWidget {
  final String title;
  final String description;
  final Color color;
  const LegendTile({super.key, required this.title, required this.description, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.bar_chart_rounded, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(description, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}

class IntelligenceEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  const IntelligenceEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.inbox_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return IntelligenceSectionCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.textMuted, size: 36),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }
}
