import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

class PartyInfoPill extends StatelessWidget {
  const PartyInfoPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cleanValue = value.trim().isEmpty ? '—' : value.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white.withOpacity(.90)),
          const SizedBox(width: 7),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withOpacity(.70),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              cleanValue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PartyHeroCard extends StatelessWidget {
  const PartyHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.initials,
    required this.typeLabel,
    required this.typeIcon,
    required this.status,
    required this.balanceLabel,
    required this.balanceValue,
    required this.balanceTone,
    required this.primaryActionLabel,
    required this.primaryActionIcon,
    required this.onPrimaryAction,
    required this.onEdit,
    this.infoPills = const [],
  });

  final String title;
  final String subtitle;
  final String initials;
  final String typeLabel;
  final IconData typeIcon;
  final String status;
  final String balanceLabel;
  final String balanceValue;
  final Color balanceTone;
  final String primaryActionLabel;
  final IconData primaryActionIcon;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onEdit;
  final List<PartyInfoPill> infoPills;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.enterpriseGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDark.withOpacity(.18),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -38,
            top: -48,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(.08),
              ),
            ),
          ),
          Positioned(
            right: 56,
            bottom: -64,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(.08), width: 22),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final content = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: compact ? 54 : 64,
                      height: compact ? 54 : 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.16),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(.22)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 18 : 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _HeroBadge(
                                icon: typeIcon,
                                label: typeLabel,
                                background: Colors.white.withOpacity(.14),
                                foreground: Colors.white,
                              ),
                              _HeroStatusBadge(status: status),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            title.trim().isEmpty ? '(No name)' : title.trim(),
                            maxLines: compact ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 21 : 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.35,
                              height: 1.05,
                            ),
                          ),
                          if (subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              subtitle.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(.78),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ],
                          if (infoPills.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Wrap(spacing: 8, runSpacing: 8, children: infoPills),
                          ],
                        ],
                      ),
                    ),
                  ],
                );

                final actions = _HeroActions(
                  balanceLabel: balanceLabel,
                  balanceValue: balanceValue,
                  balanceTone: balanceTone,
                  primaryActionLabel: primaryActionLabel,
                  primaryActionIcon: primaryActionIcon,
                  onPrimaryAction: onPrimaryAction,
                  onEdit: onEdit,
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      content,
                      const SizedBox(height: 16),
                      actions,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: content),
                    const SizedBox(width: 18),
                    SizedBox(width: 238, child: actions),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroActions extends StatelessWidget {
  const _HeroActions({
    required this.balanceLabel,
    required this.balanceValue,
    required this.balanceTone,
    required this.primaryActionLabel,
    required this.primaryActionIcon,
    required this.onPrimaryAction,
    required this.onEdit,
  });

  final String balanceLabel;
  final String balanceValue;
  final Color balanceTone;
  final String primaryActionLabel;
  final IconData primaryActionIcon;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(.20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                balanceLabel,
                style: TextStyle(
                  color: Colors.white.withOpacity(.70),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .2,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      balanceValue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.4,
                      ),
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: balanceTone, shape: BoxShape.circle),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.primaryDark,
            disabledBackgroundColor: Colors.white.withOpacity(.55),
            disabledForegroundColor: AppTheme.textMuted,
          ),
          onPressed: onPrimaryAction,
          icon: Icon(primaryActionIcon),
          label: Text(primaryActionLabel),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(.34)),
            backgroundColor: Colors.white.withOpacity(.06),
          ),
          onPressed: onEdit,
          icon: const Icon(Icons.edit_rounded),
          label: const Text('Edit Profile'),
        ),
      ],
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withOpacity(.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: .25,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStatusBadge extends StatelessWidget {
  const _HeroStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().isEmpty ? 'active' : status.trim();
    final color = AppTheme.statusColor(normalized);
    return _HeroBadge(
      icon: Icons.circle,
      label: normalized.toUpperCase(),
      background: color.withOpacity(.18),
      foreground: Colors.white,
    );
  }
}

class PartyMetric {
  const PartyMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.helper,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? helper;
}

class PartyMetricGrid extends StatelessWidget {
  const PartyMetricGrid({super.key, required this.metrics});
  final List<PartyMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemWidth = width >= 820
            ? (width - 24) / 3
            : width >= 560
                ? (width - 12) / 2
                : width;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: metrics
              .map((metric) => SizedBox(
                    width: itemWidth,
                    child: PartyMetricCard(metric: metric),
                  ))
              .toList(),
        );
      },
    );
  }
}

