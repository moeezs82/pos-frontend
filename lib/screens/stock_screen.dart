import 'dart:convert';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../widgets/product_picker_sheet.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List<dynamic> _stocks = [];
  bool _loading = true;

  // Pagination
  int _currentPage = 1;
  int _lastPage = 1;

  // Filters
  Map<String, dynamic>? _selectedProduct;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    await Future.wait([_fetchStocks(page: 1)]);
  }

  Future<void> _fetchStocks({int page = 1}) async {
    setState(() => _loading = true);
    final query = {
      "page": page.toString(),
      if (_selectedProduct != null)
        "product_id": _selectedProduct!['id'].toString(),
    };

    final uri = Uri.parse(
      "${ApiClient.baseUrl}/stocks",
    ).replace(queryParameters: query);
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final res = await http.get(
      uri,
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() {
        _stocks = data['data']['data'];
        _currentPage = data['data']['current_page'];
        _lastPage = data['data']['last_page'];
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  // ✅ Product picker bottom sheet
  Future<Map<String, dynamic>?> _pickProduct(BuildContext context) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final product = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProductPickerSheet(token: token),
    );
    if (product == null) {
      setState(() {
        _selectedProduct = null;
      });
    } else {
      return product;
    }
    // return showModalBottomSheet<Map<String, dynamic>>(
    //   context: context,
    //   isScrollControlled: true,
    //   builder: (_) => ProductPickerSheet(token: token),
    // );
  }

  // ✅ Adjust stock dialog
  Future<void> _adjustStock(dynamic stock) async {
    final qtyController = TextEditingController();
    Map<String, dynamic>? selectedProduct = stock['product'];

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text("Adjust Stock"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () async {
                  final p = await _pickProduct(context);
                  if (p != null) {
                    setStateDialog(() => selectedProduct = p);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: "Product",
                    border: OutlineInputBorder(),
                  ),
                  child: Text(selectedProduct?['name'] ?? "Select Product"),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(
                  labelText: "Quantity (+10 or -5, decimals allowed)",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final qty = double.tryParse(qtyController.text) ?? 0.0;
                if (qty != 0 && selectedProduct != null) {
                  final token = Provider.of<AuthProvider>(
                    context,
                    listen: false,
                  ).token!;
                  await http.post(
                    Uri.parse("${ApiClient.baseUrl}/stocks/adjust"),
                    headers: {
                      "Authorization": "Bearer $token",
                      "Accept": "application/json",
                    },
                    body: {
                      "product_id": selectedProduct!['id'].toString(),
                      "quantity": qty.toString(),
                      "reason": "manual adjustment",
                    },
                  );
                  Navigator.pop(context);
                  _fetchStocks(page: _currentPage);
                }
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Stocks"),
        actions: [
          const BranchIndicator(tappable: false),
          IconButton(
            onPressed: () => _fetchStocks(page: 1),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // ✅ Filters
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final p = await _pickProduct(context);
                      if (p != null) {
                        setState(() => _selectedProduct = p);
                        _fetchStocks(page: 1);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: "Filter by Product",
                        border: OutlineInputBorder(),
                      ),
                      child: Text(_selectedProduct?['name'] ?? "Select"),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _stocks.isEmpty
                ? const Center(child: Text("No stock found"))
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: _stocks.length,
                          itemBuilder: (_, i) {
                            final s = _stocks[i];
                            final product = s['product']?['name'] ?? "Unknown";
                            final qty = s['quantity'];

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                              child: ListTile(
                                title: Text(
                                  product,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text("Qty: $qty"),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (val) {
                                    if (val == "adjust") _adjustStock(s);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: "adjust",
                                      child: Text("Adjust Stock"),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // ✅ Pagination controls
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: _currentPage > 1
                                  ? () => _fetchStocks(page: _currentPage - 1)
                                  : null,
                              child: const Text("Previous"),
                            ),
                            const SizedBox(width: 16),
                            Text("Page $_currentPage of $_lastPage"),
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed: _currentPage < _lastPage
                                  ? () => _fetchStocks(page: _currentPage + 1)
                                  : null,
                              child: const Text("Next"),
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
