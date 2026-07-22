import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/branches/branch_control_screen.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_create_screen.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_screen.dart';
import 'package:enterprise_pos/screens/customers/customers_screen.dart';
import 'package:enterprise_pos/screens/home_screen.dart';
import 'package:enterprise_pos/screens/payments/party_payments_screen.dart';
import 'package:enterprise_pos/screens/product_screen.dart';
import 'package:enterprise_pos/screens/purchases/purchase_create.dart';
import 'package:enterprise_pos/screens/purchases/purchases_screen.dart';
import 'package:enterprise_pos/screens/reports/report_hub_screen.dart';
import 'package:enterprise_pos/screens/register_shifts/register_shift_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_create.dart';
// Sale Return screens remain in the project, but direct navigation is disabled
// because returns are now handled as -ve sales.
// import 'package:enterprise_pos/screens/sales/sale_returns_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_screen.dart';
import 'package:enterprise_pos/screens/stock_screen.dart';
import 'package:enterprise_pos/screens/users_screen.dart';
import 'package:enterprise_pos/screens/vendors/vendors_screen.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class PosShortcutInfo {
  final String keys;
  final String title;
  final String section;
  final IconData icon;
  final bool masterOnly;
  final String? permission;

  const PosShortcutInfo({
    required this.keys,
    required this.title,
    required this.section,
    required this.icon,
    this.masterOnly = false,
    this.permission,
  });
}

class PosShortcutCatalog {
  PosShortcutCatalog._();

  static const global = <PosShortcutInfo>[
    PosShortcutInfo(keys: 'Ctrl + /', title: 'Show shortcut guide', section: 'System', icon: Icons.keyboard_rounded),
    PosShortcutInfo(keys: 'Ctrl + H', title: 'Go to Home', section: 'Navigation', icon: Icons.home_rounded),
    PosShortcutInfo(keys: 'Ctrl + N / F2', title: 'Create Sale', section: 'Sales', icon: Icons.point_of_sale_rounded, permission: 'create-sales'),
    PosShortcutInfo(keys: 'Ctrl + L', title: 'Sales List', section: 'Sales', icon: Icons.receipt_long_rounded, permission: 'view-sales'),
    PosShortcutInfo(keys: 'Ctrl + O', title: 'New Purchase', section: 'Purchases', icon: Icons.shopping_cart_checkout_rounded, permission: 'manage-purchases'),
    PosShortcutInfo(keys: 'Ctrl + Shift + O', title: 'Purchase List', section: 'Purchases', icon: Icons.shopping_cart_rounded, permission: 'view-purchases'),
    PosShortcutInfo(keys: 'Ctrl + P', title: 'Products', section: 'Inventory', icon: Icons.inventory_2_rounded, permission: 'view-products'),
    PosShortcutInfo(keys: 'Ctrl + I', title: 'Stock', section: 'Inventory', icon: Icons.warehouse_rounded, permission: 'view-stock'),
    PosShortcutInfo(keys: 'Ctrl + Shift + C', title: 'Customers', section: 'Parties', icon: Icons.people_alt_rounded),
    PosShortcutInfo(keys: 'Ctrl + Shift + V', title: 'Vendors', section: 'Parties', icon: Icons.groups_2_rounded),
    PosShortcutInfo(keys: 'Ctrl + M', title: 'Party Payments', section: 'Parties', icon: Icons.account_balance_wallet_rounded),
    PosShortcutInfo(keys: 'Ctrl + B', title: 'Cash Ledger', section: 'Accounts', icon: Icons.payments_rounded),
    PosShortcutInfo(keys: 'Ctrl + Shift + N', title: 'New Cash Ledger Entry', section: 'Accounts', icon: Icons.add_circle_rounded),
    PosShortcutInfo(keys: 'Ctrl + E', title: 'Record Expense', section: 'Accounts', icon: Icons.money_off_rounded),
    PosShortcutInfo(keys: 'Ctrl + R', title: 'Reports', section: 'Reports', icon: Icons.analytics_rounded),
    PosShortcutInfo(keys: 'F6', title: 'Register Shift', section: 'Accounts', icon: Icons.point_of_sale_rounded),
    PosShortcutInfo(keys: 'Ctrl + U', title: 'Users', section: 'Administration', icon: Icons.manage_accounts_rounded),
    // Sale Returns shortcut intentionally disabled; returns use -ve sales.
    // PosShortcutInfo(keys: 'Ctrl + T', title: 'Sale Returns', section: 'Sales', icon: Icons.assignment_return_rounded),
    PosShortcutInfo(keys: 'Ctrl + Shift + B', title: 'Branch Control', section: 'Master Admin', icon: Icons.account_tree_rounded, masterOnly: true),
  ];

