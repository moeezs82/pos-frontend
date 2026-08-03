import 'dart:async';
import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/forms/vendor_form_screen.dart';
import 'package:enterprise_pos/services/pick_cache.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:intl/intl.dart';

class VendorPickerSheet extends StatefulWidget {
  final String token;
  const VendorPickerSheet({super.key, required this.token});

  @override
  State<VendorPickerSheet> createState() => _VendorPickerSheetState();
}

class _VendorPickerSheetState extends State<VendorPickerSheet> {
  final _money = const AppMoneyFormatter();

  List<Map<String, dynamic>> _vendors = [];
  int _page = 1;
  int _lastPage = 1;
  bool _loading = false; // only true blocking case: zero cache on first ever open
  bool _silentRefreshing = false;
  String _search = "";
  Timer? _debounce;

  late VendorService _vendorService;

  @override
  void initState() {
    super.initState();
    _vendorService = VendorService(token: widget.token);

    // Cache-first: instantly paint whatever we already have (from a
    // background prefetch or a prior picker open this session).
    final cached = VendorPickCache.cache.peek(VendorPickCache.keyFor());
    if (cached != null) {
      _vendors = cached.items;
      _page = cached.currentPage;
      _lastPage = cached.lastPage;
    } else {
      _loading = true;
    }
    _fetchVendors(page: 1, silent: cached != null);
  }

  Future<void> _fetchVendors({int page = 1, bool silent = false}) async {
    if (silent) {
      setState(() => _silentRefreshing = true);
    } else {
      setState(() => _loading = true);
    }

    try {
      PickCacheEntry<Map<String, dynamic>> entry;
      if (_search.isEmpty) {
        // Unfiltered fetch — safe to store in the shared bucket that other
        // screens/autocomplete fields read via peek().
        entry = await VendorPickCache.cache.refresh(
          VendorPickCache.keyFor(),
          () => VendorPickCache.fetchPage(_vendorService, page: page, search: _search),
          requestKey: '${VendorPickCache.keyFor()}::$_search::$page',
        );
      } else {
        // Filtered (search) fetch — must not overwrite the shared bucket,
        // or every other vendor field would start showing only this
        // search's results. Apply locally to this sheet only.
        entry = await VendorPickCache.fetchPage(_vendorService, page: page, search: _search);
      }

      if (!mounted) return;
      setState(() {
        _vendors = entry.items;
        _page = entry.currentPage;
        _lastPage = entry.lastPage;
      });
    } catch (_) {
      // Keep showing whatever was already on screen.
    } finally {
      if (mounted) setState(() {
        _loading = false;
        _silentRefreshing = false;
      });
    }
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
      VendorPickCache.cache.insertEverywhere(
        created,
        matchesExisting: (v) => v['id']?.toString() == created['id']?.toString(),
      );
      // Return newly created vendor to caller
      Future.microtask(() => Navigator.pop(context, created));
    }
  }

  num _balanceOf(Map<String, dynamic> v) {
    final raw = v['balance'] ?? v['trade_balance'];
    if (raw is num) return raw;
    return num.tryParse(raw?.toString() ?? '0') ?? 0;
  }

  /// Vendor ledger convention: balance > 0 means we owe the vendor money
  /// (accounts payable); balance < 0 means we've overpaid (an advance).
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

    final payable = balance > 0;
    final color = payable ? AppTheme.warning : AppTheme.success;
    final label = payable ? 'Payable' : 'Advance';

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

  void _onSearchChanged(String val) {
    final query = val.trim();

    final cached = VendorPickCache.cache.peek(VendorPickCache.keyFor());
    if (cached != null) {
      final q = query.toLowerCase();
      final filtered = q.isEmpty
          ? cached.items
          : cached.items.where((v) {
              final name = "${v['first_name'] ?? ''} ${v['last_name'] ?? ''}".toLowerCase();
              final phone = (v['phone'] ?? '').toString().toLowerCase();
              final email = (v['email'] ?? '').toString().toLowerCase();
              return name.contains(q) || phone.contains(q) || email.contains(q);
            }).toList();
      setState(() => _vendors = filtered);
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _search = query);
      _fetchVendors(page: 1, silent: cached != null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 🔍 Search bar (instant local filter + debounced network refine)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: "Search vendor...",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                if (_silentRefreshing)
                  const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
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
              child: (_loading && _vendors.isEmpty)
                  ? const Center(child: CircularProgressIndicator())
                  : _vendors.isEmpty
                      ? const Center(child: Text("No vendors found"))
                      : ListView.builder(
                          itemCount: _vendors.length,
                          itemBuilder: (_, i) {
                            final c = _vendors[i];
                            final first = (c['first_name'] ?? '').toString();
                            final last  = (c['last_name'] ?? '').toString();
                            final balance = _balanceOf(c);

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                              child: ListTile(
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        "$first ${last.isNotEmpty ? last : ''}".trim(),
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    _balanceChip(balance),
                                  ],
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
