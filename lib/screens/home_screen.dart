import 'package:enterprise_pos/screens/account_screen.dart';
import 'package:enterprise_pos/screens/cashbook/cashbook_screen.dart';
import 'package:enterprise_pos/screens/cashbook/expense_create_screen.dart';
import 'package:enterprise_pos/screens/customers/customers_screen.dart';
import 'package:enterprise_pos/screens/product_screen.dart';
import 'package:enterprise_pos/screens/purchases/purchase_claim_screen.dart';
import 'package:enterprise_pos/screens/purchases/purchase_create.dart';
import 'package:enterprise_pos/screens/purchases/purchases_screen.dart';
import 'package:enterprise_pos/screens/payments/party_payments_screen.dart';
import 'package:enterprise_pos/screens/reports/report_hub_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_create.dart';
import 'package:enterprise_pos/screens/sales/sale_returns_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_screen.dart';
import 'package:enterprise_pos/screens/stock_screen.dart';
import 'package:enterprise_pos/screens/vendors/vendors_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1280
        ? 4
        : width >= 900
            ? 3
            : width >= 620
                ? 2
                : 1;

    final userName = (auth.user?['name'] ?? 'User').toString();
    final rawRole = auth.user?['role'];
    final role = rawRole is List && rawRole.isNotEmpty
        ? (rawRole.first ?? 'Unknown').toString()
        : (rawRole ?? 'Unknown').toString();

    final quickActions = <_Tile>[
      _Tile(
        icon: Icons.point_of_sale_rounded,
        title: 'Create Sale',
        subtitle: 'Fast checkout',
        color: AppTheme.primary,
        emphasized: true,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateSaleScreen())),
      ),
      _Tile(
        icon: Icons.receipt_long_rounded,
        title: 'Add Expense',
        subtitle: 'Cash/account expense',
        color: AppTheme.danger,
        emphasized: true,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseCreateScreen())),
      ),
      _Tile(
        icon: Icons.account_balance_wallet_rounded,
        title: 'Party Payments',
        subtitle: 'Customer/vendor payments',
        color: AppTheme.success,
        emphasized: true,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PartyPaymentsScreen())),
      ),
      _Tile(
        icon: Icons.shopping_cart_checkout_rounded,
        title: 'New Purchase',
        subtitle: 'Supplier invoice',
        color: AppTheme.warning,
        emphasized: true,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePurchaseScreen())),
      ),
      _Tile(
        icon: Icons.analytics_rounded,
        title: 'Reports',
        subtitle: 'Balances & exports',
        color: AppTheme.purple,
        emphasized: true,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsHubScreen())),
      ),
    ];

    final management = <_Tile>[
      _Tile(icon: Icons.shopping_bag_rounded, title: 'Sales', subtitle: 'Invoices and payments', color: AppTheme.info, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesScreen()))),
      _Tile(icon: Icons.account_balance_wallet_rounded, title: 'Cash Book', subtitle: 'Cash flow and daybook', color: AppTheme.primary, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CashBookScreen()))),
      _Tile(icon: Icons.inventory_2_rounded, title: 'Products', subtitle: 'Catalog and prices', color: AppTheme.success, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductsScreen()))),
      _Tile(icon: Icons.warehouse_rounded, title: 'Stock', subtitle: 'Inventory on hand', color: AppTheme.danger, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockScreen()))),
      _Tile(icon: Icons.people_alt_rounded, title: 'Customers', subtitle: 'Receivables and profiles', color: AppTheme.warning, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomersScreen()))),
      _Tile(icon: Icons.groups_2_rounded, title: 'Vendors', subtitle: 'Suppliers and payables', color: AppTheme.purple, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VendorsScreen()))),
      _Tile(icon: Icons.assignment_return_rounded, title: 'Sale Returns', subtitle: 'Refund workflow', color: AppTheme.info, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SaleReturnsScreen()))),
      _Tile(icon: Icons.shopping_cart_rounded, title: 'Purchases', subtitle: 'Bills and payments', color: AppTheme.primaryDark, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchasesScreen()))),
      _Tile(icon: Icons.assignment_return_outlined, title: 'Purchase Claim', subtitle: 'Damage/shortage claims', color: AppTheme.warning, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseClaimsScreen()))),
      _Tile(icon: Icons.account_tree_rounded, title: 'Accounts', subtitle: 'Chart of accounts', color: AppTheme.navy, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountsScreen()))),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('CounterIQ POS'),
        actions: [
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          _WelcomeHeader(userName: userName, role: role),
          const SizedBox(height: 18),
          const _SectionTitle(title: 'Quick actions', subtitle: 'Most-used tasks are one tap away'),
          const SizedBox(height: 10),
          _TileGrid(tiles: quickActions, columns: cols),
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Manage business', subtitle: 'Sales, stock, parties, accounts and claims'),
          const SizedBox(height: 10),
          _TileGrid(tiles: management, columns: cols),
        ],
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
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateSaleScreen())),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Sale'),
          ),
        ],
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
  final Color color;
  final VoidCallback onTap;
  final bool emphasized;

  _Tile({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap, this.emphasized = false});
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
                    Text(tile.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w900, fontSize: 15)),
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
