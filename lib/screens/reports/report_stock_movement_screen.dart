import 'dart:ui';
import 'package:enterprise_pos/api/reports_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/widgets/product_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class ReportStockMovementScreen extends StatefulWidget {
  const ReportStockMovementScreen({super.key});

  @override
  State<ReportStockMovementScreen> createState() =>
      _ReportStockMovementScreenState();
}

class _ReportStockMovementScreenState extends State<ReportStockMovementScreen> {
  final _dateFmt = DateFormat('yyyy-MM-dd');
  final _dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
  late ReportsService _service;

  // Filters (ignore branch per your note)
  DateTime? _from;
  DateTime? _to;
  final List<int> _productIds = [];
  final List<Map<String, dynamic>> _selectedProducts = []; // [{id, name, sku}]
  final List<String> _types =
      []; // purchase, sale, return, transfer, adjustment
  bool _includeValue = false;
  String _order = 'asc'; // 'asc' | 'desc'

  // State
  bool _loading = false;
  String? _error;

  _SMResult? _result;
  int _page = 1;
  int _perPage = 20;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = context.read<AuthProvider>().token!;
      _service = ReportsService(token: token);
      _fetch();
    });
  }

  Future<void> _pickRange() async {
    final initial = DateTimeRange(
      start: _from ?? DateTime.now(),
      end: _to ?? DateTime.now(),
    );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: initial,
      helpText: 'Select Date Range',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          datePickerTheme: const DatePickerThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _from = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        );
        _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
        _page = 1;
      });
      _fetch();
    }
  }

  Future<void> _pickProducts() async {
    final token = context.read<AuthProvider>().token!;
    // Expecting your ProductPickerSheet to return List<Map> or a single Map — here we assume multi-select list
    final picked = await showModalBottomSheet<List<Map<String, dynamic>>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProductPickerSheet(token: token, multi: true),
    );
    if (!mounted) return;
    if (picked == null) return;

    setState(() {
      _selectedProducts
        ..clear()
        ..addAll(picked);
      _productIds
        ..clear()
        ..addAll(picked.map((e) => (e['id'] as num).toInt()));
      _page = 1;
    });
    _fetch();
  }

  void _clearProducts() {
    setState(() {
      _selectedProducts.clear();
      _productIds.clear();
      _page = 1;
    });
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getStockMovement(
        from: _from == null ? null : _dateFmt.format(_from!),
        to: _to == null ? null : _dateFmt.format(_to!),
        productIds: _productIds.isEmpty ? null : _productIds,
        types: _types.isEmpty ? null : _types,
        includeValue: _includeValue,
        page: _page,
        perPage: _perPage,
        order: _order,
      );
      setState(() => _result = _SMResult.fromJson(data));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /* --------------------------------- UI --------------------------------- */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Movement'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Rows per page',
            onSelected: (v) {
              setState(() {
                _perPage = v;
                _page = 1;
              });
              _fetch();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 20, child: Text('20 per page')),
              PopupMenuItem(value: 50, child: Text('50 per page')),
              PopupMenuItem(value: 100, child: Text('100 per page')),
            ],
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _buildFilters(),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _buildError()
            else if (_result == null)
              const SliverFillRemaining(hasScrollBody: false, child: SizedBox())
            else ...[
              _buildOpening(),
              _buildTable(),
              _buildTotals(),
              _buildPagination(),
            ],
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildFilters() {
    final dateLabel = (_from == null || _to == null)
        ? 'All Dates'
        : '${_dateFmt.format(_from!)}  —  ${_dateFmt.format(_to!)}';

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text(dateLabel, overflow: TextOverflow.ellipsis),
                  style: _btnStyle,
                ),
                OutlinedButton.icon(
                  onPressed: _pickProducts,
                  icon: const Icon(Icons.inventory_2_rounded),
                  label: Text(
                    _selectedProducts.isEmpty
                        ? 'All Products'
                        : (_selectedProducts.length == 1
                              ? _selectedProducts.first['name'] ?? 'Product'
                              : '${_selectedProducts.length} products'),
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: _btnStyle,
                ),
                if (_selectedProducts.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear products',
                    onPressed: _clearProducts,
                    icon: const Icon(Icons.clear_rounded),
                  ),
                // Type filter chips
                _TypeChips(
                  selected: _types,
                  onChanged: (list) {
                    setState(() {
                      _types
                        ..clear()
                        ..addAll(list);
                      _page = 1;
                    });
                    _fetch();
                  },
                ),
                // Include value toggle
                // Row(
                //   mainAxisSize: MainAxisSize.min,
                //   children: [
                //     const Text('Include value'),
                //     Switch(
                //       value: _includeValue,
                //       onChanged: (v) {
                //         setState(() {
                //           _includeValue = v;
                //           _page = 1;
                //         });
                //         _fetch();
                //       },
                //     ),
                //   ],
                // ),
                // Order
                DropdownButtonHideUnderline(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButton<String>(
                      value: _order,
                      items: const [
                        DropdownMenuItem(
                          value: 'asc',
                          child: Text('Oldest first'),
                        ),
                        DropdownMenuItem(
                          value: 'desc',
                          child: Text('Newest first'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _order = v;
                          _page = 1;
                        });
                        _fetch();
                      },
                    ),
                  ),
                ),
                // Refresh
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loading ? null : _fetch,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_selectedProducts.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _selectedProducts
                    .map(
                      (p) => _FilterChip(
                        label: p['sku'] ?? p['name'] ?? 'Product',
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildOpening() {
    final opening = _result!.opening;
    final qty = opening.quantity;
    final hasVal =
        _includeValue && (opening.value != null || opening.avgCost != null);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 12,
                  ),
                  child: Row(
                    children: [
                      // Expanded(
                      //   child: Column(
                      //     crossAxisAlignment: CrossAxisAlignment.start,
                      //     children: [
                      //       Text(
                      //         'Opening Quantity',
                      //         style: TextStyle(
                      //           fontSize: 12,
                      //           color: Colors.grey.shade600,
                      //         ),
                      //       ),
                      //       const SizedBox(height: 6),
                      //       Text(
                      //         _int(qty).toString(),
                      //         style: const TextStyle(
                      //           fontSize: 18,
                      //           fontWeight: FontWeight.w700,
                      //         ),
                      //       ),
                      //     ],
                      //   ),
                      // ),
                      if (hasVal) ...[
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Opening Value',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(_money(opening.value)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Avg Cost',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(_money(opening.avgCost)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildTable() {
    final rows = _result?.rows ?? [];
    final showValueCols =
        _includeValue; // if true and API returns values, you can extend the row model

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: showValueCols ? 1000 : 880,
                ),
                child: DataTable(
                  headingTextStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                  dataTextStyle: const TextStyle(fontSize: 13),
                  columnSpacing: 24,
                  headingRowHeight: 44,
                  dataRowMinHeight: 44,
                  columns: [
                    const DataColumn(label: Text('Date')),
                    const DataColumn(label: Text('Product')),
                    const DataColumn(label: Text('Type')),
                    const DataColumn(label: Text('Reference')),
                    const DataColumn(label: Text('Qty')),
                    // const DataColumn(label: Text('Qty In'), numeric: true),
                    // const DataColumn(label: Text('Qty Out'), numeric: true),
                    // const DataColumn(label: Text('Balance'), numeric: true),
                    if (showValueCols)
                      const DataColumn(label: Text('Value'), numeric: true),
                    if (showValueCols)
                      const DataColumn(label: Text('Avg Cost'), numeric: true),
                  ],
                  rows: rows.map((r) {
                    final dt = _tryParse(r.date);
                    final dateStr = dt != null
                        ? _dateTimeFmt.format(dt)
                        : r.date;
                    final type = r.type;
                    final isOut = r.qtyOut > 0;
                    return DataRow(
                      cells: [
                        DataCell(Text(dateStr)),
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.productName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                r.sku,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          Row(
                            children: [
                              Icon(
                                isOut
                                    ? Icons.call_made_rounded
                                    : Icons.call_received_rounded,
                                size: 16,
                                color: isOut
                                    ? Colors.red.shade600
                                    : Colors.green.shade700,
                              ),
                              const SizedBox(width: 6),
                              Text(type),
                            ],
                          ),
                        ),
                        DataCell(Text(r.reference)),
                        DataCell(Text((r.qty).toString())),
                        // DataCell(Text(_int(r.qtyIn).toString())),
                        // DataCell(Text(_int(r.qtyOut).toString())),
                        // DataCell(
                        //   Text(
                        //     _int(r.balanceQty).toString(),
                        //     style: const TextStyle(fontWeight: FontWeight.w600),
                        //   ),
                        // ),
                        // if (showValueCols) DataCell(Text(_money(r.value))),
                        // if (showValueCols) DataCell(Text(_money(r.avgCost))),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildTotals() {
    final t = _result!.totals;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TotalChip(label: 'Qty In', value: _int(t.qtyIn).toString()),
            _TotalChip(label: 'Qty Out', value: _int(t.qtyOut).toString()),
            _TotalChip(
              label: 'Net Qty',
              value: _int(t.netQty).toString(),
              highlight: true,
            ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildPagination() {
    final p = _result?.paging;
    if (p == null || p.lastPage <= 1) {
      return const SliverToBoxAdapter(child: SizedBox(height: 24));
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Row(
          children: [
            Text(
              'Page ${p.currentPage} of ${p.lastPage}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Previous',
              onPressed: (_loading || p.currentPage <= 1)
                  ? null
                  : () {
                      setState(() => _page = p.currentPage - 1);
                      _fetch();
                    },
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              tooltip: 'Next',
              onPressed: (_loading || p.currentPage >= p.lastPage)
                  ? null
                  : () {
                      setState(() => _page = p.currentPage + 1);
                      _fetch();
                    },
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }

  SliverFillRemaining _buildError() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 28,
              color: Colors.red,
            ),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /* ----------------------------- helpers ----------------------------- */

  DateTime? _tryParse(String v) {
    try {
      return DateTime.parse(v);
    } catch (_) {
      return null;
    }
  }

  static final _btnStyle = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  int _int(num? v) => (v ?? 0).toInt();

  String _money(num? v) {
    if (v == null) return '—';
    final n = NumberFormat.simpleCurrency(decimalDigits: 2, name: "");
    return n.format(v);
  }
}

/* ------------------------------ UI bits ------------------------------ */

class _TypeChips extends StatefulWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  const _TypeChips({required this.selected, required this.onChanged});

  @override
  State<_TypeChips> createState() => _TypeChipsState();
}

class _TypeChipsState extends State<_TypeChips> {
  static const _all = [
    'purchase',
    'sale',
    'return',
    // 'transfer',
    'adjustment',
    'purchase_claim',
  ];
  late List<String> _sel;

  @override
  void initState() {
    super.initState();
    _sel = List<String>.from(widget.selected);
  }

  @override
  void didUpdateWidget(covariant _TypeChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _sel = List<String>.from(widget.selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _all.map((t) {
        final on = _sel.contains(t);
        return FilterChip(
          label: Text(t),
          selected: on,
          onSelected: (v) {
            setState(() {
              if (v)
                _sel.add(t);
              else
                _sel.remove(t);
            });
            widget.onChanged(List<String>.from(_sel));
          },
        );
      }).toList(),
    );
  }
}

class _TotalChip extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _TotalChip({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final bg = highlight ? primary.withOpacity(0.06) : Colors.grey.shade100;
    final border = highlight ? primary.withOpacity(0.18) : Colors.grey.shade300;
    final fg = highlight ? primary : Colors.grey.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: fg)),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  const _FilterChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

/* ------------------------------- Models ------------------------------- */

class _SMResult {
  final _Opening opening;
  final List<_SMRow> rows;
  final _Totals totals;
  final _Paging? paging;
  final _SMFilters filters;

  _SMResult({
    required this.opening,
    required this.rows,
    required this.totals,
    required this.paging,
    required this.filters,
  });

  factory _SMResult.fromJson(Map<String, dynamic> json) {
    return _SMResult(
      opening: _Opening.fromJson(json['opening'] ?? {}),
      rows: (json['rows'] as List? ?? [])
          .map((e) => _SMRow.fromJson(e))
          .toList(),
      totals: _Totals.fromJson(json['totals'] ?? {}),
      paging: json['paging'] == null ? null : _Paging.fromJson(json['paging']),
      filters: _SMFilters.fromJson(json['filters'] ?? {}),
    );
  }
}

class _Opening {
  final num? quantity;
  final num? value;
  final num? avgCost;
  _Opening({this.quantity, this.value, this.avgCost});

  factory _Opening.fromJson(Map<String, dynamic> json) {
    return _Opening(
      quantity: _n(json['quantity']),
      value: _n(json['value']),
      avgCost: _n(json['avg_cost']),
    );
  }
}

class _SMRow {
  final int id;
  final String date;
  final int productId;
  final String productName;
  final String sku;
  final int branchId;
  final String? branchName;
  final String type;
  final String reference;
  final num qty;
  final num qtyIn;
  final num qtyOut;
  final num balanceQty;

  // Optional valuation fields if you extend the API later
  final num? value;
  final num? avgCost;

  _SMRow({
    required this.id,
    required this.date,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.branchId,
    required this.branchName,
    required this.type,
    required this.reference,
    required this.qty,
    required this.qtyIn,
    required this.qtyOut,
    required this.balanceQty,
    this.value,
    this.avgCost,
  });

  factory _SMRow.fromJson(Map<String, dynamic> j) {
    int i(dynamic v) =>
        (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
    return _SMRow(
      id: i(j['id']),
      date: (j['date'] ?? '').toString(),
      productId: i(j['product_id']),
      productName: (j['product_name'] ?? '').toString(),
      sku: (j['sku'] ?? '').toString(),
      branchId: i(j['branch_id']),
      branchName: j['branch_name']?.toString(),
      type: (j['type'] ?? '').toString(),
      reference: (j['reference'] ?? '').toString(),
      qty: _n(j['qty']) ?? 0,
      qtyIn: _n(j['qty_in']) ?? 0,
      qtyOut: _n(j['qty_out']) ?? 0,
      balanceQty: _n(j['balance_qty']) ?? 0,
      value: _n(j['value']),
      avgCost: _n(j['avg_cost']),
    );
  }
}

class _Totals {
  final num qtyIn;
  final num qtyOut;
  final num netQty;
  _Totals({required this.qtyIn, required this.qtyOut, required this.netQty});

  factory _Totals.fromJson(Map<String, dynamic> j) {
    return _Totals(
      qtyIn: _n(j['qty_in']) ?? 0,
      qtyOut: _n(j['qty_out']) ?? 0,
      netQty: _n(j['net_qty']) ?? 0,
    );
  }
}

class _Paging {
  final int currentPage;
  final int perPage;
  final int total;
  final int lastPage;
  _Paging({
    required this.currentPage,
    required this.perPage,
    required this.total,
    required this.lastPage,
  });

  factory _Paging.fromJson(Map<String, dynamic> j) {
    int i(dynamic v) =>
        (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
    return _Paging(
      currentPage: i(j['current_page']),
      perPage: i(j['per_page']),
      total: i(j['total']),
      lastPage: i(j['last_page']),
    );
  }
}

class _SMFilters {
  final String? from;
  final String? to;
  final List<int> productId;
  final List<int> branchId;
  final List<String> type;
  final bool includeValue;
  final String inventoryAccountCode;
  final String order;

  _SMFilters({
    required this.from,
    required this.to,
    required this.productId,
    required this.branchId,
    required this.type,
    required this.includeValue,
    required this.inventoryAccountCode,
    required this.order,
  });

  factory _SMFilters.fromJson(Map<String, dynamic> j) {
    List<int> _ints(dynamic v) =>
        (v as List? ?? []).map((e) => (e as num).toInt()).toList();
    List<String> _strs(dynamic v) =>
        (v as List? ?? []).map((e) => e.toString()).toList();

    return _SMFilters(
      from: j['from']?.toString(),
      to: j['to']?.toString(),
      productId: _ints(j['product_id']),
      branchId: _ints(j['branch_id']),
      type: _strs(j['type']),
      includeValue: (j['include_value'] is bool)
          ? (j['include_value'] as bool)
          : (j['include_value']?.toString() == '1'),
      inventoryAccountCode: (j['inventory_account_code'] ?? '1400').toString(),
      order: (j['order'] ?? 'asc').toString(),
    );
  }
}

/* ------------------------------- utils ------------------------------- */
num? _n(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString());
}
