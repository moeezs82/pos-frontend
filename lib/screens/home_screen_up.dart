import 'dart:ui';
import 'package:enterprise_pos/screens/customers/customers_screen.dart';
import 'package:enterprise_pos/screens/product_screen.dart';
import 'package:enterprise_pos/screens/purchases/purchase_claim_screen.dart';
import 'package:enterprise_pos/screens/purchases/purchases_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_returns_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_screen.dart';
import 'package:enterprise_pos/screens/stock_screen.dart';
import 'package:enterprise_pos/screens/vendors/vendors_screen.dart';
import 'package:enterprise_pos/widgets/branch_select_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/branch_provider.dart';
import 'login_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openBranchSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: const BranchSelectSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final bp = context.watch<BranchProvider>();

    final isWide = MediaQuery.of(context).size.width >= 900;
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text("Enterprise POS"),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              label: Text(
                bp.label,
                style: const TextStyle(color: Colors.white),
              ),
              avatar: const Icon(Icons.warehouse_outlined, color: Colors.white, size: 18),
              backgroundColor: Colors.white.withOpacity(.18),
              shape: StadiumBorder(side: BorderSide(color: Colors.white.withOpacity(.25))),
              onPressed: () => _openBranchSheet(context),
            ),
          ),
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

      body: Stack(
        children: [
          // Futuristic gradient background
          _HeaderGradient(),
          // Content
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _WelcomeCard(
                          name: auth.user?['name'] ?? 'User',
                          role: (auth.user?['role'] is List && auth.user?['role']?.isNotEmpty == true)
                              ? auth.user!['role'][0].toString()
                              : 'Unknown',
                          onChangeBranch: () => _openBranchSheet(context),
                        ),
                        const SizedBox(height: 12),
                        // Slim KPIs (placeholders; wire to your API later)
                        _KpiRow(
                          items: const [
                            KpiItem(label: 'Today Sales', value: '—'),
                            KpiItem(label: 'Pending Orders', value: '—'),
                            KpiItem(label: 'Low Stock', value: '—'),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // Grid
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isWide ? 6 : isTablet ? 4 : 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.05, // compact square-ish tiles
                    ),
                    delegate: SliverChildListDelegate.fixed([
                      _NavTile(
                        icon: Icons.shopping_cart_rounded,
                        label: "Sales",
                        color: Colors.lightBlueAccent,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesScreen())),
                      ),
                      _NavTile(
                        icon: Icons.assignment_return_rounded,
                        label: "Sale Returns",
                        color: Colors.indigoAccent,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SaleReturnsScreen())),
                      ),
                      _NavTile(
                        icon: Icons.shopping_cart_checkout_rounded,
                        label: "Purchases",
                        color: Colors.cyan,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchasesScreen())),
                      ),
                      _NavTile(
                        icon: Icons.assignment_turned_in_rounded,
                        label: "Purchase Claims",
                        color: Colors.deepPurpleAccent,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseClaimsScreen())),
                      ),
                      _NavTile(
                        icon: Icons.inventory_2_rounded,
                        label: "Products",
                        color: Colors.greenAccent,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductsScreen())),
                      ),
                      _NavTile(
                        icon: Icons.warehouse_rounded,
                        label: "Stock",
                        color: Colors.redAccent,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockScreen())),
                      ),
                      _NavTile(
                        icon: Icons.people_alt_rounded,
                        label: "Customers",
                        color: Colors.orangeAccent,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomersScreen())),
                      ),
                      _NavTile(
                        icon: Icons.groups_2_rounded,
                        label: "Vendors",
                        color: Colors.amberAccent,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VendorsScreen())),
                      ),
                      _NavTile(
                        icon: Icons.bar_chart_rounded,
                        label: "Reports",
                        color: Colors.purpleAccent,
                        onTap: () {
                          // TODO: route
                        },
                      ),
                      _NavTile(
                        icon: Icons.settings_rounded,
                        label: "Settings",
                        color: Colors.tealAccent,
                        onTap: () {
                          // TODO: route
                        },
                      ),
                    ]),
                  ),
                ),

                // Little footer spacing
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ---------- Header gradient (futuristic) ---------- */
class _HeaderGradient extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      height: 260,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary.withOpacity(.95),
            primary.withOpacity(.85),
            primary.withOpacity(.70),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

/* ---------- Welcome / profile glass card ---------- */
class _WelcomeCard extends StatelessWidget {
  final String name;
  final String role;
  final VoidCallback onChangeBranch;

  const _WelcomeCard({
    required this.name,
    required this.role,
    required this.onChangeBranch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(.2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white,
                child: Text(
                  initial,
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
                    Text("Welcome back,", style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                    Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text("Role: $role", style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onChangeBranch,
                icon: const Icon(Icons.swap_horiz, color: Colors.white),
                label: const Text("Change Branch", style: TextStyle(color: Colors.white)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------- KPI row (compact chips) ---------- */
class KpiItem {
  final String label;
  final String value;
  const KpiItem({required this.label, required this.value});
}

class _KpiRow extends StatelessWidget {
  final List<KpiItem> items;
  const _KpiRow({required this.items});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: items
          .map((k) => Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(.18)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(k.label, style: text.labelSmall?.copyWith(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text(k.value, style: text.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ))
          .toList()
        ..removeLast(),
    );
  }
}

/* ---------- Navigation tiles (compact, animated) ---------- */
class _NavTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white12
        : Colors.black12;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.color.withOpacity(.10),
                widget.color.withOpacity(.04),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(.15),
                blurRadius: 16,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withOpacity(.18),
                  border: Border.all(color: widget.color.withOpacity(.35)),
                ),
                child: Icon(widget.icon, color: widget.color, size: 24),
              ),
              const SizedBox(height: 10),
              Text(
                widget.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
