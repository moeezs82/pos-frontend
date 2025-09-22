import 'dart:convert';
import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/purchases/purchase_claim_create.dart';
import 'package:enterprise_pos/screens/purchases/purchase_claim_detail.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

class PurchaseClaimsScreen extends StatefulWidget {
  const PurchaseClaimsScreen({super.key});

  @override
  State<PurchaseClaimsScreen> createState() => _PurchaseClaimsScreenState();
}

class _PurchaseClaimsScreenState extends State<PurchaseClaimsScreen> {
  List<dynamic> _claims = [];
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;

  // Pagination
  int _currentPage = 1;
  int _lastPage = 1;

  // Filters
  String? _selectedBranchId;
  String _searchQuery = "";

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
    await Future.wait([_fetchClaims(page: 1), _fetchBranches()]);
  }

  Future<void> _fetchClaims({int page = 1}) async {
    setState(() => _loading = true);

    final globalBranchId = context.read<BranchProvider>().selectedBranchId;

    final query = {
      "page": page.toString(),
      if (globalBranchId != null)
        "branch_id": globalBranchId.toString()
      else if (_selectedBranchId != null)
        "branch_id": _selectedBranchId!, // local filter only when global is All
      if (_searchQuery.isNotEmpty) "search": _searchQuery,
    };

    final uri = Uri.parse(
      "${ApiClient.baseUrl}/purchase-claims",
    ).replace(queryParameters: query);
    final token = Provider.of<AuthProvider>(context, listen: false).token!;

    final res = await http.get(
      uri,
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() {
        _claims = data['data']['data'];
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

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      case 'closed':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final noBranch = context.watch<BranchProvider>().isAll;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Purchase Claims"),
        actions: [
          BranchIndicator(tappable: false),
          IconButton(
            onPressed: () => _fetchClaims(page: 1),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CreatePurchaseClaimScreen(),
            ),
          );
          if (result == true) {
            _fetchClaims(page: 1);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text("New Claim"),
      ),

      body: Column(
        children: [
          if (noBranch) ...[
            // ✅ Filters + Search
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  // Branch filter (kept consistent with your existing pattern)
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
                          child: Text("All Branches"),
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
                        _fetchClaims(page: 1);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ] else
            const SizedBox.shrink(),

          // ✅ Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search by Claim No or Invoice",
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = "");
                          _fetchClaims(page: 1);
                        },
                      )
                    : null,
              ),
              onSubmitted: (val) {
                setState(() => _searchQuery = val);
                _fetchClaims(page: 1);
              },
            ),
          ),

          const SizedBox(height: 8),

          // ✅ Claims list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _claims.isEmpty
                ? const Center(child: Text("No purchase claims found"))
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: _claims.length,
                          itemBuilder: (_, i) {
                            final c = _claims[i];

                            final claimNo = c['claim_no'];
                            final status = (c['status'] ?? '').toString();
                            final total = c['total'] ?? 0;

                            final vendor =
                                c['purchase']?['vendor']?['first_name'] ??
                                "N/A";
                            final invoice =
                                c['purchase']?['invoice_no'] ?? "N/A";
                            final branch = c['branch']?['name'] ?? "N/A";

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
                                  "Claim: $claimNo",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  "Invoice: $invoice | Vendor: $vendor | Branch: $branch\nTotal: \$${total.toString()}",
                                ),
                                trailing: Chip(
                                  label: Text(
                                    status.toUpperCase(),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  backgroundColor: _statusColor(status),
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PurchaseClaimDetailScreen(
                                        claimId: c['id'],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      // ✅ Pagination
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: _currentPage > 1
                                  ? () => _fetchClaims(page: _currentPage - 1)
                                  : null,
                              child: const Text("Previous"),
                            ),
                            const SizedBox(width: 16),
                            Text("Page $_currentPage of $_lastPage"),
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed: _currentPage < _lastPage
                                  ? () => _fetchClaims(page: _currentPage + 1)
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
