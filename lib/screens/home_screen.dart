import 'package:enterprise_pos/screens/account_screen.dart';
import 'package:enterprise_pos/screens/cashbook/cashbook_screen.dart';
import 'package:enterprise_pos/screens/cashbook/daybook_screen.dart';
import 'package:enterprise_pos/screens/customers/customers_screen.dart';
import 'package:enterprise_pos/screens/product_screen.dart';
import 'package:enterprise_pos/screens/purchases/purchase_claim_screen.dart';
import 'package:enterprise_pos/screens/reports/report_cashbook_screen.dart';
import 'package:enterprise_pos/screens/reports/report_hub_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_returns_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_screen.dart';
import 'package:enterprise_pos/screens/purchases/purchases_screen.dart';
import 'package:enterprise_pos/screens/stock_screen.dart';
import 'package:enterprise_pos/screens/users_screen.dart';
import 'package:enterprise_pos/screens/vendors/vendors_screen.dart';
import 'package:enterprise_pos/widgets/branch_select_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/branch_provider.dart';
import 'login_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // Future<void> _openBranchSheet(BuildContext context) async {
  //   await showModalBottomSheet(
  //     context: context,
  //     isScrollControlled: true,
  //     builder: (_) => SizedBox(
  //       height: MediaQuery.of(context).size.height * 0.85,
  //       child: const BranchSelectSheet(),
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final bp = context.watch<BranchProvider>();

    // Dashboard tile definitions (clean & easy to maintain)
    final tiles = <_Tile>[
      _Tile(
        icon: Icons.shopping_cart,
        title: "Sales",
        subtitle: "Create invoices",
        color: Colors.blue,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SalesScreen()),
        ),
      ),
      _Tile(
        icon: Icons.assignment_return,
        title: "Sale Returns",
        subtitle: "Process returns",
        color: Colors.indigo,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SaleReturnsScreen()),
        ),
      ),
      _Tile(
        icon: Icons.shopping_cart_checkout,
        title: "Purchases",
        subtitle: "Supplier bills",
        color: Colors.blue,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PurchasesScreen()),
        ),
      ),
      _Tile(
        icon: Icons.assignment_return_outlined,
        title: "Purchase Claim",
        subtitle: "Damage/shortage",
        color: Colors.indigo,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PurchaseClaimsScreen()),
        ),
      ),
      _Tile(
        icon: Icons.inventory_2,
        title: "Products",
        subtitle: "Catalog & SKUs",
        color: Colors.green,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProductsScreen()),
        ),
      ),
      _Tile(
        icon: Icons.warehouse,
        title: "Stocks",
        subtitle: "On-hand by branch",
        color: Colors.red,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StockScreen()),
        ),
      ),

      _Tile(
        icon: Icons.receipt_long_rounded,
        title: "Cash Book",
        subtitle: "Receipts • Payments • Expenses",
        color: Colors.teal,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReportCashbookScreen()),
        ),
      ),

      _Tile(
        icon: Icons.receipt_long_rounded,
        title: "Accounts",
        subtitle: "ASSET • Libilities • Expenses",
        color: Colors.teal,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AccountsScreen()),
        ),
      ),

      _Tile(
        icon: Icons.people,
        title: "Customers",
        subtitle: "CRM basics",
        color: Colors.orange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CustomersScreen()),
        ),
      ),
      _Tile(
        icon: Icons.groups_2,
        title: "Vendors",
        subtitle: "Supplier list",
        color: Colors.orange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VendorsScreen()),
        ),
      ),
      _Tile(
        icon: Icons.groups_2,
        title: "Users",
        subtitle: "App Users / Salesmen",
        color: Colors.orange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UsersScreen()),
        ),
      ),
      _Tile(
        icon: Icons.bar_chart,
        title: "Reports",
        subtitle: "Analytics & KPIs",
        color: Colors.purple,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReportsHubScreen()),
        ),
      ),
      _Tile(
        icon: Icons.settings,
        title: "Settings",
        subtitle: "Configuration",
        color: Colors.blueGrey,
        onTap: () {}, // hook up later
      ),
    ];

    // Responsive columns
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1100
        ? 5
        : width >= 900
        ? 4
        : width >= 600
        ? 3
        : 2;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text("POS"),
        actions: [
          // Padding(
          //   padding: const EdgeInsets.only(right: 8.0),
          //   child: ActionChip(
          //     label: Text(bp.label, style: const TextStyle(color: Colors.white)),
          //     avatar: const Icon(Icons.warehouse_outlined, color: Colors.white, size: 18),
          //     backgroundColor: Colors.blueGrey,
          //     onPressed: () => _openBranchSheet(context), // Home can change
          //   ),
          // ),
          IconButton(
            tooltip: "Logout",
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await auth.logout();
              if (!context.mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Welcome banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withOpacity(0.9),
                  theme.colorScheme.primary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white,
                  child: Text(
                    auth.user?['name'] != null
                        ? auth.user!['name'][0].toUpperCase()
                        : "?",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Welcome back,",
                        style: TextStyle(color: Colors.white70),
                      ),
                      Text(
                        auth.user?['name'] ?? "User",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        "Role: ${auth.user?['role']?[0] ?? 'Unknown'}",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // TextButton.icon(
                //   onPressed: () => _openBranchSheet(context),
                //   icon: const Icon(Icons.swap_horiz, color: Colors.white),
                //   label: const Text("Change Branch", style: TextStyle(color: Colors.white)),
                // ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Grid
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.15,
                ),
                itemCount: tiles.length,
                itemBuilder: (_, i) => _DashboardCard(tile: tiles[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class _DashboardCard extends StatelessWidget {
  final _Tile tile;
  const _DashboardCard({required this.tile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: tile.onTap,
      child: Card(
        elevation: 2,
        shadowColor: tile.color.withOpacity(0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tile.color.withOpacity(0.08),
                tile.color.withOpacity(0.02),
              ],
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon in a soft circle
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tile.color.withOpacity(0.15),
                ),
                child: Icon(tile.icon, size: 26, color: tile.color),
              ),
              const SizedBox(height: 12),
              Text(
                tile.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade900,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                tile.subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