  static const saleCreate = <PosShortcutInfo>[
    // Open Pickers
    PosShortcutInfo(keys: 'F2 / Ctrl + I', title: 'Open item selector', section: 'Open Pickers', icon: Icons.add_shopping_cart_rounded),
    PosShortcutInfo(keys: 'F3 / Ctrl + Shift + C', title: 'Pick customer', section: 'Open Pickers', icon: Icons.person_search_rounded),
    PosShortcutInfo(keys: 'F4 / Ctrl + Shift + D', title: 'Pick delivery boy', section: 'Open Pickers', icon: Icons.delivery_dining_rounded),
    // Focus Fields
    PosShortcutInfo(keys: 'Ctrl + Shift + U', title: 'Focus Customer field', section: 'Focus Fields', icon: Icons.person_rounded),
    PosShortcutInfo(keys: 'Ctrl + Shift + S', title: 'Focus Salesman field', section: 'Focus Fields', icon: Icons.badge_rounded),
    PosShortcutInfo(keys: 'Ctrl + Shift + B', title: 'Focus Delivery Boy field', section: 'Focus Fields', icon: Icons.delivery_dining_rounded),
    PosShortcutInfo(keys: 'Ctrl + Shift + V', title: 'Focus Vendor field', section: 'Focus Fields', icon: Icons.storefront_rounded),
    PosShortcutInfo(keys: 'Ctrl + Shift + P', title: 'Focus Product search', section: 'Focus Fields', icon: Icons.search_rounded),
    PosShortcutInfo(keys: 'F9', title: 'Focus barcode scanner', section: 'Focus Fields', icon: Icons.qr_code_scanner_rounded),
    PosShortcutInfo(keys: 'Ctrl + Shift + N', title: 'Focus Walk-in Name', section: 'Focus Fields', icon: Icons.person_outline_rounded),
    PosShortcutInfo(keys: 'Ctrl + Shift + H', title: 'Focus Walk-in Phone', section: 'Focus Fields', icon: Icons.phone_rounded),
    PosShortcutInfo(keys: 'Ctrl + Shift + A', title: 'Focus Walk-in Address', section: 'Focus Fields', icon: Icons.location_on_rounded),
    PosShortcutInfo(keys: 'Ctrl + Shift + G', title: 'Focus Discount field', section: 'Focus Fields', icon: Icons.discount_rounded),
    PosShortcutInfo(keys: 'Ctrl + Shift + T', title: 'Focus Tax field', section: 'Focus Fields', icon: Icons.percent_rounded),
    PosShortcutInfo(keys: 'Ctrl + Shift + R', title: 'Focus Cash Received', section: 'Focus Fields', icon: Icons.payments_rounded),
    // Sale Actions
    PosShortcutInfo(keys: 'Ctrl + Enter', title: 'Save sale', section: 'Sale Actions', icon: Icons.check_circle_rounded),
  ];

  static const cashLedgerCreate = <PosShortcutInfo>[
    PosShortcutInfo(keys: 'Ctrl + 1 .. 5', title: 'Pick entry type', section: 'Cash Ledger Entry', icon: Icons.swap_vert_rounded),
    PosShortcutInfo(keys: 'F3 / Ctrl + Shift + P', title: 'Pick party', section: 'Cash Ledger Entry', icon: Icons.person_search_rounded),
    PosShortcutInfo(keys: 'Ctrl + D', title: 'Change date', section: 'Cash Ledger Entry', icon: Icons.calendar_today_rounded),
    PosShortcutInfo(keys: 'Ctrl + Enter', title: 'Save entry', section: 'Cash Ledger Entry', icon: Icons.check_circle_rounded),
  ];

