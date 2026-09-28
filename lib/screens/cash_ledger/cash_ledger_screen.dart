import 'package:enterprise_pos/api/cash_ledger_service.dart';
import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_void_action.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_create_screen.dart';
import 'package:enterprise_pos/screens/cash_ledger/day_book_detail_screen.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_subledgers.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// The unified Cash Ledger: a single view of ALL cash movements
/// (Customer receipts, vendor payments, expenses, Qameti, loans, etc.)
///
/// Two tabs over the SAME data source: a flat, filterable Ledger feed, and a
/// Day Book that groups the same movements by calendar day with opening/
/// closing balances, drilling down into any one day.
class CashLedgerScreen extends StatefulWidget {
  const CashLedgerScreen({super.key});

  @override
  State<CashLedgerScreen> createState() => _CashLedgerScreenState();
}

class _CashLedgerScreenState extends State<CashLedgerScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  final GlobalKey<_LedgerViewState> _ledgerKey = GlobalKey<_LedgerViewState>();
  String? _selectedDayDate;

  // Track which optional tabs are visible so we can rebuild the controller
  // when addon state changes (e.g., after a version-bump refresh mid-session).
  bool _loansTabVisible  = false;
  bool _qametiTabVisible = false;

  @override
  void initState() {
    super.initState();
    _rebuildController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Rebuild TabController if addon state changed (e.g., after a refresh).
    final auth = context.read<AuthProvider>();
    final loansNow  = auth.hasAddon('loan_module');
    final qametiNow = auth.hasAddon('qameti_module');
    if (loansNow != _loansTabVisible || qametiNow != _qametiTabVisible) {
      _rebuildController(loansNow: loansNow, qametiNow: qametiNow);
    }
  }

  void _rebuildController({bool? loansNow, bool? qametiNow}) {
    final auth = context.read<AuthProvider>();
    _loansTabVisible  = loansNow  ?? auth.hasAddon('loan_module');
    _qametiTabVisible = qametiNow ?? auth.hasAddon('qameti_module');

    final count = 3 // Ledger, Expenses, Day Book — always present
        + (_loansTabVisible  ? 1 : 0)
        + (_qametiTabVisible ? 1 : 0);

    final old = _tabController;
    _tabController = TabController(length: count, vsync: this);
    old?.dispose();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _openCreate() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CashLedgerCreateScreen()),
    );
    if (created == true) {
      _ledgerKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final showLoans = auth.hasAddon('loan_module');
    final showQameti = auth.hasAddon('qameti_module');

    final tabs = <Tab>[
      const Tab(text: 'Ledger', icon: Icon(Icons.receipt_long_rounded, size: 18)),
      if (showLoans)
        const Tab(text: 'Loans', icon: Icon(Icons.request_quote_rounded, size: 18)),
      if (showQameti)
        const Tab(text: 'Qameti', icon: Icon(Icons.savings_rounded, size: 18)),
      const Tab(text: 'Expenses', icon: Icon(Icons.receipt_rounded, size: 18)),
      const Tab(text: 'Day Book', icon: Icon(Icons.calendar_view_day_rounded, size: 18)),
    ];

    final bodies = <Widget>[
      _LedgerView(key: _ledgerKey),
      if (showLoans) const SubledgerView(kind: SubledgerKind.loans),
      if (showQameti) const SubledgerView(kind: SubledgerKind.qameti),
      const SubledgerView(kind: SubledgerKind.expenses),
      _DayBookView(onOpenDay: (date) => setState(() => _selectedDayDate = date)),
    ];

    if (_selectedDayDate != null) {
      return EnterprisePage(
        title: 'Cash Ledger',
        subtitle: 'Review one day without leaving the persistent Cash Ledger workspace.',
        icon: Icons.account_balance_wallet_outlined,
        actions: [
          OutlinedButton.icon(
            onPressed: () => setState(() => _selectedDayDate = null),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back to Day Book'),
          ),
          FilledButton.icon(
            onPressed: _openCreate,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Record Entry'),
          ),
        ],
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: DayBookDetailScreen(
          date: _selectedDayDate!,
          embedded: true,
          onBack: () => setState(() => _selectedDayDate = null),
        ),
      );
    }

    return EnterprisePage(
      title: 'Cash Ledger',
      subtitle: 'Review cash movements, expenses, loans and day-book balances using the existing accounting ledger.',
      icon: Icons.account_balance_wallet_outlined,
      actions: [
        FilledButton.icon(
          onPressed: _openCreate,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Record Entry'),
        ),
      ],
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textMuted,
              dividerColor: Colors.transparent,
              tabs: tabs,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: bodies,
            ),
          ),
        ],
      ),
    );
  }

}

