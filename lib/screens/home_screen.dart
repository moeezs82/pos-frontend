import 'package:enterprise_pos/screens/account_screen.dart';
import 'package:enterprise_pos/config/backend_config.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/providers/subscription_provider.dart';
import 'package:enterprise_pos/screens/branches/branch_control_screen.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_create_screen.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_screen.dart';
import 'package:enterprise_pos/screens/customers/customers_screen.dart';
import 'package:enterprise_pos/screens/dashboard/today_snapshot_section.dart';
import 'package:enterprise_pos/screens/product_screen.dart';
import 'package:enterprise_pos/screens/units_screen.dart';
import 'package:enterprise_pos/screens/purchases/purchase_claim_screen.dart';
import 'package:enterprise_pos/screens/purchases/purchase_create.dart';
import 'package:enterprise_pos/screens/purchases/purchases_screen.dart';
import 'package:enterprise_pos/screens/payments/party_payments_screen.dart';
import 'package:enterprise_pos/screens/reports/report_hub_screen.dart';
import 'package:enterprise_pos/screens/reports/credit_control_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_create.dart';
// Sale Return screens are intentionally retained in the project, but their
// home navigation entry is disabled because returns are handled as -ve sales.
// import 'package:enterprise_pos/screens/sales/sale_returns_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_screen.dart';
import 'package:enterprise_pos/screens/settings/printer_settings_screen.dart';
import 'package:enterprise_pos/screens/settings/backup_restore_screen.dart';
import 'package:enterprise_pos/screens/stock_screen.dart';
import 'package:enterprise_pos/screens/subscription/branch_lock_screen.dart';
import 'package:enterprise_pos/screens/subscription/subscription_management_screen.dart';
import 'package:enterprise_pos/screens/sync/offline_sync_screen.dart';
import 'package:enterprise_pos/screens/users_screen.dart';
import 'package:enterprise_pos/screens/vendors/vendors_screen.dart';
import 'package:enterprise_pos/providers/offline_queue_provider.dart';
import 'package:enterprise_pos/providers/register_shift_provider.dart';
import 'package:enterprise_pos/screens/register_shifts/register_shift_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/app_keyboard_shortcuts.dart';
import 'package:enterprise_pos/widgets/subscription_warning_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final branch = context.watch<BranchProvider>();
    final sub = context.watch<SubscriptionProvider>();
    final offlineQueue = context.watch<OfflineQueueProvider>();
    final registerShift = context.watch<RegisterShiftProvider>();
    final masterNeedsBranch = auth.isMasterAdmin && !branch.hasActiveBranch;

    // ── Branch lock gate ─────────────────────────────────────────────────────
    // When the current branch's subscription is expired or suspended, replace
    // the entire home UI with the lock screen.  This is a widget swap inside
    // the same authenticated scaffold — the Navigator stack, queued offline
    // sales, and the Sanctum token are all preserved so the user can log out
    // or switch to another active branch without data loss.
    if (sub.isLocked && branch.hasActiveBranch) {
      return const BranchLockScreen();
    }
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1280
        ? 4
        : width >= 900
            ? 3
            : width >= 620
                ? 2
                : 1;

    final userName = (auth.user?['name'] ?? 'User').toString();
    final role = auth.roleLabel;

    _Tile branchControlTile() => _Tile(
          icon: Icons.account_tree_rounded,
          title: 'Branch Control',
          shortcut: 'Ctrl+Shift+B',
          subtitle: branch.hasActiveBranch ? 'Switch active branch' : 'Select working branch',
          color: AppTheme.navy,
          emphasized: true,
          onTap: () => PosNavigation.openSingleton(
              routeId: PosRouteIds.branchControl,
              builder: (_) => const BranchControlScreen()),
        );

    final quickActions = <_Tile>[
      if (auth.isMasterAdmin) branchControlTile(),
      if (auth.hasPermission('manage-printer-settings'))
        _Tile(
          icon: Icons.print_rounded,
          title: 'Printer Settings',
          subtitle: 'Configure and test the receipt printer',
          color: AppTheme.navy,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())),
        ),
      if (auth.isMasterAdmin)
        _Tile(
          icon: Icons.workspace_premium_rounded,
          title: 'Branch Subscriptions',
          subtitle: 'Manage subscription status for all branches',
          color: AppTheme.purple,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionManagementScreen())),
        ),
      // Units of measure. Gated on view-units, not on Master Admin: a branch
      // manager who maintains the catalogue needs this, and the backend
      // enforces manage-units on the write endpoints anyway.
      if (auth.hasPermission('view-units'))
        _Tile(
          icon: Icons.straighten_rounded,
          title: 'Units',
          subtitle: 'Manage units and decimal quantity rules',
          color: AppTheme.navy,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UnitsScreen(token: auth.token!),
            ),
          ),
        ),
      if (auth.hasAnyPermission(const [
        'view-register-shifts',
        'open-register-shift',
        'close-own-register-shift',
        'manage-register-shifts',
      ])) _Tile(
        icon: Icons.point_of_sale_rounded,
        title: registerShift.hasActiveShift ? 'Active Shift' : 'Open Shift',
        shortcut: 'F6',
        subtitle: registerShift.hasActiveShift ? 'Shift #${registerShift.id} • Manage drawer' : 'Start register before sales',
        color: registerShift.hasActiveShift ? AppTheme.success : AppTheme.warning,
        emphasized: true,
        onTap: () => PosNavigation.openSingleton(
            routeId: PosRouteIds.registerShift,
            builder: (_) => const RegisterShiftScreen()),
      ),
      if (auth.hasPermission('create-sales')) _Tile(
        icon: Icons.point_of_sale_rounded,
        title: 'Create Sale',
        shortcut: 'Ctrl+N / F2',
        subtitle: 'Fast checkout',
        color: AppTheme.primary,
        emphasized: true,
        onTap: () {
          if (!registerShift.hasActiveShift) {
            PosNavigation.openSingleton(
                routeId: PosRouteIds.registerShift,
                builder: (_) => const RegisterShiftScreen());
            return;
          }
          PosNavigation.openSingleton(
              routeId: PosRouteIds.createSale,
              builder: (_) => const CreateSaleScreen());
        },
      ),
      if (auth.hasPermission('manage-cashbook')) _Tile(
        icon: Icons.receipt_long_rounded,
        title: 'Add Expense',
        shortcut: 'Ctrl+E',
        subtitle: 'Cash/account expense',
        color: AppTheme.danger,
        emphasized: true,
        onTap: () => PosNavigation.openSingleton(
            routeId: PosRouteIds.cashLedgerCreate,
            builder: (_) => const CashLedgerCreateScreen(initialCategory: 'OTHER_EXPENSE')),
      ),
      if (auth.hasAnyPermission(const ['manage-receipts', 'manage-payments'])) _Tile(
        icon: Icons.account_balance_wallet_rounded,
        title: 'Party Payments',
        shortcut: 'Ctrl+M',
        subtitle: 'Customer/vendor payments',
        color: AppTheme.success,
        emphasized: true,
        onTap: () => PosNavigation.openSingleton(
            routeId: PosRouteIds.partyPayments,
            builder: (_) => const PartyPaymentsScreen()),
      ),
      if (auth.hasPermission('manage-purchases')) _Tile(
        icon: Icons.shopping_cart_checkout_rounded,
        title: 'New Purchase',
        shortcut: 'Ctrl+O',
        subtitle: 'Supplier invoice',
        color: AppTheme.warning,
        emphasized: true,
        onTap: () => PosNavigation.openSingleton(
            routeId: PosRouteIds.createPurchase,
            builder: (_) => const CreatePurchaseScreen()),
      ),
      if (auth.hasPermission('view-reports')) _Tile(
        icon: Icons.analytics_rounded,
        title: 'Reports',
        shortcut: 'Ctrl+R',
        subtitle: 'Balances & exports',
        color: AppTheme.purple,
        emphasized: true,
        onTap: () => PosNavigation.openSingleton(
            routeId: PosRouteIds.reports,
            builder: (_) => const ReportsHubScreen()),
      ),
    ];

    final management = <_Tile>[
      if (auth.hasPermission('view-sales')) _Tile(icon: Icons.shopping_bag_rounded, title: 'Sales', shortcut: 'Ctrl+L', subtitle: 'Invoices and payments', color: AppTheme.info, onTap: () => PosNavigation.openSingleton(routeId: PosRouteIds.sales, builder: (_) => const SalesScreen())),
      if (auth.hasPermission('view-cashbook')) _Tile(icon: Icons.account_balance_wallet_rounded, title: 'Cash Ledger', shortcut: 'Ctrl+B', subtitle: 'All cash in/out, plus daily Day Book', color: AppTheme.primary, onTap: () => PosNavigation.openSingleton(routeId: PosRouteIds.cashLedger, builder: (_) => const CashLedgerScreen())),
      if (auth.hasPermission('view-products')) _Tile(icon: Icons.inventory_2_rounded, title: 'Products', shortcut: 'Ctrl+P', subtitle: 'Catalog and prices', color: AppTheme.success, onTap: () => PosNavigation.openSingleton(routeId: PosRouteIds.products, builder: (_) => const ProductsScreen())),
      if (auth.hasPermission('view-stock')) _Tile(icon: Icons.warehouse_rounded, title: 'Stock', shortcut: 'Ctrl+I', subtitle: 'Inventory on hand', color: AppTheme.danger, onTap: () => PosNavigation.openSingleton(routeId: PosRouteIds.stock, builder: (_) => const StockScreen())),
      if (auth.hasPermission('view-customers')) _Tile(icon: Icons.people_alt_rounded, title: 'Customers', shortcut: 'Ctrl+Shift+C', subtitle: 'Receivables and profiles', color: AppTheme.warning, onTap: () => PosNavigation.openSingleton(routeId: PosRouteIds.customers, builder: (_) => const CustomersScreen())),
      if (auth.hasPermission('view-vendors')) _Tile(icon: Icons.groups_2_rounded, title: 'Vendors', shortcut: 'Ctrl+Shift+V', subtitle: 'Suppliers and payables', color: AppTheme.purple, onTap: () => PosNavigation.openSingleton(routeId: PosRouteIds.vendors, builder: (_) => const VendorsScreen())),
      if (auth.hasPermission('view-party-credit-limit-audits')) _Tile(icon: Icons.policy_rounded, title: 'Credit Control', subtitle: 'Exposure, overrides and blocked attempts', color: AppTheme.warning, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreditControlScreen()))),
      // Sale Returns intentionally hidden: returns are now entered as -ve sales.
      // _Tile(icon: Icons.assignment_return_rounded, title: 'Sale Returns', shortcut: 'Ctrl+T', subtitle: 'Refund workflow', color: AppTheme.info, onTap: () => PosNavigation.openSingleton(routeId: PosRouteIds.saleReturns, builder: (_) => const SaleReturnsScreen())),
      if (auth.hasPermission('view-purchases')) _Tile(icon: Icons.shopping_cart_rounded, title: 'Purchases', shortcut: 'Ctrl+Shift+O', subtitle: 'Bills and payments', color: AppTheme.primaryDark, onTap: () => PosNavigation.openSingleton(routeId: PosRouteIds.purchases, builder: (_) => const PurchasesScreen())),
      if (auth.hasPermission('manage-purchases')) _Tile(icon: Icons.assignment_return_outlined, title: 'Purchase Claim', subtitle: 'Damage/shortage claims', color: AppTheme.warning, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseClaimsScreen()))),
      if (auth.hasPermission('view-users')) _Tile(icon: Icons.manage_accounts_rounded, title: 'Users', shortcut: 'Ctrl+U', subtitle: 'Staff and role access', color: AppTheme.info, onTap: () => PosNavigation.openSingleton(routeId: PosRouteIds.users, builder: (_) => const UsersScreen())),
      if (BackendConfig.isLocal && auth.hasAnyPermission(const ['create-backups', 'restore-backups']))
        _Tile(
          icon: Icons.backup_rounded,
          title: 'Backup & Restore',
          subtitle: 'Protect and recover complete local business data',
          color: AppTheme.navy,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BackupRestoreScreen()),
          ),
        ),
      // Chart of Accounts is Master-Admin only (backend enforces; this hides the
      // affordance so ordinary users never see or reach it).
      if (auth.isMasterAdmin)
        _Tile(icon: Icons.account_tree_rounded, title: 'Accounts', subtitle: 'Chart of accounts', color: AppTheme.navy, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountsScreen()))),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('CounterIQ POS'),
        actions: [
          IconButton(
            tooltip: 'Keyboard shortcuts (Ctrl + /)',
            onPressed: () => showAppShortcutGuide(context),
            icon: const Icon(Icons.keyboard_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _OfflineSyncBadge(
              pendingCount: offlineQueue.pendingCount,
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const OfflineSyncScreen()));
                if (context.mounted) context.read<OfflineQueueProvider>().refresh();
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: BranchIndicator(tappable: false),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () async {
                await auth.logout();
                if (!context.mounted) return;
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Logout'),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Non-blocking expiry warning — appears as a slim coloured strip
          // when the subscription is within the alert window but not yet
          // locked.  It is placed outside the scrollable list so it stays
          // visible even when the user scrolls down the tile grid.
          const SubscriptionWarningBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
              children: [
                _WelcomeHeader(userName: userName, role: role),
                const SizedBox(height: 18),
                if (masterNeedsBranch) ...[
                  _MasterBranchRequiredCard(
                    onOpenBranchControl: () => PosNavigation.openSingleton(routeId: PosRouteIds.branchControl, builder: (_) => const BranchControlScreen()),
                  ),
                ] else ...[
                  const _ShortcutHintBar(),
                  const SizedBox(height: 16),
                  const TodaySnapshotSection(),
                  const SizedBox(height: 20),
                  const _SectionTitle(title: 'Quick actions', subtitle: 'Most-used tasks are one tap away'),
                  const SizedBox(height: 10),
                  _TileGrid(tiles: quickActions, columns: cols),
                  const SizedBox(height: 20),
                  const _SectionTitle(title: 'Manage business', subtitle: 'Sales, stock, parties, accounts and claims'),
                  const SizedBox(height: 10),
                  _TileGrid(tiles: management, columns: cols),
                ],
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'Powered by A Developers',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// AppBar entry point into the offline-sales sync queue (handover doc
/// §2.4). Shows nothing extra when the queue is empty; a numbered pill once
/// there are sales waiting to sync.
class _OfflineSyncBadge extends StatelessWidget {
  final int pendingCount;
  final VoidCallback onTap;

  const _OfflineSyncBadge({required this.pendingCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasPending = pendingCount > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              hasPending ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
              color: hasPending ? AppTheme.warning : AppTheme.textMuted,
            ),
            if (hasPending)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: AppTheme.danger, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    pendingCount > 99 ? '99+' : '$pendingCount',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  final String userName;
  final String role;

  const _WelcomeHeader({required this.userName, required this.role});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final branch = context.watch<BranchProvider>();
    final canCreateSale = !auth.isMasterAdmin || branch.hasActiveBranch;

    void openSaleOrWarn() {
      if (!canCreateSale) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a working branch from Branch Control first.')),
        );
        return;
      }
      PosNavigation.openSingleton(
          routeId: PosRouteIds.createSale,
          builder: (_) => const CreateSaleScreen());
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppTheme.primarySoft,
            foregroundColor: AppTheme.primary,
            child: Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome, $userName', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(role, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: openSaleOrWarn,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Sale'),
          ),
        ],
      ),
    );
  }
}


