import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/purchase_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/purchases/purchase_create.dart';
import 'package:enterprise_pos/screens/purchases/purchase_detail.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  // Data
  List<dynamic> _purchases = [];
  List<Map<String, dynamic>> _branches = [];

  // State
  bool _loading = true;
  int _currentPage = 1;
  int _lastPage = 1;

  // Filters
  String? _selectedBranchId; // String? for Dropdown compatibility
  int? _selectedVendorId; // comes from VendorPickerSheet (int?)
  String? _selectedVendorLabel; // "First Last" for UI
  String _sortBy = "date"; // "date" | "total"
  String _searchQuery = "";

  // UI
  final TextEditingController _searchController = TextEditingController();

  // Services
  late CommonService _commonService;
  late PurchaseService _purchaseService;

  // Auth token (needed to open picker)
  late String _token;

  @override
  void initState() {
    super.initState();
    _token = Provider.of<AuthProvider>(context, listen: false).token!;
    _commonService = CommonService(token: _token);
    _purchaseService = PurchaseService(token: _token);
    _fetchInitial();
  }

  Future<void> _fetchInitial() async {
    await Future.wait([_fetchBranches(), _fetchPurchases(page: 1)]);
  }

  Future<void> _fetchBranches() async {
    final result = await _commonService.getBranches();
    setState(() => _branches = result);
  }

  Future<void> _fetchPurchases({int page = 1}) async {
    setState(() => _loading = true);
    try {
      final data = await _purchaseService.getPurchases(
        page: page,
        sortBy: _sortBy,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        branchId: _selectedBranchId != null
            ? int.tryParse(_selectedBranchId!)
            : null,
        vendorId: _selectedVendorId,
      );

      setState(() {
        _purchases = (data['data'] as List?) ?? [];
        _currentPage = data['current_page'] ?? 1;
        _lastPage = data['last_page'] ?? 1;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      // You can show a snackbar/toast here if desired
    }
  }

  Future<void> _openVendorPicker() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: VendorPickerSheet(token: _token),
      ),
    );

    // picked will be:
    //  - null => "No Vendor (Walk-in)" was chosen
    //  - Map {...} => first_name/last_name/email/phone/... of selected vendor
    setState(() {
      if (picked == null) {
        _selectedVendorId = null;
        _selectedVendorLabel = null;
      } else {
        _selectedVendorId = picked['id'] as int?;
        final first = (picked['first_name'] ?? '').toString();
        final last = (picked['last_name'] ?? '').toString();
        final full = [first, last].where((s) => s.trim().isNotEmpty).join(' ');
        _selectedVendorLabel = full.isEmpty ? 'Vendor #${picked['id']}' : full;
      }
    });

    _fetchPurchases(page: 1);
  }

  Color _chipColor(String status) {
    switch (status) {
      case 'paid':
      case 'received':
        return Colors.green;
      case 'partial':
        return Colors.orange;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Purchases"),
        actions: [
          IconButton(
            onPressed: () => _fetchPurchases(page: 1),
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh",
          ),
        ],
      ),

      // ➕ Add Purchase
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreatePurchaseScreen()),
          );
          if (created == true) _fetchPurchases(page: 1);
        },
        icon: const Icon(Icons.add),
        label: const Text("Add Purchase"),
      ),

      body: Column(
        children: [
          // Filters Row
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                // Branch filter
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _selectedBranchId,
                    hint: const Text("Filter by Branch"),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text("All Branches"),
                      ),
                      ..._branches.map(
                        (b) => DropdownMenuItem<String?>(
                          value: b['id'].toString(),
                          child: Text(b['name']),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedBranchId = val);
                      _fetchPurchases(page: 1);
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // Vendor Picker trigger
                Expanded(
                  child: InkWell(
                    onTap: _openVendorPicker,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: "Filter by Vendor",
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedVendorLabel ?? "All Vendors",
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_selectedVendorId != null)
                            IconButton(
                              tooltip: "Clear vendor",
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _selectedVendorId = null;
                                  _selectedVendorLabel = null;
                                });
                                _fetchPurchases(page: 1);
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

                // Sort
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
                    _fetchPurchases(page: 1);
                  },
                ),
              ],
            ),
          ),

          // Search box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search by Invoice or Vendor",
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = "");
                          _fetchPurchases(page: 1);
                        },
                      )
                    : null,
              ),
              onSubmitted: (val) {
                setState(() => _searchQuery = val);
                _fetchPurchases(page: 1);
              },
            ),
          ),

          const SizedBox(height: 8),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _purchases.isEmpty
                ? const Center(child: Text("No purchases found"))
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: _purchases.length,
                          itemBuilder: (_, i) {
                            final p = _purchases[i];
                            final invoice = p['invoice_no'];
                            // Backend may return vendor as {first_name, last_name, ...}
                            final vFirst = p['vendor']?['first_name'] ?? '';
                            final vLast = p['vendor']?['last_name'] ?? '';
                            final vendor =
                                ([vFirst, vLast]
                                        .where(
                                          (s) => s.toString().trim().isNotEmpty,
                                        )
                                        .join(' ')
                                        .trim())
                                    .isNotEmpty
                                ? [vFirst, vLast]
                                      .where(
                                        (s) => s.toString().trim().isNotEmpty,
                                      )
                                      .join(' ')
                                : 'N/A';

                            final branch = p['branch']?['name'] ?? "N/A";
                            final total = (p['total'] ?? 0).toString();
                            final paid = (p['paid_amount'] ?? 0).toString();

                            final payStatus = (p['status'] ?? 'pending')
                                .toString(); // pending|partial|paid
                            final recvStatus = (p['receive_status'] ?? 'ordered')
                                .toString(); // ordered|partial|received|cancelled

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
                                isThreeLine: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ), // ↑ extra height
                                title: Text(
                                  "PO: $invoice",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  "Vendor: $vendor | Branch: $branch\n"
                                  "Total: \$$total | Paid: \$$paid",
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: true,
                                ),
                                trailing: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    alignment: WrapAlignment.end,
                                    children: [
                                      Chip(
                                        label: Text(
                                          "Pay: ${payStatus.toUpperCase()}",
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        backgroundColor: _chipColor(payStatus),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        padding: EdgeInsets.zero,
                                        labelPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                      ),
                                      Chip(
                                        label: Text(
                                          "Recv: ${recvStatus.toUpperCase()}",
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        backgroundColor: _chipColor(recvStatus),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
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
                                      builder: (_) => PurchaseDetailScreen(
                                        purchaseId: p['id'],
                                      ),
                                    ),
                                  );
                                  if (result == true) {
                                    _fetchPurchases(
                                      page: _currentPage,
                                    ); // refresh sales list
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      // Pagination
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: _currentPage > 1
                                  ? () =>
                                        _fetchPurchases(page: _currentPage - 1)
                                  : null,
                              child: const Text("Previous"),
                            ),
                            const SizedBox(width: 16),
                            Text("Page $_currentPage of $_lastPage"),
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed: _currentPage < _lastPage
                                  ? () =>
                                        _fetchPurchases(page: _currentPage + 1)
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
