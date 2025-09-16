import 'package:enterprise_pos/forms/product_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  int _page = 1;
  int _lastPage = 1;
  bool _loading = false;
  String _search = "";
  final List<dynamic> _products = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchProducts(reset: true);
  }

  Future<void> _fetchProducts({bool reset = false}) async {
    setState(() => _loading = true);

    if (reset) {
      _products.clear();
      _page = 1;
    }

    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token!;
      final data =
          await ApiService.getProducts(token, page: _page, search: _search);

      final wrapper = (data['data'] as List).first;
      final items = wrapper['products'] as List<dynamic>;

      setState(() {
        _products.clear();
        _products.addAll(items);
        _page = wrapper['current_page'];
        _lastPage = wrapper['last_page'];
      });
    } catch (e) {
      debugPrint("Error loading products: $e");
    }

    setState(() => _loading = false);
  }

  void _onSearch() {
    setState(() => _search = _searchController.text);
    _fetchProducts(reset: true);
  }

  Future<void> _onRefresh() async {
    await _fetchProducts(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Products"),
        centerTitle: true,
      ),

      // ➕ Floating Add Button
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProductFormScreen()),
          );
          if (result == true) {
            _fetchProducts(reset: true);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text("Add Product"),
      ),

      // 📍 Pagination Bar at Bottom
      bottomNavigationBar: _products.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    onPressed: _page > 1
                        ? () {
                            setState(() => _page--);
                            _fetchProducts();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text("Previous"),
                  ),
                  Text("Page $_page / $_lastPage"),
                  ElevatedButton.icon(
                    onPressed: _page < _lastPage
                        ? () {
                            setState(() => _page++);
                            _fetchProducts();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text("Next"),
                  ),
                ],
              ),
            )
          : null,

      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 🔎 Search Bar
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search products...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSubmitted: (_) => _onSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _onSearch,
                  icon: const Icon(Icons.search),
                  label: const Text("Search"),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 📦 Product List
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _products.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 120),
                              Icon(Icons.inventory_2_outlined,
                                  size: 64, color: Colors.grey),
                              SizedBox(height: 12),
                              Center(
                                child: Text("No products found",
                                    style: TextStyle(color: Colors.grey)),
                              ),
                            ],
                          )
                        : ListView.builder(
                            itemCount: _products.length,
                            itemBuilder: (context, index) {
                              final p = _products[index];
                              final stock =
                                  (p['stocks'] as List?)?.isNotEmpty == true
                                      ? p['stocks'][0]['quantity'].toString()
                                      : "0";
                              final brand = p['brand']?['name'] ?? "—";
                              final category = p['category']?['name'] ?? "—";

                              return Card(
                                margin:
                                    const EdgeInsets.symmetric(vertical: 6),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        theme.colorScheme.primaryContainer,
                                    child: Text(
                                      p['name'][0].toUpperCase(),
                                      style: TextStyle(
                                        color: theme
                                            .colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    p['name'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    "SKU: ${p['sku']} | Price: \$${p['price']} | Stock: $stock\n"
                                    "Brand: $brand | Category: $category",
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Icon(
                                    Icons.edit,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                  onTap: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            ProductFormScreen(product: p),
                                      ),
                                    );
                                    if (result == true) {
                                      _fetchProducts(reset: true);
                                    }
                                  },
                                ),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
