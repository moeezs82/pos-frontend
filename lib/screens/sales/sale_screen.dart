import 'dart:async';
import 'dart:convert';
import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/sales/sale_create.dart';
import 'package:enterprise_pos/screens/sales/sale_detail.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List<dynamic> _sales = [];
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;

  // Pagination
  int _currentPage = 1;
  int _lastPage = 1;

  // Filters
  String? _selectedBranchId;
  String _searchQuery = "";
  int? _selectedCustomerId; // comes from CustomerPickerSheet (int?)
  String? _selectedCustomerLabel; // "First Last" for UI
  String _sortBy = "date"; // date | total

  final TextEditingController _searchController = TextEditingController();

  late CommonService _commonService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _commonService = CommonService(token: token);
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    await Future.wait([_fetchSales(page: 1), _fetchBranches()]);
  }

  Future<void> _fetchSales({int page = 1}) async {
    setState(() => _loading = true);

    final globalBranchId = context.read<BranchProvider>().selectedBranchId;

    final Map<String, String> query = {
      "page": page.toString(),
      "sort_by": _sortBy,

      if (globalBranchId != null)
        "branch_id": globalBranchId.toString()
      else if (_selectedBranchId != null)
        "branch_id": _selectedBranchId!, // local filter only when global is All
      if (_selectedCustomerId != null)
        "customer_id": _selectedCustomerId!.toString(),
      if (_searchQuery.isNotEmpty) "search": _searchQuery,
    };

    final uri = Uri.parse(
      "${ApiClient.baseUrl}/sales",
    ).replace(queryParameters: query);
    final token = Provider.of<AuthProvider>(context, listen: false).token!;

    final res = await http.get(
      uri,
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() {
        _sales = data['data']['data'];
        _currentPage = data['data']['current_page'];
        _lastPage = data['data']['last_page'];
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchBranches() async {
    final result = await _commonService.getBranches();
    setState(() => _branches = result);
  }

  Future<void> _openCustomerPicker() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final picked = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: CustomerPickerSheet(token: token),
      ),
    );

    // picked will be:
    //  - null => "No Customer (Walk-in)" was chosen
    //  - Map {...} => first_name/last_name/email/phone/... of selected customer
    setState(() {
      if (picked == null) {
        _selectedCustomerId = null;
        _selectedCustomerLabel = null;
      } else {
        _selectedCustomerId = picked['id'] as int?;
        final first = (picked['first_name'] ?? '').toString();
        final last = (picked['last_name'] ?? '').toString();
        final full = [first, last].where((s) => s.trim().isNotEmpty).join(' ');
        _selectedCustomerLabel = full.isEmpty
            ? 'Customer #${picked['id']}'
            : full;
      }
    });

    _fetchSales(page: 1);
  }

  @override
  Widget build(BuildContext context) {
    final isAll = context.watch<BranchProvider>().isAll;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sales"),
        actions: [
          BranchIndicator(tappable: false),
          IconButton(
            onPressed: () => _fetchSales(page: 1),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      // ➕ Floating Add Button
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateSaleScreen()),
          );
          if (result == true) {
            _fetchSales(page: 1);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text("Add Sale"),
      ),
      body: Column(
        children: [
          // ✅ Filters + Search
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                if (isAll) ...[
                  // Local Branch filter only when global = All Branches
                  // Branch filter
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
                        _fetchSales(page: 1);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else
                  const SizedBox.shrink(),
                // Customer Picker trigger
                Expanded(
                  child: InkWell(
                    onTap: _openCustomerPicker,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: "Filter by Customer",
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedCustomerLabel ?? "All Customers",
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_selectedCustomerId != null)
                            IconButton(
                              tooltip: "Clear customer",
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _selectedCustomerId = null;
                                  _selectedCustomerLabel = null;
                                });
                                _fetchSales(page: 1);
                              },
                            )
                          else
                            const Icon(Icons.search),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Sort dropdown
                DropdownButton<String>(
                  value: _sortBy,
                  items: const [
                    DropdownMenuItem(
                      value: "date",
                      child: Text("Sort by Date"),
                    ),
                    DropdownMenuItem(
                      value: "total",
                      child: Text("Sort by Amount"),
                    ),
                  ],
                  onChanged: (val) {
                    setState(() => _sortBy = val!);
                    _fetchSales(page: 1);
                  },
                ),
              ],
            ),
          ),

          // ✅ Search box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search by Invoice or Customer",
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = "");
                          _fetchSales(page: 1);
                        },
                      )
                    : null,
              ),
              onSubmitted: (val) {
                setState(() => _searchQuery = val);
                _fetchSales(page: 1);
              },
            ),
          ),

          const SizedBox(height: 8),

          // ✅ Sales list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sales.isEmpty
                ? const Center(child: Text("No sales found"))
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: _sales.length,
                          itemBuilder: (_, i) {
                            final s = _sales[i];
                            final invoice = s['invoice_no'];
                            final customer =
                                s['customer']?['first_name'] ?? "Walk-in";
                            final branch = s['branch']?['name'] ?? "N/A";
                            final total = s['total'];
                            final status = s['status'];
                            final paid = s['paid_amount'] ?? 0;
                            final balance = s['balance'] ?? 0;

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
                                  "Invoice: $invoice",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  // "Customer: $customer | Branch: $branch\nTotal: \$${total.toString()} | Paid: \$${paid.toString()} | Balance: \$${balance.toString()}",
                                  "Customer: $customer | Branch: $branch\nTotal: \$${total.toString()} | Paid: \$${paid.toString()}",
                                ),
                                trailing: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: "Copy invoice",
                                        icon: const Icon(Icons.copy, size: 20),
                                        onPressed: () async {
                                          await Clipboard.setData(
                                            ClipboardData(
                                              text: invoice.toString(),
                                            ),
                                          );
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text("Copied: $invoice"),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 6),
                                      Chip(
                                        label: Text(
                                          status.toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        backgroundColor: status == "paid"
                                            ? Colors.green
                                            : status == "partial"
                                            ? Colors.orange
                                            : Colors.red,
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        labelPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          SaleDetailScreen(saleId: s['id']),
                                    ),
                                  );
                                  if (result == true) {
                                    _fetchSales(
                                      page: _currentPage,
                                    ); // refresh sales list
                                  }
                                },
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
                                  ? () => _fetchSales(page: _currentPage - 1)
                                  : null,
                              child: const Text("Previous"),
                            ),
                            const SizedBox(width: 16),
                            Text("Page $_currentPage of $_lastPage"),
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed: _currentPage < _lastPage
                                  ? () => _fetchSales(page: _currentPage + 1)
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
