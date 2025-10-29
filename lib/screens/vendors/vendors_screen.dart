import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/vendors/vendor_edit_screen.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../forms/vendor_form_screen.dart';

class VendorsScreen extends StatefulWidget {
  const VendorsScreen({super.key});

  @override
  State<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends State<VendorsScreen> {
  // Paging
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;

  // UI state
  bool _loading = false;
  String _search = "";
  final _searchController = TextEditingController();

  // Data
  final List<Map<String, dynamic>> _vendors = [];

  // Services
  late VendorService _vendorService;
  VoidCallback? _branchListener;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _vendorService = VendorService(token: token);

    // Refetch when branch changes
    final branchProv = Provider.of<BranchProvider>(context, listen: false);
    _branchListener = () => _fetchVendors(reset: true);
    branchProv.addListener(_branchListener!);

    _fetchVendors(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    final branchProv = Provider.of<BranchProvider>(context, listen: false);
    if (_branchListener != null) branchProv.removeListener(_branchListener!);
    super.dispose();
  }

  Future<void> _fetchVendors({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);

    if (reset) {
      _vendors.clear();
      _page = 1;
      _lastPage = 1;
      _total = 0;
    }

    try {
      final int? branchId = context.read<BranchProvider>().selectedBranchId;

      final data = await _vendorService.getVendors(
        page: _page,
        search: _search,
        includeBalance: true, // always include balances (no toggle)
        branchId: branchId,
      );

      final wrapper = (data['data'] as Map<String, dynamic>?) ?? const {};
      final items =
          (wrapper['vendors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

      setState(() {
        _vendors
          ..clear()
          ..addAll(items);
        _page = (wrapper['current_page'] as num?)?.toInt() ?? _page;
        _lastPage = (wrapper['last_page'] as num?)?.toInt() ?? _lastPage;
        _total = (wrapper['total'] as num?)?.toInt() ?? _total;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Failed to load vendors: $e")));
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _onRefresh() => _fetchVendors(reset: true);

  void _onSearchSubmit() {
    setState(() => _search = _searchController.text.trim());
    _fetchVendors(reset: true);
  }

  Future<void> _deleteVendor(int id) async {
    try {
      await _vendorService.deleteVendor(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Vendor deleted")));
      _fetchVendors(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Delete failed: $e")));
    }
  }

  String _money(num? v) => (v ?? 0).toStringAsFixed(2);
  String _initials(String? first, String? last) {
    final a = (first ?? '').trim();
    final b = (last ?? '').trim();
    final s = ((a.isNotEmpty ? a[0] : '') + (b.isNotEmpty ? b[0] : '')).toUpperCase();
    return s.isEmpty ? '?' : s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSubtle = theme.textTheme.bodySmall?.color?.withOpacity(0.75);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Vendors"),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8.0),
            child: BranchIndicator(tappable: false),
          ),
        ],
      ),

      // FAB docked like customers
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VendorFormScreen()),
          );
          if (result == true) _fetchVendors(reset: true);
        },
        child: const Icon(Icons.add),
      ),

      // Pagination bar
      bottomNavigationBar: _vendors.isNotEmpty
          ? BottomAppBar(
              shape: const CircularNotchedRectangle(),
              notchMargin: 6,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Total: $_total",
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text("Page $_page / $_lastPage",
                          style: TextStyle(color: onSubtle)),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _page > 1 && !_loading
                                ? () {
                                    setState(() => _page--);
                                    _fetchVendors();
                                  }
                                : null,
                            icon: const Icon(Icons.chevron_left),
                            label: const Text("Previous"),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _page < _lastPage && !_loading
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
                    ],
                  ),
                ),
              ),
            )
          : null,

      body: Column(
        children: [
          // Slim search
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: "Search name, phone, email…",
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onSubmitted: (_) => _onSearchSubmit(),
            ),
          ),
          const Divider(height: 1),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _vendors.isEmpty
                    ? const _EmptyState(
                        title: "No vendors",
                        subtitle: "Add a vendor or switch branch.",
                      )
                    : RefreshIndicator(
                        onRefresh: _onRefresh,
                        child: ListView.separated(
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: _vendors.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final v = _vendors[i];
                            final first = (v['first_name'] ?? '') as String;
                            final last = (v['last_name'] ?? '') as String;
                            final fullName = "$first $last".trim();
                            final email = v['email'] ?? '—';
                            final phone = v['phone'] ?? '—';
                            final status = (v['status'] ?? 'active').toString();

                            final num balance = (v['balance'] as num?) ?? 0;
                            final num totPurch = (v['total_purchases'] as num?) ?? 0;
                            final num totPay   = (v['total_payments'] as num?) ?? 0;
                            final String? lastActivity = v['last_activity_at'] as String?;

                            // Gentle color hint for balance (AP: positive → we owe)
                            Color balColor = theme.textTheme.bodyLarge?.color ?? Colors.black;
                            if (balance > 0)      balColor = Colors.orange.shade800;
                            else if (balance < 0) balColor = Colors.green.shade800;
                            else                  balColor = onSubtle ?? Colors.grey;

                            return ListTile(
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: theme.colorScheme.primaryContainer,
                                child: Text(
                                  _initials(first, last),
                                  style: TextStyle(
                                    color: theme.colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      fullName.isEmpty ? "(No name)" : fullName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ),
                                  _StatusDot(status: status),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Phone: $phone  •  Email: $email",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: onSubtle, fontSize: 12),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Text("Bal: ",
                                            style: TextStyle(color: onSubtle, fontSize: 12)),
                                        Text(_money(balance),
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                              color: balColor,
                                            )),
                                        const SizedBox(width: 10),
                                        Text("Purchases: ${_money(totPurch)}",
                                            style: TextStyle(color: onSubtle, fontSize: 12)),
                                        const SizedBox(width: 10),
                                        Text("Payments: ${_money(totPay)}",
                                            style: TextStyle(color: onSubtle, fontSize: 12)),
                                        if (lastActivity != null && lastActivity.isNotEmpty)
                                          Expanded(
                                            child: Text(
                                              "  •  Last: $lastActivity",
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(color: onSubtle, fontSize: 12),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              trailing: PopupMenuButton<String>(
                                tooltip: "Actions",
                                onSelected: (vMenu) async {
                                  if (vMenu == 'edit') {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => VendorFormScreen(vendor: v),
                                      ),
                                    );
                                    if (result == true) _fetchVendors(reset: true);
                                  }
                                  if (vMenu == 'delete') {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text("Delete Vendor"),
                                        content: Text(
                                          "Delete '${fullName.isEmpty ? 'this vendor' : fullName}'?",
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text("Cancel"),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text("Delete",
                                                style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await _deleteVendor(v['id'] as int);
                                      _fetchVendors(reset: true);
                                    }
                                  }
                                },
                                itemBuilder: (ctx) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: ListTile(
                                      dense: true,
                                      leading: Icon(Icons.edit_rounded, size: 18),
                                      title: Text("Edit"),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      dense: true,
                                      leading: Icon(Icons.delete_rounded,
                                          size: 18, color: Colors.red),
                                      title: Text("Delete"),
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => VendorEditScreen(vendorId: v['id']),
                                    // builder: (_) => VendorFormScreen(vendor: v),
                                  ),
                                );
                                _fetchVendors(reset: true);
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/* ---------------------------- Small widgets ---------------------------- */

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color c;
    if (s == 'active') c = Colors.green;
    else if (s == 'inactive' || s == 'blocked') c = Colors.red;
    else c = Colors.grey;
    return Icon(Icons.circle, size: 8, color: c);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = theme.textTheme.bodySmall?.color?.withOpacity(0.75);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 54, color: sub),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: sub)),
          ],
        ),
      ),
    );
  }
}
