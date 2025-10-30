// lib/screens/reports/report_top_bottom_products_screen.dart
import 'dart:ui';
import 'package:enterprise_pos/api/reports_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class ReportTopBottomProductsScreen extends StatefulWidget {
  const ReportTopBottomProductsScreen({super.key});

  @override
  State<ReportTopBottomProductsScreen> createState() => _ReportTopBottomProductsScreenState();
}

class _ReportTopBottomProductsScreenState extends State<ReportTopBottomProductsScreen> {
  final _currency = NumberFormat.simpleCurrency(decimalDigits: 2, name: "");
  final _num = NumberFormat('#,##0.##');
  final _dateFmt = DateFormat('yyyy-MM-dd');

  late ReportsService _service;

  // Filters
  DateTime? _from;
  DateTime? _to;
  int? _branchId;
  int? _salesmanId;
  int? _customerId;
  int? _categoryId;
  int? _vendorId;

  String _sortBy = 'revenue'; // revenue | margin | qty
  String _direction = 'desc'; // asc | desc

  // State
  bool _loading = false;
  String? _error;

  _TBResult? _result;
  int _currentPage = 1;
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
      _branchId = context.read<BranchProvider>().selectedBranchId;
      _fetch();
    });
  }

  Future<void> _pickRange() async {
    final initial = DateTimeRange(start: _from ?? DateTime.now(), end: _to ?? DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: initial,
      helpText: 'Select Date Range',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          datePickerTheme: const DatePickerThemeData(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
        _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
        _currentPage = 1;
      });
      _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getTopBottomProducts(
        from: _from == null ? null : _dateFmt.format(_from!),
        to: _to == null ? null : _dateFmt.format(_to!),
        branchId: _branchId,
        salesmanId: _salesmanId,
        customerId: _customerId,
        categoryId: _categoryId,
        vendorId: _vendorId,
        sortBy: _sortBy,
        direction: _direction,
        page: _currentPage,
        perPage: _perPage,
      );
      setState(() => _result = _TBResult.fromJson(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /* ------------------------------- UI ------------------------------- */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products — Top / Bottom'),
        actions: [
          // Rows-per-page
          PopupMenuButton<int>(
            tooltip: 'Rows per page',
            onSelected: (v) {
              setState(() {
                _perPage = v;
                _currentPage = 1;
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
            else ...[
              _buildHeaderKpis(),
              _buildTable(),
              _buildPagination(),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _result == null
          ? null
          : _BottomTotalsBar(totals: _result!.totals, currency: _currency, numFmt: _num),
    );
  }

  SliverToBoxAdapter _buildFilters() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Date range
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range_rounded),
              label: Text(
                (_from == null || _to == null)
                    ? 'All Dates'
                    : '${_dateFmt.format(_from!)}  —  ${_dateFmt.format(_to!)}',
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            // Sort By
            _DropdownChip<String>(
              tooltip: 'Sort by',
              value: _sortBy,
              items: const [
                DropdownMenuItem(value: 'revenue', child: Text('Revenue')),
                DropdownMenuItem(value: 'margin', child: Text('Margin')),
                DropdownMenuItem(value: 'qty', child: Text('Quantity')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _sortBy = v;
                  _currentPage = 1;
                });
                _fetch();
              },
              icon: Icons.sort_rounded,
            ),
            // Direction
            _DropdownChip<String>(
              tooltip: 'Direction',
              value: _direction,
              items: const [
                DropdownMenuItem(value: 'desc', child: Text('High → Low')),
                DropdownMenuItem(value: 'asc', child: Text('Low → High')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _direction = v;
                  _currentPage = 1;
                });
                _fetch();
              },
              icon: Icons.swap_vert_rounded,
            ),
            // Refresh
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _fetch,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildHeaderKpis() {
    final t = _result?.totals;
    if (t == null) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Row(
          children: [
            _KpiCard(label: 'Qty', value: _num.format(t.qty)),
            const SizedBox(width: 8),
            _KpiCard(label: 'Revenue', value: _currency.format(t.revenue)),
            const SizedBox(width: 8),
            _KpiCard(label: 'COGS', value: _currency.format(t.cogs)),
            const SizedBox(width: 8),
            _KpiCard(label: 'Margin', value: _currency.format(t.margin), highlight: true, highlightColor: Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildTable() {
    final rows = _result?.rows ?? [];
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
            child: Column(
              children: [
                const _TableHeader(),
                const Divider(height: 1),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No products for selected filters', style: TextStyle(color: Colors.grey.shade600)),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            _Cell(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(r.sku, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                ],
                              ),
                            ),
                            _Cell(child: Text(_num.format(r.qty), textAlign: TextAlign.right)),
                            _Cell(child: Text(_currency.format(r.revenue), textAlign: TextAlign.right)),
                            _Cell(child: Text(_currency.format(r.cogs), textAlign: TextAlign.right)),
                            _Cell(
                              child: Text(
                                _currency.format(r.margin),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            _Cell(
                              child: Text(
                                r.refundQty > 0
                                    ? '${_num.format(r.refundQty)}  (${(r.refundRate * 100).toStringAsFixed(1)}%)'
                                    : '—',
                                textAlign: TextAlign.right,
                                style: TextStyle(color: r.refundQty > 0 ? Colors.orange.shade700 : Colors.grey.shade600),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildPagination() {
    final p = _result?.pagination;
    if (p == null || p.lastPage <= 1) return const SliverToBoxAdapter(child: SizedBox(height: 24));
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Row(
          children: [
            Text('Page ${p.currentPage} of ${p.lastPage}', style: TextStyle(color: Colors.grey.shade700)),
            const Spacer(),
            IconButton(
              tooltip: 'Previous',
              onPressed: (_loading || p.currentPage <= 1)
                  ? null
                  : () {
                      setState(() => _currentPage = p.currentPage - 1);
                      _fetch();
                    },
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              tooltip: 'Next',
              onPressed: (_loading || p.currentPage >= p.lastPage)
                  ? null
                  : () {
                      setState(() => _currentPage = p.currentPage + 1);
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
            const Icon(Icons.error_outline_rounded, size: 28, color: Colors.red),
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
}

/* ------------------------------- UI Bits ------------------------------- */

class _DropdownChip<T> extends StatelessWidget {
  final String tooltip;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?) onChanged;
  final IconData icon;
  const _DropdownChip({
    required this.tooltip,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                items: items,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final Color? highlightColor;
  const _KpiCard({required this.label, required this.value, this.highlight = false, this.highlightColor});

  @override
  Widget build(BuildContext context) {
    final bg = highlight ? (highlightColor ?? Theme.of(context).colorScheme.primary).withOpacity(0.05) : Colors.white;
    final border = highlight
        ? (highlightColor ?? Theme.of(context).colorScheme.primary).withOpacity(0.18)
        : Colors.grey.shade200;
    final labelColor = highlight ? (highlightColor ?? Theme.of(context).colorScheme.primary) : Colors.grey.shade600;
    final valueColor = highlight ? (highlightColor ?? Theme.of(context).colorScheme.primary) : Colors.grey.shade900;

    return Expanded(
      child: Card(
        color: bg,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
              const SizedBox(height: 6),
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: valueColor)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final th = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _Cell(flex: 3, child: Text('Product', style: th)),
          _Cell(child: Text('Qty', textAlign: TextAlign.right, style: th)),
          _Cell(child: Text('Revenue', textAlign: TextAlign.right, style: th)),
          _Cell(child: Text('COGS', textAlign: TextAlign.right, style: th)),
          _Cell(child: Text('Margin', textAlign: TextAlign.right, style: th)),
          _Cell(child: Text('Refunds', textAlign: TextAlign.right, style: th)),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final Widget child;
  final int flex;
  final TextAlign? textAlign;
  const _Cell({required this.child, this.flex = 1, this.textAlign});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Align(
        alignment: textAlign == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft,
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 13),
          child: child,
        ),
      ),
    );
  }
}

class _BottomTotalsBar extends StatelessWidget {
  final _Totals totals;
  final NumberFormat currency;
  final NumberFormat numFmt;
  const _BottomTotalsBar({required this.totals, required this.currency, required this.numFmt});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          const Text('Totals', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          _TotalChip(label: 'Qty', value: numFmt.format(totals.qty)),
          const SizedBox(width: 8),
          _TotalChip(label: 'Revenue', value: currency.format(totals.revenue)),
          const SizedBox(width: 8),
          _TotalChip(label: 'COGS', value: currency.format(totals.cogs)),
          const SizedBox(width: 8),
          _TotalChip(label: 'Margin', value: currency.format(totals.margin), highlight: true, color: primary),
        ],
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final Color? color;
  const _TotalChip({required this.label, required this.value, this.highlight = false, this.color});

  @override
  Widget build(BuildContext context) {
    final primary = color ?? Theme.of(context).colorScheme.primary;
    final bg = highlight ? primary.withOpacity(0.06) : Colors.grey.shade100;
    final fg = highlight ? primary : Colors.grey.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: highlight ? primary.withOpacity(0.18) : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: fg)),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

/* ------------------------------- Models ------------------------------- */

class _TBResult {
  final List<_TBRow> rows;
  final _Totals totals;
  final _Pagination pagination;

  _TBResult({required this.rows, required this.totals, required this.pagination});

  factory _TBResult.fromJson(Map<String, dynamic> json) {
    final rows = (json['rows'] as List? ?? []).map((e) => _TBRow.fromJson(e)).toList();
    return _TBResult(
      rows: rows,
      totals: _Totals.fromJson(json['totals'] ?? {}),
      pagination: _Pagination.fromJson(json['pagination'] ?? {}),
    );
  }
}

class _TBRow {
  final int productId;
  final String name;
  final String sku;
  final double qty;
  final double revenue;
  final double cogs;
  final double margin;
  final double refundQty;
  final double refundRate;

  _TBRow({
    required this.productId,
    required this.name,
    required this.sku,
    required this.qty,
    required this.revenue,
    required this.cogs,
    required this.margin,
    required this.refundQty,
    required this.refundRate,
  });

  factory _TBRow.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '0') ?? 0.0;
    int i(dynamic v) => (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
    return _TBRow(
      productId: i(json['product_id']),
      name: (json['name'] ?? '').toString(),
      sku: (json['sku'] ?? '').toString(),
      qty: d(json['qty']),
      revenue: d(json['revenue']),
      cogs: d(json['cogs']),
      margin: d(json['margin']),
      refundQty: d(json['refund_qty']),
      refundRate: d(json['refund_rate']),
    );
  }
}

class _Totals {
  final double qty;
  final double revenue;
  final double cogs;
  final double margin;

  _Totals({required this.qty, required this.revenue, required this.cogs, required this.margin});

  factory _Totals.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '0') ?? 0.0;
    return _Totals(
      qty: d(json['qty']),
      revenue: d(json['revenue']),
      cogs: d(json['cogs']),
      margin: d(json['margin']),
    );
  }
}

class _Pagination {
  final int currentPage;
  final int perPage;
  final int lastPage;
  final int totalProducts;

  _Pagination({required this.currentPage, required this.perPage, required this.lastPage, required this.totalProducts});

  factory _Pagination.fromJson(Map<String, dynamic> json) {
    int i(dynamic v) => (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
    return _Pagination(
      currentPage: i(json['current_page']),
      perPage: i(json['per_page']),
      lastPage: i(json['last_page']),
      totalProducts: i(json['total_products']),
    );
  }
}
