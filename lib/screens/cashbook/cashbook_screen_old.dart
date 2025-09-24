import 'dart:async';
import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/cashbook_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CashBookScreen extends StatefulWidget {
  const CashBookScreen({super.key});

  @override
  State<CashBookScreen> createState() => _CashBookScreenState();
}

class _CashBookScreenState extends State<CashBookScreen> {
  // Services
  late CommonService _commonService;
  late CashBookService _cashService;

  // Data (transactions mode)
  List<dynamic> _txns = [];

  // Data (daily mode)
  List<Map<String, dynamic>> _dailyRows = [];

  // Dropdown data
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _accounts = []; // optional

  // Flags
  bool _loading = true;
  bool _dailyMode = false; // false => Transactions, true => Daily

  // Pagination
  int _currentPage = 1;
  int _lastPage = 1;

  // Totals (transactions)
  String _opening = "0.00";
  String _inflow = "0.00";
  String _outflow = "0.00";
  String _net = "0.00";
  String _closing = "0.00";
  String _pageInflow = "0.00";
  String _pageOutflow = "0.00";

  // Totals (daily)
  String _dOpening = "0.00";
  String _dTotIn = "0.00";
  String _dTotOut = "0.00";
  String _dTotExp = "0.00";
  String _dTotNet = "0.00";
  String _dTotClosing = "0.00";
  String _dPageIn = "0.00";
  String _dPageOut = "0.00";
  String _dPageExp = "0.00";
  String _dPageNet = "0.00";

