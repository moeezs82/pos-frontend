import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

class EnterprisePage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final List<Widget> appBarActions;
  final Widget child;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final EdgeInsetsGeometry padding;

  const EnterprisePage({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    this.appBarActions = const [],
    required this.child,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: appBarActions),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        top: false,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EnterprisePageHeader(
                title: title,
                subtitle: subtitle,
                icon: icon,
                actions: actions,
              ),
              const SizedBox(height: 14),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class EnterprisePageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;

  const EnterprisePageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppTheme.primary, size: 24),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.35,
                      ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

class EnterpriseToolbar extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const EnterpriseToolbar({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

class EnterpriseSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSearch;
  final VoidCallback? onClear;

  const EnterpriseSearchField({
    super.key,
    required this.controller,
    this.hintText = 'Search...',
    this.onSubmitted,
    this.onChanged,
    this.onSearch,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: 'Clear',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
            IconButton(
              tooltip: 'Search',
              onPressed: onSearch,
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class EnterpriseEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const EnterpriseEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 58,
              width: 58,
              decoration: BoxDecoration(
                color: AppTheme.surfaceSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 30, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class EnterpriseStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const EnterpriseStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
              letterSpacing: .2,
            ),
          ),
        ],
      ),
    );
  }
}

class EnterprisePaginationBar extends StatelessWidget {
  final int page;
  final int lastPage;
  final int? total;
  final bool loading;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const EnterprisePaginationBar({
    super.key,
    required this.page,
    required this.lastPage,
    this.total,
    this.loading = false,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
          boxShadow: AppTheme.softShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                total == null ? 'Page $page of $lastPage' : 'Total $total  •  Page $page of $lastPage',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: loading ? null : onPrevious,
              icon: const Icon(Icons.chevron_left_rounded),
              label: const Text('Previous'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: loading ? null : onNext,
              icon: const Icon(Icons.chevron_right_rounded),
              label: const Text('Next'),
            ),
          ],
        ),
      ),
    );
  }
}

class EnterpriseMetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData? icon;

  const EnterpriseMetricChip({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            '$label: ',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
