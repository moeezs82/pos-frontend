import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_service.dart';

class CustomerPickerSheet extends StatefulWidget {
  final String token;
  const CustomerPickerSheet({super.key, required this.token});

  @override
  State<CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<CustomerPickerSheet> {
  List<Map<String, dynamic>> _customers = [];
  int _page = 1;
  int _lastPage = 1;
  bool _loading = false;
  String _search = "";
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchCustomers(page: 1);
  }

  Future<void> _fetchCustomers({int page = 1}) async {
    setState(() => _loading = true);

    final data = await ApiService.getCustomers(
      widget.token,
      page: page,
      search: _search,
    );

    final wrapper = (data['data'] as List).first;
    final newCustomers =
        (wrapper['customers'] as List).cast<Map<String, dynamic>>();

    setState(() {
      _customers = newCustomers;
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
                hintText: "Search customer...",
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), () {
                  setState(() => _search = val);
                  _fetchCustomers(page: 1);
                });
              },
            ),
            const SizedBox(height: 12),

            // 📋 Customers list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _customers.isEmpty
                      ? const Center(child: Text("No customers found"))
                      : ListView.builder(
                          itemCount: _customers.length + 1, // +1 for deselect
                          itemBuilder: (_, i) {
                            if (i == 0) {
                              // First option = Walk-in / No Customer
                              return Card(
                                color: Colors.grey.shade200,
                                margin: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 2),
                                child: ListTile(
                                  leading: const Icon(Icons.clear,
                                      color: Colors.red),
                                  title: const Text(
                                    "No Customer (Walk-in)",
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  onTap: () => Navigator.pop(context, null),
                                ),
                              );
                            }

                            final c = _customers[i - 1];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  vertical: 4, horizontal: 2),
                              child: ListTile(
                                title: Text(
                                  "${c['first_name']} ${c['last_name'] ?? ''}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (c['email'] != null &&
                                        c['email'].toString().isNotEmpty)
                                      Text("Email: ${c['email']}"),
                                    if (c['phone'] != null &&
                                        c['phone'].toString().isNotEmpty)
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
                  onPressed:
                      _page > 1 ? () => _fetchCustomers(page: _page - 1) : null,
                  child: const Text("Previous"),
                ),
                const SizedBox(width: 16),
                Text("Page $_page of $_lastPage"),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _page < _lastPage
                      ? () => _fetchCustomers(page: _page + 1)
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
