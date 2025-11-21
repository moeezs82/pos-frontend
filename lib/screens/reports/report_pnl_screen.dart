import 'dart:ui';
import 'package:enterprise_pos/api/reports_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class ReportPnLScreen extends StatefulWidget {
  const ReportPnLScreen({super.key});

  @override
  State<ReportPnLScreen> createState() => _ReportPnLScreenState();
}

class _ReportPnLScreenState extends State<ReportPnLScreen> {
  late ReportsService _service;

  final _currency = NumberFormat.simpleCurrency(decimalDigits: 2, name: "");
  final _dateFmt = DateFormat('yyyy-MM-dd');

  // Filters
  DateTime? _from;
  DateTime? _to;
  int? _branchId;

  // State
  bool _loading = false;
  String? _error;
  _PnL? _pnl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to   = DateTime(now.year, now.month + 1, 0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = context.read<AuthProvider>().token!;
      _service = ReportsService(token: token);
      _branchId = context.read<BranchProvider?>()?.selectedBranchId;
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
        _to   = DateTime(picked.end.year, picked.end.month, picked.end.day);
      });
      _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _service.getProfitAndLoss(
        from: _from == null ? null : _dateFmt.format(_from!),
        to:   _to   == null ? null : _dateFmt.format(_to!),
        branchId: _branchId,
      );
      setState(() => _pnl = _PnL.fromJson(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = (_from == null || _to == null)
        ? 'All Dates'
        : '${_dateFmt.format(_from!)}  —  ${_dateFmt.format(_to!)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profit & Loss'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _fetch,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorView(message: _error!, onRetry: _fetch)
                : _pnl == null
                    ? const SizedBox()
                    : CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _pickRange,
                                    icon: const Icon(Icons.date_range_rounded),
                                    label: Text(dateLabel, overflow: TextOverflow.ellipsis),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                  if (_branchId != null)
                                    _FilterChip(label: 'Branch #$_branchId'),
                                ],
                              ),
                            ),
                          ),

                          // Summary cards
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                              child: Row(
                                children: [
                                  _SummaryCard(
                                    label: 'Gross Profit',
                                    value: _pnl!.grossProfit,
                                    currency: _currency,
                                    highlight: true,
                                  ),
                                  const SizedBox(width: 8),
                                  _SummaryCard(
                                    label: 'Net Profit',
                                    value: _pnl!.netProfit,
                                    currency: _currency,
                                    highlight: true,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Income
                          _Section(
                            title: 'Income',
                            rows: _pnl!.income.rows,
                            total: _pnl!.income.total,
                            currency: _currency,
                          ),

                          // COGS
                          _Section(
                            title: 'COGS',
                            rows: _pnl!.cogs.rows,
                            total: _pnl!.cogs.total,
                            currency: _currency,
                          ),

                          // Expenses
                          _Section(
                            title: 'Expenses',
                            rows: _pnl!.expenses.rows,
                            total: _pnl!.expenses.total,
                            currency: _currency,
                          ),

                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        ],
                      ),
      ),
    );
  }
}

/* =============================== UI bits =============================== */

class _SummaryCard extends StatelessWidget {
  final String label;
  final double value;
  final NumberFormat currency;
  final bool highlight;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.currency,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final isNeg = value < 0;
    final primary = Theme.of(context).colorScheme.primary;
    final bg = highlight ? primary.withOpacity(0.06) : Colors.grey.shade100;
    final border = highlight ? primary.withOpacity(0.18) : Colors.grey.shade300;

    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              Text(
                currency.format(value),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isNeg ? Colors.red.shade600 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<_PnLRow> rows;
  final double total;
  final NumberFormat currency;

  const _Section({
    required this.title,
    required this.rows,
    required this.total,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final heading = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.25),
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),

                // Table header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text('Account', style: heading)),
                      Expanded(child: Align(alignment: Alignment.centerRight, child: Text('Amount', style: heading))),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Rows
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('No rows', style: TextStyle(color: Colors.grey.shade600)),
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
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.accountName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text('${r.accountCode} • ${r.typeCode}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(currency.format(r.amount),
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                const Divider(height: 1),

                // Total row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      const Expanded(
                        flex: 2,
                        child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            currency.format(total),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
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

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, size: 28, color: Colors.red),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
      ]),
    );
  }
}

/* =============================== Models =============================== */

class _PnL {
  final _SectionData income;
  final _SectionData cogs;
  final _SectionData expenses;
  final double grossProfit;
  final double netProfit;

  _PnL({
    required this.income,
    required this.cogs,
    required this.expenses,
    required this.grossProfit,
    required this.netProfit,
  });

  factory _PnL.fromJson(Map<String, dynamic> json) {
    final sections = (json['sections'] ?? {}) as Map<String, dynamic>;
    return _PnL(
      income: _SectionData.fromJson(sections['income'] ?? {}),
      cogs: _SectionData.fromJson(sections['cogs'] ?? {}),
      expenses: _SectionData.fromJson(sections['expenses'] ?? {}),
      grossProfit: _d(sections['gross_profit']),
      netProfit: _d(sections['net_profit']),
    );
  }
}

class _SectionData {
  final List<_PnLRow> rows;
  final double total;
  _SectionData({required this.rows, required this.total});

  factory _SectionData.fromJson(Map<String, dynamic> j) {
    final list = (j['rows'] as List? ?? []).map((e) => _PnLRow.fromJson(e)).toList();
    return _SectionData(rows: list, total: _d(j['total']));
  }
}

class _PnLRow {
  final int accountId;
  final String accountCode;
  final String accountName;
  final String typeCode;
  final double amount;

  _PnLRow({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.typeCode,
    required this.amount,
  });

  factory _PnLRow.fromJson(Map<String, dynamic> j) {
    int i(dynamic v) => (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
    return _PnLRow(
      accountId: i(j['account_id']),
      accountCode: (j['account_code'] ?? '').toString(),
      accountName: (j['account_name'] ?? '').toString(),
      typeCode: (j['type_code'] ?? '').toString(),
      amount: _d(j['amount']),
    );
  }
}

double _d(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '0') ?? 0.0;
