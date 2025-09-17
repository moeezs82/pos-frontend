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
  bool _loading = false;
  bool _hasMore = true;
  String _search = "";
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100) {
        if (!_loading && _hasMore) {
          _page++;
          _fetchProducts();
        }
      }
    });
  }

  Future<void> _fetchProducts({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _products.clear();
      _hasMore = true;
    }
    if (!_hasMore) return;

    setState(() => _loading = true);
    final data = await ApiService.getProducts(widget.token, page: _page, search: _search);
    final wrapper = (data['data'] as List).first;
      // final newProducts = wrapper['products'] as List<dynamic>;
    final newProducts = (wrapper['products'] as List).cast<Map<String, dynamic>>();
    setState(() {
      _products.addAll(newProducts);
      _hasMore = newProducts.isNotEmpty;
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
                  _fetchProducts(reset: true);
                });
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _products.length + 1,
                itemBuilder: (_, i) {
                  if (i == _products.length) {
                    return _loading
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()))
                        : const SizedBox.shrink();
                  }
                  final p = _products[i];
                  return ListTile(
                    title: Text(p['name']),
                    subtitle: Text("SKU: ${p['sku']}"),
                    onTap: () => Navigator.pop(context, p),
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

