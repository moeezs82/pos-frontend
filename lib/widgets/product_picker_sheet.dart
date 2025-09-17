import 'package:flutter/material.dart';
import 'dart:async';

import '../services/api_service.dart'; // adjust path

class ProductPickerSheet extends StatefulWidget {
  final String token;
  const ProductPickerSheet({super.key, required this.token});

  @override
  State<ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<ProductPickerSheet> {
  List<Map<String, dynamic>> _products = [];
  int _page = 1;
  int _lastPage = 1;
  bool _loading = false;
  String _search = "";
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchProducts(page: 1);
  }

  Future<void> _fetchProducts({int page = 1}) async {
    setState(() => _loading = true);

    final data = await ApiService.getProducts(
      widget.token,
      page: page,
      search: _search,
    );

    final wrapper = (data['data'] as List).first;
    final newProducts = (wrapper['products'] as List)
        .cast<Map<String, dynamic>>();

    setState(() {
      _products = newProducts;
      _page = wrapper['current_page'];
      _lastPage = wrapper['last_page'];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 🔍 Search bar
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Search product...",
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), () {
                  setState(() => _search = val);
                  _fetchProducts(page: 1);
                });
              },
            ),
            const SizedBox(height: 12),

            // 📋 Products list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _products.isEmpty
                  ? const Center(child: Text("No products found"))
                  : ListView.builder(
                      itemCount: _products.length + 1,
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          // First option = Walk-in / No Customer
                          return Card(
                            color: Colors.grey.shade200,
                            margin: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 2,
                            ),
                            child: ListTile(
                              leading: const Icon(
                                Icons.clear,
                                color: Colors.red,
                              ),
                              title: const Text(
                                "-------",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              onTap: () => Navigator.pop(context, null),
                            ),
                          );
                        }

                        final p = _products[i-1];
                        final category =
                            p['category']?['name'] ?? "Uncategorized";
                        final price = p['price']?.toString() ?? "0";
                        final discount = p['discount']?.toString() ?? "0";

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            title: Text(
                              p['name'] ?? "Unnamed",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                                        padding: const EdgeInsets.only(
                                          left: 8.0,
                                        ),
                                        child: Text(
                                          "Discount: \$$discount",
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.w500,
                                          ),
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

            // ⏩ Pagination controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _page > 1
                      ? () => _fetchProducts(page: _page - 1)
                      : null,
                  child: const Text("Previous"),
                ),
                const SizedBox(width: 16),
                Text("Page $_page of $_lastPage"),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _page < _lastPage
                      ? () => _fetchProducts(page: _page + 1)
                      : null,
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