  // Filters
  String? _accountId; // optional
  String? _method; // cash|card|bank|wallet
  String? _type; // receipt|payment|expense|transfer_in|transfer_out
  String? _search;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  // static dropdowns
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
    _commonService = CommonService(token: token);
    _cashService = CashBookService(token: token);
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    await Future.wait([
      _fetchBranches(),
      _fetchAccounts(),
    ]);
    _fetch(page: 1);
  }

  void _fetch({int page = 1}) {
    if (_dailyMode) {
      _fetchDailySummary(page: page);
    } else {
      _fetchCashBook(page: page);
    }
  }

  Future<void> _fetchBranches() async {
    try {
      final result = await _commonService.getBranches();
      setState(() => _branches = result);
    } catch (_) {}
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
      _fetch(page: 1);
    }
  }

  // ========= Transactions fetch =========
  Future<void> _fetchCashBook({int page = 1}) async {
    setState(() => _loading = true);
    final globalBranchId = context.read<BranchProvider>().selectedBranchId;

    try {
      final res = await _cashService.getCashBook(
        page: page,
        perPage: 50,
        status: "approved",
        accountId: _accountId,
        branchId: globalBranchId?.toString(),
        dateFrom: _dateFrom != null ? _fmtDate(_dateFrom!) : null,
        dateTo: _dateTo != null ? _fmtDate(_dateTo!) : null,
        source: null, // "sales" | "purchases" (optional)
        type: _type,
        method: _method,
        amountMin: null,
        amountMax: null,
        search: _search,
      );

      final data = res["data"] ?? res;

      setState(() {
        _txns = List<Map<String, dynamic>>.from(data['transactions'] ?? []);
        _opening = (data['opening_balance'] ?? "0.00").toString();
        _inflow = (data['inflow'] ?? "0.00").toString();
        _outflow = (data['outflow'] ?? "0.00").toString();
        _net = (data['net_change'] ?? "0.00").toString();
        _closing = (data['closing_balance'] ?? "0.00").toString();
        _pageInflow = (data['page_inflow'] ?? "0.00").toString();
        _pageOutflow = (data['page_outflow'] ?? "0.00").toString();

        final p = data['pagination'] ?? {};
        _currentPage = (p['current_page'] ?? 1) as int;
        _lastPage = (p['last_page'] ?? 1) as int;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  // ========= Daily Summary fetch =========
  Future<void> _fetchDailySummary({int page = 1}) async {
    setState(() => _loading = true);
    final globalBranchId = context.read<BranchProvider>().selectedBranchId;

    try {
      final res = await _cashService.getCashBookDailySummary(
        page: page,
        perPage: 30, // requested page size
        status: "approved",
        accountId: _accountId,
        branchId: globalBranchId?.toString(),
        dateFrom: _dateFrom != null ? _fmtDate(_dateFrom!) : null,
        dateTo: _dateTo != null ? _fmtDate(_dateTo!) : null,
        source: null, // aggregate across sources
        type: null,   // keep null; daily sums should include all movement types
        method: _method,
        amountMin: null,
        amountMax: null,
        search: _search,
      );

      final data = res["data"] ?? res;
      final totals = (data['totals'] ?? {}) as Map<String, dynamic>;
      final pageTotals = (data['page_totals'] ?? {}) as Map<String, dynamic>;

      setState(() {
        _dOpening   = (data['opening_balance'] ?? "0.00").toString();
        _dTotIn     = (totals['payment_in'] ?? "0.00").toString();
        _dTotOut    = (totals['payment_out'] ?? "0.00").toString();
        _dTotExp    = (totals['expense'] ?? "0.00").toString();
        _dTotNet    = (totals['net'] ?? "0.00").toString();
        _dTotClosing= (totals['closing'] ?? "0.00").toString();

        _dPageIn    = (pageTotals['payment_in'] ?? "0.00").toString();
        _dPageOut   = (pageTotals['payment_out'] ?? "0.00").toString();
        _dPageExp   = (pageTotals['expense'] ?? "0.00").toString();
        _dPageNet   = (pageTotals['net'] ?? "0.00").toString();

        _dailyRows = List<Map<String, dynamic>>.from(data['rows'] ?? []);

        final p = data['pagination'] ?? {};
        _currentPage = (p['current_page'] ?? 1) as int;
        _lastPage = (p['last_page'] ?? 1) as int;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  // ========= UI Blocks =========
  Widget _totalsHeader() {
    TextStyle label = const TextStyle(fontSize: 12, color: Colors.grey);
    TextStyle value = const TextStyle(fontSize: 16, fontWeight: FontWeight.bold);

    Widget cell(String t, String v, {Color? color}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(t, style: label), Text(v, style: value.copyWith(color: color))],
        );

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: _dailyMode
              ? [
                  cell("Opening", _dOpening),
                  cell("In", _dTotIn),
                  cell("Out", _dTotOut),
                  cell("Expense", _dTotExp),
                  cell("Net", _dTotNet, color: (_parse(_dTotNet) >= 0) ? Colors.green : Colors.red),
                  cell("Closing", _dTotClosing),
                  const Divider(),
                  cell("Page In", _dPageIn),
                  cell("Page Out", _dPageOut),
                  cell("Page Exp", _dPageExp),
                  cell("Page Net", _dPageNet, color: (_parse(_dPageNet) >= 0) ? Colors.green : Colors.red),
                ]
              : [
                  cell("Opening", _opening),
                  cell("Inflow", _inflow),
                  cell("Outflow", _outflow),
                  cell("Net", _net, color: (_parse(_net) >= 0) ? Colors.green : Colors.red),
                  cell("Closing", _closing),
                  const Divider(),
                  cell("Page Inflow", _pageInflow),
                  cell("Page Outflow", _pageOutflow),
                ],
        ),
      ),
    );
  }

  double _parse(String s) => double.tryParse(s) ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final noBranch = context.watch<BranchProvider>().isAll;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Cash Book"),
        actions: [
          // Transactions / Daily toggle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ToggleButtons(
              isSelected: [_dailyMode == false, _dailyMode == true],
              onPressed: (idx) {
                final newDaily = idx == 1;
                if (newDaily != _dailyMode) {
                  setState(() {
                    _dailyMode = newDaily;
                    _currentPage = 1;
                  });
                  _fetch(page: 1);
                }
              },
              borderRadius: BorderRadius.circular(8),
              constraints: const BoxConstraints(minWidth: 90),
              children: const [
                Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("Transactions")),
                Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("Daily")),
              ],
            ),
          ),
          const SizedBox(width: 8),
          BranchIndicator(tappable: false),
          IconButton(
            onPressed: () => _fetch(page: 1),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _dailyMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _addExpenseDialog,
              icon: const Icon(Icons.remove_circle),
              label: const Text("Add Expense"),
            ),
      body: Column(
        children: [
          // Filters row 1
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                if (_accounts.isNotEmpty)
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _accountId,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: "Account",
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String>(value: null, child: Text("All Accounts")),
                        ..._accounts.map((a) => DropdownMenuItem<String>(
                              value: a['id'].toString(),
                              child: Text("${a['name']} (${a['code'] ?? ''})"),
                            )),
                      ],
                      onChanged: (val) {
                        setState(() => _accountId = val);
                        _fetch(page: 1);
                      },
                    ),
                  ),
                if (_accounts.isNotEmpty) const SizedBox(width: 8),

                // Branch (display-only since global BranchProvider already applies)
                if (noBranch)
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: null,
                      decoration: const InputDecoration(
                        labelText: "Branch (Global applies)",
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem<String>(value: null, child: Text("All Branches")),
                      ],
                      onChanged: (_) {},
                    ),
                  ),
              ],
            ),
          ),

          // Filters row 2
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _method,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: "Method",
                      border: OutlineInputBorder(),
                    ),
                    items: _methodOptions
                        .map((m) => DropdownMenuItem<String>(
                              value: m['value'] as String?,
                              child: Text(m['label'] as String),
                            ))
                        .toList(),
                    onChanged: (val) {
                      setState(() => _method = val);
                      _fetch(page: 1);
                    },
                  ),
                ),
                const SizedBox(width: 8),

                if (!_dailyMode)
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _type,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: "Type",
                        border: OutlineInputBorder(),
                      ),
                      items: _typeOptions
                          .map((t) => DropdownMenuItem<String>(
                                value: t['value'] as String?,
                                child: Text(t['label'] as String),
                              ))
                          .toList(),
                      onChanged: (val) {
                        setState(() => _type = val);
                        _fetch(page: 1);
                      },
                    ),
                  )
                else
                  const Spacer(),

                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: "Search",
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      setState(() => _search = v);
                      _fetch(page: 1);
                    },
                  ),
                ),
              ],
            ),
          ),

          // Date range
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDateRange,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: "Date Range",
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        (_dateFrom == null && _dateTo == null)
                            ? "All dates"
                            : "${_fmtDate(_dateFrom!)} → ${_fmtDate(_dateTo!)}",
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _dateFrom = null;
                      _dateTo = null;
                      _currentPage = 1;
                    });
                    _fetch(page: 1);
                  },
                  icon: const Icon(Icons.clear),
                  label: const Text("Clear Dates"),
                ),
              ],
            ),
          ),

          // Totals
          _totalsHeader(),

          // List + pagination
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_dailyMode ? _buildDailyList() : _buildTxnList()),
          ),
        ],
      ),
    );
  }

  Widget _buildTxnList() {
    if (_txns.isEmpty) return const Center(child: Text("No transactions found"));
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _txns.length,
            itemBuilder: (_, i) {
              final t = _txns[i];
              final type = (t['type'] ?? '').toString();
              final date = (t['date'] ?? '').toString();
              final amount = (t['amount'] ?? '0.00').toString();
              final method = (t['method'] ?? '').toString();
              final note = (t['note'] ?? '').toString();
              final reference = (t['reference'] ?? '').toString();
              final running = (t['running_balance'] ?? '0.00').toString();
              final source = (t['source'] ?? '').toString();

              final isIn = (type == 'receipt' || type == 'transfer_in');
              final sign = isIn ? '+' : '-';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                child: ListTile(
                  title: Text(
                    "$date • ${type.toUpperCase()} • $sign$amount",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isIn ? Colors.green : Colors.red,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (reference.isNotEmpty) Text("Ref: $reference"),
                      if (method.isNotEmpty) Text("Method: $method"),
                      if (source.isNotEmpty) Text("Source: $source"),
                      if (note.isNotEmpty) Text(note),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: const [
                      Text("Running"),
                    ],
                  ),
                  leading: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.account_balance_wallet),
                      Text(running, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _paginationBar(),
      ],
    );
  }

  Widget _buildDailyList() {
    if (_dailyRows.isEmpty) return const Center(child: Text("No daily data"));
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _dailyRows.length,
            itemBuilder: (_, i) {
              final r = _dailyRows[i];
              final date = (r['date'] ?? '').toString();
              final pin = (r['payment_in'] ?? '0.00').toString();
              final pout = (r['payment_out'] ?? '0.00').toString();
              final exp = (r['expense'] ?? '0.00').toString();
              final net = (r['net'] ?? '0.00').toString();
              final closing = (r['closing'] ?? '0.00').toString();
              final opening = (r['opening'] ?? '0.00').toString();

              final netVal = double.tryParse(net) ?? 0.0;
              final netColor = netVal >= 0 ? Colors.green : Colors.red;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                child: ListTile(
                  title: Text(date, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _kv("Opening", opening, bold: true),
                        _kv("In", pin),
                        _kv("Out", pout),
                        _kv("Expense", exp),
                        _kv("Net", net, color: netColor, bold: true),
                        _kv("Closing", closing, bold: true),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _paginationBar(),
      ],
    );
  }

  Widget _kv(String k, String v, {Color? color, bool bold = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          v,
          style: TextStyle(
            fontSize: 16,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _paginationBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: _currentPage > 1 ? () => _fetch(page: _currentPage - 1) : null,
            child: const Text("Previous"),
          ),
          const SizedBox(width: 16),
          Text("Page $_currentPage of $_lastPage"),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: _currentPage < _lastPage ? () => _fetch(page: _currentPage + 1) : null,
            child: const Text("Next"),
          ),
        ],
      ),
    );
  }

  // ======= Add Expense dialog (unchanged) =======
  Future<void> _addExpenseDialog() async {
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    String? method = 'cash';
    String? accountId; // optional
    DateTime? txnDate = DateTime.now();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text("Add Expense"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: const InputDecoration(
                    labelText: "Payment Method",
                    border: OutlineInputBorder(),
                  ),
                  items: _methodOptions
                      .where((m) => m['value'] != null)
                      .map((m) => DropdownMenuItem<String>(
                            value: m['value'] as String,
                            child: Text(m['label'] as String),
                          ))
                      .toList(),
                  onChanged: (val) => setStateDialog(() => method = val),
                ),
                const SizedBox(height: 12),
                if (_accounts.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: accountId,
                    decoration: const InputDecoration(
                      labelText: "Account (optional)",
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text("Auto by Method"),
                      ),
                      ..._accounts.map((a) => DropdownMenuItem<String>(
                            value: a['id'].toString(),
                            child: Text("${a['name']} (${a['code'] ?? ''})"),
                          ))
                    ],
                    onChanged: (val) => setStateDialog(() => accountId = val),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: "Amount",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(
                    labelText: "Reference (optional)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: "Note (optional)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: txnDate ?? DateTime.now(),
                      firstDate: DateTime(2020, 1, 1),
                      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                    );
                    if (picked != null) setStateDialog(() => txnDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: "Transaction Date",
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      txnDate != null ? _fmtDate(txnDate!) : "Select date (optional)",
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text) ?? 0;
                if (amount <= 0) return;

                final globalBranchId =
                    context.read<BranchProvider>().selectedBranchId;

                try {
                  await _cashService.createExpense(
                    accountId: accountId,
                    method: accountId == null ? method : null,
                    amount: amount.toStringAsFixed(2),
                    txnDate: txnDate != null ? _fmtDate(txnDate!) : null,
                    branchId: globalBranchId?.toString(),
                    reference: refCtrl.text.trim().isNotEmpty ? refCtrl.text.trim() : null,
                    note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                    status: "approved",
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    _fetch(page: _currentPage);
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }
}