class _MasterBranchRequiredCard extends StatelessWidget {
  final VoidCallback onOpenBranchControl;

  const _MasterBranchRequiredCard({required this.onOpenBranchControl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.warning.withOpacity(.35)),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select a working branch first', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppTheme.navy)),
                SizedBox(height: 4),
                Text(
                  'Master admin data is loaded branch-wise. Choose a branch from Branch Control before opening sales, purchases, stock, payments or reports.',
                  style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onOpenBranchControl,
            icon: const Icon(Icons.account_tree_rounded),
            label: const Text('Open Branch Control'),
          ),
        ],
      ),
    );
  }
}


class _ShortcutHintBar extends StatelessWidget {
  const _ShortcutHintBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.navy,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.keyboard_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Keyboard-first POS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                SizedBox(height: 2),
                Text('Press Ctrl + / anytime to view shortcuts. Use Ctrl + N or F2 for a new sale.', style: TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w700, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withOpacity(.35)),
            ),
            onPressed: () => showAppShortcutGuide(context),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('View'),
          ),
        ],
      ),
    );
  }
}

class _ShortcutBadge extends StatelessWidget {
  final String text;

  const _ShortcutBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600, fontSize: 12.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TileGrid extends StatelessWidget {
  final List<_Tile> tiles;
  final int columns;
  const _TileGrid({required this.tiles, required this.columns});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: width >= 620 ? 2.6 : 3.2,
      ),
      itemCount: tiles.length,
      itemBuilder: (_, i) => _DashboardCard(tile: tiles[i]),
    );
  }
}

class _Tile {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? shortcut;
  final Color color;
  final VoidCallback onTap;
  final bool emphasized;

  _Tile({required this.icon, required this.title, required this.subtitle, this.shortcut, required this.color, required this.onTap, this.emphasized = false});
}

class _DashboardCard extends StatelessWidget {
  final _Tile tile;
  const _DashboardCard({required this.tile});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: tile.onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tile.emphasized ? tile.color.withOpacity(.32) : AppTheme.border),
            boxShadow: tile.emphasized ? AppTheme.softShadow : null,
          ),
          child: Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(color: tile.color.withOpacity(.10), borderRadius: BorderRadius.circular(15)),
                child: Icon(tile.icon, color: tile.color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(tile.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w900, fontSize: 15)),
                        ),
                        if (tile.shortcut != null) ...[
                          const SizedBox(width: 8),
                          _ShortcutBadge(text: tile.shortcut!),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(tile.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
