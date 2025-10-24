import 'dart:async';
import 'package:enterprise_pos/api/cashbook_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cashbook_daily_summary_screen.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cb_date_range_bar.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cb_filters.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cb_totals.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cb_pagination.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Simple model for one expense line (top-level so Dart treats it as a type).
class _ExpenseLine {
  String? accountId;
  final TextEditingController amount = TextEditingController();
  final TextEditingController memo = TextEditingController();
  void dispose() {
    amount.dispose();
    memo.dispose();
  }
}

class DayBookScreen extends StatefulWidget {
  const DayBookScreen({super.key});

  @override
  State<DayBookScreen> createState() => _DayBookScreenState();
}

class _DayBookScreenState extends State<DayBookScreen> {
  // Services
  late CashBookService _cashService;

  // Data
  List<Map<String, dynamic>> _dailyRows = [];
  List<Map<String, dynamic>> _accounts = [];

  // Flags
  bool _loading = true;

  // Pagination / ordering
  int _currentPage = 1;
  int _lastPage = 1;
  final int _perPage = 30;
  final String _order = 'desc'; // newest first

  // Totals (overall + page)
  String _dOpening = "0.00",
      _dTotIn = "0.00",
      _dTotOut = "0.00",
      _dTotExp = "0.00",
      _dTotNet = "0.00",
      _dTotClosing = "0.00",
      _dPageIn = "0.00",
      _dPageOut = "0.00",
      _dPageExp = "0.00",
      _dPageNet = "0.00";

