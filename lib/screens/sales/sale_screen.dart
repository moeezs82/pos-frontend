import 'dart:async';
import 'dart:convert';
import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/sales/sale_create.dart';
import 'package:enterprise_pos/screens/sales/picking_list_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_detail.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/utils/customer_display_utils.dart';

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
  String? _paymentStatusFilter;
  String? _saleTypeFilter;
  int? _saleSourceId;
  int? _areaId;
  int? _salesmanId;
  int? _deliveryBoyId;
  int? _createdById;
  List<Map<String, dynamic>> _saleSources = const [];
  List<Map<String, dynamic>> _areas = const [];
  List<Map<String, dynamic>> _salesmen = const [];
  List<Map<String, dynamic>> _deliveryBoys = const [];
  List<Map<String, dynamic>> _creators = const [];
  List<String> _saleTypes = const [];

  // UI
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _currency = const AppMoneyFormatter();
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
    await Future.wait([
      _fetchBranches(),
      _fetchFilterOptions(),
      _fetchSales(page: 1, replace: true),
    ]);
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
      // if (!isAll && globalBranchId != null)
      //   "branch_id": globalBranchId.toString(),
      // if (isAll && _selectedBranchId != null) "branch_id": _selectedBranchId!,
      if (_selectedCustomerId != null)
        "customer_id": _selectedCustomerId!.toString(),
      if (_searchQuery.isNotEmpty) "search": _searchQuery,
      if (_fromDate != null) "date_from": _fmtDate(_fromDate!),
      if (_toDate != null) "date_to": _fmtDate(_toDate!),
      if (_paymentStatusFilter != null) "payment_status": _paymentStatusFilter!,
      if (_saleTypeFilter != null) "sale_type": _saleTypeFilter!,
      if (_saleSourceId != null) "sale_source_id": _saleSourceId.toString(),
      if (_areaId != null) "area_id": _areaId.toString(),
      if (_salesmanId != null) "salesman_id": _salesmanId.toString(),
      if (_deliveryBoyId != null) "delivery_boy_id": _deliveryBoyId.toString(),
      if (_createdById != null) "created_by": _createdById.toString(),
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

  Future<void> _fetchFilterOptions() async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token!;
      final res = await http.get(
        Uri.parse("${ApiClient.baseUrl}/sales/filter-options"),
        headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
      );
      if (res.statusCode != 200 || !mounted) return;
      final decoded = jsonDecode(res.body);
      final raw = decoded is Map ? decoded['data'] : null;
      if (raw is! Map) return;
      List<Map<String, dynamic>> refs(String key) {
        final list = raw[key];
        if (list is! List) return const [];
        return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      final types = raw['sale_types'];
      setState(() {
        _saleSources = refs('sale_sources');
        _areas = refs('areas');
        _salesmen = refs('salesmen');
        _deliveryBoys = refs('delivery_boys');
        _creators = refs('creators');
        _saleTypes = types is List ? types.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() : const [];
      });
    } catch (_) {
      // Filters are convenience only; sales remain usable if references fail.
    }
  }

  int get _advancedFilterCount => [
        _paymentStatusFilter,
        _saleTypeFilter,
        _saleSourceId,
        _areaId,
        _salesmanId,
        _deliveryBoyId,
        _createdById,
      ].where((e) => e != null).length;

  String _refName(List<Map<String, dynamic>> rows, int? id) {
    if (id == null) return '';
    for (final row in rows) {
      if (_toInt(row['id']) == id) return (row['name'] ?? '#$id').toString();
    }
    return '#$id';
  }

  Future<void> _openAdvancedFilters() async {
    var payment = _paymentStatusFilter;
    var saleType = _saleTypeFilter;
    var sourceId = _saleSourceId;
    var areaId = _areaId;
    var salesmanId = _salesmanId;
    var deliveryBoyId = _deliveryBoyId;
    var createdById = _createdById;

    final applied = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          DropdownMenuItem<int?> allItem(String label) => DropdownMenuItem<int?>(value: null, child: Text(label));
          List<DropdownMenuItem<int?>> refItems(List<Map<String, dynamic>> rows, String allLabel) => [
                allItem(allLabel),
                ...rows.map((r) => DropdownMenuItem<int?>(
                      value: _toInt(r['id']),
                      child: Text((r['name'] ?? '').toString(), overflow: TextOverflow.ellipsis),
                    )),
              ];
          return AlertDialog(
            title: const Text('Sale Filters'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<String?>(
                        value: payment,
                        decoration: const InputDecoration(labelText: 'Payment Status', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem<String?>(value: null, child: Text('All Statuses')),
                          DropdownMenuItem(value: 'paid', child: Text('Paid')),
                          DropdownMenuItem(value: 'partial', child: Text('Partial')),
                          DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                        ],
                        onChanged: (v) => setLocalState(() => payment = v),
                      ),
                    ),
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<String?>(
                        value: saleType,
                        decoration: const InputDecoration(labelText: 'Sale Type', border: OutlineInputBorder()),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All Types')),
                          ..._saleTypes.map((v) => DropdownMenuItem<String?>(value: v, child: Text(_prettyLabel(v)))),
                        ],
                        onChanged: (v) => setLocalState(() => saleType = v),
                      ),
                    ),
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<int?>(
                        value: sourceId,
                        decoration: const InputDecoration(labelText: 'Sale From', border: OutlineInputBorder()),
                        items: refItems(_saleSources, 'All Sources'),
                        onChanged: (v) => setLocalState(() => sourceId = v),
                      ),
                    ),
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<int?>(
                        value: areaId,
                        decoration: const InputDecoration(labelText: 'Town / Area', border: OutlineInputBorder()),
                        items: refItems(_areas, 'All Areas'),
                        onChanged: (v) => setLocalState(() => areaId = v),
                      ),
                    ),
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<int?>(
                        value: salesmanId,
                        decoration: const InputDecoration(labelText: 'Salesman', border: OutlineInputBorder()),
                        items: refItems(_salesmen, 'All Salesmen'),
                        onChanged: (v) => setLocalState(() => salesmanId = v),
                      ),
                    ),
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<int?>(
                        value: deliveryBoyId,
                        decoration: const InputDecoration(labelText: 'Delivery Boy', border: OutlineInputBorder()),
                        items: refItems(_deliveryBoys, 'All Delivery Boys'),
                        onChanged: (v) => setLocalState(() => deliveryBoyId = v),
                      ),
                    ),
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<int?>(
                        value: createdById,
                        decoration: const InputDecoration(labelText: 'Created By / Cashier', border: OutlineInputBorder()),
                        items: refItems(_creators, 'All Users'),
                        onChanged: (v) => setLocalState(() => createdById = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setLocalState(() {
                    payment = null;
                    saleType = null;
                    sourceId = null;
                    areaId = null;
                    salesmanId = null;
                    deliveryBoyId = null;
                    createdById = null;
                  });
                },
                child: const Text('Clear'),
              ),
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Apply')),
            ],
          );
        },
      ),
    );
    if (applied != true || !mounted) return;
    setState(() {
      _paymentStatusFilter = payment;
      _saleTypeFilter = saleType;
      _saleSourceId = sourceId;
      _areaId = areaId;
      _salesmanId = salesmanId;
      _deliveryBoyId = deliveryBoyId;
      _createdById = createdById;
    });
    await _fetchInitial();
  }

  String _prettyLabel(String value) {
    if (value.trim().isEmpty) return value;
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}')
        .join(' ');
  }

  Future<void> _clearAdvancedFilter(String key) async {
    setState(() {
      switch (key) {
        case 'payment': _paymentStatusFilter = null; break;
        case 'type': _saleTypeFilter = null; break;
        case 'source': _saleSourceId = null; break;
        case 'area': _areaId = null; break;
        case 'salesman': _salesmanId = null; break;
        case 'delivery': _deliveryBoyId = null; break;
        case 'creator': _createdById = null; break;
      }
    });
    await _fetchInitial();
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

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  ({String label, Color color}) _paymentStatus(dynamic sale) {
    final raw = (sale['payment_status'] ?? '').toString().toLowerCase();
    if (raw == 'paid') return (label: "PAID", color: Colors.green);
    if (raw == 'partial') return (label: "PARTIAL", color: Colors.orange);
    if (raw == 'unpaid' || raw == 'pending') return (label: "UNPAID", color: Colors.red);
    final total = _toDouble(sale['total']);
    final paid = _toDouble(sale['paid_amount']);
    if (total <= 0.004 || paid >= total - 0.004) return (label: "PAID", color: Colors.green);
    if (paid <= 0.004) return (label: "UNPAID", color: Colors.red);
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
        _selectedCustomerId = _toInt(picked['id']);
        _selectedCustomerLabel = CustomerDisplayUtils.nameWithArea(
          picked,
          fallback: 'Customer #${picked['id']}',
        );
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


  Future<void> _openPickingList() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PickingListScreen(
          initialFromDate: _fromDate,
          initialToDate: _toDate,
          initialCustomerId: _selectedCustomerId,
          initialCustomerLabel: _selectedCustomerLabel,
          initialSearch: _searchQuery,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAll = context.watch<BranchProvider>().isAll;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Sales"),
        actions: [
          const BranchIndicator(tappable: false),
          IconButton(
            tooltip: 'Picking List',
            onPressed: _openPickingList,
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          IconButton(
            tooltip: 'Refresh sales',
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
                      hintText: "Invoice, customer, product, SKU or barcode",
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
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: _openAdvancedFilters,
                  icon: const Icon(Icons.filter_alt_outlined, size: 18),
                  label: Text(_advancedFilterCount == 0 ? 'Filters' : 'Filters ($_advancedFilterCount)'),
                ),
              ],
            ),
          ),
          if (_fromDate != null || _toDate != null || _advancedFilterCount > 0)
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
                  if (_paymentStatusFilter != null)
                    InputChip(label: Text('Payment: ${_prettyLabel(_paymentStatusFilter!)}'), onDeleted: () => _clearAdvancedFilter('payment')),
                  if (_saleTypeFilter != null)
                    InputChip(label: Text('Type: ${_prettyLabel(_saleTypeFilter!)}'), onDeleted: () => _clearAdvancedFilter('type')),
                  if (_saleSourceId != null)
                    InputChip(label: Text('From: ${_refName(_saleSources, _saleSourceId)}'), onDeleted: () => _clearAdvancedFilter('source')),
                  if (_areaId != null)
                    InputChip(label: Text('Area: ${_refName(_areas, _areaId)}'), onDeleted: () => _clearAdvancedFilter('area')),
                  if (_salesmanId != null)
                    InputChip(label: Text('Salesman: ${_refName(_salesmen, _salesmanId)}'), onDeleted: () => _clearAdvancedFilter('salesman')),
                  if (_deliveryBoyId != null)
                    InputChip(label: Text('Rider: ${_refName(_deliveryBoys, _deliveryBoyId)}'), onDeleted: () => _clearAdvancedFilter('delivery')),
                  if (_createdById != null)
                    InputChip(label: Text('Created By: ${_refName(_creators, _createdById)}'), onDeleted: () => _clearAdvancedFilter('creator')),
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
                              final offlineRef =
                                  (s['offline_invoice_no'] ?? '').toString();
                              final saleSource =
                                  (s['sale_source_name'] ?? 'Counter').toString();
                              final customer =
                                  (s['customer']?['first_name'] ?? 'Walk-in')
                                      .toString();
                              final total = _toDouble(s['total']);
                              final paid = _toDouble(s['paid_amount']);
                              final balance = s['balance_amount'] != null
                                  ? _toDouble(s['balance_amount'])
                                  : (total - paid).clamp(0, double.infinity).toDouble();
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

                              final invoiceDateStr = (s['invoice_date'] ?? '').toString();

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
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.shade50,
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: Colors.blueGrey.shade100),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.hub_outlined, size: 11, color: Colors.blueGrey),
                                          const SizedBox(width: 4),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 110),
                                            child: Tooltip(
                                              message: saleSource,
                                              child: Text(
                                                saleSource,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.blueGrey),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    _amountChip(
                                      context,
                                      "Date",
                                      invoiceDateStr,
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
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: st.color,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        st.label,
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                                      ),
                                    ),
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
                                              "Cust: $customer",
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      // Show offline origin indicator when
                                      // the sale was created offline.
                                      if (offlineRef.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 1),
                                          child: Text(
                                            'Offline ref: $offlineRef',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.blueGrey,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
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
                                          if (balance > 0.004)
                                            _amountChip(
                                              context,
                                              "Due",
                                              _currency.format(balance),
                                              Colors.deepOrange,
                                              icon: Icons.account_balance_wallet_outlined,
                                            ),
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
                                        saleId: _toInt(s['id']) ?? 0,
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
