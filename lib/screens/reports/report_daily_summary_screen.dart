import 'dart:ui';
import 'package:enterprise_pos/api/reports_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class ReportDailySummaryScreen extends StatefulWidget {
  const ReportDailySummaryScreen({super.key});

  @override
  State<ReportDailySummaryScreen> createState() =>
      _ReportDailySummaryScreenState();
}

class _ReportDailySummaryScreenState extends State<ReportDailySummaryScreen> {
  final _currency = NumberFormat.simpleCurrency(decimalDigits: 2, name: "");
  final _dateFmt = DateFormat('yyyy-MM-dd');

  late ReportsService _service;

  // Filters
  DateTime? _from;
  DateTime? _to;
  int? _branchId;
  int? _salesmanId;
  int? _customerId;

  // State
  bool _loading = false;
  String? _error;

  _DailySummaryResult? _result;
  int _currentPage = 1;
  int _perPage = 30;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = Provider.of<AuthProvider>(context, listen: false).token!;
      _service = ReportsService(token: token);
      _branchId = context.read<BranchProvider>().selectedBranchId;
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            // Works across Flutter versions
            datePickerTheme: const DatePickerThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _from = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        );
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
      final data = await _service.getDailySummary(
        from: _from == null ? null : _dateFmt.format(_from!),
        to: _to == null ? null : _dateFmt.format(_to!),
        branchId: _branchId,
        salesmanId: _salesmanId,
        customerId: _customerId,
        page: _currentPage,
        perPage: _perPage,
      );
      setState(() => _result = _DailySummaryResult.fromJson(data));
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
        title: const Text('Sales — Daily Summary'),
        actions: [
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
              PopupMenuItem(value: 15, child: Text('15 per page')),
              PopupMenuItem(value: 30, child: Text('30 per page')),
              PopupMenuItem(value: 50, child: Text('50 per page')),
            ],
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _buildHeader(),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _buildError()
            else ...[
              _buildKpis1(),
              _buildKpis2(),
              _buildTable(),
              _buildPagination(),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _result == null
          ? null
          : _BottomTotalsBar(totals: _result!.grandTotals, currency: _currency),
    );
  }

  SliverToBoxAdapter _buildHeader() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_rounded),
                label: Text(
                  (_from == null || _to == null)
                      ? 'All Dates'
                      : '${_dateFmt.format(_from!)}  —  ${_dateFmt.format(_to!)}',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loading ? null : _fetch,
            ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildKpis1() {
    final t = _result?.pageTotals;
    if (t == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          children: [
            _KpiCard(label: 'Gross', value: _currency.format(t.gross)),
            const SizedBox(width: 8),
            _KpiCard(label: 'Discounts', value: _currency.format(t.discounts)),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildKpis2() {
    final t = _result?.pageTotals;
    if (t == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final primary = Theme.of(context).colorScheme.primary;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            _KpiCard(label: 'Returns', value: _currency.format(t.returns)),
            const SizedBox(width: 8),
            _KpiCard(
              label: 'Net',
              value: _currency.format(t.net),
              highlight: true,
              highlightColor: primary,
            ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildTable() {
    final rows = _result?.days ?? [];
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
                    child: Text(
                      'No data for selected range',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final isNeg = r.net < 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            const _Cell(flex: 2, child: SizedBox()),
                            _Cell(
                              flex: 2,
                              child: Text(
                                r.date,
                                style: const TextStyle(
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            _Cell(
                              child: Text(
                                _currency.format(r.gross),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            _Cell(
                              child: Text(
                                _currency.format(r.discounts),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            _Cell(
                              child: Text(
                                _currency.format(r.tax),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            _Cell(
                              child: Text(
                                _currency.format(r.returns),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            _Cell(
                              child: Text(
                                _currency.format(r.net),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isNeg ? Colors.red.shade600 : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                const Divider(height: 1),
                _TotalsRow(
                  label: 'Page Totals',
                  totals: _result?.pageTotals,
                  currency: _currency,
                ),
                if (_result?.grandTotals != null &&
                    _result!.grandTotals != _result!.pageTotals)
                  _TotalsRow(
                    label: 'Grand Totals',
                    totals: _result?.grandTotals,
                    currency: _currency,
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
}

/* ------------------------------- UI Bits ------------------------------- */

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final Color? highlightColor;
  const _KpiCard({
    required this.label,
    required this.value,
    this.highlight = false,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = highlight
        ? (highlightColor ?? Theme.of(context).colorScheme.primary).withOpacity(
            0.05,
          )
        : Colors.white;
    final border = highlight
        ? (highlightColor ?? Theme.of(context).colorScheme.primary).withOpacity(
            0.18,
          )
        : Colors.grey.shade200;
    final labelColor = highlight
        ? (highlightColor ?? Theme.of(context).colorScheme.primary)
        : Colors.grey.shade600;
    final valueColor = highlight
        ? (highlightColor ?? Theme.of(context).colorScheme.primary)
        : Colors.grey.shade900;

    return Expanded(
      child: Card(
        color: bg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
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
    final th = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.grey.shade700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const _Cell(flex: 2, child: Text('')),
          _Cell(flex: 2, child: Text('Date', style: th)),
          _Cell(
            child: Text('Gross', textAlign: TextAlign.right, style: th),
          ),
          _Cell(
            child: Text('Discounts', textAlign: TextAlign.right, style: th),
          ),
          _Cell(
            child: Text('Tax', textAlign: TextAlign.right, style: th),
          ),
          _Cell(
            child: Text('Returns', textAlign: TextAlign.right, style: th),
          ),
          _Cell(
            child: Text('Net', textAlign: TextAlign.right, style: th),
          ),
        ],
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  final String label;
  final _Totals? totals;
  final NumberFormat currency;
  const _TotalsRow({
    required this.label,
    required this.totals,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    if (totals == null) return const SizedBox.shrink();
    final styleLabel = TextStyle(
      fontWeight: FontWeight.w600,
      color: Colors.grey.shade800,
    );
    final styleNum = const TextStyle(fontWeight: FontWeight.w600);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          const _Cell(flex: 2, child: SizedBox()),
          _Cell(flex: 2, child: Text(label, style: styleLabel)),
          _Cell(
            child: Text(
              currency.format(totals!.gross),
              textAlign: TextAlign.right,
              style: styleNum,
            ),
          ),
          _Cell(
            child: Text(
              currency.format(totals!.discounts),
              textAlign: TextAlign.right,
              style: styleNum,
            ),
          ),
          _Cell(
            child: Text(
              currency.format(totals!.tax),
              textAlign: TextAlign.right,
              style: styleNum,
            ),
          ),
          _Cell(
            child: Text(
              currency.format(totals!.returns),
              textAlign: TextAlign.right,
              style: styleNum,
            ),
          ),
          _Cell(
            child: Text(
              currency.format(totals!.net),
              textAlign: TextAlign.right,
              style: styleNum,
            ),
          ),
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
        alignment: textAlign == TextAlign.right
            ? Alignment.centerRight
            : Alignment.centerLeft,
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
  const _BottomTotalsBar({required this.totals, required this.currency});

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
          const Text(
            'Grand Totals',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          _TotalChip(label: 'Gross', value: totals.gross, currency: currency),
          const SizedBox(width: 8),
          _TotalChip(
            label: 'Discounts',
            value: totals.discounts,
            currency: currency,
          ),
          const SizedBox(width: 8),
          _TotalChip(
            label: 'Returns',
            value: totals.returns,
            currency: currency,
          ),
          const SizedBox(width: 8),
          _TotalChip(
            label: 'Net',
            value: totals.net,
            currency: currency,
            highlight: true,
            color: primary,
          ),
        ],
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  final String label;
  final double value;
  final NumberFormat currency;
  final bool highlight;
  final Color? color;
  const _TotalChip({
    required this.label,
    required this.value,
    required this.currency,
    this.highlight = false,
    this.color,
  });

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
        border: Border.all(
          color: highlight ? primary.withOpacity(0.18) : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: fg)),
          const SizedBox(width: 6),
          Text(
            currency.format(value),
            style: TextStyle(fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------- Models ------------------------------- */

class _DailySummaryResult {
  final List<_DailyRow> days;
  final _Totals pageTotals;
  final _Totals grandTotals;
  final _Pagination pagination;

  _DailySummaryResult({
    required this.days,
    required this.pageTotals,
    required this.grandTotals,
    required this.pagination,
  });

  factory _DailySummaryResult.fromJson(Map<String, dynamic> json) {
    final days = (json['days'] as List? ?? [])
        .map((e) => _DailyRow.fromJson(e))
        .toList();
    return _DailySummaryResult(
      days: days,
      pageTotals: _Totals.fromJson(json['page_totals'] ?? {}),
      grandTotals: _Totals.fromJson(json['grand_totals'] ?? {}),
      pagination: _Pagination.fromJson(json['pagination'] ?? {}),
    );
  }
}

class _DailyRow {
  final String date;
  final double gross;
  final double discounts;
  final double tax;
  final double returns;
  final double net;

  _DailyRow({
    required this.date,
    required this.gross,
    required this.discounts,
    required this.tax,
    required this.returns,
    required this.net,
  });

  factory _DailyRow.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v is num)
        ? v.toDouble()
        : double.tryParse(v?.toString() ?? '0') ?? 0.0;
    return _DailyRow(
      date: (json['date'] ?? '').toString(),
      gross: d(json['gross']),
      discounts: d(json['discounts']),
      tax: d(json['tax']),
      returns: d(json['returns']),
      net: d(json['net']),
    );
  }
}

class _Totals {
  final double gross;
  final double discounts;
  final double tax;
  final double returns;
  final double net;

  _Totals({
    required this.gross,
    required this.discounts,
    required this.tax,
    required this.returns,
    required this.net,
  });

  factory _Totals.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v is num)
        ? v.toDouble()
        : double.tryParse(v?.toString() ?? '0') ?? 0.0;
    return _Totals(
      gross: d(json['gross']),
      discounts: d(json['discounts']),
      tax: d(json['tax']),
      returns: d(json['returns']),
      net: d(json['net']),
    );
  }
}

class _Pagination {
  final int currentPage;
  final int perPage;
  final int lastPage;
  final int totalDays;

  _Pagination({
    required this.currentPage,
    required this.perPage,
    required this.lastPage,
    required this.totalDays,
  });

  factory _Pagination.fromJson(Map<String, dynamic> json) {
    int i(dynamic v) =>
        (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
    return _Pagination(
      currentPage: i(json['current_page']),
      perPage: i(json['per_page']),
      lastPage: i(json['last_page']),
      totalDays: i(json['total_days']),
    );
  }
}