  static const purchaseCreate = <PosShortcutInfo>[
    PosShortcutInfo(keys: 'F2 / Ctrl + I', title: 'Select items', section: 'Create Purchase', icon: Icons.add_shopping_cart_rounded),
    PosShortcutInfo(keys: 'F3 / Ctrl + Shift + V', title: 'Pick vendor', section: 'Create Purchase', icon: Icons.storefront_rounded),
    PosShortcutInfo(keys: 'F9', title: 'Focus barcode scanner', section: 'Create Purchase', icon: Icons.qr_code_scanner_rounded),
    PosShortcutInfo(keys: 'Ctrl + Enter', title: 'Save purchase', section: 'Create Purchase', icon: Icons.check_circle_rounded),
  ];

  static const purchaseClaimCreate = <PosShortcutInfo>[
    PosShortcutInfo(keys: 'F3 / Ctrl + Shift + V', title: 'Pick vendor', section: 'Create Purchase Claim', icon: Icons.storefront_rounded),
    PosShortcutInfo(keys: 'Ctrl + Enter', title: 'Save claim', section: 'Create Purchase Claim', icon: Icons.check_circle_rounded),
  ];

  static const saleReturnCreate = <PosShortcutInfo>[
    PosShortcutInfo(keys: 'F3 / Ctrl + Shift + C', title: 'Pick customer / sale', section: 'Create Sale Return', icon: Icons.person_search_rounded),
    PosShortcutInfo(keys: 'Ctrl + Enter', title: 'Save return', section: 'Create Sale Return', icon: Icons.check_circle_rounded),
  ];

  static const quickSave = <PosShortcutInfo>[
    PosShortcutInfo(keys: 'Ctrl + Enter', title: 'Save', section: 'Forms', icon: Icons.check_circle_rounded),
    PosShortcutInfo(keys: 'Esc', title: 'Cancel / close', section: 'Forms', icon: Icons.close_rounded),
  ];
}

class AppKeyboardShortcuts extends StatelessWidget {
  final Widget child;

