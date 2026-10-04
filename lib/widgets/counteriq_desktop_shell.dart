import 'package:enterprise_pos/config/backend_config.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/providers/offline_queue_provider.dart';
import 'package:enterprise_pos/providers/register_shift_provider.dart';
import 'package:enterprise_pos/providers/subscription_provider.dart';
import 'package:enterprise_pos/screens/account_screen.dart';
import 'package:enterprise_pos/screens/branches/branch_control_screen.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_screen.dart';
import 'package:enterprise_pos/screens/cashbook/cashbook_screen.dart';
import 'package:enterprise_pos/screens/dashboard/low_stock_screen.dart';
import 'package:enterprise_pos/screens/customers/customers_screen.dart';
import 'package:enterprise_pos/screens/intelligence/intelligence_hub_screen.dart';
import 'package:enterprise_pos/screens/payments/party_payments_screen.dart';
import 'package:enterprise_pos/screens/product_groups_screen.dart';
import 'package:enterprise_pos/screens/purchases/purchase_claim_screen.dart';
import 'package:enterprise_pos/screens/purchases/purchases_screen.dart';
import 'package:enterprise_pos/screens/register_shifts/register_shift_screen.dart';
import 'package:enterprise_pos/screens/reports/credit_control_screen.dart';
import 'package:enterprise_pos/screens/reports/enterprise_reports_workspace_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_create.dart';
import 'package:enterprise_pos/screens/sales/sale_screen.dart';
import 'package:enterprise_pos/screens/sales/picking_list_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_returns_screen.dart';
import 'package:enterprise_pos/screens/sales_orders/sales_order_form_screen.dart';
import 'package:enterprise_pos/screens/sales_orders/sales_orders_screen.dart';
import 'package:enterprise_pos/screens/settings/backup_restore_screen.dart';
import 'package:enterprise_pos/screens/settings/payment_methods_admin_screen.dart';
import 'package:enterprise_pos/screens/settings/printer_settings_screen.dart';
import 'package:enterprise_pos/screens/stock_screen.dart';
import 'package:enterprise_pos/screens/subscription/branch_lock_screen.dart';
import 'package:enterprise_pos/screens/subscription/subscription_management_screen.dart';
import 'package:enterprise_pos/screens/sync/offline_sync_screen.dart';
import 'package:enterprise_pos/screens/units_screen.dart';
import 'package:enterprise_pos/screens/users_screen.dart';
import 'package:enterprise_pos/screens/vendors/vendors_screen.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_keyboard_shortcuts.dart';
import 'package:enterprise_pos/services/batch_print_job_service.dart';
import 'package:enterprise_pos/widgets/backup_reminder_gate.dart';
import 'package:enterprise_pos/widgets/batch_print_progress_panel.dart';
import 'package:enterprise_pos/widgets/subscription_warning_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shared desktop chrome for the redesigned CounterIQ workspace.
///
/// The first shell mounted under HomeScreen owns the persistent desktop
/// chrome. If a redesigned module also wraps itself in this widget, the nested
/// shell automatically collapses to its content only. This keeps one sidebar
/// and one top bar alive while preserving each module's existing public API.
class _CounterIQDesktopShellScope extends InheritedWidget {
  const _CounterIQDesktopShellScope({required super.child});

  static bool hasShell(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CounterIQDesktopShellScope>() != null;

  @override
  bool updateShouldNotify(_CounterIQDesktopShellScope oldWidget) => false;
}

class CounterIQDesktopShell extends StatefulWidget {
  static bool isPersistentShellMounted(BuildContext context) =>
      _CounterIQDesktopShellScope.hasShell(context);

  final String activeRouteId;
  final Widget child;
  final VoidCallback onOpenProducts;

  const CounterIQDesktopShell({
    super.key,
    required this.activeRouteId,
    required this.child,
    required this.onOpenProducts,
  });

  @override
  State<CounterIQDesktopShell> createState() => _CounterIQDesktopShellState();
}

class _CounterIQDesktopShellState extends State<CounterIQDesktopShell> {
  bool _sidebarCollapsed = false;

  bool _isActive(String routeId) => widget.activeRouteId == routeId;

