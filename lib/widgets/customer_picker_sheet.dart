import 'dart:async';
import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/forms/customer_form_screen.dart';
import 'package:flutter/material.dart';

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

  late CustomerService _customerService;

  @override
  void initState() {
    super.initState();
    _customerService = CustomerService(token: widget.token);
    _fetchCustomers(page: 1);
  }

  Future<void> _fetchCustomers({int page = 1}) async {
    setState(() => _loading = true);

    final data = await _customerService.getCustomers(
      page: page,
      search: _search,
    );

    final wrapper = (data['data'] as List).first;
    final newCustomers = (wrapper['customers'] as List)
        .cast<Map<String, dynamic>>();

    setState(() {
      _customers = newCustomers;
      _page = wrapper['current_page'];
      _lastPage = wrapper['last_page'];
      _loading = false;
    });
  }

  Future<void> _quickAddCustomer() async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CustomerFormScreen(),
      ),
    );

    if (created != null && created is Map<String, dynamic>) {
      setState(() {
        _customers.insert(0, created); // 👈 add at the top
      });
      // // Delay the pop until after the current frame
      Future.microtask(() {
        Navigator.pop(context, created);
      });
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
                      itemCount:
                          _customers.length + 2, // +1 Walk-in, +1 Quick Add
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          // First option = Walk-in / No Customer
                          return Card(
                            color: Colors.grey.shade200,
                            margin: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 2,
                            ),
                            child: ListTile(
                              leading: const Icon(
                                Icons.clear,
                                color: Colors.red,
                              ),
                              title: const Text(
                                "No Customer (Walk-in)",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              onTap: () => Navigator.pop(context, null),
                            ),
                          );
                        }

                        if (i == 1) {
                          // Last option = Quick Add
                          return Card(
                            color: Colors.green.shade50,
                            margin: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 2,
                            ),
                            child: ListTile(
                              leading: const Icon(
                                Icons.add_circle,
                                color: Colors.green,
                              ),
                              title: const Text(
                                "Quick Add New Customer",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              onTap: _quickAddCustomer,
                            ),
                          );
                        }

                        final c = _customers[i - 2];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 2,
                          ),
                          child: ListTile(
                            title: Text(
                              "${c['first_name']} ${c['last_name'] ?? ''}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
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
                  onPressed: _page > 1
                      ? () => _fetchCustomers(page: _page - 1)
                      : null,
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
