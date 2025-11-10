import 'package:enterprise_pos/api/cashbook_service.dart';
import 'package:enterprise_pos/api/reports_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class ReportCashbookScreen extends StatefulWidget {
  const ReportCashbookScreen({super.key});

  @override
  State<ReportCashbookScreen> createState() => _ReportCashbookScreenState();
}

class _ExpenseLine {
  String? accountId;
  final TextEditingController amount = TextEditingController();
  final TextEditingController memo = TextEditingController();
  void dispose() {
    amount.dispose();
    memo.dispose();
  }
}

class _ReportCashbookScreenState extends State<ReportCashbookScreen> {
  final _currency = NumberFormat.simpleCurrency(decimalDigits: 2, name: "");
  final _dateFmt = DateFormat('yyyy-MM-dd');

  late ReportsService _service;
  late CashBookService _cashService;

  List<Map<String, dynamic>> _accounts = [];

  // Static dropdowns (kept for UI continuity)
  final _methodOptions = const [
    {'value': null, 'label': 'All methods'},
    {'value': 'cash', 'label': 'Cash'},
    {'value': 'card', 'label': 'Card'},
    {'value': 'bank', 'label': 'Bank'},
    {'value': 'wallet', 'label': 'Wallet'},
  ];
  final _typeOptions = const [
    {'value': null, 'label': 'All types'},
    {'value': 'receipt', 'label': 'Receipt (In)'},
    {'value': 'payment', 'label': 'Payment (Out)'},
    {'value': 'expense', 'label': 'Expense (Out)'},
    {'value': 'transfer_in', 'label': 'Transfer In'},
    {'value': 'transfer_out', 'label': 'Transfer Out'},
  ];