  // Filters (only branch/date affect /daybook; others are kept for UI continuity)
  String? _accountId; // ignored by /daybook
  String? _method; // ignored by /daybook
  String? _type; // ignored by /daybook
  String? _search; // ignored by /daybook
  DateTime? _dateFrom;
  DateTime? _dateTo;

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

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _cashService = CashBookService(token: token);
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    await _fetchAccounts();
    await _fetchDaybook(page: 1);
  }

  Future<void> _fetchAccounts() async {
    try {
      final list = await _cashService.getAccounts(isActive: true);
      setState(() => _accounts = list);
    } catch (_) {
      setState(() => _accounts = []);
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initialFirst = _dateFrom ?? now.subtract(const Duration(days: 30));
    final initialLast = _dateTo ?? now;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: initialFirst, end: initialLast),
    );
    if (range != null) {
      setState(() {
        _dateFrom = range.start;
        _dateTo = range.end;
        _currentPage = 1;
      });
      _fetchDaybook(page: 1);
    }
  }

  // ======= Daybook fetch (with pagination + desc order) =======
  Future<void> _fetchDaybook({int page = 1}) async {
    setState(() => _loading = true);
    final globalBranchId = context.read<BranchProvider>().selectedBranchId;

    try {
      final res = await _cashService.getDayBookSummary(
        branchId: globalBranchId?.toString(), // nullable → all branches
        dateFrom: _dateFrom != null
            ? _fmtDate(_dateFrom!)
            : null, // nullable → server defaults last 30 days
        dateTo: _dateTo != null ? _fmtDate(_dateTo!) : null,
        page: page,
        perPage: _perPage,
        order: _order,
      );

      // Expected shape from backend:
      // {
      //   opening,
      //   totals: { in, out, expense, net, closing },
      //   page_totals: { in, out, expense, net },
      //   days: [ {date, opening, in, out, expense, net, closing}, ... ],
      //   pagination: { total, per_page, current_page, last_page },
      //   order
      // }

      final opening = (res['opening'] ?? 0).toString();
      final totals = Map<String, dynamic>.from(res['totals'] ?? {});
      final pageTotals = Map<String, dynamic>.from(res['page_totals'] ?? {});
      final days = List<Map<String, dynamic>>.from(res['days'] ?? const []);
      final p = Map<String, dynamic>.from(res['pagination'] ?? {});

      setState(() {
        _dOpening = opening;
        _dTotIn = (totals['in'] ?? 0).toString();
        _dTotOut = (totals['out'] ?? 0).toString();
        _dTotExp = (totals['expense'] ?? 0).toString();
        _dTotNet = (totals['net'] ?? 0).toString();
        _dTotClosing = (totals['closing'] ?? 0).toString();

        // Page totals (slice totals)
        _dPageIn = (pageTotals['in'] ?? 0).toString();
        _dPageOut = (pageTotals['out'] ?? 0).toString();
        _dPageExp = (pageTotals['expense'] ?? 0).toString();
        _dPageNet = (pageTotals['net'] ?? 0).toString();

        _dailyRows = days
            .map(
              (m) => {
                'date': m['date'],
                'opening': m['opening'],
                'in': m['in'],
                'out': m['out'],
                'expense': m['expense'],
                'net': m['net'],
                'closing': m['closing'],
              },
            )
            .toList();

        _currentPage = (p['current_page'] ?? 1) as int;
        _lastPage = (p['last_page'] ?? 1) as int;

        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  double _parse(String s) => double.tryParse(s) ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final noBranch = context.watch<BranchProvider>().isAll;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Day Book"),
        actions: [
          const BranchIndicator(tappable: false),
          IconButton(
            onPressed: () => _fetchDaybook(page: _currentPage),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Two FABs: bulk + single
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'fab-bulk-expense',
            onPressed: _addExpensesBulkDialog,
            icon: const Icon(Icons.playlist_add),
            label: const Text("Add Expense"),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters kept for UI; only branch/date affect daybook.
          CBFilters(
            accounts: _accounts,
            showBranchNote: noBranch,
            accountValue: _accountId,
            methodValue: _method,
            typeValue: _type,
            methodOptions: _methodOptions,
            typeOptions: _typeOptions,
            showType: false, // daybook ignores type; keep hidden
            onAccountChanged: (v) {
              setState(() => _accountId = v);
              _fetchDaybook(page: 1);
            },
            onMethodChanged: (v) {
              setState(() => _method = v);
              _fetchDaybook(page: 1);
            },
            onTypeChanged: (v) {
              setState(() => _type = v);
              _fetchDaybook(page: 1);
            },
            onSearchSubmit: (s) {
              setState(() => _search = s);
              _fetchDaybook(page: 1);
            },
          ),

          CBDateRangeBar(
            from: _dateFrom,
            to: _dateTo,
            fmt: _fmtDate,
            onPick: _pickDateRange,
            onClear: () {
              setState(() {
                _dateFrom = null;
                _dateTo = null; // server default: last 30 days
                _currentPage = 1;
              });
              _fetchDaybook(page: 1);
            },
          ),

          // Totals row (now shows expense & page-expense)
          CBTotals(
            dailyMode: true, // always daily
            dOpening: _dOpening,
            dIn: _dTotIn,
            dOut: _dTotOut,
            dExp: _dTotExp,
            dNet: _dTotNet,
            dClosing: _dTotClosing,
            dPageIn: _dPageIn,
            dPageOut: _dPageOut,
            dPageExp: _dPageExp,
            dPageNet: _dPageNet,
            // legacy transaction totals not used here:
            opening: "0.00",
            inflow: "0.00",
            outflow: "0.00",
            net: "0.00",
            closing: "0.00",
            pageInflow: "0.00",
            pageOutflow: "0.00",
            parse: _parse,
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : CashbookDailySummaryScreen(
                    rows: _dailyRows, // server already returns DESC order
                    fetch: () async => _fetchDaybook(page: _currentPage),
                  ),
          ),

          // Pagination (server-driven)
          CBPagination(
            currentPage: _currentPage,
            lastPage: _lastPage,
            onPrev: _currentPage > 1
                ? () => _fetchDaybook(page: _currentPage - 1)
                : null,
            onNext: _currentPage < _lastPage
                ? () => _fetchDaybook(page: _currentPage + 1)
                : null,
          ),
        ],
      ),
    );
  }

  // ======= Single expense dialog (posts to /cashbook/expense) =======
  // Future<void> _addExpenseDialog() async {
  //   final amountCtrl = TextEditingController();
  //   final refCtrl = TextEditingController();
  //   final noteCtrl = TextEditingController();

  //   String? method = 'cash';
  //   String? accountId; // optional
  //   DateTime? txnDate = DateTime.now();

  //   await showDialog(
  //     context: context,
  //     builder: (_) => StatefulBuilder(
  //       builder: (context, setStateDialog) => AlertDialog(
  //         title: const Text("Add Expense"),
  //         content: SingleChildScrollView(
  //           child: Column(
  //             mainAxisSize: MainAxisSize.min,
  //             children: [
  //               DropdownButtonFormField<String>(
  //                 value: method,
  //                 decoration: const InputDecoration(
  //                   labelText: "Payment Method",
  //                   border: OutlineInputBorder(),
  //                 ),
  //                 items: const [
  //                   DropdownMenuItem(value: 'cash', child: Text('Cash')),
  //                   DropdownMenuItem(value: 'card', child: Text('Card')),
  //                   DropdownMenuItem(value: 'bank', child: Text('Bank')),
  //                   DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
  //                 ],
  //                 onChanged: (val) => setStateDialog(() => method = val),
  //               ),
  //               const SizedBox(height: 12),
  //               if (_accounts.isNotEmpty)
  //                 DropdownButtonFormField<String>(
  //                   value: accountId,
  //                   decoration: const InputDecoration(
  //                     labelText: "Account (optional)",
  //                     border: OutlineInputBorder(),
  //                   ),
  //                   items: [
  //                     const DropdownMenuItem<String>(
  //                       value: null,
  //                       child: Text("Auto by Method"),
  //                     ),
  //                     ..._accounts.map(
  //                       (a) => DropdownMenuItem<String>(
  //                         value: a['id'].toString(),
  //                         child: Text("${a['name']} (${a['code'] ?? ''})"),
  //                       ),
  //                     ),
  //                   ],
  //                   onChanged: (val) => setStateDialog(() => accountId = val),
  //                 ),
  //               const SizedBox(height: 12),
  //               TextField(
  //                 controller: amountCtrl,
  //                 keyboardType: const TextInputType.numberWithOptions(
  //                   decimal: true,
  //                 ),
  //                 decoration: const InputDecoration(
  //                   labelText: "Amount",
  //                   border: OutlineInputBorder(),
  //                 ),
  //               ),
  //               const SizedBox(height: 12),
  //               TextField(
  //                 controller: refCtrl,
  //                 decoration: const InputDecoration(
  //                   labelText: "Reference (optional)",
  //                   border: OutlineInputBorder(),
  //                 ),
  //               ),
  //               const SizedBox(height: 12),
  //               TextField(
  //                 controller: noteCtrl,
  //                 decoration: const InputDecoration(
  //                   labelText: "Note (optional)",
  //                   border: OutlineInputBorder(),
  //                 ),
  //               ),
  //               const SizedBox(height: 12),
  //               InkWell(
  //                 onTap: () async {
  //                   final picked = await showDatePicker(
  //                     context: context,
  //                     initialDate: txnDate ?? DateTime.now(),
  //                     firstDate: DateTime(2020, 1, 1),
  //                     lastDate: DateTime(DateTime.now().year + 1, 12, 31),
  //                   );
  //                   if (picked != null) setStateDialog(() => txnDate = picked);
  //                 },
  //                 child: InputDecorator(
  //                   decoration: const InputDecoration(
  //                     labelText: "Transaction Date",
  //                     border: OutlineInputBorder(),
  //                   ),
  //                   child: Text(
  //                     txnDate != null
  //                         ? _fmtDate(txnDate!)
  //                         : "Select date (optional)",
  //                   ),
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //         actions: [
  //           TextButton(
  //             onPressed: () => Navigator.pop(context),
  //             child: const Text("Cancel"),
  //           ),
  //           ElevatedButton(
  //             onPressed: () async {
  //               final amount = double.tryParse(amountCtrl.text) ?? 0;
  //               if (amount <= 0) return;

  //               final globalBranchId = context
  //                   .read<BranchProvider>()
  //                   .selectedBranchId;

  //               try {
  //                 await _cashService.createExpense(
  //                   accountId: accountId,
  //                   method: accountId == null ? method : null,
  //                   amount: amount.toStringAsFixed(2),
  //                   txnDate: txnDate != null ? _fmtDate(txnDate!) : null,
  //                   branchId: globalBranchId?.toString(),
  //                   reference: refCtrl.text.trim().isNotEmpty
  //                       ? refCtrl.text.trim()
  //                       : null,
  //                   note: noteCtrl.text.trim().isNotEmpty
  //                       ? noteCtrl.text.trim()
  //                       : null,
  //                   status: "approved",
  //                 );
  //                 if (context.mounted) {
  //                   Navigator.pop(context);
  //                   _fetchDaybook(page: _currentPage); // refresh current page
  //                 }
  //               } catch (e) {
  //                 if (context.mounted) {
  //                   Navigator.pop(context);
  //                   ScaffoldMessenger.of(
  //                     context,
  //                   ).showSnackBar(SnackBar(content: Text(e.toString())));
  //                 }
  //               }
  //             },
  //             child: const Text("Save"),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  // ======= Bulk expense dialog (one JE, many lines) =======
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
                                    _fetchDaybook(page: _currentPage);
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
}
