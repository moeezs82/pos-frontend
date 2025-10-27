import 'dart:async';
import 'dart:convert';
import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/sales/sale_create.dart';
import 'package:enterprise_pos/screens/sales/sale_detail.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  // Data
  final _sales = <dynamic>[];
  List<Map<String, dynamic>> _branches = [];

  // Paging
  int _currentPage = 1;
  int _lastPage = 1;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool get _hasMore => _currentPage < _lastPage;

  // Filters
  String? _selectedBranchId; // only used when global is "All"
  int? _selectedCustomerId;
  String? _selectedCustomerLabel;
  String _sortBy = "date"; // 'date' | 'total'
  String _searchQuery = "";
  DateTime? _fromDate;
  DateTime? _toDate;

  // UI
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _currency = NumberFormat.simpleCurrency(name: "", decimalDigits: 2);
  Timer? _searchDebounce;

  late CommonService _commonService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _commonService = CommonService(token: token);
    _attachScrollListener();
    _fetchInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _attachScrollListener() {
    _scrollController.addListener(() {
      if (_loadingMore || !_hasMore) return;
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent * 0.8) {
        _loadMore();
      }
    });
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _fetchInitial() async {
    setState(() {
      _initialLoading = true;
      _sales.clear();
      _currentPage = 1;
    });
    await Future.wait([_fetchBranches(), _fetchSales(page: 1, replace: true)]);
    if (mounted) setState(() => _initialLoading = false);
  }

  Future<void> _fetchBranches() async {
    // final result = await _commonService.getBranches();
    if (!mounted) return;
    setState(() => _branches = []);
  }

  Future<void> _fetchSales({required int page, bool replace = false}) async {
    final globalBranchId = context.read<BranchProvider>().selectedBranchId;
    final bool isAll = context.read<BranchProvider>().isAll;

    final params = <String, String>{
      "page": page.toString(),
      "sort_by": _sortBy == 'total' ? 'total' : 'date',
      if (!isAll && globalBranchId != null)
        "branch_id": globalBranchId.toString(),
      if (isAll && _selectedBranchId != null) "branch_id": _selectedBranchId!,
      if (_selectedCustomerId != null)
        "customer_id": _selectedCustomerId!.toString(),
      if (_searchQuery.isNotEmpty) "search": _searchQuery,
      if (_fromDate != null) "date_from": _fmtDate(_fromDate!),
      if (_toDate != null) "date_to": _fmtDate(_toDate!),
    };

    final uri = Uri.parse(
      "${ApiClient.baseUrl}/sales",
    ).replace(queryParameters: params);
    final token = Provider.of<AuthProvider>(context, listen: false).token!;

    final res = await http.get(
      uri,
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    if (res.statusCode != 200) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Failed to load sales")));
      }
      return;
    }

    final data = jsonDecode(res.body);
    final List list = data['data']['data'];
    final int current = data['data']['current_page'];
    final int last = data['data']['last_page'];

    setState(() {
      _currentPage = current;
      _lastPage = last;
      if (replace) {
        _sales
          ..clear()
          ..addAll(list);
      } else {
        _sales.addAll(list);
      }
    });
  }

  Future<void> _loadMore() async {
    if (!_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      await _fetchSales(page: _currentPage + 1, replace: false);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _onRefresh() async {
    await _fetchInitial();
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searchQuery = val.trim());
      await _fetchInitial();
    });
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  ({String label, Color color}) _paymentStatus(dynamic sale) {
    final total = _toDouble(sale['total']);
    final paid = _toDouble(sale['paid_amount']);
    if (total > 0 && paid >= total) return (label: "PAID", color: Colors.green);
    if (paid <= 0) return (label: "UNPAID", color: Colors.red);
    return (label: "PARTIAL", color: Colors.orange);
  }

  Future<void> _openCustomerPicker() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final picked = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: CustomerPickerSheet(token: token),
      ),
    );

    setState(() {
      if (picked == null) {
        _selectedCustomerId = null;
        _selectedCustomerLabel = null;
      } else {
        _selectedCustomerId = picked['id'] as int?;
        final first = (picked['first_name'] ?? '').toString();
        final last = (picked['last_name'] ?? '').toString();
        final full = [first, last].where((s) => s.trim().isNotEmpty).join(' ');
        _selectedCustomerLabel = full.isEmpty
            ? 'Customer #${picked['id']}'
            : full;
      }
    });

    await _fetchInitial();
  }

  Future<void> _pickFromDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _fromDate = picked);
      await _fetchInitial();
    }
  }

  Future<void> _pickToDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? _fromDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _toDate = picked);
      await _fetchInitial();
    }
  }

  void _clearDates() async {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    await _fetchInitial();
  }

  @override
  Widget build(BuildContext context) {
    final isAll = context.watch<BranchProvider>().isAll;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Sales"),
        actions: [
          // const BranchIndicator(tappable: false),
          IconButton(
            onPressed: () => _fetchInitial(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateSaleScreen()),
          );
          if (created == true && mounted) _fetchInitial();
        },
        icon: const Icon(Icons.add),
        label: const Text("Add"),
      ),

      body: Column(
        children: [
          // ── Slim filter/search bar ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(
              children: [
                // if (isAll) ...[
                //   Expanded(
                //     flex: 14,
                //     child: DropdownButtonFormField<String>(
                //       value: _selectedBranchId,
                //       decoration: const InputDecoration(
                //         labelText: "Branch",
                //         border: OutlineInputBorder(),
                //         isDense: true,
                //       ),
                //       items: [
                //         const DropdownMenuItem<String>(
                //           value: null,
                //           child: Text("All"),
                //         ),
                //         ..._branches.map(
                //           (b) => DropdownMenuItem<String>(
                //             value: b['id'].toString(),
                //             child: Text(b['name'].toString()),
                //           ),
                //         ),
                //       ],
                //       onChanged: (v) async {
                //         setState(() => _selectedBranchId = v);
                //         await _fetchInitial();
                //       },
                //     ),
                //   ),
                //   const SizedBox(width: 6),
                // ],

                // Customer selector
                Expanded(
                  flex: 16,
                  child: InkWell(
                    onTap: _openCustomerPicker,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: "Customer",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      isEmpty: _selectedCustomerId == null,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedCustomerLabel ?? "All",
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_selectedCustomerId != null)
                            GestureDetector(
                              onTap: () async {
                                setState(() {
                                  _selectedCustomerId = null;
                                  _selectedCustomerLabel = null;
                                });
                                await _fetchInitial();
                              },
                              child: const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(Icons.clear, size: 18),
                              ),
                            )
                          else
                            const Icon(Icons.search, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Sort
                SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<String>(
                    value: _sortBy,
                    decoration: const InputDecoration(
                      labelText: "Sort",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: "date", child: Text("Date")),
                      DropdownMenuItem(value: "total", child: Text("Amount")),
                    ],
                    onChanged: (v) async {
                      setState(() => _sortBy = v ?? 'date');
                      await _fetchInitial();
                    },
                  ),
                ),
              ],
            ),
          ),

          // Search + quick date filters (tiny)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: "Invoice or customer",
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged("");
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  tooltip: "Dates",
                  icon: const Icon(Icons.calendar_month),
                  onSelected: (v) {
                    if (v == 'from') _pickFromDate();
                    if (v == 'to') _pickToDate();
                    if (v == 'clear') _clearDates();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'from', child: Text('Set From')),
                    PopupMenuItem(value: 'to', child: Text('Set To')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'clear', child: Text('Clear')),
                  ],
                ),
              ],
            ),
          ),
          if (_fromDate != null || _toDate != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Wrap(
                spacing: 6,
                children: [
                  if (_fromDate != null)
                    InputChip(
                      label: Text(
                        "From: ${DateFormat.yMMMd().format(_fromDate!)}",
                      ),
                      onDeleted: () async {
                        setState(() => _fromDate = null);
                        await _fetchInitial();
                      },
                    ),
                  if (_toDate != null)
                    InputChip(
                      label: Text("To: ${DateFormat.yMMMd().format(_toDate!)}"),
                      onDeleted: () async {
                        setState(() => _toDate = null);
                        await _fetchInitial();
                      },
                    ),
                ],
              ),
            ),

          // ── List + infinite scroll ──────────────────────────────────────────
          Expanded(
            child: _initialLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: _sales.isEmpty
                        ? const Center(child: Text("No sales found"))
                        : ListView.separated(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _sales.length + (_loadingMore ? 1 : 0),
                            separatorBuilder: (_, __) =>
                                const Divider(height: 0),
                            itemBuilder: (_, i) {
                              if (_loadingMore && i == _sales.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }

                              final s = _sales[i];
                              final invoice = (s['invoice_no'] ?? '')
                                  .toString();
                              final customer =
                                  (s['customer']?['first_name'] ?? 'Walk-in')
                                      .toString();
                              final branch = (s['branch']?['name'] ?? 'N/A')
                                  .toString();
                              final total = _toDouble(s['total']);
                              final paid = _toDouble(s['paid_amount']);
                              final balance = (total - paid).clamp(
                                0,
                                double.infinity,
                              );
                              final st = _paymentStatus(s);

                              final createdAtStr =
                                  (s['created_at'] ?? s['date'] ?? '')
                                      .toString();
                              final dt = _tryParseDate(createdAtStr);
                              final dateLabel = dt != null
                                  ? DateFormat('yMMMd').format(dt)
                                  : '';
                              final timeLabel = dt != null
                                  ? DateFormat('HH:mm').format(dt)
                                  : '';

                              return ListTile(
                                dense: true,
                                visualDensity: const VisualDensity(
                                  horizontal: -2,
                                  vertical: -2,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),

                                // ✅ Scales down to avoid overflow
                                leading: dt == null
                                    ? const SizedBox(width: 42)
                                    : SizedBox(
                                        width: 42,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 4,
                                              horizontal: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blueGrey.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.blueGrey.shade100,
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  DateFormat(
                                                    'MMM',
                                                  ).format(dt).toUpperCase(),
                                                  style: const TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.blueGrey,
                                                  ),
                                                ),
                                                Text(
                                                  DateFormat('d').format(dt),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                Text(
                                                  DateFormat(
                                                    'E',
                                                  ).format(dt).toUpperCase(),
                                                  style: const TextStyle(
                                                    fontSize: 8,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.blueGrey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        invoice,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    _amountChip(
                                      context,
                                      "Date",
                                      dateLabel,
                                      Colors.blue,
                                      icon: Icons.calendar_month,
                                    ),
                                    _amountChip(
                                      context,
                                      "Amount",
                                      _currency.format(total),
                                      Colors.red,
                                      icon: Icons.summarize,
                                    ),
                                    // Container(
                                    //   padding: const EdgeInsets.symmetric(
                                    //     horizontal: 6,
                                    //     vertical: 2,
                                    //   ),
                                    //   decoration: BoxDecoration(
                                    //     color: st.color,
                                    //     borderRadius: BorderRadius.circular(6),
                                    //   ),
                                    //   child: Text(
                                    //     st.label,
                                    //     style: const TextStyle(
                                    //       color: Colors.white,
                                    //       fontSize: 11,
                                    //       fontWeight: FontWeight.w700,
                                    //     ),
                                    //   ),
                                    // ),
                                  ],
                                ),

                                subtitle: DefaultTextStyle(
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black87,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              "Cust: $customer • $branch",
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          // if (dt != null)
                                          //   Text(
                                          //     "$dateLabel • $timeLabel",
                                          //     style: const TextStyle(
                                          //       color: Colors.grey,
                                          //       fontSize: 11,
                                          //       fontWeight: FontWeight.w500,  
                                          //     ),
                                          //   ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Wrap(
                                        spacing: 0,
                                        runSpacing: 0,
                                        children: [
                                          // _amountChip(
                                          //   context,
                                          //   "Total",
                                          //   _currency.format(total),
                                          //   Colors.blue,
                                          //   icon: Icons.summarize,
                                          // ),
                                          // _amountChip(
                                          //   context,
                                          //   "Paid",
                                          //   _currency.format(paid),
                                          //   Colors.green,
                                          //   icon: Icons.payments,
                                          // ),
                                          // _amountChip(
                                          //   context,
                                          //   "Bal",
                                          //   _currency.format(balance),
                                          //   balance <= 0
                                          //       ? Colors.teal
                                          //       : Colors
                                          //             .deepOrange, // green if cleared, orange if due
                                          //   icon: balance <= 0
                                          //       ? Icons.check_circle
                                          //       : Icons
                                          //             .account_balance_wallet_outlined,
                                          // ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                trailing: IconButton(
                                  tooltip: "Copy invoice",
                                  icon: const Icon(Icons.copy, size: 18),
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: invoice),
                                    );
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text("Copied: $invoice"),
                                      ),
                                    );
                                  },
                                ),

                                onTap: () async {
                                  final changed = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SaleDetailScreen(
                                        saleId: s['id'] as int,
                                      ),
                                    ),
                                  );
                                  if (changed == true && mounted)
                                    _fetchInitial();
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

DateTime? _tryParseDate(dynamic v) {
  if (v == null) return null;
  try {
    return DateTime.parse(v.toString());
  } catch (_) {
    return null;
  }
}

Widget _miniPill(String label, String value) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    margin: const EdgeInsets.only(right: 6),
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Text(
      "$label: $value",
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}

// Pick readable fg on any bg
(Color fg, Color bg) _chipPalette(BuildContext ctx, Color base) {
  final isDark = Theme.of(ctx).brightness == Brightness.dark;
  final bg = isDark ? base.withOpacity(.25) : base.withOpacity(.12);
  final fg = isDark ? base.withOpacity(.95) : base.withOpacity(.90);
  return (fg, bg);
}

Widget _amountChip(
  BuildContext ctx,
  String label,
  String value,
  Color base, {
  IconData? icon,
}) {
  final (fg, bg) = _chipPalette(ctx, base);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    margin: const EdgeInsets.only(right: 6, top: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: base.withOpacity(.35), width: 1),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
        ],
        Text(
          "$label: ",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800, // 🔥 emphasize the number
            color: fg,
          ),
        ),
      ],
    ),
  );
}
