import 'package:enterprise_pos/screens/cashbook/widgets/cashbook_daily_summary_screen.dart';
import 'package:enterprise_pos/screens/reports/report_cashbook_screen.dart';
import 'package:enterprise_pos/screens/reports/report_daily_summary_screen.dart';
import 'package:enterprise_pos/screens/reports/report_ledger_screen.dart';
import 'package:enterprise_pos/screens/reports/report_pnl_screen.dart';
import 'package:enterprise_pos/screens/reports/report_stock_movement_screen.dart';
import 'package:enterprise_pos/screens/reports/report_top_bottom_products_screen.dart';
import 'package:flutter/material.dart';

class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = _reportGroups;

    return Scaffold(
      appBar: AppBar(title: const Text('Reports'), centerTitle: false),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: groups.length,
        itemBuilder: (_, gi) {
          final g = groups[gi];
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _GroupBlock(group: g),
          );
        },
      ),
    );
  }
}

/* ----------------------------- Group Section ----------------------------- */

class _GroupBlock extends StatelessWidget {
  final _ReportGroup group;
  const _GroupBlock({required this.group});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    int cols = 1;
    if (w >= 1200)
      cols = 4;
    else if (w >= 920)
      cols = 3;
    else if (w >= 640)
      cols = 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GroupHeader(title: group.title, caption: group.caption),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: group.items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.32,
          ),
          itemBuilder: (_, i) => _ReportCard(item: group.items[i]),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  final String caption;
  const _GroupHeader({required this.title, required this.caption});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

/* --------------------------------- Cards -------------------------------- */