  @override
  Widget build(BuildContext context) {
    // A redesigned module may still wrap its content in CounterIQDesktopShell
    // for standalone compatibility. When it is mounted inside the persistent
    // Home workspace, do not build another sidebar/top bar or re-watch shell
    // providers; render only the module content.
    if (_CounterIQDesktopShellScope.hasShell(context)) {
      return widget.child;
    }

    final auth = context.watch<AuthProvider>();
    final branch = context.watch<BranchProvider>();
    final sub = context.watch<SubscriptionProvider>();
    final offline = context.watch<OfflineQueueProvider>();
    final shift = context.watch<RegisterShiftProvider>();

    if (sub.isLocked && branch.hasActiveBranch) {
      return const BranchLockScreen();
    }

    final masterNeedsBranch = auth.isMasterAdmin && !branch.hasActiveBranch;
    final userName = (auth.user?['name'] ?? 'User').toString();
    final role = auth.roleLabel;
    final navGroups = masterNeedsBranch
        ? _branchRequiredNavigation(auth)
        : _buildNavigation(auth, shift);
    final allEntries = navGroups
        .expand((group) => _flattenEntries(group.entries))
        .toList(growable: false);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final forcedCompact = constraints.maxWidth < 1080;
          final compactSidebar = forcedCompact || _sidebarCollapsed;
          final sidebarWidth = compactSidebar ? 72.0 : 220.0;

          return Row(
            children: [
              SizedBox(
                width: sidebarWidth,
                child: _DesktopSidebar(
                  groups: navGroups,
                  compact: compactSidebar,
                  userName: userName,
                  role: role,
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    _DesktopTopBar(
                      compactSidebar: compactSidebar,
                      canToggleSidebar: !forcedCompact,
                      onToggleSidebar: () => setState(
                        () => _sidebarCollapsed = !_sidebarCollapsed,
                      ),
                      branch: branch,
                      auth: auth,
                      shift: shift,
                      offlinePending: offline.pendingCount,
                      allEntries: allEntries,
                      onLogout: _logout,
                    ),
                    const SubscriptionWarningBanner(),
                    const BackupReminderGate(),
                    Expanded(
                      child: masterNeedsBranch
                          ? _BranchRequiredView(
                              onOpenBranchControl: _openBranchControl,
                            )
                          : _CounterIQDesktopShellScope(
                              child: Stack(
                                children: [
                                  widget.child,
                                  Positioned(
                                    right: 20,
                                    bottom: 20,
                                    child: ListenableBuilder(
                                      listenable: BatchPrintJobService.instance,
                                      builder: (context, _) {
                                        final job =
                                            BatchPrintJobService.instance.currentJob;
                                        if (job == null) {
                                          return const SizedBox.shrink();
                                        }
                                        return BatchPrintProgressPanel(
                                          job: job,
                                          onCancel: () => job.cancel(),
                                          onDismiss: () =>
                                              BatchPrintJobService.instance.clearJob(),
                                          onOpenFolder: BatchPrintJobService
                                                      .instance.pdfFolderPath !=
                                                  null
                                              ? (path) =>
                                                  openFolderInExplorer(path)
                                              : null,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Iterable<_NavEntry> _flattenEntries(List<_NavEntry> entries) sync* {
    for (final entry in entries) {
      if (entry.onTap != null) yield entry;
      if (entry.children.isNotEmpty) {
        yield* _flattenEntries(entry.children);
      }
    }
  }

  _NavEntry _reportLeaf({
    required String key,
    required String title,
    required IconData icon,
  }) {
    final routeId = PosRouteIds.report(key);
    return _NavEntry(
      icon: icon,
      title: title,
      active: _isActive(routeId),
      onTap: () => PosNavigation.openSingleton(
        routeId: routeId,
        builder: (_) => EnterpriseReportsWorkspaceScreen(initialReportKey: key),
      ),
    );
  }

  _NavEntry _reportSection({
    required String title,
    required IconData icon,
    required List<_NavEntry> children,
  }) {
    return _NavEntry(
      icon: icon,
      title: title,
      active: children.any((entry) => entry.active),
      children: children,
      initiallyExpanded: children.any((entry) => entry.active),
    );
  }

  _NavEntry _reportsTree() {
    final sales = <_NavEntry>[
      _reportLeaf(key: 'sales-summary', title: 'Sales Summary', icon: Icons.summarize_rounded),
      _reportLeaf(key: 'sales-detail', title: 'Sales Detail', icon: Icons.receipt_long_rounded),
      _reportLeaf(key: 'sales-by-product', title: 'Sales by Product', icon: Icons.inventory_2_outlined),
      _reportLeaf(key: 'sales-by-vendor', title: 'Sales by Vendor', icon: Icons.local_shipping_outlined),
      _reportLeaf(key: 'sales-by-category', title: 'Sales by Category', icon: Icons.category_outlined),
      _reportLeaf(key: 'sales-by-brand', title: 'Sales by Brand', icon: Icons.sell_outlined),
      _reportLeaf(key: 'sales-by-customer', title: 'Sales by Customer', icon: Icons.people_alt_outlined),
      _reportLeaf(key: 'sales-by-salesman', title: 'Sales by Cashier', icon: Icons.badge_outlined),
      _reportLeaf(key: 'sales-by-hour', title: 'Hourly Sales', icon: Icons.schedule_outlined),
      _reportLeaf(key: 'sales-by-payment-method', title: 'Payment Collection', icon: Icons.payments_outlined),
      _reportLeaf(key: 'sales-by-source', title: 'Sales by Source', icon: Icons.hub_outlined),
      _reportLeaf(key: 'sales-by-area', title: 'Sales by Town / Area', icon: Icons.location_on_outlined),
      _reportLeaf(key: 'delivery-boy-cash', title: 'Delivery Boy Cash', icon: Icons.delivery_dining_outlined),
      _reportLeaf(key: 'discount-report', title: 'Discount Report', icon: Icons.percent_rounded),
      _reportLeaf(key: 'tax-report', title: 'Tax Report', icon: Icons.account_balance_outlined),
    ];

    final purchases = <_NavEntry>[
      _reportLeaf(key: 'purchase-summary', title: 'Purchase Summary', icon: Icons.shopping_cart_checkout_outlined),
      _reportLeaf(key: 'purchase-detail', title: 'Purchase Detail', icon: Icons.article_outlined),
      _reportLeaf(key: 'purchase-by-product', title: 'Purchase by Product', icon: Icons.add_business_outlined),
      _reportLeaf(key: 'purchase-by-vendor', title: 'Purchase by Vendor', icon: Icons.groups_2_outlined),
      _reportLeaf(key: 'vendor-payment-summary', title: 'Vendor Payments', icon: Icons.outbox_outlined),
      _reportLeaf(key: 'purchase-claim-summary', title: 'Purchase Claim Summary', icon: Icons.report_problem_outlined),
      _reportLeaf(key: 'purchase-claim-detail', title: 'Purchase Claim Detail', icon: Icons.assignment_late_outlined),
    ];

    final inventory = <_NavEntry>[
      _reportLeaf(key: 'current-stock', title: 'Current Stock', icon: Icons.warehouse_outlined),
      _reportLeaf(key: 'low-stock', title: 'Low Stock / Reorder', icon: Icons.warning_amber_rounded),
      _reportLeaf(key: 'stock-valuation', title: 'Stock Valuation', icon: Icons.price_check_outlined),
      _reportLeaf(key: 'stock-movement', title: 'Stock Movement Ledger', icon: Icons.swap_vert_circle_outlined),
      _reportLeaf(key: 'inventory-adjustment', title: 'Inventory Adjustment', icon: Icons.tune_rounded),
    ];

    final finance = <_NavEntry>[
      _reportLeaf(key: 'profit-loss', title: 'Profit & Loss', icon: Icons.trending_up_rounded),
      _reportLeaf(key: 'expense-report', title: 'Expense Report', icon: Icons.receipt_long_outlined),
      _reportLeaf(key: 'trial-balance', title: 'Trial Balance', icon: Icons.balance_outlined),
      _reportLeaf(key: 'ledger-detail', title: 'Ledger Detail', icon: Icons.list_alt_outlined),
    ];

    final parties = <_NavEntry>[
      _reportLeaf(key: 'customer-receivables', title: 'Customer Receivables', icon: Icons.person_search_outlined),
      _reportLeaf(key: 'vendor-payables', title: 'Vendor Payables', icon: Icons.group_work_outlined),
      _reportLeaf(key: 'area-customer-potential', title: 'Area Customer Potential', icon: Icons.travel_explore_outlined),
    ];

    final returns = <_NavEntry>[
      _reportLeaf(key: 'sale-return-summary', title: 'Sale Return Summary', icon: Icons.assignment_return_outlined),
      _reportLeaf(key: 'sale-return-detail', title: 'Sale Return Detail', icon: Icons.undo_rounded),
    ];

    final sections = <_NavEntry>[
      _reportSection(title: 'Sales', icon: Icons.point_of_sale_outlined, children: sales),
      _reportSection(title: 'Purchases', icon: Icons.shopping_cart_outlined, children: purchases),
      _reportSection(title: 'Inventory', icon: Icons.inventory_2_outlined, children: inventory),
      _reportSection(title: 'Finance', icon: Icons.account_balance_wallet_outlined, children: finance),
      _reportSection(title: 'Parties', icon: Icons.people_outline_rounded, children: parties),
      _reportSection(title: 'Returns', icon: Icons.assignment_return_outlined, children: returns),
    ];

    return _NavEntry(
      icon: Icons.analytics_outlined,
      title: 'Reports',
      shortcut: 'Ctrl+R',
      active: PosRouteIds.isReportRoute(widget.activeRouteId),
      children: sections,
      initiallyExpanded: PosRouteIds.isReportRoute(widget.activeRouteId),
    );
  }

  List<_NavGroup> _branchRequiredNavigation(AuthProvider auth) {
    return [
      _NavGroup(
        label: '',
        entries: [
          _NavEntry(
            icon: Icons.home_rounded,
            title: 'Home',
            active: _isActive(PosRouteIds.home),
            onTap: _openHome,
          ),
        ],
      ),
      _NavGroup(
        label: 'Administration',
        entries: [
          _NavEntry(
            icon: Icons.account_tree_outlined,
            title: 'Branch Control',
            active: _isActive(PosRouteIds.branchControl),
            onTap: _openBranchControl,
          ),
          if (auth.isMasterAdmin)
            _NavEntry(
              icon: Icons.workspace_premium_outlined,
              title: 'Subscriptions',
              active: _isActive(PosRouteIds.subscriptions),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.subscriptions,
                builder: (_) => const SubscriptionManagementScreen(),
              ),
            ),
        ],
      ),
    ];
  }

  List<_NavGroup> _buildNavigation(
    AuthProvider auth,
    RegisterShiftProvider shift,
  ) {
    return [
      _NavGroup(
        label: '',
        entries: [
          _NavEntry(
            icon: Icons.home_rounded,
            title: 'Home',
            active: _isActive(PosRouteIds.home),
            onTap: _openHome,
          ),
        ],
      ),
      _NavGroup(
        label: 'Sales',
        entries: [
          if (auth.hasPermission('create-sales'))
            _NavEntry(
              icon: Icons.add_shopping_cart_rounded,
              title: 'New Sale',
              shortcut: 'F2',
              active: _isActive(PosRouteIds.createSale),
              onTap: () => _openSale(shift),
            ),
          if (auth.hasPermission('view-sales'))
            _NavEntry(
              icon: Icons.receipt_long_rounded,
              title: 'Sales History',
              active: _isActive(PosRouteIds.sales),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.sales,
                builder: (_) => const SalesScreen(),
              ),
            ),
          if (auth.hasPermission('view-sales'))
            _NavEntry(
              icon: Icons.inventory_outlined,
              title: 'Picking List',
              active: _isActive(PosRouteIds.pickingList),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.pickingList,
                builder: (_) => const PickingListScreen(),
              ),
            ),
          if (auth.hasPermission('view-sales'))
            _NavEntry(
              icon: Icons.assignment_return_outlined,
              title: 'Sale Returns',
              active: _isActive(PosRouteIds.saleReturns),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.saleReturns,
                builder: (_) => const SaleReturnsScreen(),
              ),
            ),
          if (auth.hasPermission('create-sales-orders'))
            _NavEntry(
              icon: Icons.assignment_add,
              title: 'New Sales Order',
              active: _isActive(PosRouteIds.salesOrderCreate),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.salesOrderCreate,
                builder: (_) => const SalesOrderFormScreen(),
              ),
            ),
          if (auth.hasPermission('view-sales-orders'))
            _NavEntry(
              icon: Icons.assignment_outlined,
              title: 'Sales Orders',
              active: _isActive(PosRouteIds.salesOrders),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.salesOrders,
                builder: (_) => const SalesOrdersScreen(),
              ),
            ),
          if (auth.hasAnyPermission(const [
            'view-register-shifts',
            'open-register-shift',
            'close-own-register-shift',
            'manage-register-shifts',
          ]))
            _NavEntry(
              icon: Icons.point_of_sale_rounded,
              title: shift.hasActiveShift ? 'Register Shift' : 'Open Register',
              active: _isActive(PosRouteIds.registerShift),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.registerShift,
                builder: (_) => const RegisterShiftScreen(),
              ),
            ),
        ],
      ),
      _NavGroup(
        label: 'Inventory',
        entries: [
          if (auth.hasPermission('view-products'))
            _NavEntry(
              icon: Icons.inventory_2_outlined,
              title: 'Products',
              active: _isActive(PosRouteIds.products),
              onTap: _isActive(PosRouteIds.products)
                  ? () {}
                  : widget.onOpenProducts,
            ),
          if (auth.hasPermission('view-products'))
            _NavEntry(
              icon: Icons.account_tree_outlined,
              title: 'Product Groups',
              active: _isActive(PosRouteIds.productGroups),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.productGroups,
                builder: (_) => const ProductGroupsScreen(),
              ),
            ),
          if (auth.hasPermission('view-stock'))
            _NavEntry(
              icon: Icons.warning_amber_rounded,
              title: 'Low Stock',
              active: _isActive(PosRouteIds.lowStock),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.lowStock,
                builder: (_) => const LowStockScreen(),
              ),
            ),
          if (auth.hasPermission('view-stock'))
            _NavEntry(
              icon: Icons.warehouse_outlined,
              title: 'Stock',
              active: _isActive(PosRouteIds.stock),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.stock,
                builder: (_) => const StockScreen(),
              ),
            ),
          if (auth.hasPermission('view-purchases'))
            _NavEntry(
              icon: Icons.shopping_cart_outlined,
              title: 'Purchases',
              active: _isActive(PosRouteIds.purchases),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.purchases,
                builder: (_) => const PurchasesScreen(),
              ),
            ),
          if (auth.hasPermission('manage-purchases'))
            _NavEntry(
              icon: Icons.assignment_return_outlined,
              title: 'Purchase Claims',
              active: _isActive(PosRouteIds.purchaseClaims),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.purchaseClaims,
                builder: (_) => const PurchaseClaimsScreen(),
              ),
            ),
        ],
      ),
      _NavGroup(
        label: 'Parties',
        entries: [
          if (auth.hasPermission('view-customers'))
            _NavEntry(
              icon: Icons.people_alt_outlined,
              title: 'Customers',
              active: _isActive(PosRouteIds.customers),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.customers,
                builder: (_) => const CustomersScreen(),
              ),
            ),
          if (auth.hasPermission('view-vendors'))
            _NavEntry(
              icon: Icons.groups_2_outlined,
              title: 'Vendors',
              active: _isActive(PosRouteIds.vendors),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.vendors,
                builder: (_) => const VendorsScreen(),
              ),
            ),
          if (auth.hasAnyPermission(const [
            'manage-receipts',
            'manage-payments',
          ]))
            _NavEntry(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Party Payments',
              active: _isActive(PosRouteIds.partyPayments),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.partyPayments,
                builder: (_) => const PartyPaymentsScreen(),
              ),
            ),
          if (auth.hasPermission('view-party-credit-limit-audits'))
            _NavEntry(
              icon: Icons.policy_outlined,
              title: 'Credit Control',
              active: _isActive(PosRouteIds.creditControl),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.creditControl,
                builder: (_) => const CreditControlScreen(),
              ),
            ),
        ],
      ),
      _NavGroup(
        label: 'Finance & Analysis',
        entries: [
          if (auth.hasPermission('view-cashbook'))
            _NavEntry(
              icon: Icons.receipt_long_rounded,
              title: 'Expenses',
              active: _isActive(PosRouteIds.expenses),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.expenses,
                builder: (_) => const CashBookScreen(),
              ),
            ),
          if (auth.hasPermission('view-cashbook'))
            _NavEntry(
              icon: Icons.account_balance_wallet_rounded,
              title: 'Cash Ledger',
              active: _isActive(PosRouteIds.cashLedger),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.cashLedger,
                builder: (_) => const CashLedgerScreen(),
              ),
            ),
          if (auth.hasPermission('view-reports')) _reportsTree(),
          if (auth.hasAddon('intelligence') &&
              auth.hasPermission('view-intelligence'))
            _NavEntry(
              icon: Icons.auto_awesome_rounded,
              title: 'Intelligence',
              active: _isActive(PosRouteIds.intelligence),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.intelligence,
                builder: (_) => const IntelligenceHubScreen(),
              ),
            ),
        ],
      ),
      _NavGroup(
        label: 'Administration',
        entries: [
          if (auth.hasPermission('view-users'))
            _NavEntry(
              icon: Icons.manage_accounts_outlined,
              title: 'Users',
              active: _isActive(PosRouteIds.users),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.users,
                builder: (_) => const UsersScreen(),
              ),
            ),
          if (auth.hasPermission('view-units'))
            _NavEntry(
              icon: Icons.straighten_rounded,
              title: 'Units',
              active: _isActive(PosRouteIds.units),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.units,
                builder: (_) => UnitsScreen(token: auth.token!),
              ),
            ),
          if (auth.hasPermission('manage-printer-settings'))
            _NavEntry(
              icon: Icons.print_outlined,
              title: 'Printer Settings',
              active: _isActive(PosRouteIds.printerSettings),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.printerSettings,
                builder: (_) => const PrinterSettingsScreen(),
              ),
            ),
          if (BackendConfig.isLocal &&
              auth.hasAnyPermission(const [
                'create-backups',
                'restore-backups',
              ]))
            _NavEntry(
              icon: Icons.backup_outlined,
              title: 'Backup & Restore',
              active: _isActive(PosRouteIds.backupRestore),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.backupRestore,
                builder: (_) => const BackupRestoreScreen(),
              ),
            ),
          if (auth.isMasterAdmin)
            _NavEntry(
              icon: Icons.account_tree_outlined,
              title: 'Branch Control',
              active: _isActive(PosRouteIds.branchControl),
              onTap: _openBranchControl,
            ),
          if (auth.isMasterAdmin)
            _NavEntry(
              icon: Icons.workspace_premium_outlined,
              title: 'Subscriptions',
              active: _isActive(PosRouteIds.subscriptions),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.subscriptions,
                builder: (_) => const SubscriptionManagementScreen(),
              ),
            ),
          if (auth.isMasterAdmin)
            _NavEntry(
              icon: Icons.account_balance_outlined,
              title: 'Accounts',
              active: _isActive(PosRouteIds.accounts),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.accounts,
                builder: (_) => const AccountsScreen(),
              ),
            ),
          if (auth.isMasterAdmin)
            _NavEntry(
              icon: Icons.payments_outlined,
              title: 'Payment Methods',
              active: _isActive(PosRouteIds.paymentMethods),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.paymentMethods,
                builder: (_) => const PaymentMethodsAdminScreen(),
              ),
            ),
          _NavEntry(
            icon: Icons.cloud_sync_outlined,
            title: 'Offline Sync',
            active: _isActive(PosRouteIds.offlineSync),
            onTap: () => PosNavigation.openSingleton(
              routeId: PosRouteIds.offlineSync,
              builder: (_) => const OfflineSyncScreen(),
            ),
          ),
        ],
      ),
    ].where((group) => group.entries.isNotEmpty).toList(growable: false);
  }

  void _openHome() {
    if (_isActive(PosRouteIds.home)) return;
    if (PosWorkspaceNavigation.tryOpen(PosRouteIds.home)) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openSale(RegisterShiftProvider shift) {
    if (!shift.hasActiveShift) {
      PosNavigation.openSingleton(
        routeId: PosRouteIds.registerShift,
        builder: (_) => const RegisterShiftScreen(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open a register shift before starting a sale.'),
        ),
      );
      return;
    }
    PosNavigation.openSingleton(
      routeId: PosRouteIds.createSale,
      builder: (_) => const CreateSaleScreen(),
    );
  }

  void _openBranchControl() {
    PosNavigation.openSingleton(
      routeId: PosRouteIds.branchControl,
      builder: (_) => const BranchControlScreen(),
    );
  }

  Future<void> _logout() async {
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    // Home is the first authenticated route. Home itself observes AuthProvider
    // and swaps back to LoginScreen, so clearing module routes here avoids
    // importing LoginScreen into the shared shell and keeps route ownership in
    // the existing authentication flow.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class _DesktopSidebar extends StatelessWidget {
  final List<_NavGroup> groups;
  final bool compact;
  final String userName;
  final String role;

  const _DesktopSidebar({
    required this.groups,
    required this.compact,
    required this.userName,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 62,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 13 : 14),
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: AppTheme.enterpriseGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'C',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Text(
                        'CounterIQ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.navy,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.35,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? 8 : 10,
                10,
                compact ? 8 : 10,
                12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final group in groups) ...[
                    if (!compact && group.label.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(9, 10, 8, 5),
                        child: Text(
                          group.label.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .75,
                          ),
                        ),
                      ),
                    ] else if (compact && group.label.isNotEmpty)
                      const SizedBox(height: 7),
                    for (final entry in group.entries)
                      _SidebarEntry(entry: entry, compact: compact),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(compact ? 9 : 11),
            child: compact
                ? CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.primarySoft,
                    foregroundColor: AppTheme.primary,
                    child: Text(
                      userName.isEmpty ? '?' : userName[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  )
                : Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppTheme.primarySoft,
                        foregroundColor: AppTheme.primary,
                        child: Text(
                          userName.isEmpty ? '?' : userName[0].toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.navy,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              role,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
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

class _SidebarEntry extends StatefulWidget {
  final _NavEntry entry;
  final bool compact;
  final int depth;

  const _SidebarEntry({
    super.key,
    required this.entry,
    required this.compact,
    this.depth = 0,
  });

  @override
  State<_SidebarEntry> createState() => _SidebarEntryState();
}

class _SidebarEntryState extends State<_SidebarEntry> {
  late bool _expanded;

  bool get _hasChildren => widget.entry.children.isNotEmpty;
  bool get _hasActiveDescendant =>
      widget.entry.children.any(_entryContainsActive);

  bool _entryContainsActive(_NavEntry entry) {
    if (entry.active) return true;
    return entry.children.any(_entryContainsActive);
  }

  @override
  void initState() {
    super.initState();
    _expanded = widget.entry.initiallyExpanded || _hasActiveDescendant;
  }

  @override
  void didUpdateWidget(covariant _SidebarEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasActiveDescendant && !_expanded) {
      _expanded = true;
    }
  }

  VoidCallback? _firstAction(List<_NavEntry> entries) {
    for (final entry in entries) {
      if (entry.onTap != null) return entry.onTap;
      final nested = _firstAction(entry.children);
      if (nested != null) return nested;
    }
    return null;
  }

  void _handleTap() {
    if (_hasChildren) {
      if (widget.compact) {
        _firstAction(widget.entry.children)?.call();
      } else {
        setState(() => _expanded = !_expanded);
      }
      return;
    }
    widget.entry.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final compact = widget.compact;
    final foreground =
        entry.active ? AppTheme.primary : const Color(0xFF475569);
    final background = entry.active
        ? AppTheme.primary.withOpacity(.08)
        : Colors.transparent;

    final row = Material(
      color: background,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: _handleTap,
        child: SizedBox(
          height: widget.depth == 0 ? 39 : 35,
          child: Padding(
            padding: EdgeInsets.only(
              left: compact ? 0 : 10 + (widget.depth * 12),
              right: compact ? 0 : 8,
            ),
            child: Row(
              mainAxisAlignment:
                  compact ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(
                  entry.icon,
                  color: foreground,
                  size: widget.depth == 0 ? 19 : 16.5,
                ),
                if (!compact) ...[
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: widget.depth == 0 ? 12 : 11.2,
                        fontWeight: entry.active || _hasActiveDescendant
                            ? FontWeight.w900
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                  if (entry.shortcut != null && !_hasChildren)
                    Text(
                      entry.shortcut!,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (_hasChildren)
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 17,
                      color: _hasActiveDescendant
                          ? AppTheme.primary
                          : AppTheme.textMuted,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    final wrappedRow = Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: compact ? Tooltip(message: entry.title, child: row) : row,
    );

    if (!_hasChildren || compact || !_expanded) return wrappedRow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        wrappedRow,
        for (final child in entry.children)
          _SidebarEntry(
            key: ValueKey('${widget.depth + 1}:${child.title}'),
            entry: child,
            compact: false,
            depth: widget.depth + 1,
          ),
      ],
    );
  }
}

class _DesktopTopBar extends StatelessWidget {
  final bool compactSidebar;
  final bool canToggleSidebar;
  final VoidCallback onToggleSidebar;
  final BranchProvider branch;
  final AuthProvider auth;
  final RegisterShiftProvider shift;
  final int offlinePending;
  final List<_NavEntry> allEntries;
  final VoidCallback onLogout;

  const _DesktopTopBar({
    required this.compactSidebar,
    required this.canToggleSidebar,
    required this.onToggleSidebar,
    required this.branch,
    required this.auth,
    required this.shift,
    required this.offlinePending,
    required this.allEntries,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hideSecondary = constraints.maxWidth < 850;
          return Row(
            children: [
              if (canToggleSidebar)
                IconButton(
                  tooltip: compactSidebar
                      ? 'Expand sidebar'
                      : 'Collapse sidebar',
                  onPressed: onToggleSidebar,
                  icon: Icon(
                    compactSidebar
                        ? Icons.menu_open_rounded
                        : Icons.menu_rounded,
                    size: 20,
                  ),
                ),
              if (canToggleSidebar) const SizedBox(width: 2),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 410),
                    child: _CommandSearchButton(entries: allEntries),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (!hideSecondary && auth.isMasterAdmin)
                _TopChip(
                  icon: branch.hasActiveBranch
                      ? Icons.apartment_rounded
                      : Icons.warning_amber_rounded,
                  label: branch.label,
                  onTap: () => PosNavigation.openSingleton(
                    routeId: PosRouteIds.branchControl,
                    builder: (_) => const BranchControlScreen(),
                  ),
                ),
              if (!hideSecondary &&
                  auth.hasAnyPermission(const [
                    'view-register-shifts',
                    'open-register-shift',
                    'close-own-register-shift',
                    'manage-register-shifts',
                  ])) ...[
                const SizedBox(width: 7),
                _TopChip(
                  icon: shift.hasActiveShift
                      ? Icons.check_circle_rounded
                      : Icons.point_of_sale_rounded,
                  label: shift.hasActiveShift
                      ? 'Register Open'
                      : 'No Register',
                  accent: shift.hasActiveShift
                      ? AppTheme.success
                      : AppTheme.warning,
                  onTap: () => PosNavigation.openSingleton(
                    routeId: PosRouteIds.registerShift,
                    builder: (_) => const RegisterShiftScreen(),
                  ),
                ),
              ],
              ListenableBuilder(
                listenable: BatchPrintJobService.instance,
                builder: (context, _) {
                  final job = BatchPrintJobService.instance.currentJob;
                  if (job == null || (job.isDone && job.errors.isEmpty)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: BatchPrintStatusChip(
                      job: job,
                      onTap: () => PosNavigation.openSingleton(
                        routeId: PosRouteIds.sales,
                        builder: (_) => const SalesScreen(),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 7),
              _SyncButton(pendingCount: offlinePending),
              const SizedBox(width: 5),
              PopupMenuButton<String>(
                tooltip: 'Account menu',
                position: PopupMenuPosition.under,
                onSelected: (value) {
                  if (value == 'shortcuts') showAppShortcutGuide(context);
                  if (value == 'logout') onLogout();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'shortcuts',
                    child: ListTile(
                      leading: Icon(Icons.keyboard_rounded),
                      title: Text('Keyboard shortcuts'),
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      leading: Icon(Icons.logout_rounded),
                      title: Text('Logout'),
                    ),
                  ),
                ],
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: AppTheme.primarySoft,
                        foregroundColor: AppTheme.primary,
                        child: Text(
                          ((auth.user?['name'] ?? 'U').toString().isEmpty
                                  ? 'U'
                                  : (auth.user?['name'] ?? 'U').toString()[0])
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (!hideSecondary) ...[
                        const SizedBox(width: 7),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 110),
                          child: Text(
                            (auth.user?['name'] ?? 'User').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.navy,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 17,
                        color: AppTheme.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CommandSearchButton extends StatelessWidget {
  final List<_NavEntry> entries;
  const _CommandSearchButton({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _CommandPalette(entries: entries),
        ),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Search modules & actions…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandPalette extends StatefulWidget {
  final List<_NavEntry> entries;
  const _CommandPalette({required this.entries});

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.entries.where((entry) {
      final q = _query.trim().toLowerCase();
      return q.isEmpty || entry.title.toLowerCase().contains(q);
    }).toList(growable: false);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 560,
        height: 470,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: 'Search sales, products, stock, reports…',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: visible.isEmpty
                  ? const Center(
                      child: Text(
                        'No matching module or action.',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 2),
                      itemBuilder: (_, index) {
                        final entry = visible[index];
                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          leading: Icon(
                            entry.icon,
                            color: AppTheme.textMuted,
                          ),
                          title: Text(entry.title),
                          trailing: const Icon(
                            Icons.keyboard_return_rounded,
                            size: 17,
                            color: Color(0xFF94A3B8),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            entry.onTap?.call();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color accent;

  const _TopChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = AppTheme.navy,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        height: 38,
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.navy,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  final int pendingCount;
  const _SyncButton({required this.pendingCount});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: pendingCount > 0
          ? '$pendingCount offline sales waiting to sync'
          : 'Offline sales sync',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OfflineSyncScreen()),
          );
          if (context.mounted) {
            context.read<OfflineQueueProvider>().refresh();
          }
        },
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Center(
                child: Icon(
                  Icons.sync_rounded,
                  size: 18,
                  color: AppTheme.textMuted,
                ),
              ),
              if (pendingCount > 0)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: const BoxDecoration(
                      color: AppTheme.warning,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      pendingCount > 9 ? '9+' : '$pendingCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 7.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BranchRequiredView extends StatelessWidget {
  final VoidCallback onOpenBranchControl;
  const _BranchRequiredView({required this.onOpenBranchControl});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.warning.withOpacity(.25),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(.09),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.account_tree_rounded,
                  color: AppTheme.warning,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Select a working branch',
                style: TextStyle(
                  color: AppTheme.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Master Admin works inside one branch at a time. Select a branch before opening sales, purchases, stock, payments, reports or Intelligence.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onOpenBranchControl,
                icon: const Icon(Icons.apartment_rounded),
                label: const Text('Open Branch Control'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavGroup {
  final String label;
  final List<_NavEntry> entries;
  const _NavGroup({required this.label, required this.entries});
}

class _NavEntry {
  final IconData icon;
  final String title;
  final String? shortcut;
  final VoidCallback? onTap;
  final bool active;
  final List<_NavEntry> children;
  final bool initiallyExpanded;

  const _NavEntry({
    required this.icon,
    required this.title,
    this.onTap,
    this.shortcut,
    this.active = false,
    this.children = const <_NavEntry>[],
    this.initiallyExpanded = false,
  });
}