  String _fmtDate(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  Future<void> _addExpensesBulkDialog() async {
    final refCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    String? method = 'cash';
    String? payAccountId;
    DateTime? txnDate = DateTime.now();

    final List<_ExpenseLine> lines = <_ExpenseLine>[_ExpenseLine()];

    double _calcTotal() {
      double sum = 0;
      for (final l in lines) sum += double.tryParse(l.amount.text) ?? 0.0;
      return sum;
    }

    bool _canSave() {
      if (_calcTotal() <= 0) return false;
      for (final l in lines) {
        final amt = double.tryParse(l.amount.text) ?? 0.0;
        if ((l.accountId == null || l.accountId!.isEmpty) || amt <= 0)
          return false;
      }
      if ((payAccountId == null || payAccountId!.isEmpty) &&
          (method == null || method!.isEmpty))
        return false;
      return true;
    }

    String? _findAccountCode(String? id) {
      if (id == null || id.isEmpty) return null;
      final m = _accounts.firstWhere(
        (a) => a['id'].toString() == id,
        orElse: () => <String, dynamic>{},
      );
      return (m['code'] ?? '').toString().isEmpty ? null : m['code'].toString();
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 640),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Title
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          "Add Multiple Expenses",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: "Close",
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Content (scrollable)
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(right: 4, bottom: 4),
                      child: Column(
                        children: [
                          // Row 1: Method + Payment Account
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: method,
                                  decoration: const InputDecoration(
                                    labelText: "Payment Method",
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'cash',
                                      child: Text('Cash'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'card',
                                      child: Text('Card'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'bank',
                                      child: Text('Bank'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'wallet',
                                      child: Text('Wallet'),
                                    ),
                                  ],
                                  onChanged: (val) =>
                                      setStateDialog(() => method = val),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: payAccountId,
                                  decoration: const InputDecoration(
                                    labelText: "Payment Account (optional)",
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: [
                                    const DropdownMenuItem<String>(
                                      value: null,
                                      child: Text("Auto by Method"),
                                    ),
                                    ..._accounts.map(
                                      (a) => DropdownMenuItem<String>(
                                        value: a['id'].toString(),
                                        child: Text(
                                          "${a['name']} (${a['code'] ?? ''})",
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) =>
                                      setStateDialog(() => payAccountId = val),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Row 2: Date
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: txnDate ?? DateTime.now(),
                                firstDate: DateTime(2020, 1, 1),
                                lastDate: DateTime(
                                  DateTime.now().year + 1,
                                  12,
                                  31,
                                ),
                              );
                              if (picked != null)
                                setStateDialog(() => txnDate = picked);
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: "Transaction Date",
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  txnDate != null
                                      ? _fmtDate(txnDate!)
                                      : "Select date",
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Row 3: Reference + Note
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: refCtrl,
                                  decoration: const InputDecoration(
                                    labelText: "Reference (optional)",
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: noteCtrl,
                                  decoration: const InputDecoration(
                                    labelText: "Note (optional)",
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Lines header
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  "Expense Lines",
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => setStateDialog(
                                  () => lines.add(_ExpenseLine()),
                                ),
                                icon: const Icon(Icons.add),
                                label: const Text("Add line"),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Lines (no ListView -> no nested viewport)
                          ...List.generate(lines.length, (i) {
                            final l = lines[i];
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: i == lines.length - 1 ? 0 : 8,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Account
                                  Expanded(
                                    flex: 4,
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      value:
                                          (l.accountId == null ||
                                              l.accountId!.isEmpty)
                                          ? null
                                          : l.accountId,
                                      decoration: const InputDecoration(
                                        labelText: "Expense Account",
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items: _accounts.map((a) {
                                        return DropdownMenuItem<String>(
                                          value: a['id'].toString(),
                                          child: Text(
                                            "${a['name']} (${a['code'] ?? ''})",
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (val) => setStateDialog(
                                        () => l.accountId = val ?? '',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Amount
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: l.amount,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: "Amount",
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      onChanged: (_) => setStateDialog(() {}),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Line note
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: l.memo,
                                      decoration: const InputDecoration(
                                        labelText: "Line note (optional)",
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Remove
                                  IconButton(
                                    tooltip: "Remove line",
                                    onPressed: lines.length == 1
                                        ? null
                                        : () => setStateDialog(() {
                                            final removed = lines.removeAt(i);
                                            removed.dispose();
                                          }),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            );
                          }),

                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              "Total: ${_calcTotal().toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Cancel"),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text("Save"),
                        onPressed: _canSave()
                            ? () async {
                                final branchId = context
                                    .read<BranchProvider>()
                                    .selectedBranchId;
                                try {
                                  final payloadLines = lines.map((l) {
                                    final code = _findAccountCode(l.accountId);
                                    return {
                                      "account_id": l.accountId,
                                      if (code != null) "account_code": code,
                                      "amount":
                                          (double.tryParse(l.amount.text) ?? 0)
                                              .toStringAsFixed(2),
                                      if (l.memo.text.trim().isNotEmpty)
                                        "note": l.memo.text.trim(),
                                    };
                                  }).toList();

                                  await _cashService.createExpensesBulk(
                                    paymentAccountId: payAccountId,
                                    method:
                                        (payAccountId == null ||
                                            payAccountId!.isEmpty)
                                        ? method
                                        : null,
                                    branchId: branchId?.toString(),
                                    txnDate: txnDate != null
                                        ? _fmtDate(txnDate!)
                                        : null,
                                    reference: refCtrl.text.trim().isNotEmpty
                                        ? refCtrl.text.trim()
                                        : null,
                                    note: noteCtrl.text.trim().isNotEmpty
                                        ? noteCtrl.text.trim()
                                        : null,
                                    status: "approved",
                                    singleEntry: true,
                                    lines: payloadLines,
                                  );

                                  if (mounted) {
                                    Navigator.pop(context);
                                    _fetch();
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  }
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Cleanup if dialog is dismissed
    for (final l in lines) {
      l.dispose();
    }
  }



  // Filters
  DateTime? _from;
  DateTime? _to;
  int? _branchId;
  bool _includeBank = true;
  List<int> _accountIds = []; // optional override

  // State
  bool _loading = false;
  String? _error;

  _CashbookResult? _result;
  int? _currentPage; // nullable: when null we don't send 'page' (server returns all or its default)
  int _perPage = 1000; // server default

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to   = DateTime(now.year, now.month + 1, 0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = context.read<AuthProvider>().token!;
      _service = ReportsService(token: token);
      _cashService = CashBookService(token: token);
      _branchId = context.read<BranchProvider?>()?.selectedBranchId;
      _fetch();
      _fetchAccounts();
    });
  }

  Future<void> _fetchAccounts() async {
    try {
      final list = await _cashService.getAccounts(isActive: true);
      setState(() => _accounts = list);
    } catch (_) {
      setState(() => _accounts = []);
    }
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
        _currentPage = null; // reset; let server decide unless user paginates manually
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
      final data = await _service.getCashbookDaily(
        from: _from == null ? null : _dateFmt.format(_from!),
        to: _to == null ? null : _dateFmt.format(_to!),
        branchId: _branchId,
        includeBank: _includeBank,
        accountIds: _accountIds.isEmpty ? null : _accountIds,
        page: _currentPage,     // nullable (omit when null)
        perPage: _perPage,
      );
      setState(() => _result = _CashbookResult.fromJson(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAccountsDialog() async {
    final ctrl = TextEditingController(text: _accountIds.join(', '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Override Accounts (IDs)'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              hintText: 'e.g. 1000, 1010',
              labelText: 'Account IDs (comma separated)',
            ),
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
          ],
        );
      },
    );
    if (ok == true) {
      final raw = ctrl.text.trim();
      final ids = raw
          .split(',')
          .map((e) => int.tryParse(e.trim()))
          .where((v) => v != null)
          .cast<int>()
          .toList();
      setState(() {
        _accountIds = ids;
        _currentPage = null;
      });
      _fetch();
    }
  }

  /* -------------------------------- UI -------------------------------- */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cashbook — Daily'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Rows per page',
            onSelected: (v) {
              setState(() {
                _perPage = v;
                _currentPage = 1; // enable pagination explicitly if user chooses rows per page
              });
              _fetch();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 1000, child: Text('1000 per page (default)')),
              PopupMenuItem(value: 100, child: Text('100 per page')),
              PopupMenuItem(value: 30, child: Text('30 per page')),
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

    final accountsBadge = _result?.filters.accountIds ?? _accountIds;
    final usingBank = _result?.filters.includeBank ?? _includeBank;

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
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                // Include bank toggle
                // Row(
                //   mainAxisSize: MainAxisSize.min,
                //   children: [
                //     const Text('Include Bank'),
                //     Switch(
                //       value: _includeBank,
                //       onChanged: (v) {
                //         setState(() {
                //           _includeBank = v;
                //           _currentPage = null;
                //         });
                //         _fetch();
                //       },
                //     ),
                //   ],
                // ),
                // Accounts override
                OutlinedButton.icon(
                  onPressed: _addExpensesBulkDialog,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Add Expense'),
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
            const SizedBox(height: 8),
            // Small summary chips of active filters
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_branchId != null)
                  _FilterChip(label: 'Branch #$_branchId'),
                _FilterChip(label: usingBank ? 'Cash + Bank' : 'Cash only'),
                if (accountsBadge.isNotEmpty) _FilterChip(label: 'Accounts: ${accountsBadge.join(', ')}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildOpening() {
    final open = _result!.opening;
    final neg = open < 0;
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
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Opening', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      const SizedBox(height: 6),
                      Text(
                        _currency.format(open),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: neg ? Colors.red.shade600 : null,
                        ),
                      ),
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
                    child: Text('No data for selected range', style: TextStyle(color: Colors.grey.shade600)),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final negNet = r.net < 0;
                      final negClosing = r.closing < 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            _Cell(flex: 2, child: Text(r.date, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
                            _Cell(child: Text(_currency.format(r.receipts), textAlign: TextAlign.right)),
                            _Cell(child: Text(_currency.format(r.payments), textAlign: TextAlign.right)),
                            _Cell(child: Text(_currency.format(r.expense), textAlign: TextAlign.right)),
                            _Cell(
                              child: Text(
                                _currency.format(r.net),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: negNet ? Colors.red.shade600 : null,
                                ),
                              ),
                            ),
                            _Cell(
                              child: Text(
                                _currency.format(r.closing),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: negClosing ? Colors.red.shade600 : null,
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

  SliverToBoxAdapter _buildTotals() {
    final t = _result!.totals;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TotalChip(label: 'Receipts', value: _currency.format(t.receipts)),
            _TotalChip(label: 'Payments', value: _currency.format(t.payments)),
            _TotalChip(label: 'Expense', value: _currency.format(t.expense)),
            _TotalChip(label: 'Net', value: _currency.format(t.net), highlight: true),
            _TotalChip(label: 'Closing', value: _currency.format(t.closing), highlight: true),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildPagination() {
    final p = _result?.pagination;
    if (p == null) return const SliverToBoxAdapter(child: SizedBox(height: 24));
    if (p.lastPage <= 1) return const SliverToBoxAdapter(child: SizedBox(height: 24));

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
          _Cell(child: Text('Receipts', textAlign: TextAlign.right, style: th)),
          _Cell(child: Text('Payments', textAlign: TextAlign.right, style: th)),
          _Cell(child: Text('Expense', textAlign: TextAlign.right, style: th)),
          _Cell(child: Text('Net', textAlign: TextAlign.right, style: th)),
          _Cell(child: Text('Closing', textAlign: TextAlign.right, style: th)),
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

class _TotalChip extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _TotalChip({required this.label, required this.value, this.highlight = false});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final bg = highlight ? primary.withOpacity(0.06) : Colors.grey.shade100;
    final border = highlight ? primary.withOpacity(0.18) : Colors.grey.shade300;
    final fg = highlight ? primary : Colors.grey.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: fg)),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

/* ------------------------------- Models ------------------------------- */

class _CashbookResult {
  final double opening;
  final List<_CashbookRow> rows;
  final _CashbookTotals totals;
  final _CashbookFilters filters;
  final _Pagination? pagination;

  _CashbookResult({
    required this.opening,
    required this.rows,
    required this.totals,
    required this.filters,
    required this.pagination,
  });

  factory _CashbookResult.fromJson(Map<String, dynamic> json) {
    return _CashbookResult(
      opening: _d(json['opening']),
      rows: (json['rows'] as List? ?? []).map((e) => _CashbookRow.fromJson(e)).toList(),
      totals: _CashbookTotals.fromJson(json['totals'] ?? {}),
      filters: _CashbookFilters.fromJson(json['filters'] ?? {}),
      pagination: json['pagination'] == null ? null : _Pagination.fromJson(json['pagination']),
    );
  }
}

class _CashbookRow {
  final String date;
  final double receipts;
  final double payments;
  final double expense;
  final double net;
  final double closing;

  _CashbookRow({
    required this.date,
    required this.receipts,
    required this.payments,
    required this.expense,
    required this.net,
    required this.closing,
  });

  factory _CashbookRow.fromJson(Map<String, dynamic> json) {
    return _CashbookRow(
      date: (json['date'] ?? '').toString(),
      receipts: _d(json['receipts']),
      payments: _d(json['payments']),
      expense: _d(json['expense']),
      net: _d(json['net']),
      closing: _d(json['closing']),
    );
  }
}

class _CashbookTotals {
  final double receipts;
  final double payments;
  final double expense;
  final double net;
  final double closing;

  _CashbookTotals({
    required this.receipts,
    required this.payments,
    required this.expense,
    required this.net,
    required this.closing,
  });

  factory _CashbookTotals.fromJson(Map<String, dynamic> json) {
    return _CashbookTotals(
      receipts: _d(json['receipts']),
      payments: _d(json['payments']),
      expense: _d(json['expense']),
      net: _d(json['net']),
      closing: _d(json['closing']),
    );
  }
}

class _CashbookFilters {
  final String? from;
  final String? to;
  final int? branchId;
  final List<int> accountIds;
  final bool includeBank;

  _CashbookFilters({
    required this.from,
    required this.to,
    required this.branchId,
    required this.accountIds,
    required this.includeBank,
  });

  factory _CashbookFilters.fromJson(Map<String, dynamic> json) {
    return _CashbookFilters(
      from: json['from']?.toString(),
      to: json['to']?.toString(),
      branchId: (json['branch_id'] as num?)?.toInt(),
      accountIds: (json['account_ids'] as List? ?? []).map((e) => (e as num).toInt()).toList(),
      includeBank: (json['include_bank'] is bool)
          ? (json['include_bank'] as bool)
          : (json['include_bank']?.toString() == '1'),
    );
  }
}

class _Pagination {
  final int currentPage;
  final int perPage;
  final int lastPage;
  final int totalDays;

  _Pagination({required this.currentPage, required this.perPage, required this.lastPage, required this.totalDays});

  factory _Pagination.fromJson(Map<String, dynamic> json) {
    int i(dynamic v) => (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
    return _Pagination(
      currentPage: i(json['current_page']),
      perPage: i(json['per_page']),
      lastPage: i(json['last_page']),
      totalDays: i(json['total_days']),
    );
  }
}

/* -------------------------- helpers -------------------------- */
double _d(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '0') ?? 0.0;