class _ReportCard extends StatefulWidget {
  final _ReportItem item;
  const _ReportCard({required this.item});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

typedef ScreenBuilder = Widget Function(BuildContext);

final Map<String, ScreenBuilder> _reportRouteBuilders = {
  'sales_day_summary': (_) => const ReportDailySummaryScreen(),
  'top_bottom_products': (_) => const ReportTopBottomProductsScreen(),
  // 'sales_by_category':           (_) => const SalesByCategoryScreen(),
  // 'hourly_heatmap':              (_) => const HourlyHeatmapScreen(),
  'customer_ledger': (_) => const ReportLedgerScreen(partyType: "customer"),
  'vendor_ap': (_) => const ReportLedgerScreen(partyType: 'vendor'),
  'cashbook_daily': (_) => const ReportCashbookScreen(),
  'profit_loss': (_) => const ReportPnLScreen(),
  // 'tax_summary':                 (_) => const TaxSummaryScreen(),
  'stock_movement': (_) => const ReportStockMovementScreen(),
  // 'gross_margin':                (_) => const GrossMarginScreen(),
  // 'returns_analytics':           (_) => const ReturnsAnalyticsScreen(),
};

class _ReportCardState extends State<_ReportCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 0.06,
    );
    _scale = Tween<double>(
      begin: 1,
      end: 0.94,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.surface;
    final borderColor = scheme.outlineVariant;

    return GestureDetector(
      onTapDown: (_) => _c.forward(),
      onTapCancel: () => _c.reverse(),
      onTapUp: (_) => _c.reverse(),
      onTap: () {
        final builder = _reportRouteBuilders[widget.item.key];
        if (builder != null) {
          Navigator.of(context).push(MaterialPageRoute(builder: builder));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No route for ${widget.item.title}')),
          );
        }
      },
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
            boxShadow: [
              // soft, professional shadow
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Accent strip
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    height: 4,
                    color: widget.item.accent ?? scheme.primary,
                  ),
                ),
              ),

              // Watermark icon (very subtle)
              Positioned(
                right: -6,
                bottom: -2,
                child: Icon(
                  widget.item.icon,
                  size: 92,
                  color: scheme.onSurface.withOpacity(0.04),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IconPill(
                      icon: widget.item.icon,
                      tint: widget.item.accent ?? scheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((widget.item.subtitle ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.item.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        if (widget.item.meta != null)
                          _MetaRow(meta: widget.item.meta!),
                        const Spacer(),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconPill extends StatelessWidget {
  final IconData icon;
  final Color tint;
  const _IconPill({required this.icon, required this.tint});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tint.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: 8),
          Text(
            'Report',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final Map<String, String> meta;
  const _MetaRow({required this.meta});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = meta.entries.toList(growable: false);
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: entries
          .map(
            (e) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e.key,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Text(e.value, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          )
          .toList(),
    );
  }
}

/* --------------------------------- Data --------------------------------- */

class _ReportGroup {
  final String title;
  final String caption;
  final List<_ReportItem> items;
  _ReportGroup({
    required this.title,
    required this.caption,
    required this.items,
  });
}

class _ReportItem {
  final String key;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Map<String, String>? meta;
  final Color? accent;
  _ReportItem({
    required this.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.meta,
    this.accent,
  });
}

final _reportGroups = <_ReportGroup>[
  _ReportGroup(
    title: 'Sales',
    caption: 'Daily health & performance',
    items: [
      _ReportItem(
        key: 'sales_day_summary',
        title: 'Sales Day Summary',
        subtitle: 'Totals, tenders, refunds',
        icon: Icons.today_rounded,
        meta: const {'Period': 'Today'},
        accent: const Color(0xFF09142B), // brand accent
      ),
      _ReportItem(
        key: 'top_bottom_products',
        title: 'Top/Bottom Products',
        subtitle: 'Best & worst performers',
        icon: Icons.bar_chart_rounded,
        meta: const {'Sort': 'Revenue'},
      ),
      // _ReportItem(
      //   key: 'sales_by_category',
      //   title: 'Sales by Category',
      //   subtitle: 'Contribution & mix',
      //   icon: Icons.category_rounded,
      //   meta: const {'View': 'GM%'},
      // ),
      // _ReportItem(
      //   key: 'hourly_heatmap',
      //   title: 'Hourly Heatmap',
      //   subtitle: 'Traffic vs sales by hour',
      //   icon: Icons.schedule_rounded,
      //   meta: const {'TZ': 'Branch'},
      // ),
    ],
  ),
  _ReportGroup(
    title: 'Finance',
    caption: 'Receivables, payables & cash',
    items: [
      _ReportItem(
        key: 'customer_ledger',
        title: 'Customer Ledger',
        subtitle: 'AR balance & activity',
        icon: Icons.account_balance_wallet_rounded,
        meta: const {'Aging': 'Yes'},
      ),
      _ReportItem(
        key: 'vendor_ap',
        title: 'Vendor A/P',
        subtitle: 'Payables & aging',
        icon: Icons.inventory_2_rounded,
        meta: const {'Due': 'This week'},
      ),
      _ReportItem(
        key: 'cashbook_daily',
        title: 'CashBook Daily',
        subtitle: 'Opening, receipts, payments',
        icon: Icons.receipt_long_rounded,
        meta: const {'Status': 'Balanced'},
      ),
      _ReportItem(
        key: 'profit_loss',
        title: 'Profit & Loss',
        subtitle: 'Income, Expense & Net Profit',
        icon: Icons.receipt_long_rounded,
        meta: const {'Period': 'MTD'},
      ),
      // _ReportItem(
      //   key: 'tax_summary',
      //   title: 'Tax Summary',
      //   subtitle: 'Collected & payable',
      //   icon: Icons.account_balance_rounded,
      //   meta: const {'VAT': 'Enabled'},
      // ),
    ],
  ),
  _ReportGroup(
    title: 'Inventory',
    caption: 'Movement & profitability',
    items: [
      _ReportItem(
        key: 'stock_movement',
        title: 'Stock Movement',
        subtitle: 'In/Out, adjustments',
        icon: Icons.swap_vert_circle_rounded,
        meta: const {'Basis': 'Avg Cost'},
      ),
      // _ReportItem(
      //   key: 'gross_margin',
      //   title: 'Gross Margin',
      //   subtitle: 'GM% by product/category',
      //   icon: Icons.pie_chart_rounded,
      //   meta: const {'Period': 'MTD'},
      // ),
      _ReportItem(
        key: 'returns_analytics',
        title: 'Returns Analytics',
        subtitle: 'Rate, reasons, impact',
        icon: Icons.undo_rounded,
        meta: const {'Trend': '3 mo'},
      ),
    ],
  ),
];

/* --------------------------- Quick theming tip --------------------------- */
/*
In your MaterialApp theme, set:
colorScheme: ColorScheme.fromSeed(
  seedColor: const Color(0xFF09142B),
  brightness: Brightness.light, // or dark
),
This screen will automatically pick subtle, professional colors.
*/
