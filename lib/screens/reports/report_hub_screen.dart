import 'package:enterprise_pos/screens/cashbook/expense_create_screen.dart';
import 'package:enterprise_pos/screens/reports/enterprise_reports_workspace_screen.dart';
import 'package:enterprise_pos/screens/reports/party_balances_screen.dart';
import 'package:enterprise_pos/screens/reports/report_cashbook_screen.dart';
import 'package:enterprise_pos/screens/reports/report_daily_summary_screen.dart';
import 'package:enterprise_pos/screens/reports/report_ledger_screen.dart';
import 'package:enterprise_pos/screens/reports/report_pnl_screen.dart';
import 'package:enterprise_pos/screens/reports/report_stock_movement_screen.dart';
import 'package:enterprise_pos/screens/reports/report_top_bottom_products_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';

class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1200 ? 4 : width >= 900 ? 3 : width >= 620 ? 2 : 1;

    return Scaffold(
      appBar: AppBar(title: const Text('Reports Command Center'), centerTitle: false, actions: const [Padding(padding: EdgeInsets.only(right: 8), child: BranchIndicator(tappable: false))]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _HeroHeader(
            onOpenAll: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EnterpriseReportsWorkspaceScreen())),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: cols == 1 ? 2.7 : 1.28,
            children: [
              _CommandCard(
                icon: Icons.people_alt_rounded,
                title: 'Customer Balances',
                subtitle: 'All receivables, tap customer for ledger, receive payment, create sale, edit customer.',
                accent: Colors.orange,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PartyBalancesScreen(partyType: 'customer'))),
              ),
              _CommandCard(
                icon: Icons.groups_2_rounded,
                title: 'Vendor Balances',
                subtitle: 'All payables, tap vendor for ledger, pay vendor, create purchase, edit vendor.',
                accent: Colors.indigo,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PartyBalancesScreen(partyType: 'vendor'))),
              ),
              _CommandCard(
                icon: Icons.receipt_long_rounded,
                title: 'Create Expense',
                subtitle: 'Record expense with backend customer/vendor counterparty, payment method, account, date and reference.',
                accent: Colors.red,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseCreateScreen())),
              ),
              _CommandCard(
                icon: Icons.dashboard_customize_rounded,
                title: 'All Enterprise Reports',
                subtitle: 'Sales, purchases, inventory, accounting, tax, returns, cashbook, P&L, trial balance.',
                accent: Colors.purple,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EnterpriseReportsWorkspaceScreen())),
              ),
              _CommandCard(
                icon: Icons.point_of_sale_rounded,
                title: 'Sales Performance',
                subtitle: 'Open the new report workspace directly on sales summary.',
                accent: Colors.green,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EnterpriseReportsWorkspaceScreen(initialReportKey: 'sales-summary'))),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionTitle(title: 'Enterprise report shortcuts', caption: 'One tap access to full backend reports with date-time filters and exports'),
          const SizedBox(height: 10),
          _ShortcutWrap(items: _enterpriseShortcuts),
          const SizedBox(height: 22),
          _SectionTitle(title: 'Existing focused views', caption: 'Kept for safety; these screens still work as before'),
          const SizedBox(height: 10),
          _ShortcutWrap(items: _legacyShortcuts),
        ],
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final VoidCallback onOpenAll;

  const _HeroHeader({required this.onOpenAll});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.analytics_rounded, color: AppTheme.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reports', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                const Text('Balances, ledgers, PDF and Excel exports in one place.', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onOpenAll,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open All'),
          ),
        ],
      ),
    );
  }
}

class _CommandCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _CommandCard({required this.icon, required this.title, required this.subtitle, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(color: accent.withOpacity(.10), borderRadius: BorderRadius.circular(13)),
                    child: Icon(icon, color: accent),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                ],
              ),
              const SizedBox(height: 12),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Expanded(child: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w500, fontSize: 12))),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String caption;

  const _SectionTitle({required this.title, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 22, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(caption, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShortcutWrap extends StatelessWidget {
  final List<_ReportShortcut> items;

  const _ShortcutWrap({required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((item) => ActionChip(
            avatar: Icon(item.icon, size: 18),
            label: Text(item.title),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => item.builder(context))),
          )).toList(),
    );
  }
}

class _ReportShortcut {
  final String title;
  final IconData icon;
  final Widget Function(BuildContext) builder;

  const _ReportShortcut({required this.title, required this.icon, required this.builder});
}

final _enterpriseShortcuts = <_ReportShortcut>[
  _ReportShortcut(title: 'Sales Summary', icon: Icons.summarize_rounded, builder: (_) => const EnterpriseReportsWorkspaceScreen(initialReportKey: 'sales-summary')),
  _ReportShortcut(title: 'Sales Detail', icon: Icons.receipt_long_rounded, builder: (_) => const EnterpriseReportsWorkspaceScreen(initialReportKey: 'sales-detail')),
  _ReportShortcut(title: 'Sales by Product', icon: Icons.inventory_2_rounded, builder: (_) => const EnterpriseReportsWorkspaceScreen(initialReportKey: 'sales-by-product')),
  _ReportShortcut(title: 'Purchases', icon: Icons.shopping_cart_checkout_rounded, builder: (_) => const EnterpriseReportsWorkspaceScreen(initialReportKey: 'purchase-summary')),
  _ReportShortcut(title: 'Current Stock', icon: Icons.warehouse_rounded, builder: (_) => const EnterpriseReportsWorkspaceScreen(initialReportKey: 'current-stock')),
  _ReportShortcut(title: 'Stock Valuation', icon: Icons.price_check_rounded, builder: (_) => const EnterpriseReportsWorkspaceScreen(initialReportKey: 'stock-valuation')),
  _ReportShortcut(title: 'Cashbook', icon: Icons.account_balance_wallet_rounded, builder: (_) => const EnterpriseReportsWorkspaceScreen(initialReportKey: 'cashbook')),
  _ReportShortcut(title: 'P&L', icon: Icons.trending_up_rounded, builder: (_) => const EnterpriseReportsWorkspaceScreen(initialReportKey: 'profit-loss')),
  _ReportShortcut(title: 'Trial Balance', icon: Icons.balance_rounded, builder: (_) => const EnterpriseReportsWorkspaceScreen(initialReportKey: 'trial-balance')),
];

final _legacyShortcuts = <_ReportShortcut>[
  _ReportShortcut(title: 'Old Daily Summary', icon: Icons.today_rounded, builder: (_) => const ReportDailySummaryScreen()),
  _ReportShortcut(title: 'Top/Bottom Products', icon: Icons.bar_chart_rounded, builder: (_) => const ReportTopBottomProductsScreen()),
  _ReportShortcut(title: 'Customer Ledger', icon: Icons.person_search_rounded, builder: (_) => const ReportLedgerScreen(partyType: 'customer')),
  _ReportShortcut(title: 'Vendor Ledger', icon: Icons.group_work_rounded, builder: (_) => const ReportLedgerScreen(partyType: 'vendor')),
  _ReportShortcut(title: 'Old Cashbook', icon: Icons.receipt_long_rounded, builder: (_) => const ReportCashbookScreen()),
  _ReportShortcut(title: 'Old P&L', icon: Icons.query_stats_rounded, builder: (_) => const ReportPnLScreen()),
  _ReportShortcut(title: 'Old Stock Movement', icon: Icons.swap_vert_circle_rounded, builder: (_) => const ReportStockMovementScreen()),
];
