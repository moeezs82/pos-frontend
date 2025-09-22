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

  // Data
  List<dynamic> _txns = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _accounts = []; // optional
  bool _loading = true;

  // Pagination
  int _currentPage = 1;
  int _lastPage = 1;

  // Totals
  String _opening = "0.00";
  String _inflow = "0.00";
  String _outflow = "0.00";
  String _net = "0.00";
  String _closing = "0.00";
  String _pageInflow = "0.00";
  String _pageOutflow = "0.00";

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
      _fetchAccounts(), // optional, safe if endpoint doesn't exist (returns empty)
    ]);
    _fetchCashBook(page: 1);
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
      });
      _fetchCashBook(page: 1);
    }
  }

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

      final data = res["data"] ?? res; // support ApiResponse or raw

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
      // Optional: show snackbar
      // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

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
                    _fetchCashBook(page: _currentPage);
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

  Widget _totalsHeader() {
    TextStyle label = const TextStyle(fontSize: 12, color: Colors.grey);
    TextStyle value = const TextStyle(fontSize: 16, fontWeight: FontWeight.bold);

    Widget cell(String t, String v) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(t, style: label), Text(v, style: value)],
        );

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            cell("Opening", _opening),
            cell("Inflow", _inflow),
            cell("Outflow", _outflow),
            cell("Net", _net),
            cell("Closing", _closing),
            const Divider(),
            cell("Page Inflow", _pageInflow),
            cell("Page Outflow", _pageOutflow),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final noBranch = context.watch<BranchProvider>().isAll;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Cash Book"),
        actions: [
          BranchIndicator(tappable: false),
          IconButton(
            onPressed: () => _fetchCashBook(page: 1),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpenseDialog,
        icon: const Icon(Icons.remove_circle),
        label: const Text("Add Expense"),
      ),
      body: Column(
        children: [
          // Filters bar
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // Account filter (optional)
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
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text("All Accounts"),
                        ),
                        ..._accounts.map((a) => DropdownMenuItem<String>(
                              value: a['id'].toString(),
                              child: Text("${a['name']} (${a['code'] ?? ''})"),
                            )),
                      ],
                      onChanged: (val) {
                        setState(() => _accountId = val);
                        _fetchCashBook(page: 1);
                      },
                    ),
                  ),
                if (_accounts.isNotEmpty) const SizedBox(width: 8),

                // Branch (local note; global BranchProvider already applied)
                if (noBranch)
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: null,
                      decoration: const InputDecoration(
                        labelText: "Branch (Global applies)",
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text("All Branches"),
                        ),
                      ],
                      onChanged: (_) {},
                    ),
                  ),
              ],
            ),
          ),

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
                      _fetchCashBook(page: 1);
                    },
                  ),
                ),
                const SizedBox(width: 8),
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
                      _fetchCashBook(page: 1);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: "Search",
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      setState(() => _search = v);
                      _fetchCashBook(page: 1);
                    },
                  ),
                ),
              ],
            ),
          ),

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
                    });
                    _fetchCashBook(page: 1);
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
                : _txns.isEmpty
                    ? const Center(child: Text("No transactions found"))
                    : Column(
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
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
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
                                      children: [
                                        const Text("Running"),
                                        Text(
                                          running,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton(
                                  onPressed: _currentPage > 1
                                      ? () => _fetchCashBook(page: _currentPage - 1)
                                      : null,
                                  child: const Text("Previous"),
                                ),
                                const SizedBox(width: 16),
                                Text("Page $_currentPage of $_lastPage"),
                                const SizedBox(width: 16),
                                ElevatedButton(
                                  onPressed: _currentPage < _lastPage
                                      ? () => _fetchCashBook(page: _currentPage + 1)
                                      : null,
                                  child: const Text("Next"),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