  const AppKeyboardShortcuts({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final branch = context.watch<BranchProvider>();

    return Focus(
      autofocus: true,
      skipTraversal: true,
      canRequestFocus: true,
      child: CallbackShortcuts(
        bindings: _bindings(context, auth, branch),
        child: child,
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _bindings(BuildContext context, AuthProvider auth, BranchProvider branch) {
    // Each destination is an open-or-focus call with a stable route id and a
    // LAZY builder, so an already-open module is revealed (with its unfinished
    // state) instead of a duplicate being pushed.
    void open(String id, WidgetBuilder b, {String? permission}) {
      if (permission != null && !auth.hasPermission(permission)) return;
      _openBusiness(auth, branch, id, b);
    }

    return <ShortcutActivator, VoidCallback>{
      _ctrl(LogicalKeyboardKey.slash): () => _showShortcutGuide(context, auth),
      _cmd(LogicalKeyboardKey.slash): () => _showShortcutGuide(context, auth),
      const SingleActivator(LogicalKeyboardKey.f1): () => _showShortcutGuide(context, auth),

      _ctrl(LogicalKeyboardKey.keyH): () => _goHome(auth),
      _cmd(LogicalKeyboardKey.keyH): () => _goHome(auth),

      _ctrl(LogicalKeyboardKey.keyN): () => open(PosRouteIds.createSale, (_) => const CreateSaleScreen(), permission: 'create-sales'),
      _cmd(LogicalKeyboardKey.keyN): () => open(PosRouteIds.createSale, (_) => const CreateSaleScreen(), permission: 'create-sales'),
      const SingleActivator(LogicalKeyboardKey.f2): () => open(PosRouteIds.createSale, (_) => const CreateSaleScreen(), permission: 'create-sales'),

      _ctrl(LogicalKeyboardKey.keyL): () => open(PosRouteIds.sales, (_) => const SalesScreen(), permission: 'view-sales'),
      _cmd(LogicalKeyboardKey.keyL): () => open(PosRouteIds.sales, (_) => const SalesScreen(), permission: 'view-sales'),

      _ctrl(LogicalKeyboardKey.keyO): () => open(PosRouteIds.createPurchase, (_) => const CreatePurchaseScreen(), permission: 'manage-purchases'),
      _cmd(LogicalKeyboardKey.keyO): () => open(PosRouteIds.createPurchase, (_) => const CreatePurchaseScreen(), permission: 'manage-purchases'),
      _ctrlShift(LogicalKeyboardKey.keyO): () => open(PosRouteIds.purchases, (_) => const PurchasesScreen(), permission: 'view-purchases'),
      _cmdShift(LogicalKeyboardKey.keyO): () => open(PosRouteIds.purchases, (_) => const PurchasesScreen(), permission: 'view-purchases'),

      _ctrl(LogicalKeyboardKey.keyP): () => open(PosRouteIds.products, (_) => const ProductsScreen(), permission: 'view-products'),
      _cmd(LogicalKeyboardKey.keyP): () => open(PosRouteIds.products, (_) => const ProductsScreen(), permission: 'view-products'),

      _ctrl(LogicalKeyboardKey.keyI): () => open(PosRouteIds.stock, (_) => const StockScreen(), permission: 'view-stock'),
      _cmd(LogicalKeyboardKey.keyI): () => open(PosRouteIds.stock, (_) => const StockScreen(), permission: 'view-stock'),

      _ctrlShift(LogicalKeyboardKey.keyC): () => open(PosRouteIds.customers, (_) => const CustomersScreen(), permission: 'view-customers'),
      _cmdShift(LogicalKeyboardKey.keyC): () => open(PosRouteIds.customers, (_) => const CustomersScreen(), permission: 'view-customers'),

      _ctrlShift(LogicalKeyboardKey.keyV): () => open(PosRouteIds.vendors, (_) => const VendorsScreen(), permission: 'view-vendors'),
      _cmdShift(LogicalKeyboardKey.keyV): () => open(PosRouteIds.vendors, (_) => const VendorsScreen(), permission: 'view-vendors'),

      _ctrl(LogicalKeyboardKey.keyM): () => open(PosRouteIds.partyPayments, (_) => const PartyPaymentsScreen()),
      _cmd(LogicalKeyboardKey.keyM): () => open(PosRouteIds.partyPayments, (_) => const PartyPaymentsScreen()),

      _ctrl(LogicalKeyboardKey.keyB): () => open(PosRouteIds.cashLedger, (_) => const CashLedgerScreen(), permission: 'view-cashbook'),
      _cmd(LogicalKeyboardKey.keyB): () => open(PosRouteIds.cashLedger, (_) => const CashLedgerScreen(), permission: 'view-cashbook'),

      _ctrlShift(LogicalKeyboardKey.keyN): () => open(PosRouteIds.cashLedgerCreate, (_) => const CashLedgerCreateScreen()),
      _cmdShift(LogicalKeyboardKey.keyN): () => open(PosRouteIds.cashLedgerCreate, (_) => const CashLedgerCreateScreen()),

      // Record Expense = the consolidated Cash Ledger entry with Other Expense
      // preselected. Same route id as Ctrl+Shift+N so the two shortcuts never
      // create duplicate Record Entry screens (an already-open one is focused,
      // preserving unsaved Loan/Qameti data rather than switching category).
      _ctrl(LogicalKeyboardKey.keyE): () => open(PosRouteIds.cashLedgerCreate, (_) => const CashLedgerCreateScreen(initialCategory: 'OTHER_EXPENSE')),
      _cmd(LogicalKeyboardKey.keyE): () => open(PosRouteIds.cashLedgerCreate, (_) => const CashLedgerCreateScreen(initialCategory: 'OTHER_EXPENSE')),

      _ctrl(LogicalKeyboardKey.keyR): () => open(PosRouteIds.reports, (_) => const ReportsHubScreen(), permission: 'view-reports'),
      _cmd(LogicalKeyboardKey.keyR): () => open(PosRouteIds.reports, (_) => const ReportsHubScreen(), permission: 'view-reports'),

      const SingleActivator(LogicalKeyboardKey.f6): () =>
          open(PosRouteIds.registerShift, (_) => const RegisterShiftScreen(), permission: 'view-register-shifts'),

      _ctrl(LogicalKeyboardKey.keyU): () => open(PosRouteIds.users, (_) => const UsersScreen(), permission: 'view-users'),
      _cmd(LogicalKeyboardKey.keyU): () => open(PosRouteIds.users, (_) => const UsersScreen(), permission: 'view-users'),

      // Sale Returns navigation intentionally disabled; returns use -ve sales.
      // _ctrl(LogicalKeyboardKey.keyT): () => open(PosRouteIds.saleReturns, (_) => const SaleReturnsScreen()),
      // _cmd(LogicalKeyboardKey.keyT): () => open(PosRouteIds.saleReturns, (_) => const SaleReturnsScreen()),

      _ctrlShift(LogicalKeyboardKey.keyB): () => _openBranchControl(auth),
      _cmdShift(LogicalKeyboardKey.keyB): () => _openBranchControl(auth),

      _ctrl(LogicalKeyboardKey.digit1): () => open(PosRouteIds.createSale, (_) => const CreateSaleScreen()),
      _ctrl(LogicalKeyboardKey.numpad1): () => open(PosRouteIds.createSale, (_) => const CreateSaleScreen()),
      _ctrl(LogicalKeyboardKey.digit2): () => open(PosRouteIds.sales, (_) => const SalesScreen()),
      _ctrl(LogicalKeyboardKey.numpad2): () => open(PosRouteIds.sales, (_) => const SalesScreen()),
      _ctrl(LogicalKeyboardKey.digit3): () => open(PosRouteIds.products, (_) => const ProductsScreen()),
      _ctrl(LogicalKeyboardKey.numpad3): () => open(PosRouteIds.products, (_) => const ProductsScreen()),
      _ctrl(LogicalKeyboardKey.digit4): () => open(PosRouteIds.stock, (_) => const StockScreen()),
      _ctrl(LogicalKeyboardKey.numpad4): () => open(PosRouteIds.stock, (_) => const StockScreen()),
      _ctrl(LogicalKeyboardKey.digit5): () => open(PosRouteIds.customers, (_) => const CustomersScreen()),
      _ctrl(LogicalKeyboardKey.numpad5): () => open(PosRouteIds.customers, (_) => const CustomersScreen()),
      _ctrl(LogicalKeyboardKey.digit6): () => open(PosRouteIds.vendors, (_) => const VendorsScreen()),
      _ctrl(LogicalKeyboardKey.numpad6): () => open(PosRouteIds.vendors, (_) => const VendorsScreen()),
      _ctrl(LogicalKeyboardKey.digit7): () => open(PosRouteIds.createPurchase, (_) => const CreatePurchaseScreen()),
      _ctrl(LogicalKeyboardKey.numpad7): () => open(PosRouteIds.createPurchase, (_) => const CreatePurchaseScreen()),
      _ctrl(LogicalKeyboardKey.digit8): () => open(PosRouteIds.partyPayments, (_) => const PartyPaymentsScreen()),
      _ctrl(LogicalKeyboardKey.numpad8): () => open(PosRouteIds.partyPayments, (_) => const PartyPaymentsScreen()),
      _ctrl(LogicalKeyboardKey.digit9): () => open(PosRouteIds.reports, (_) => const ReportsHubScreen()),
      _ctrl(LogicalKeyboardKey.numpad9): () => open(PosRouteIds.reports, (_) => const ReportsHubScreen()),
      _ctrl(LogicalKeyboardKey.digit0): () => open(PosRouteIds.cashLedger, (_) => const CashLedgerScreen()),
      _ctrl(LogicalKeyboardKey.numpad0): () => open(PosRouteIds.cashLedger, (_) => const CashLedgerScreen()),
    };
  }

  static SingleActivator _ctrl(LogicalKeyboardKey key) => SingleActivator(key, control: true);
  static SingleActivator _cmd(LogicalKeyboardKey key) => SingleActivator(key, meta: true);
  static SingleActivator _ctrlShift(LogicalKeyboardKey key) => SingleActivator(key, control: true, shift: true);
  static SingleActivator _cmdShift(LogicalKeyboardKey key) => SingleActivator(key, meta: true, shift: true);

  void _goHome(AuthProvider auth) {
    if (!auth.isAuthenticated) return;
    appNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  void _openBranchControl(AuthProvider auth) {
    if (!auth.isAuthenticated) return;
    if (!auth.isMasterAdmin) {
      _message('Branch Control is available only for master admin.');
      return;
    }
    PosNavigation.openSingleton(
      routeId: PosRouteIds.branchControl,
      builder: (_) => const BranchControlScreen(),
    );
  }

  void _openBusiness(
    AuthProvider auth,
    BranchProvider branch,
    String routeId,
    WidgetBuilder builder,
  ) {
    if (!auth.isAuthenticated) return;
    if (auth.isMasterAdmin && !branch.hasActiveBranch) {
      _message('Please select a working branch from Branch Control first.');
      PosNavigation.openSingleton(
        routeId: PosRouteIds.branchControl,
        builder: (_) => const BranchControlScreen(),
      );
      return;
    }
    PosNavigation.openSingleton(routeId: routeId, builder: builder);
  }

  static void _message(String text) {
    final messenger = appScaffoldMessengerKey.currentState;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

void showAppShortcutGuide(
  BuildContext context, {
  bool includeSaleCreate = false,
  List<PosShortcutInfo> extra = const [],
}) {
  final auth = context.read<AuthProvider>();
  _showShortcutGuide(context, auth, includeSaleCreate: includeSaleCreate, extra: extra);
}

void _showShortcutGuide(
  BuildContext context,
  AuthProvider auth, {
  bool includeSaleCreate = false,
  List<PosShortcutInfo> extra = const [],
}) {
  final globalRows =
      PosShortcutCatalog.global.where((item) =>
          (!item.masterOnly || auth.isMasterAdmin) &&
          (item.permission == null || auth.hasPermission(item.permission!))).toList();

  showDialog(
    context: appNavigatorKey.currentContext ?? context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.keyboard_rounded, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Keyboard shortcuts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.navy)),
                        SizedBox(height: 2),
                        Text('Use the keyboard for fast POS navigation and sale entry.', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Global shortcuts (flat, no section header) ─────────
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ...globalRows.map((item) => _ShortcutCard(info: item)),
                          ...extra.map((item) => _ShortcutCard(info: item)),
                        ],
                      ),
                      // ── Create Sale shortcuts grouped by section ───────────
                      if (includeSaleCreate) ...[
                        const SizedBox(height: 20),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        const Text(
                          'Create Sale',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppTheme.navy),
                        ),
                        const SizedBox(height: 12),
                        ..._buildSaleCreateSections(),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Tip: Focus-field shortcuts select all text in numeric fields so typing immediately replaces the value.',
                style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Groups [PosShortcutCatalog.saleCreate] by [section] and returns a list of
/// section-header + card-wrap widgets in insertion order.
List<Widget> _buildSaleCreateSections() {
  final ordered = <String>[];
  final grouped = <String, List<PosShortcutInfo>>{};

  for (final info in PosShortcutCatalog.saleCreate) {
    if (!grouped.containsKey(info.section)) {
      ordered.add(info.section);
      grouped[info.section] = [];
    }
    grouped[info.section]!.add(info);
  }

  final widgets = <Widget>[];
  for (final section in ordered) {
    widgets.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          section,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppTheme.textMuted,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
    widgets.add(
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: grouped[section]!.map((item) => _ShortcutCard(info: item)).toList(),
      ),
    );
    widgets.add(const SizedBox(height: 14));
  }
  return widgets;
}

class _ShortcutCard extends StatelessWidget {
  final PosShortcutInfo info;

  const _ShortcutCard({required this.info});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: AppTheme.surfaceSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(info.icon, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.navy)),
                const SizedBox(height: 5),
                _KeyBadge(text: info.keys),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyBadge extends StatelessWidget {
  final String text;

  const _KeyBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.navy,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
      ),
    );
  }
}

/// Shared key-modifier builders for per-screen [CallbackShortcuts], so every
/// create/detail screen wires Ctrl+Enter (and friends) the same way instead
/// of each file rolling its own SingleActivator helpers.
SingleActivator posCtrl(LogicalKeyboardKey key) => SingleActivator(key, control: true);
SingleActivator posCmd(LogicalKeyboardKey key) => SingleActivator(key, meta: true);
SingleActivator posCtrlShift(LogicalKeyboardKey key) => SingleActivator(key, control: true, shift: true);
SingleActivator posCmdShift(LogicalKeyboardKey key) => SingleActivator(key, meta: true, shift: true);

/// The standard "save" binding set: Ctrl/Cmd + Enter, including the numpad
/// Enter key. Spread this into a screen's CallbackShortcuts bindings map.
Map<ShortcutActivator, VoidCallback> posSaveShortcuts(VoidCallback onSave) => {
      posCtrl(LogicalKeyboardKey.enter): onSave,
      posCmd(LogicalKeyboardKey.enter): onSave,
      posCtrl(LogicalKeyboardKey.numpadEnter): onSave,
      posCmd(LogicalKeyboardKey.numpadEnter): onSave,
    };
