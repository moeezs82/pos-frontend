// lib/screens/reports/report_ledger_screen.dart
import 'package:enterprise_pos/api/reports_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';


class ReportLedgerScreen extends StatefulWidget {
  final String partyType; // 'customer' | 'vendor' (fixed by caller)
  final int? partyId;     // optional: can start null

  const ReportLedgerScreen({
    super.key,
    required this.partyType,
    this.partyId,
  });

  @override
  State<ReportLedgerScreen> createState() => _ReportLedgerScreenState();
}

class _ReportLedgerScreenState extends State<ReportLedgerScreen> {
  final _currency = NumberFormat.simpleCurrency(decimalDigits: 2, name: "");
  final _dateFmt = DateFormat('yyyy-MM-dd');
  final _dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  late ReportsService _service;

  // Fixed by widget
  late final String _partyType;

  // Optional selection (NOT required)
  int? _partyId;
  Map<String, dynamic>? _selectedParty; // will hold customer/vendor map with 'name'

  // Filters
  DateTime? _from;
  DateTime? _to;
  int? _branchId;

  // State
  bool _loading = false;
  String? _error;

  _LedgerResult? _result;
  int _currentPage = 1;
  int _perPage = 15;

  @override
  void initState() {
    super.initState();
    _partyType = (widget.partyType == 'vendor') ? 'vendor' : 'customer';
    _partyId = widget.partyId; // may be null

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
      final data = await _service.getLedger(
        partyType: _partyType,
        partyId: _partyId, // nullable: omitted from query when null
        from: _from == null ? null : _dateFmt.format(_from!),
        to: _to == null ? null : _dateFmt.format(_to!),
        page: _currentPage,
        perPage: _perPage,
        branchId: _branchId,
      );
      setState(() => _result = _LedgerResult.fromJson(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /* ------------------------------- Party picker ------------------------------- */

  Future<void> _pickParty() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final Map<String, dynamic>? picked = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _partyType == 'customer'
          ? CustomerPickerSheet(token: token)
          : VendorPickerSheet(token: token),
    );
    if (!mounted) return;

    setState(() {
      _selectedParty = picked;
      _partyId = picked?['id'] as int?;
      _currentPage = 1;
    });
    _fetch();
  }

  void _clearParty() {
    setState(() {
      _selectedParty = null;
      _partyId = null;
      _currentPage = 1;
    });
    _fetch();
  }

  /* ------------------------------- UI ------------------------------- */

  @override
  Widget build(BuildContext context) {
    final title = _partyType == 'customer' ? 'Customer Ledger' : 'Vendor A/P';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
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
            _buildFilters(),
            if (_loading)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              _buildError()
            else if (_result == null)
              const SliverFillRemaining(hasScrollBody: false, child: SizedBox()) // initial empty while fetching
            else ...[
              _buildOpenings(),
              _buildTable(),
              _buildPagination(),
            ],
          ],
        ),
      ),
      bottomNavigationBar: (_result == null)
          ? null
          : _BottomBarSummary(
              opening: _result!.opening,
              openingForPage: _result!.openingForPage,
              currency: _currency,
            ),
    );
  }

  SliverToBoxAdapter _buildFilters() {
    final labelAll = _partyType == 'customer' ? 'All customers' : 'All vendors';
    final partyLabel = _selectedParty?['first_name']?.toString().trim();
    final visibleLabel = (partyLabel == null || partyLabel.isEmpty)
        ? (_partyId == null ? labelAll : '${_partyType == "customer" ? "Customer" : "Vendor"} #$_partyId')
        : partyLabel;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Party picker (optional)
            OutlinedButton.icon(
              onPressed: _pickParty,
              icon: const Icon(Icons.search_rounded),
              label: Text(visibleLabel, overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (_partyId != null)
              IconButton(
                tooltip: 'Clear selection',
                onPressed: _clearParty,
                icon: const Icon(Icons.clear_rounded),
              ),

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

  SliverToBoxAdapter _buildOpenings() {
    final o = _result!;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            _StatCard(label: 'Opening', value: _currency.format(o.opening)),
            const SizedBox(width: 8),
            _StatCard(label: 'Opening (for page)', value: _currency.format(o.openingForPage)),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildTable() {
    final rows = _result?.items ?? [];
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
                    child: Text('No entries for selected filters', style: TextStyle(color: Colors.grey.shade600)),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final dt = _tryParse(r.date);
                      final dateStr = dt != null ? _dateTimeFmt.format(dt) : r.date;
                      final isNeg = r.balance < 0;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            _Cell(flex: 2, child: Text(dateStr, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
                            _Cell(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.memo, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(r.accountName, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                ],
                              ),
                            ),
                            _Cell(child: Text(r.debit == 0 ? '—' : _currency.format(r.debit), textAlign: TextAlign.right)),
                            _Cell(child: Text(r.credit == 0 ? '—' : _currency.format(r.credit), textAlign: TextAlign.right)),
                            _Cell(
                              child: Text(
                                _currency.format(r.balance),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isNeg ? Colors.red.shade600 : null,
                                ),
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

  DateTime? _tryParse(String v) {
    try { return DateTime.parse(v); } catch (_) { return null; }
  }
}

/* ------------------------------- UI Bits ------------------------------- */

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
          _Cell(flex: 2, child: Text('Date', style: th)),
          _Cell(flex: 3, child: Text('Memo / Account', style: th)),
          _Cell(child: Text('Debit', textAlign: TextAlign.right, style: th)),
          _Cell(child: Text('Credit', textAlign: TextAlign.right, style: th)),
          _Cell(child: Text('Balance', textAlign: TextAlign.right, style: th)),
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

/* ------------------------------- Models ------------------------------- */

class _LedgerResult {
  final String partyType;
  final int? partyId; // nullable if API returns it missing
  final double opening;
  final double openingForPage;
  final List<_LedgerRow> items;
  final _Pagination pagination;

  _LedgerResult({
    required this.partyType,
    required this.partyId,
    required this.opening,
    required this.openingForPage,
    required this.items,
    required this.pagination,
  });

  factory _LedgerResult.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '0') ?? 0.0;
    int? iN(dynamic v) => (v == null) ? null : ((v is num) ? v.toInt() : int.tryParse(v.toString()));

    return _LedgerResult(
      partyType: (json['party_type'] ?? '').toString(),
      partyId: iN(json['party_id']),
      opening: d(json['opening']),
      openingForPage: d(json['opening_for_page']),
      items: (json['items'] as List? ?? []).map((e) => _LedgerRow.fromJson(e)).toList(),
      pagination: _Pagination.fromJson({
        'current_page': json['current_page'],
        'per_page': json['per_page'],
        'last_page': json['last_page'],
        'total': json['total'],
      }),
    );
  }
}

class _LedgerRow {
  final int postingId;
  final int journalEntryId;
  final String date; // keep raw for formatting
  final int branchId;
  final String accountName;
  final String memo;
  final double debit;
  final double credit;
  final double balance;

  _LedgerRow({
    required this.postingId,
    required this.journalEntryId,
    required this.date,
    required this.branchId,
    required this.accountName,
    required this.memo,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  factory _LedgerRow.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '0') ?? 0.0;
    int i(dynamic v) => (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;

    return _LedgerRow(
      postingId: i(json['posting_id']),
      journalEntryId: i(json['journal_entry_id']),
      date: (json['date'] ?? '').toString(),
      branchId: i(json['branch_id']),
      accountName: (json['account_name'] ?? '').toString(),
      memo: (json['memo'] ?? '').toString(),
      debit: d(json['debit']),
      credit: d(json['credit']),
      balance: d(json['balance']),
    );
  }
}

class _Pagination {
  final int currentPage;
  final int perPage;
  final int lastPage;
  final int total;

  _Pagination({
    required this.currentPage,
    required this.perPage,
    required this.lastPage,
    required this.total,
  });

  factory _Pagination.fromJson(Map<String, dynamic> json) {
    int i(dynamic v) => (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
    return _Pagination(
      currentPage: i(json['current_page']),
      perPage: i(json['per_page']),
      lastPage: i(json['last_page']),
      total: i(json['total']),
    );
  }
}

class _BottomBarSummary extends StatelessWidget {
  final double opening;
  final double openingForPage;
  final NumberFormat currency;

  const _BottomBarSummary({
    super.key,
    required this.opening,
    required this.openingForPage,
    required this.currency,
  });

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
          const Text('Opening', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          _Chip(label: currency.format(opening)),
          const SizedBox(width: 16),
          Text('Page Opening', style: TextStyle(fontWeight: FontWeight.w600, color: primary)),
          const SizedBox(width: 8),
          _Chip(label: currency.format(openingForPage), highlight: true, color: primary),
          const Spacer(),
          Text('Double-entry • Running balance', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool highlight;
  final Color? color;
  const _Chip({required this.label, this.highlight = false, this.color});

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
      child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: fg)),
    );
  }
}
