import 'dart:async';
import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/forms/vendor_form_screen.dart';
import 'package:flutter/material.dart';

class VendorPickerSheet extends StatefulWidget {
  final String token;
  const VendorPickerSheet({super.key, required this.token});

  @override
  State<VendorPickerSheet> createState() => _VendorPickerSheetState();
}

class _VendorPickerSheetState extends State<VendorPickerSheet> {
  List<Map<String, dynamic>> _vendors = [];
  int _page = 1;
  int _lastPage = 1;
  bool _loading = false;
  String _search = "";
  Timer? _debounce;

  late VendorService _vendorService;

  @override
  void initState() {
    super.initState();
    _vendorService = VendorService(token: widget.token);
    _fetchVendors(page: 1);
  }

  Future<void> _fetchVendors({int page = 1}) async {
    setState(() => _loading = true);

    final data = await _vendorService.getVendors(
      page: page,
      search: _search,
    );

    // your vendor API format:
    // res = { data: [ { vendors: [...], current_page: x, last_page: y } ] }
    final wrapper = data['data'];
    final newVendors = (wrapper['vendors'] as List).cast<Map<String, dynamic>>();

    setState(() {
      _vendors = newVendors;
      _page = wrapper['current_page'];
      _lastPage = wrapper['last_page'];
      _loading = false;
    });
  }

  Future<void> _quickAddVendor() async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const VendorFormScreen(),
      ),
    );

    if (created != null && created is Map<String, dynamic>) {
      setState(() {
        _vendors.insert(0, created);
      });
      // Return newly created vendor to caller
      Future.microtask(() => Navigator.pop(context, created));
    }
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
                hintText: "Search vendor...",
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), () {
                  setState(() => _search = val);
                  _fetchVendors(page: 1);
                });
              },
            ),
            const SizedBox(height: 12),

            // ✅ Always-visible actions (outside the vendor list)
            Column(
              children: [
                Card(
                  color: Colors.grey.shade200,
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: ListTile(
                    leading: const Icon(Icons.clear, color: Colors.red),
                    title: const Text(
                      "No Vendor (Walk-in)",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () => Navigator.pop(context, null),
                  ),
                ),
                Card(
                  color: Colors.green.shade50,
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: ListTile(
                    leading: const Icon(Icons.add_circle, color: Colors.green),
                    title: const Text(
                      "Quick Add New Vendor",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: _quickAddVendor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // 📋 Vendors list (only fetched records)
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _vendors.isEmpty
                      ? const Center(child: Text("No vendors found"))
                      : ListView.builder(
                          itemCount: _vendors.length,
                          itemBuilder: (_, i) {
                            final c = _vendors[i];
                            final first = (c['first_name'] ?? '').toString();
                            final last  = (c['last_name'] ?? '').toString();
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                              child: ListTile(
                                title: Text(
                                  "$first ${last.isNotEmpty ? last : ''}".trim(),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if ((c['email'] ?? '').toString().isNotEmpty)
                                      Text("Email: ${c['email']}"),
                                    if ((c['phone'] ?? '').toString().isNotEmpty)
                                      Text("Phone: ${c['phone']}"),
                                  ],
                                ),
                                onTap: () => Navigator.pop(context, c),
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
                  onPressed: _page > 1 ? () => _fetchVendors(page: _page - 1) : null,
                  child: const Text("Previous"),
                ),
                const SizedBox(width: 16),
                Text("Page $_page of $_lastPage"),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _page < _lastPage ? () => _fetchVendors(page: _page + 1) : null,
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
