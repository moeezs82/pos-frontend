import 'package:enterprise_pos/screens/customers_screen.dart';
import 'package:enterprise_pos/screens/product_screen.dart';
import 'package:enterprise_pos/screens/sale_screen.dart';
import 'package:enterprise_pos/screens/stock_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Enterprise POS"),
        actions: [
          IconButton(
            tooltip: "Logout",
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await auth.logout();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 User info header
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    auth.user?['name'] != null
                        ? auth.user!['name'][0].toUpperCase()
                        : "?",
                    style: TextStyle(
                      fontSize: 24,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Welcome back,", style: theme.textTheme.bodyMedium),
                    Text(
                      auth.user?['name'] ?? "User",
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "Role: ${auth.user?['role']?[0] ?? 'Unknown'}",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 🔹 Dashboard grid
            Expanded(
              child: GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _DashboardCard(
                    icon: Icons.shopping_cart,
                    title: "Sales",
                    color: Colors.blue,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SalesScreen()),
                      );
                    },
                  ),
                  _DashboardCard(
                    icon: Icons.inventory_2,
                    title: "Products",
                    color: Colors.green,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProductsScreen(),
                        ),
                      );
                    },
                  ),
                  _DashboardCard(
                    icon: Icons.warehouse, // or Icons.store
                    title: "Stocks",
                    color: Colors.red,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StockScreen()),
                      );
                    },
                  ),
                  _DashboardCard(
                    icon: Icons.people,
                    title: "Customers",
                    color: Colors.orange,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CustomersScreen(),
                        ),
                      );
                    },
                  ),
                  _DashboardCard(
                    icon: Icons.bar_chart,
                    title: "Reports",
                    color: Colors.purple,
                    onTap: () {
                      // TODO: Navigate to Reports screen
                    },
                  ),
                  _DashboardCard(
                    icon: Icons.settings,
                    title: "Settings",
                    color: Colors.teal,
                    onTap: () {
                      // TODO: Navigate to Settings screen
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Card(
        color: color.withOpacity(0.1),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
