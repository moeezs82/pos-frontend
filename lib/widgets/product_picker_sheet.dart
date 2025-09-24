import 'dart:async';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/forms/product_form_screen.dart';
import 'package:flutter/material.dart';

class ProductPickerSheet extends StatefulWidget {
  final String token;
  final int? vendorId; 

  const ProductPickerSheet({
    super.key,
    required this.token,
    this.vendorId, 
  });

  @override
  State<ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<ProductPickerSheet> {
  final List<Map<String, dynamic>> _products = [];
  int _page = 1;
  int _lastPage = 1;
  bool _loading = false;
  String _search = "";
  Timer? _debounce;

  late ProductService _productService;

  @override
  void initState() {
    super.initState();
    _productService = ProductService(token: widget.token);
    _fetchProducts(page: 1, reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _quickAddProduct() async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const ProductFormScreen(),
      ),
    );

    if (created != null && created is Map<String, dynamic>) {
      // Optimistically insert on top and return it
      setState(() => _products.insert(0, created));
      // Pop the sheet returning the created product
      Future.microtask(() => Navigator.pop(context, created));
    }
  }

  Future<void> _fetchProducts({int page = 1, bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final data = await _productService.getProducts(
        page: page,
        search: _search,
        vendorId: widget.vendorId, // ⬅️ pass vendor filter
      );

      // ==== Robust parsing (handles multiple shapes) ====
      // Expected possibilities:
      //  A) { data: { products: { data: [...], current_page, last_page } } }
      //  B) { data: [{ products: [...], current_page, last_page }] }
      //  C) { products: { data: [...], current_page, last_page } }
      //  D) { products: [...], current_page, last_page }
      //  E) { data: [...]} (already the list)
      //  F) Flat list [...]
      List<Map<String, dynamic>> newProducts = [];
      int currentPage = 1;
      int lastPage = 1;

      dynamic root = data['data'] ?? data;

      // If root is a list, pick first object that has products or treat as products
      if (root is List && root.isNotEmpty) {
        // e.g. case B
        root = root.first;
      }

      dynamic productsNode;
      if (root is Map) {
        productsNode = root['products'] ?? root['data'] ?? root;
      } else {
        productsNode = root;
      }

      if (productsNode is Map) {
        // productsNode might be a paginated object { data: [...], current_page, last_page }
        final listNode = productsNode['data'];
        if (listNode is List) {
          newProducts = listNode.cast<Map<String, dynamic>>();
        }
        currentPage = (productsNode['current_page'] ?? root['current_page'] ?? 1) as int;
        lastPage = (productsNode['last_page'] ?? root['last_page'] ?? 1) as int;
      } else if (productsNode is List) {
        newProducts = productsNode.cast<Map<String, dynamic>>();
        currentPage = (root is Map ? (root['current_page'] ?? 1) : 1) as int;
        lastPage = (root is Map ? (root['last_page'] ?? 1) : 1) as int;
      }

      setState(() {
        if (reset) {
          _products
            ..clear()
            ..addAll(newProducts);
        } else {
          _products.addAll(newProducts);
        }
        _page = currentPage;
        _lastPage = lastPage;
      });
    } catch (e) {
      // Optionally show a toast/snackbar
      // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to load products: $e")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() => _search = val.trim());
      _fetchProducts(page: 1, reset: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 🔍 Search
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Search product...",
                border: OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),

            // 📋 Products
            Expanded(
              child: _loading && _products.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _products.isEmpty
                      ? const Center(child: Text("No products found"))
                      : ListView.builder(
                          itemCount: _products.length + 2, // No product + Quick Add
                          itemBuilder: (_, i) {
                            if (i == 0) {
                              // No product
                              return Card(
                                color: Colors.grey.shade200,
                                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                child: ListTile(
                                  leading: const Icon(Icons.clear, color: Colors.red),
                                  title: const Text("-------", style: TextStyle(fontWeight: FontWeight.bold)),
                                  onTap: () => Navigator.pop(context, null),
                                ),
                              );
                            }
                            if (i == 1) {
                              // Quick Add
                              return Card(
                                color: Colors.green.shade50,
                                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                child: ListTile(
                                  leading: const Icon(Icons.add_circle, color: Colors.green),
                                  title: const Text("Quick Add New Product", style: TextStyle(fontWeight: FontWeight.bold)),
                                  onTap: _quickAddProduct,
                                ),
                              );
                            }

                            final p = _products[i - 2];
                            final category = p['category']?['name'] ?? "Uncategorized";
                            final price = p['price']?.toString() ?? "0";
                            final discount = p['discount']?.toString() ?? "0";

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              child: ListTile(
                                title: Text(p['name'] ?? "Unnamed", style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("SKU: ${p['sku'] ?? '-'}"),
                                    Text("Category: $category"),
                                    Row(
                                      children: [
                                        Text("Price: \$$price"),
                                        if (discount != "0")
                                          Padding(
                                            padding: const EdgeInsets.only(left: 8.0),
                                            child: Text(
                                              "Discount: \$$discount",
                                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                onTap: () => Navigator.pop(context, p),
                              ),
                            );
                          },
                        ),
            ),

            // ⏩ Pagination
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: !_loading && _page > 1 ? () => _fetchProducts(page: _page - 1) : null,
                  child: const Text("Previous"),
                ),
                const SizedBox(width: 16),
                Text("Page $_page of $_lastPage"),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: !_loading && _page < _lastPage ? () => _fetchProducts(page: _page + 1) : null,
                  child: const Text("Next"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
