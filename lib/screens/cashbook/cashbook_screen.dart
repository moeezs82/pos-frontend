import 'package:enterprise_pos/api/cashbook_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_create_screen.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cashbook_daily_summary_screen.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cb_date_range_bar.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cb_filters.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cb_mode_toggle.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cb_pagination.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cb_totals.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cb_txn_list.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CashBookScreen extends StatefulWidget {
  const CashBookScreen({super.key});

  @override
  State<CashBookScreen> createState() => _CashBookScreenState();
}

class _CashBookScreenState extends State<CashBookScreen> {
  // Services
  late CashBookService _cashService;

  // Data (transactions mode)
  List<Map<String, dynamic>> _txns = [];

  // Data (daily mode)
  List<Map<String, dynamic>> _dailyRows = [];

  // Dropdown data
  List<Map<String, dynamic>> _accounts = [];

  // Flags
  bool _loading = true;
  bool _dailyMode = true; // DEFAULT: Daily view

  // Pagination
  int _currentPage = 1;
  int _lastPage = 1;

  // Totals (transactions)
  String _opening = "0.00",
      _inflow = "0.00",
      _outflow = "0.00",
      _net = "0.00",
      _closing = "0.00",
      _pageInflow = "0.00",
      _pageOutflow = "0.00";

  // Totals (daily)
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

  // Per-method funds breakdown (Cash / Bank / KNET / …) for the daily summary.
  List<Map<String, dynamic>> _dByMethod = [];

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
    _cashService = CashBookService(token: token);
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    await _fetchAccounts();
    _fetch(page: 1); // defaults to daily
  }

  void _fetch({int page = 1}) {
    if (_dailyMode) {
      _fetchDailySummary(page: page);
    } else {
      _fetchCashBook(page: page);
    }
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
    } catch (_) {
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
        type: null, // keep null; daily sums should include all movement types
        method: _method,
        amountMin: null,
        amountMax: null,
        search: _search,
      );

      final data = res["data"] ?? res;
      final totals = (data['totals'] ?? {}) as Map<String, dynamic>;
      final pageTotals = (data['page_totals'] ?? {}) as Map<String, dynamic>;

      setState(() {
        _dOpening = (data['opening_balance'] ?? "0.00").toString();
        _dTotIn = (totals['payment_in'] ?? "0.00").toString();
        _dTotOut = (totals['payment_out'] ?? "0.00").toString();
        _dTotExp = (totals['expense'] ?? "0.00").toString();
        _dTotNet = (totals['net'] ?? "0.00").toString();
        _dTotClosing = (totals['closing'] ?? "0.00").toString();

        _dPageIn = (pageTotals['payment_in'] ?? "0.00").toString();
        _dPageOut = (pageTotals['payment_out'] ?? "0.00").toString();
        _dPageExp = (pageTotals['expense'] ?? "0.00").toString();
        _dPageNet = (pageTotals['net'] ?? "0.00").toString();

        _dailyRows = List<Map<String, dynamic>>.from(data['rows'] ?? []);
        _dByMethod = List<Map<String, dynamic>>.from(
          (data['by_method'] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? const [],
        );

        final p = data['pagination'] ?? {};
        _currentPage = (p['current_page'] ?? 1) as int;
        _lastPage = (p['last_page'] ?? 1) as int;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  double _parse(String s) => double.tryParse(s) ?? 0.0;

  /// Funds-by-method breakdown for the selected period: closing balance per
  /// method with opening / in / out. Answers "how much cash vs bank vs KNET".
  Widget _fundsByMethodCard() {
    String money(dynamic v) =>
        (v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0)
            .toStringAsFixed(2);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Funds by method',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 8),
            // Header
            Row(
              children: const [
                Expanded(flex: 3, child: Text('Method', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700))),
                Expanded(flex: 2, child: Text('Opening', textAlign: TextAlign.right, style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700))),
                Expanded(flex: 2, child: Text('In', textAlign: TextAlign.right, style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700))),
                Expanded(flex: 2, child: Text('Out', textAlign: TextAlign.right, style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700))),
                Expanded(flex: 2, child: Text('Closing', textAlign: TextAlign.right, style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700))),
              ],
            ),
            const Divider(height: 12),
            ..._dByMethod.map((m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text((m['name'] ?? m['method'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700))),
                      Expanded(flex: 2, child: Text(money(m['opening']), textAlign: TextAlign.right)),
                      Expanded(flex: 2, child: Text(money(m['in']), textAlign: TextAlign.right, style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600))),
                      Expanded(flex: 2, child: Text(money(m['out']), textAlign: TextAlign.right, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600))),
                      Expanded(flex: 2, child: Text(money(m['closing']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
                    ],
                  ),
                )),
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
          CBModeToggle(
            dailyMode: _dailyMode,
            onChanged: (bool makeDaily) {
              setState(() {
                _dailyMode = makeDaily;
                _currentPage = 1;
              });
              _fetch(page: 1);
            },
          ),
          const SizedBox(width: 8),
          const BranchIndicator(tappable: false),
          IconButton(
            onPressed: () => _fetch(page: 1),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: 
      FloatingActionButton.extended(
              onPressed: _openExpenseCreate,
              icon: const Icon(Icons.remove_circle),
              label: const Text("Add Expense"),
            ),
      body: Column(
        children: [
          CBFilters(
            accounts: _accounts,
            showBranchNote: false,
            accountValue: _accountId,
            methodValue: _method,
            typeValue: _type,
            methodOptions: _methodOptions,
            typeOptions: _typeOptions,
            showType: !_dailyMode,
            onAccountChanged: (v) {
              setState(() => _accountId = v);
              _fetch(page: 1);
            },
            onMethodChanged: (v) {
              setState(() => _method = v);
              _fetch(page: 1);
            },
            onTypeChanged: (v) {
              setState(() => _type = v);
              _fetch(page: 1);
            },
            onSearchSubmit: (s) {
              setState(() => _search = s);
              _fetch(page: 1);
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
                _dateTo = null;
                _currentPage = 1;
              });
              _fetch(page: 1);
            },
          ),

          CBTotals(
            dailyMode: _dailyMode,
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
            opening: _opening,
            inflow: _inflow,
            outflow: _outflow,
            net: _net,
            closing: _closing,
            pageInflow: _pageInflow,
            pageOutflow: _pageOutflow,
            parse: _parse,
          ),

          if (_dailyMode && _dByMethod.isNotEmpty) _fundsByMethodCard(),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_dailyMode
                      ? CashbookDailySummaryScreen(rows: _dailyRows, fetch: () async { await _fetchDailySummary(); },)
                      : CBTxnList(txns: _txns)),
          ),

          CBPagination(
            currentPage: _currentPage,
            lastPage: _lastPage,
            onPrev: _currentPage > 1
                ? () => _fetch(page: _currentPage - 1)
                : null,
            onNext: _currentPage < _lastPage
                ? () => _fetch(page: _currentPage + 1)
                : null,
          ),
        ],
      ),
    );
  }


  Future<void> _openExpenseCreate() async {
    // Consolidated: expenses are recorded via Cash Ledger → Other Expense.
    // Named route so a later Ctrl+E focuses this instance instead of duplicating.
    final created = await Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: PosRouteIds.cashLedgerCreate),
        builder: (_) => const CashLedgerCreateScreen(initialCategory: 'OTHER_EXPENSE'),
      ),
    );
    if (created == true && mounted) {
      _fetch(page: 1);
    }
  }
}