class PartyMetricCard extends StatelessWidget {
  const PartyMetricCard({super.key, required this.metric});
  final PartyMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: metric.color.withOpacity(.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(metric.icon, color: metric.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: metric.color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.2,
                  ),
                ),
                if (metric.helper != null && metric.helper!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    metric.helper!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PartySegmentedTabBar extends StatelessWidget {
  const PartySegmentedTabBar({
    super.key,
    required this.controller,
    required this.tabs,
  });

  final TabController controller;
  final List<Tab> tabs;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: TabBar(
        controller: controller,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        indicatorSize: TabBarIndicatorSize.tab,
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        indicator: BoxDecoration(
          color: AppTheme.primarySoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary.withOpacity(.25)),
        ),
        labelColor: AppTheme.primaryDark,
        unselectedLabelColor: AppTheme.textMuted,
        labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        tabs: tabs,
      ),
    );
  }
}

class PartySectionCard extends StatelessWidget {
  const PartySectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: child,
    );
  }
}

class PartyDocumentRow extends StatelessWidget {
  const PartyDocumentRow({
    super.key,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.amount,
    required this.primaryMeta,
    required this.secondaryMeta,
    required this.openAmount,
    required this.onTap,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String amount;
  final String primaryMeta;
  final String secondaryMeta;
  final String openAmount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final leading = Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              );
              final detail = Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.trim().isEmpty ? 'Document' : title.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.navy,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      children: [
                        _MetaChip(icon: Icons.calendar_today_rounded, label: primaryMeta),
                        if (secondaryMeta.trim().isNotEmpty)
                          _MetaChip(icon: Icons.event_available_rounded, label: secondaryMeta),
                        _MetaChip(icon: Icons.account_balance_wallet_rounded, label: 'Open $openAmount'),
                      ],
                    ),
                  ],
                ),
              );
              final total = Column(
                crossAxisAlignment: compact ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    amount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [leading, const SizedBox(width: 12), detail]),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        total,
                        const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  leading,
                  const SizedBox(width: 12),
                  detail,
                  const SizedBox(width: 16),
                  SizedBox(width: 120, child: total),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textMuted),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              label.trim().isEmpty ? '—' : label.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PartyLedgerSummary extends StatelessWidget {
  const PartyLedgerSummary({
    super.key,
    required this.opening,
    required this.pageStart,
  });

  final String opening;
  final String pageStart;

  @override
  Widget build(BuildContext context) {
    return PartyMetricGrid(
      metrics: [
        PartyMetric(
          label: 'Opening Balance',
          value: opening,
          icon: Icons.account_balance_rounded,
          color: AppTheme.info,
          helper: 'Before selected range',
        ),
        PartyMetric(
          label: 'Page Start Balance',
          value: pageStart,
          icon: Icons.timeline_rounded,
          color: AppTheme.purple,
          helper: 'Before first row on this page',
        ),
      ],
    );
  }
}

class PartyLedgerRow extends StatelessWidget {
  const PartyLedgerRow({
    super.key,
    required this.date,
    required this.memo,
    required this.account,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.icon,
    required this.accentColor,
  });

  final String date;
  final String memo;
  final String account;
  final String debit;
  final String credit;
  final String balance;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final left = Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memo.trim().isEmpty ? '(No memo)' : memo.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      children: [
                        _MetaChip(icon: Icons.calendar_today_rounded, label: date.trim().isEmpty ? '—' : date),
                        if (account.trim().isNotEmpty)
                          _MetaChip(icon: Icons.account_tree_rounded, label: account),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

          final amountRow = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              _AmountBadge(label: 'Dr', value: debit, color: AppTheme.danger),
              _AmountBadge(label: 'Cr', value: credit, color: AppTheme.success),
              _AmountBadge(label: 'Bal', value: balance, color: AppTheme.navy, prominent: true),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [left, const SizedBox(height: 12), amountRow],
            );
          }
          return Row(
            children: [
              Expanded(child: left),
              const SizedBox(width: 14),
              SizedBox(width: 300, child: amountRow),
            ],
          );
        },
      ),
    );
  }
}

class _AmountBadge extends StatelessWidget {
  const _AmountBadge({
    required this.label,
    required this.value,
    required this.color,
    this.prominent = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 84),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(prominent ? .08 : .06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(prominent ? .18 : .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(.72),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: prominent ? 13.5 : 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class PartyPager extends StatelessWidget {
  const PartyPager({
    super.key,
    required this.page,
    required this.lastPage,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int lastPage;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(
            'Total $total  •  Page $page of $lastPage',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: page > 1 ? onPrev : null,
                icon: const Icon(Icons.chevron_left_rounded),
                label: const Text('Previous'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: page < lastPage ? onNext : null,
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PartyEmptyState extends StatelessWidget {
  const PartyEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return PartySectionCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: AppTheme.surfaceSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: AppTheme.textMuted, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.navy,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PartyErrorView extends StatelessWidget {
  const PartyErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: PartySectionCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 58,
                width: 58,
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(.08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.error_outline_rounded, size: 30, color: AppTheme.danger),
              ),
              const SizedBox(height: 12),
              const Text(
                'Unable to load details',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