/// Tab 1: the flat, filterable feed of every cash movement.
class _LedgerView extends StatefulWidget {
  const _LedgerView({super.key});

  @override
  State<_LedgerView> createState() => _LedgerViewState();
}

class _LedgerViewState extends State<_LedgerView> {
  late final CashLedgerService _service;
  final _money = const AppMoneyFormatter();

  bool _loading = true;
  bool _loadingFlow = true;

  static const int _requestedPerPage = 40;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 52;
  final ScrollController _pageScrollController = ScrollController();
  final ScrollController _scrollController = ScrollController();
  int _serverPerPage = _requestedPerPage;
  final Map<int, List<Map<String, dynamic>>> _pages = {};
  final Set<int> _loadingPages = {};
  int _lastPage = 1;
  int _total = 0;
  int _requestGeneration = 0;

  Map<String, dynamic> _summary = {};
  num _opening = 0;

  // Filters
  DateTime _dateFrom = DateTime.now().subtract(const Duration(days: 29));
  DateTime _dateTo = DateTime.now();
  /// cash_ledger_entry_id currently being voided (spinner on that row only).
  String? _voidingId;

  String _direction = 'all'; // in|out|all
  String _kind = 'all';      // all|module|received|sent|expense
  bool _fundsExpanded = false;

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _service = CashLedgerService(token: token);
    _scrollController.addListener(_onScroll);
    refresh();
  }

  @override
  void dispose() {
    _pageScrollController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  Future<void> refresh() async {
    await Future.wait([_fetchFlow(), _fetchList(page: 1, reset: true)]);
  }

  Future<void> _fetchFlow() async {
    setState(() => _loadingFlow = true);
    try {
      final data = await _service.getCashFlow(
        from: _fmtDate(_dateFrom),
        to: _fmtDate(_dateTo),
      );
      if (!mounted) return;
      final s = Map<String, dynamic>.from(data['summary'] ?? {});
      setState(() {
        _summary = s;
        _opening = _toNum(s['opening']);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _summary = {}; _opening = 0; });
    } finally {
      if (mounted) setState(() => _loadingFlow = false);
    }
  }

  Future<void> _fetchList({int page = 1, bool reset = false}) async {
    if (reset) ++_requestGeneration;
    final generation = _requestGeneration;
    if (reset) { _pages.clear(); _loadingPages.clear(); _lastPage = 1; _total = 0; _serverPerPage = _requestedPerPage; if (_scrollController.hasClients) _scrollController.jumpTo(0); }
    if (_loadingPages.contains(page) || page < 1 || (_total > 0 && page > _lastPage)) return;
    _loadingPages.add(page);
    if (mounted && _pages.isEmpty) setState(() => _loading = true);
    try {
      final data = await _service.getTransactions(page: page, perPage: _requestedPerPage, from: _fmtDate(_dateFrom), to: _fmtDate(_dateTo), direction: _direction, kind: _kind);
      if (!mounted || generation != _requestGeneration) return;
      final items = (data['items'] as List? ?? []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      setState(() {
        final reportedPerPage = (data['per_page'] as num?)?.toInt();
        if (reportedPerPage != null && reportedPerPage > 0) {
          _serverPerPage = reportedPerPage;
        } else if (items.isNotEmpty && page < ((data['last_page'] as num?)?.toInt() ?? 1)) {
          // Be defensive with older servers that omit per_page but return a
          // fixed page size different from the requested size.
          _serverPerPage = items.length;
        }
        _pages[page] = items;
        _lastPage = (data['last_page'] as num?)?.toInt() ?? 1;
        _total = (data['total'] as num?)?.toInt() ??
            (_lastPage <= 1 ? items.length : _lastPage * _serverPerPage);
        _evictPages(keepPage: page);
      });
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
    finally { _loadingPages.remove(page); if (mounted) setState(() => _loading = false); }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _total <= 0) return;
    final first = (_scrollController.offset / _rowExtent).floor().clamp(0,_total-1);
    final last = (first + (_scrollController.position.viewportDimension/_rowExtent).ceil()+5).clamp(0,_total-1);
    final fp=first~/_serverPerPage+1, lp=last~/_serverPerPage+1;
    for(var page=fp; page<=lp; page++){ if(!_pages.containsKey(page)) _fetchList(page:page); }
    if(lp<_lastPage && !_pages.containsKey(lp+1)) _fetchList(page:lp+1);
  }

  Map<String,dynamic>? _itemAt(int index){
    final page=index~/_serverPerPage+1, off=index%_serverPerPage; final rows=_pages[page];
    if(rows==null){ _fetchList(page:page); return null; }
    return off<rows.length?rows[off]:null;
  }

  void _evictPages({required int keepPage}){
    if(_pages.length<=_maxCachedPages)return;
    final keys=_pages.keys.toList()..sort((a,b)=>(b-keepPage).abs().compareTo((a-keepPage).abs()));
    while(_pages.length>_maxCachedPages&&keys.isNotEmpty){_pages.remove(keys.removeAt(0));}
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
    );
    if (range != null) {
      setState(() {
        _dateFrom = range.start;
        _dateTo = range.end;
      });
      refresh();
    }
  }

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString().replaceAll(',', '')) ?? 0;
  }

  Future<void> _showDetails(Map<String, dynamic> e) async {
    final amount = _toNum(e['amount']);
    final direction = (e['direction'] ?? '').toString();
    final label = (e['label'] ?? '').toString();
    final canVoid = (e['can_void'] ?? false) == true;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text('${e['date'] ?? '—'} • ${direction.toUpperCase()}',
                          style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Text(
                  '${direction == 'in' ? '+' : '-'} ${_money.format(amount)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: direction == 'in' ? AppTheme.success : AppTheme.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DetailRow(label: 'Source', value: (e['source'] ?? 'journal').toString()),
            _DetailRow(label: 'Party', value: (e['party'] ?? 'Unlinked').toString()),
            if ((e['reference_name'] ?? '').toString().isNotEmpty)
              _DetailRow(label: 'Reference', value: e['reference_name'].toString()),
            if ((e['memo'] ?? '').toString().isNotEmpty)
              _DetailRow(label: 'Memo', value: e['memo'].toString()),
            _DetailRow(label: 'Status', value: (e['status'] ?? 'posted').toString()),
            const SizedBox(height: 16),
            if (canVoid)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmVoid(e);
                  },
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Void & reverse'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Row-level void, the same action the details sheet offers — just reachable
  /// in one tap. Shares the confirm dialog and guards with the Day Book day
  /// details screen via CashVoid.
  /// Reverse a customer receipt / vendor payment shown in this feed. These rows
  /// have no cash_ledger_entry behind them, so the cash-ledger void endpoint
  /// cannot touch them — they go through the party-payment reversal endpoints,
  /// exactly as the Party Payments screen does.
  Future<void> _reversePayment(Map<String, dynamic> e) async {
    final payId = CashVoid.paymentId(e);
    final partyId = CashVoid.paymentPartyId(e);
    final kind = CashVoid.paymentType(e);
    if (payId == null || partyId == null || kind == null) return;
    if (_voidingId != null) return;

    final label = (e['party'] ?? 'this party').toString();
    final reason = await CashVoid.askReversalReason(context, label);
    if (reason == null || !mounted) return;

    final busyKey = 'pay_$payId';
    setState(() => _voidingId = busyKey);
    try {
      if (kind == 'customer_receipt') {
        await CustomerService(token: context.read<AuthProvider>().token!)
            .reverseReceipt(customerId: partyId, receiptId: payId, reason: reason);
      } else {
        await VendorService(token: context.read<AuthProvider>().token!)
            .reversePayment(vendorId: partyId, paymentId: payId, reason: reason);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment reversed.')),
      );
      refresh();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _voidingId = null);
    }
  }

  Future<void> _voidEntry(Map<String, dynamic> e) async {
    final id = CashVoid.entryId(e);
    if (id == null || _voidingId != null) return;
    if (!await CashVoid.confirm(context)) return;
    if (!mounted) return;

    setState(() => _voidingId = id);
    try {
      await _service.voidEntry(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry voided and reversed.')),
      );
      refresh();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _voidingId = null);
    }
  }

  Future<void> _confirmVoid(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void entry?'),
        content: const Text('This posts a reversing journal entry. The original record is kept for audit.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final cleId = e['cash_ledger_entry_id'];
      if (cleId != null) {
        await _service.voidEntry(cleId.toString());
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry voided and reversed.')));
        refresh();
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final tableHeight = (viewportHeight * 0.46).clamp(320.0, 520.0);

    return Scrollbar(
      controller: _pageScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _pageScrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFilterBar(),
            const SizedBox(height: 10),
            _buildSummary(),
            const SizedBox(height: 10),
            if (_total > 0) _buildLedgerHeader(),
            if (_total > 0) const SizedBox(height: 1),
            SizedBox(
              height: tableHeight,
              child: _loading && _pages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _total == 0
                      ? _buildList()
                      : Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          child: RefreshIndicator(
                            onRefresh: refresh,
                            child: ListView.builder(
                              controller: _scrollController,
                              primary: false,
                              itemExtent: _rowExtent,
                              itemCount: _total,
                              cacheExtent: _rowExtent * 12,
                              itemBuilder: (_, index) {
                                final item = _itemAt(index);
                                return item == null
                                    ? const Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      )
                                    : _buildRow(item);
                              },
                            ),
                          ),
                        ),
            ),
            if (_total > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$_total entries • ${_lastPage} server pages • bounded cache ${_pages.length}/$_maxCachedPages pages',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final incoming = Map<String, dynamic>.from(_summary['incoming'] ?? {});
    final outgoing = Map<String, dynamic>.from(_summary['outgoing'] ?? {});
    final inTotal = _toNum(incoming['total']);
    final outTotal = _toNum(outgoing['total']);
    final closing = _toNum(_summary['closing']);
    final hasMethods = ((_summary['by_account'] as List?)?.isNotEmpty ?? false);

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _CompactStat(label: 'Opening Balance', value: _money.format(_opening), color: AppTheme.navy, icon: Icons.account_balance_wallet_outlined)),
            const SizedBox(width: 10),
            Expanded(child: _CompactStat(label: 'Total Received', value: _money.format(inTotal), color: AppTheme.success, icon: Icons.south_west_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _CompactStat(label: 'Total Paid', value: _money.format(outTotal), color: AppTheme.danger, icon: Icons.north_east_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _CompactStat(label: 'Closing Balance', value: _money.format(closing), color: AppTheme.navy, icon: Icons.account_balance_wallet_rounded)),
          ],
        ),
        if (hasMethods) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _fundsExpanded = !_fundsExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(9)),
                          child: const Icon(Icons.bar_chart_rounded, color: AppTheme.primary, size: 18),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Funds by method', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                              SizedBox(height: 2),
                              Text('Opening, received, paid and closing balance by payment method.', style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
                            ],
                          ),
                        ),
                        Text(_fundsExpanded ? 'Hide' : 'Show', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 12)),
                        const SizedBox(width: 4),
                        Icon(_fundsExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppTheme.primary),
                      ],
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 180),
                  crossFadeState: _fundsExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _fundsByMethod(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Per-fund breakdown (Cash / Bank / KNET Clearing / …) for the selected
  /// period: opening + in - out = closing for each.
  Widget _fundsByMethod() {
    final list = List<Map<String, dynamic>>.from(
      (_summary['by_account'] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? const [],
    );
    if (list.isEmpty) return const SizedBox.shrink();

    Widget cell(String text, {int flex = 2, TextAlign align = TextAlign.right, TextStyle? style}) =>
        Expanded(flex: flex, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(text, textAlign: align, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)));

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              cell('Method', flex: 3, align: TextAlign.left, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w800)),
              cell('Opening', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w800)),
              cell('In', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w800)),
              cell('Out', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w800)),
              cell('Closing', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w800)),
            ]),
          ),
          const Divider(height: 1),
          ...list.map((m) {
            final methods = (m['methods'] as List?)?.cast<dynamic>() ?? const [];
            final label = methods.isNotEmpty ? methods.join(' / ') : (m['name'] ?? '').toString();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
              child: Row(children: [
                cell(label, flex: 3, align: TextAlign.left, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                cell(_money.format(_toNum(m['opening'])), style: const TextStyle(fontSize: 12)),
                cell(_money.format(_toNum(m['in'])), style: const TextStyle(fontSize: 12, color: AppTheme.success, fontWeight: FontWeight.w700)),
                cell(_money.format(_toNum(m['out'])), style: const TextStyle(fontSize: 12, color: AppTheme.danger, fontWeight: FontWeight.w700)),
                cell(_money.format(_toNum(m['closing'])), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
              ]),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range_rounded, size: 17),
            label: Text('${_fmtDate(_dateFrom)}  →  ${_fmtDate(_dateTo)}'),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              value: _direction,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Direction', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All directions')),
                DropdownMenuItem(value: 'in', child: Text('Incoming')),
                DropdownMenuItem(value: 'out', child: Text('Outgoing')),
              ],
              onChanged: (v) {
                if (v == null || v == _direction) return;
                setState(() => _direction = v);
                _fetchList(page: 1, reset: true);
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              value: _kind,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Source', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All sources')),
                DropdownMenuItem(value: 'received', child: Text('Received')),
                DropdownMenuItem(value: 'sent', child: Text('Paid')),
                DropdownMenuItem(value: 'expense', child: Text('Expenses')),
                DropdownMenuItem(value: 'module', child: Text('Module only')),
              ],
              onChanged: (v) {
                if (v == null || v == _kind) return;
                setState(() => _kind = v);
                _fetchList(page: 1, reset: true);
              },
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: refresh,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerHeader() {
    Widget h(String t, int flex, {TextAlign align = TextAlign.left}) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(t, textAlign: align, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: AppTheme.textMuted)),
      ),
    );
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        h('DATE', 2),
        h('REFERENCE', 2),
        h('TYPE / PARTY', 4),
        h('METHOD', 2),
        h('IN', 2, align: TextAlign.right),
        h('OUT', 2, align: TextAlign.right),
        h('ACTIONS', 1, align: TextAlign.center),
      ]),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_total == 0) {
      return EnterprisePanel(
        child: Column(
          children: [
            if (_opening != 0) ...[
              Container(
                margin: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.navy.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.navy.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.navy),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No transactions in this period. Carried-forward opening balance: ${_money.format(_opening)}',
                        style: const TextStyle(fontSize: 13, color: AppTheme.navy, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Icon(Icons.receipt_long_outlined, size: 56, color: AppTheme.textMuted),
            const SizedBox(height: 10),
            const Text('No entries matching filters', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildRow(Map<String, dynamic> e) {
    final direction = (e['direction'] ?? '').toString();
    final label = (e['label'] ?? 'Entry').toString();
    final party = (e['party'] ?? 'Unlinked').toString();
    final amount = _toNum(e['amount']);
    final method = (e['method'] ?? e['account']?['name'] ?? '—').toString();
    final reference = (e['reference'] ?? e['reference_name'] ?? '—').toString();
    final date = (e['date'] ?? '—').toString();
    final color = direction == 'in' ? AppTheme.success : AppTheme.danger;

    Widget c(Widget child, int flex, {Alignment align = Alignment.centerLeft}) => Expanded(
      flex: flex,
      child: Container(
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: child,
      ),
    );

    return InkWell(
      onTap: () => _showDetails(e),
      child: Container(
        height: _rowExtent,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(children: [
          c(Text(date, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)), 2),
          c(Text(reference, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppTheme.primaryDark)), 2),
          c(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5))),
              const SizedBox(width: 5),
              CashVoidedBadge(row: e),
            ]),
            const SizedBox(height: 2),
            Text(party, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5)),
          ]), 4),
          c(Text(method, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)), 2),
          c(Text(direction == 'in' ? _money.format(amount) : '—', maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: direction == 'in' ? AppTheme.success : AppTheme.textMuted)), 2, align: Alignment.centerRight),
          c(Text(direction == 'out' ? _money.format(amount) : '—', maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: direction == 'out' ? AppTheme.danger : AppTheme.textMuted)), 2, align: Alignment.centerRight),
          c(CashVoidButton(
            row: e,
            busy: _voidingId != null && (_voidingId == CashVoid.entryId(e) || _voidingId == 'pay_${CashVoid.paymentId(e)}'),
            onVoid: () => _voidEntry(e),
            onReverse: () => _reversePayment(e),
          ), 1, align: Alignment.center),
        ]),
      ),
    );
  }



}

