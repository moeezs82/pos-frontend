import 'package:enterprise_pos/config/backend_config.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/providers/offline_queue_provider.dart';
import 'package:enterprise_pos/providers/register_shift_provider.dart';
import 'package:enterprise_pos/providers/subscription_provider.dart';
import 'package:enterprise_pos/screens/account_screen.dart';
import 'package:enterprise_pos/screens/branches/branch_control_screen.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_screen.dart';
import 'package:enterprise_pos/screens/customers/customers_screen.dart';
import 'package:enterprise_pos/screens/intelligence/intelligence_hub_screen.dart';
import 'package:enterprise_pos/screens/payments/party_payments_screen.dart';
import 'package:enterprise_pos/screens/purchases/purchase_claim_screen.dart';
import 'package:enterprise_pos/screens/purchases/purchases_screen.dart';
import 'package:enterprise_pos/screens/register_shifts/register_shift_screen.dart';
import 'package:enterprise_pos/screens/reports/credit_control_screen.dart';
import 'package:enterprise_pos/screens/reports/report_hub_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_create.dart';
import 'package:enterprise_pos/screens/sales/sale_screen.dart';
import 'package:enterprise_pos/screens/settings/backup_restore_screen.dart';
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
import 'package:enterprise_pos/widgets/backup_reminder_gate.dart';
import 'package:enterprise_pos/widgets/subscription_warning_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shared desktop chrome for the redesigned CounterIQ workspace.
///
/// Phase 1 intentionally migrates Home and Products only. Other modules keep
/// their existing screens until their redesign phase, but navigation from this
/// shell still opens those exact existing routes so no transactional behaviour
/// is changed.
class CounterIQDesktopShell extends StatefulWidget {
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
        .expand((group) => group.entries)
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
                          : widget.child,
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
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SubscriptionManagementScreen(),
                ),
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
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PurchaseClaimsScreen(),
                ),
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
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreditControlScreen()),
              ),
            ),
        ],
      ),
      _NavGroup(
        label: 'Finance & Analysis',
        entries: [
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
          if (auth.hasPermission('view-reports'))
            _NavEntry(
              icon: Icons.analytics_outlined,
              title: 'Reports',
              shortcut: 'Ctrl+R',
              active: _isActive(PosRouteIds.reports),
              onTap: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.reports,
                builder: (_) => const ReportsHubScreen(),
              ),
            ),
          if (auth.hasAddon('intelligence') &&
              auth.hasPermission('view-intelligence'))
            _NavEntry(
              icon: Icons.auto_awesome_rounded,
              title: 'Intelligence',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const IntelligenceHubScreen(),
                ),
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
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => UnitsScreen(token: auth.token!)),
              ),
            ),
          if (auth.hasPermission('manage-printer-settings'))
            _NavEntry(
              icon: Icons.print_outlined,
              title: 'Printer Settings',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PrinterSettingsScreen(),
                ),
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
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BackupRestoreScreen(),
                ),
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
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SubscriptionManagementScreen(),
                ),
              ),
            ),
          if (auth.isMasterAdmin)
            _NavEntry(
              icon: Icons.account_balance_outlined,
              title: 'Accounts',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccountsScreen()),
              ),
            ),
        ],
      ),
    ].where((group) => group.entries.isNotEmpty).toList(growable: false);
  }

  void _openHome() {
    if (_isActive(PosRouteIds.home)) return;
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

class _SidebarEntry extends StatelessWidget {
  final _NavEntry entry;
  final bool compact;

  const _SidebarEntry({required this.entry, required this.compact});

  @override
  Widget build(BuildContext context) {
    final foreground =
        entry.active ? AppTheme.primary : const Color(0xFF475569);
    final child = Material(
      color: entry.active
          ? AppTheme.primary.withOpacity(.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: entry.onTap,
        child: SizedBox(
          height: 39,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(entry.icon, color: foreground, size: 19),
                if (!compact) ...[
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 12,
                        fontWeight: entry.active
                            ? FontWeight.w900
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                  if (entry.shortcut != null)
                    Text(
                      entry.shortcut!,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: compact ? Tooltip(message: entry.title, child: child) : child,
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
                            entry.onTap();
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
  final VoidCallback onTap;
  final bool active;

  const _NavEntry({
    required this.icon,
    required this.title,
    required this.onTap,
    this.shortcut,
    this.active = false,
  });
}
