import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../forms/vendor_form_screen.dart';

class VendorsScreen extends StatefulWidget {
  const VendorsScreen({super.key});

  @override
  State<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends State<VendorsScreen> {
  int _page = 1;
  int _lastPage = 1;
  bool _loading = false;
  String _search = "";
  final List<dynamic> _vendors = [];
  final _searchController = TextEditingController();

  late VendorService _vendorService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _vendorService = VendorService(token: token);
    _fetchVendors(reset: true);
  }

  Future<void> _fetchVendors({bool reset = false}) async {
    setState(() => _loading = true);

    if (reset) {
      _vendors.clear();
      _page = 1;
    }

    try {
      final data = await _vendorService.getVendors(
        page: _page,
        search: _search,
      );

      // 👇 adjust according to your backend pagination structure
      final wrapper = (data['data'] as List).first;
      final items = wrapper['vendors'] as List<dynamic>;

      setState(() {
        _vendors.clear();
        _vendors.addAll(items);
        _page = wrapper['current_page'];
        _lastPage = wrapper['last_page'];
      });
    } catch (e) {
      debugPrint("Error loading vendors: $e");
    }

    setState(() => _loading = false);
  }

  void _onSearch() {
    setState(() => _search = _searchController.text);
    _fetchVendors(reset: true);
  }

  Future<void> _onRefresh() async {
    await _fetchVendors(reset: true);
  }

  Future<void> _deleteVendor(int id) async {
    try {
      await _vendorService.deleteVendor(id);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vendor deleted successfully")),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to delete vendor: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Vendors"),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 8.0),
            child: BranchIndicator(tappable: false),
          ),
        ],
      ),

      // ➕ Floating Add Button
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VendorFormScreen()),
          );
          if (!mounted) return;
          if (result != null) {
            _fetchVendors(reset: true);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text("Add Vendor"),
      ),

      // 📍 Pagination Bar at Bottom
      bottomNavigationBar: _vendors.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    onPressed: _page > 1
                        ? () {
                            setState(() => _page--);
                            _fetchVendors();
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
                            _fetchVendors();
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
                      hintText: "Search vendors...",
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

            // 👥 Vendor List
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _vendors.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Icon(
                            Icons.people_outline,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 12),
                          Center(
                            child: Text(
                              "No vendors found",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        itemCount: _vendors.length,
                        itemBuilder: (context, index) {
                          final c = _vendors[index];
                          final fullName =
                              "${c['first_name']} ${c['last_name'] ?? ''}"
                                  .trim();
                          final email = c['email'] ?? "—";
                          final phone = c['phone'] ?? "—";
                          final status = c['status'] ?? "active";

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                child: Text(
                                  fullName.isNotEmpty
                                      ? fullName[0].toUpperCase()
                                      : "?",
                                  style: TextStyle(
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              title: Text(
                                fullName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                "Phone: $phone | Email: $email\nStatus: $status",
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: SizedBox(
                                width: 70,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    // ✏️ Edit
                                    GestureDetector(
                                      child: Icon(
                                        Icons.edit,
                                        size: 20,
                                        color: theme.colorScheme.primary,
                                      ),
                                      onTap: () async {
                                        final result = await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                VendorFormScreen(vendor: c),
                                          ),
                                        );
                                        if (result == true) {
                                          _fetchVendors(reset: true);
                                        }
                                      },
                                    ),
                                    const SizedBox(width: 12),
                                    // 🗑️ Delete
                                    GestureDetector(
                                      child: const Icon(
                                        Icons.delete,
                                        size: 20,
                                        color: Colors.red,
                                      ),
                                      onTap: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text("Delete Vendor"),
                                            content: Text(
                                              "Are you sure you want to delete '$fullName'?",
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text("Cancel"),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text(
                                                  "Delete",
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirm == true) {
                                          await _deleteVendor(c['id']);
                                          _fetchVendors(reset: true);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
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