/// Tab 2: the SAME cash movements, grouped by calendar day with running
/// opening/closing balances. Tap a day to drill into every transaction
/// that happened that day.
class _DayBookView extends StatefulWidget {
  final ValueChanged<String> onOpenDay;
  const _DayBookView({required this.onOpenDay});

  @override
  State<_DayBookView> createState() => _DayBookViewState();
}

class _DayBookViewState extends State<_DayBookView> {
  late final CashLedgerService _service;
  final _money = const AppMoneyFormatter();
  final _dayFmt = DateFormat('EEE, d MMM');

  static const int _requestedPerPage = 40;
  int _serverPerPage = _requestedPerPage;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 78;
  bool _loading = true;
  final ScrollController _pageScrollController = ScrollController();
  final ScrollController _scrollController = ScrollController();
  final Map<int,List<Map<String,dynamic>>> _pages = {};
  final Set<int> _loadingPages = {};
  Map<String, dynamic> _totals = {};
  num _opening = 0;
  int _total = 0;
  int _lastPage = 1;
  int _requestGeneration = 0;

  DateTime _dateFrom = DateTime.now().subtract(const Duration(days: 29));
  DateTime _dateTo = DateTime.now();

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _service = CashLedgerService(token: token);
    _scrollController.addListener(_onScroll);
    _fetch(page: 1, reset: true);
  }

  @override
  void dispose(){ _pageScrollController.dispose(); _scrollController.dispose(); super.dispose(); }

  String _fmtDate(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString().replaceAll(',', '')) ?? 0;
  }

  Future<void> _fetch({int page = 1, bool reset = false}) async {
    if (reset) ++_requestGeneration;
    final generation = _requestGeneration;
    if(reset){_pages.clear();_loadingPages.clear();_lastPage=1;_total=0;_serverPerPage=_requestedPerPage;if(_scrollController.hasClients)_scrollController.jumpTo(0);if(_pageScrollController.hasClients)_pageScrollController.jumpTo(0);}
    if(_loadingPages.contains(page)||page<1||(_total>0&&page>_lastPage))return;
    _loadingPages.add(page); if(mounted&&_pages.isEmpty)setState(()=>_loading=true);
    try{
      final data=await _service.getDayBook(from:_fmtDate(_dateFrom),to:_fmtDate(_dateTo),page:page,perPage:_requestedPerPage,order:'desc');
      if(!mounted||generation!=_requestGeneration)return;
      final days=(data['days'] as List? ?? []).whereType<Map>().map((e)=>e.cast<String,dynamic>()).toList();
      final pg=Map<String,dynamic>.from(data['pagination']??{});
      setState((){
        final reportedPerPage=(pg['per_page'] as num?)?.toInt()??0;
        if(reportedPerPage>0){
          _serverPerPage=reportedPerPage;
        }else if(page==1&&days.isNotEmpty){
          _serverPerPage=days.length;
        }
        _pages[page]=days;
        if(page==1){_totals=Map<String,dynamic>.from(data['totals']??{});_opening=_toNum(data['opening']);}
        _lastPage=(pg['last_page'] as num?)?.toInt()??1;
        _total=(pg['total'] as num?)?.toInt()??(_lastPage<=1?days.length:_lastPage*_serverPerPage);
        _evictPages(keepPage:page);
      });
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}
    finally{_loadingPages.remove(page);if(mounted)setState(()=>_loading=false);}
  }

  void _onScroll(){if(!_scrollController.hasClients||_total<=0)return;final first=(_scrollController.offset/_rowExtent).floor().clamp(0,_total-1);final last=(first+(_scrollController.position.viewportDimension/_rowExtent).ceil()+5).clamp(0,_total-1);final fp=first~/_serverPerPage+1,lp=last~/_serverPerPage+1;for(var p=fp;p<=lp;p++){if(!_pages.containsKey(p))_fetch(page:p);}if(lp<_lastPage&&!_pages.containsKey(lp+1))_fetch(page:lp+1);}
  Map<String,dynamic>? _dayAt(int index){final p=index~/_serverPerPage+1,o=index%_serverPerPage;final rows=_pages[p];if(rows==null){_fetch(page:p);return null;}return o<rows.length?rows[o]:null;}
  void _evictPages({required int keepPage}){if(_pages.length<=_maxCachedPages)return;final keys=_pages.keys.toList()..sort((a,b)=>(b-keepPage).abs().compareTo((a-keepPage).abs()));while(_pages.length>_maxCachedPages&&keys.isNotEmpty){_pages.remove(keys.removeAt(0));}}

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
    );
    if (range != null) {
      setState(() {
        _dateFrom = range.start;
        _dateTo = range.end;
      });
      _fetch(page: 1, reset: true);
    }
  }

  void _openDay(String date) => widget.onOpenDay(date);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final listHeight = (constraints.maxHeight * .62).clamp(320.0, 620.0);
        return Scrollbar(
          controller: _pageScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _pageScrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              children: [
                _buildSummary(),
                const SizedBox(height: 12),
                SizedBox(
                  height: listHeight,
                  child: _loading && _pages.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _total == 0
                          ? _buildDaysList()
                          : RefreshIndicator(
                              onRefresh: () => _fetch(page: 1, reset: true),
                              child: Scrollbar(
                                controller: _scrollController,
                                thumbVisibility: true,
                                child: ListView.builder(
                                  controller: _scrollController,
                                  itemExtent: _rowExtent,
                                  itemCount: _total,
                                  cacheExtent: _rowExtent * 12,
                                  itemBuilder: (_, i) {
                                    final d = _dayAt(i);
                                    return d == null
                                        ? const Center(
                                            child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          )
                                        : _buildDayRow(d);
                                  },
                                ),
                              ),
                            ),
                ),
                if (_total > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$_total days • $_lastPage server pages • bounded cache ${_pages.length}/$_maxCachedPages pages',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummary() {
    final totIn = _toNum(_totals['in']);
    final totOut = _toNum(_totals['out']);
    final closing = _toNum(_totals['closing']);

    return EnterprisePanel(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EnterpriseSectionHeader(
            title: 'Day Book',
            subtitle: '${_fmtDate(_dateFrom)} → ${_fmtDate(_dateTo)}',
            icon: Icons.calendar_view_day_rounded,
            color: AppTheme.primary,
            trailing: IconButton(
              tooltip: 'Change date range',
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range_rounded),
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Row(
              children: [
                Expanded(child: _CompactStat(label: 'Opening', value: _money.format(_opening), color: AppTheme.navy, icon: Icons.account_balance_wallet_outlined)),
                const SizedBox(width: 10),
                Expanded(child: _CompactStat(label: 'Received', value: _money.format(totIn), color: AppTheme.success, icon: Icons.south_west_rounded)),
                const SizedBox(width: 10),
                Expanded(child: _CompactStat(label: 'Paid', value: _money.format(totOut), color: AppTheme.danger, icon: Icons.north_east_rounded)),
                const SizedBox(width: 10),
                Expanded(child: _CompactStat(label: 'Closing', value: _money.format(closing), color: AppTheme.navy, icon: Icons.account_balance_wallet_rounded)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDaysList() {
    if (_loading) return const SizedBox.shrink();
    if (_total == 0) {
      return EnterprisePanel(
        child: Column(
          children: const [
            SizedBox(height: 16),
            Icon(Icons.event_busy_rounded, size: 56, color: AppTheme.textMuted),
            SizedBox(height: 10),
            Text('No activity in this range', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w800)),
            SizedBox(height: 16),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildDayRow(Map<String, dynamic> d) {
    final date = (d['date'] ?? '').toString();
    final inAmt = _toNum(d['in']);
    final outAmt = _toNum(d['out']);
    final closing = _toNum(d['closing']);
    final count = (d['transaction_count'] as num?)?.toInt() ?? 0;
    final hasActivity = inAmt != 0 || outAmt != 0;

    String heading = date;
    try {
      heading = _dayFmt.format(DateTime.parse(date));
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListTile(
        onTap: hasActivity ? () => _openDay(date) : null,
        leading: Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            color: (hasActivity ? AppTheme.primary : AppTheme.textMuted).withOpacity(.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            Icons.calendar_today_rounded,
            color: hasActivity ? AppTheme.primary : AppTheme.textMuted,
            size: 18,
          ),
        ),
        title: Text(heading, style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.navy)),
        subtitle: Text(
          hasActivity ? '$count transaction${count == 1 ? '' : 's'} • Closing ${_money.format(closing)}' : 'No activity',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: hasActivity
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('+ ${_money.format(inAmt)}', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w800, fontSize: 12.5)),
                  Text('- ${_money.format(outAmt)}', style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w800, fontSize: 12.5)),
                ],
              )
            : const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
      ),
    );
  }


}

class _CompactStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _CompactStat({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700, fontSize: 11)),
                const SizedBox(height: 3),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _StatBox({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
