import 'dart:async';
import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/forms/customer_form_screen.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CustomerPickerSheet extends StatefulWidget {
  final String token;
  const CustomerPickerSheet({super.key, required this.token});

  @override
  State<CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<CustomerPickerSheet> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _money = const AppMoneyFormatter();

  List<Map<String, dynamic>> _customers = [];
  int _page = 1;
  int _lastPage = 1;
  // _loading now only ever drives a thin top progress bar — it never gates
  // showing the list, since we always have *something* (cache) to show
  // instantly. true on the very first ever load (no cache at all yet).
  bool _loading = false;
  bool _silentRefreshing = false;
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

    // Cache-first: paint whatever we already have instantly (could be from
    // a prefetch fired when the sale screen opened, or a previous picker
    // open this session), then always kick a silent refresh per product
    // decision — never trust the cache blindly, but never block on it
    // either.
    final cached = CustomerPickCache.cache.peek(CustomerPickCache.keyFor());
    if (cached != null) {
      _customers = cached.items;
      _page = cached.currentPage;
      _lastPage = cached.lastPage;
    } else {
      _loading = true; // nothing to show at all yet — only true blocking case
    }
    _fetchCustomers(page: 1, silent: cached != null);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _fetchCustomers({required int page, bool replace = true, bool silent = false}) async {
    if (silent) {
      setState(() => _silentRefreshing = true);
    } else {
      setState(() => _loading = true);
    }

    try {
      if (_search.isEmpty) {
        // Unfiltered fetch — this is the "main" bucket every other screen
        // and autocomplete field reads via peek(). Safe to store directly.
        final entry = await CustomerPickCache.cache.refresh(
          CustomerPickCache.keyFor(),
          () => CustomerPickCache.fetchPage(_customerService, page: page, search: _search),
          requestKey: '${CustomerPickCache.keyFor()}::$_search::$page',
        );

        if (!mounted) return;
        setState(() {
          if (replace) {
            _customers = entry.items;
          } else {
            _customers.addAll(entry.items);
          }
          _page = entry.currentPage;
          _lastPage = entry.lastPage;
        });
      } else {
        // Filtered (search) fetch — results are specific to this query and
        // must NOT overwrite the shared "all customers" bucket, or every
        // other screen reading that bucket would start seeing only this
        // search's results. Fetch via the service directly and apply only
        // to this sheet's local list.
        final entry = await CustomerPickCache.fetchPage(_customerService, page: page, search: _search);
        if (!mounted) return;
        setState(() {
          if (replace) {
            _customers = entry.items;
          } else {
            _customers.addAll(entry.items);
          }
          _page = entry.currentPage;
          _lastPage = entry.lastPage;
        });
      }
    } catch (_) {
      // Silent refresh failing is fine — keep showing whatever we had.
      // A non-silent (first ever, no-cache) failure surfaces as empty list,
      // same as before.
    } finally {
      if (mounted) setState(() {
        _loading = false;
        _silentRefreshing = false;
      });
    }
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
      CustomerPickCache.cache.insertEverywhere(
        created,
        matchesExisting: (c) => c['id']?.toString() == created['id']?.toString(),
      );
      Future.microtask(() => Navigator.pop(context, created));
    }
  }

  void _onSearchChanged(String val) {
    final query = val.trim();

    // Instant local filter against whatever is cached right now — no
    // waiting for debounce or network for the common "type a few letters"
    // case.
    final cached = CustomerPickCache.cache.peek(CustomerPickCache.keyFor());
    if (cached != null) {
      final q = query.toLowerCase();
      final filtered = q.isEmpty
          ? cached.items
          : cached.items.where((c) {
              final name = "${c['first_name'] ?? ''} ${c['last_name'] ?? ''}".toLowerCase();
              final phone = (c['phone'] ?? '').toString().toLowerCase();
              final email = (c['email'] ?? '').toString().toLowerCase();
              return name.contains(q) || phone.contains(q) || email.contains(q);
            }).toList();
      setState(() => _customers = filtered);
    }

    // Background network search still runs (debounced) to catch matches
    // outside the cached page/dataset, and to keep the cache itself fresh
    // for this query.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _search = query);
      _fetchCustomers(page: 1, silent: cached != null);
    });
  }

  num _balanceOf(Map<String, dynamic> c) {
    final raw = c['balance'];
    if (raw is num) return raw;
    return num.tryParse(raw?.toString() ?? '0') ?? 0;
  }

  /// Customer ledger convention: balance > 0 means the customer owes money
  /// (accounts receivable); balance < 0 means they're in credit (overpaid).
  Widget _balanceChip(num balance) {
    if (balance == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.surfaceSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Text(
          'Settled',
          style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700, fontSize: 11),
        ),
      );
    }

    final owes = balance > 0;
    final color = owes ? AppTheme.danger : AppTheme.success;
    final label = owes ? 'Owes' : 'Credit';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Text(
        '$label ${_money.format(balance.abs())}',
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
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
                if (_silentRefreshing)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
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
              child: (_loading && _customers.isEmpty)
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
                        final balance = _balanceOf(c);

                        return ListTile(
                          dense: true,
                          visualDensity: visualDense,
                          contentPadding: denseTile,
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _balanceChip(balance),
                            ],
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
