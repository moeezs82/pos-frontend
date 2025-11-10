import 'dart:async';
import 'dart:convert';
import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
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
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;

  // Pagination
  int _currentPage = 1;
  int _lastPage = 1;

  // Filters
  String? _selectedBranchId;
  Map<String, dynamic>? _selectedProduct;

  late CommonService _commonService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _commonService = CommonService(token: token);
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    await Future.wait([_fetchStocks(page: 1)]);
    // await Future.wait([_fetchStocks(page: 1), _fetchBranches()]);
  }

  Future<void> _fetchStocks({int page = 1}) async {
    setState(() => _loading = true);
    final globalBranchId = context.read<BranchProvider>().selectedBranchId;

    final query = {
      "page": page.toString(),
      // if (globalBranchId != null)
      //   "branch_id": globalBranchId.toString()
      // else if (_selectedBranchId != null)
      //   "branch_id": _selectedBranchId!, // local filter only when global is All
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

  // Future<void> _fetchBranches() async {
  //   final result = await _commonService.getBranches();
  //   setState(() => _branches = result);
  // }

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
    String? selectedBranchId = stock['branch_id'].toString();
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
              // DropdownButtonFormField<String>(
              //   value: selectedBranchId,
              //   decoration: const InputDecoration(
              //     labelText: "Branch",
              //     border: OutlineInputBorder(),
              //   ),
              //   items: _branches.map<DropdownMenuItem<String>>((b) {
              //     return DropdownMenuItem(
              //       value: b['id'].toString(),
              //       child: Text(b['name']),
              //     );
              //   }).toList(),
              //   onChanged: (val) =>
              //       setStateDialog(() => selectedBranchId = val),
              // ),
              // const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Quantity (+10 or -5)",
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
                final qty = int.tryParse(qtyController.text) ?? 0;
                if (qty != 0 &&
                    selectedProduct != null &&
                    selectedBranchId != null) {
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
                      // "branch_id": selectedBranchId!,
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

  // ✅ Transfer stock dialog
  Future<void> _transferStock(dynamic stock) async {
    final qtyController = TextEditingController();
    String? fromBranchId = stock['branch_id'].toString();
    String? toBranchId;
    Map<String, dynamic>? selectedProduct = stock['product'];

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text("Transfer Stock"),
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
              DropdownButtonFormField<String>(
                value: fromBranchId,
                decoration: const InputDecoration(
                  labelText: "From Branch",
                  border: OutlineInputBorder(),
                ),
                items: _branches.map<DropdownMenuItem<String>>((b) {
                  return DropdownMenuItem(
                    value: b['id'].toString(),
                    child: Text(b['name']),
                  );
                }).toList(),
                onChanged: (val) => setStateDialog(() => fromBranchId = val),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: toBranchId,
                decoration: const InputDecoration(
                  labelText: "To Branch",
                  border: OutlineInputBorder(),
                ),
                items: _branches.map<DropdownMenuItem<String>>((b) {
                  return DropdownMenuItem(
                    value: b['id'].toString(),
                    child: Text(b['name']),
                  );
                }).toList(),
                onChanged: (val) => setStateDialog(() => toBranchId = val),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Quantity",
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
                final qty = int.tryParse(qtyController.text) ?? 0;
                if (qty > 0 &&
                    selectedProduct != null &&
                    fromBranchId != null &&
                    toBranchId != null) {
                  final token = Provider.of<AuthProvider>(
                    context,
                    listen: false,
                  ).token!;
                  await http.post(
                    Uri.parse("${ApiClient.baseUrl}/stocks/transfer"),
                    headers: {
                      "Authorization": "Bearer $token",
                      "Accept": "application/json",
                    },
                    body: {
                      "product_id": selectedProduct!['id'].toString(),
                      "from_branch": fromBranchId!,
                      "to_branch": toBranchId!,
                      "quantity": qty.toString(),
                    },
                  );
                  Navigator.pop(context);
                  _fetchStocks(page: _currentPage);
                }
              },
              child: const Text("Transfer"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final noBranch = context.watch<BranchProvider>().isAll;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Stocks"),
        actions: [
          // BranchIndicator(tappable: false),
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
                if (noBranch)
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedBranchId,
                    hint: const Text("Filter by Branch"),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text("All Branches"), // unselect option
                      ),
                      ..._branches.map<DropdownMenuItem<String>>(
                        (b) => DropdownMenuItem(
                          value: b['id'].toString(),
                          child: Text(b['name']),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedBranchId = val);
                      _fetchStocks(page: 1);
                    },
                  ),
                ),
                const SizedBox(width: 8),
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
                            final branch = s['branch']?['name'] ?? "N/A";
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
                                // subtitle: Text("Branch: $branch | Qty: $qty"),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (val) {
                                    if (val == "adjust") _adjustStock(s);
                                    if (val == "transfer") _transferStock(s);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: "adjust",
                                      child: Text("Adjust Stock"),
                                    ),
                                    // PopupMenuItem(
                                    //   value: "transfer",
                                    //   child: Text("Transfer Stock"),
                                    // ),
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
