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
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

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

    // Auto focus search
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });

    _fetchCustomers(page: 1);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _fetchCustomers({required int page, bool replace = true}) async {
    setState(() => _loading = true);

    final data = await _customerService.getCustomers(
      page: page,
      search: _search,
    );

    final wrapper = data['data'];
    final newCustomers = (wrapper['customers'] as List)
        .cast<Map<String, dynamic>>();
    final lastPage = (wrapper['last_page'] ?? 1) as int;

    if (!mounted) return;
    setState(() {
      if (replace) {
        _customers = newCustomers;
      } else {
        _customers.addAll(newCustomers);
      }
      _page = page; // ← set to requested page
      _lastPage = lastPage;
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
      if (!mounted) return;
      setState(() => _customers.insert(0, created));
      Future.microtask(() => Navigator.pop(context, created));
    }
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      setState(() => _search = val.trim());
      _fetchCustomers(page: 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final denseTile = const EdgeInsets.symmetric(horizontal: 8, vertical: 6);
    final visualDense = const VisualDensity(horizontal: -2, vertical: -3);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomInset),
        child: Column(
          children: [
            // Title + Close (tight)
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Select Customer",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 20,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Search (isDense + autofocus)
            TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _fetchCustomers(page: 1),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: (_searchCtrl.text.isNotEmpty)
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged("");
                        },
                      )
                    : null,
                hintText: "Search customer…",
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Quick options (no cards, just light containers)
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: ListTile(
                dense: true,
                visualDensity: visualDense,
                contentPadding: denseTile,
                leading: const Icon(
                  Icons.person_off_outlined,
                  color: Colors.red,
                ),
                title: const Text(
                  "No Customer (Walk-in)",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () => Navigator.pop(context, null),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: ListTile(
                dense: true,
                visualDensity: visualDense,
                contentPadding: denseTile,
                leading: const Icon(
                  Icons.person_add_alt_1_outlined,
                  color: Colors.green,
                ),
                title: const Text(
                  "Quick Add",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: _quickAddCustomer,
              ),
            ),

            const SizedBox(height: 8),

            // List (dense tiles + simple dividers)
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _customers.isEmpty
                  ? const Center(child: Text("No customers found"))
                  : ListView.separated(
                      itemCount: _customers.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: 0.6,
                        color: Theme.of(context).dividerColor.withOpacity(0.6),
                      ),
                      itemBuilder: (_, i) {
                        final c = _customers[i];
                        final first = (c['first_name'] ?? '').toString();
                        final last = (c['last_name'] ?? '').toString();
                        final name = "$first ${last.isNotEmpty ? last : ''}"
                            .trim();
                        final email = (c['email'] ?? '').toString();
                        final phone = (c['phone'] ?? '').toString();

                        return ListTile(
                          dense: true,
                          visualDensity: visualDense,
                          contentPadding: denseTile,
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Row(
                            children: [
                              if (email.isNotEmpty)
                                Expanded(
                                  child: Text(
                                    email,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (email.isNotEmpty && phone.isNotEmpty)
                                const SizedBox(width: 8),
                              if (phone.isNotEmpty) Text(phone),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
            ),

            // Pagination (compact)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: !_loading && _page > 1
                      ? () => _fetchCustomers(page: _page - 1)
                      : null,
                  child: const Text("Prev"),
                ),
                const SizedBox(width: 8),
                Text(
                  "$_page / $_lastPage",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: !_loading && _page < _lastPage
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
