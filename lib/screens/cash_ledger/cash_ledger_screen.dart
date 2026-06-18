import 'package:enterprise_pos/api/cash_ledger_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_create_screen.dart';
import 'package:enterprise_pos/screens/cash_ledger/day_book_detail_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:flutter/material.dart';
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
  late final TabController _tabController;
  final GlobalKey<_LedgerViewState> _ledgerKey = GlobalKey<_LedgerViewState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Ledger'),
        // subtitle: const Text('Unified view of all cash movements'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 8), child: BranchIndicator(tappable: false)),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Ledger', icon: Icon(Icons.receipt_long_rounded, size: 20)),
            Tab(text: 'Day Book', icon: Icon(Icons.calendar_view_day_rounded, size: 20)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Record Entry'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LedgerView(key: _ledgerKey),
          const _DayBookView(),
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
  final _money = NumberFormat('#,##0.00');

  bool _loading = true;
  bool _loadingFlow = true;

  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _lastPage = 1;

  Map<String, dynamic> _summary = {};

  // Filters
  DateTime _dateFrom = DateTime.now().subtract(const Duration(days: 29));
  DateTime _dateTo = DateTime.now();
  String _direction = 'all'; // in|out|all
  String _kind = 'all';      // all|module|received|sent|expense

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _service = CashLedgerService(token: token);
    refresh();
  }

  String _fmtDate(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  Future<void> refresh() async {
    await Future.wait([_fetchFlow(), _fetchList(page: 1)]);
  }

  Future<void> _fetchFlow() async {
    setState(() => _loadingFlow = true);
    try {
      final data = await _service.getCashFlow(
        from: _fmtDate(_dateFrom),
        to: _fmtDate(_dateTo),
      );
      if (!mounted) return;
      setState(() => _summary = Map<String, dynamic>.from(data['summary'] ?? {}));
    } catch (_) {
      if (!mounted) return;
      setState(() => _summary = {});
    } finally {
      if (mounted) setState(() => _loadingFlow = false);
    }
  }

  Future<void> _fetchList({int page = 1}) async {
    setState(() => _loading = true);
    try {
      final data = await _service.getTransactions(
        page: page,
        perPage: 25,
        from: _fmtDate(_dateFrom),
        to: _fmtDate(_dateTo),
        direction: _direction,
        kind: _kind,
      );
      if (!mounted) return;
      final items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      setState(() {
        _items = items;
        _page = (data['current_page'] as num?)?.toInt() ?? page;
        _lastPage = (data['last_page'] as num?)?.toInt() ?? 1;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _buildSummary(),
          const SizedBox(height: 14),
          _buildFilterBar(),
          const SizedBox(height: 14),
          _buildList(),
          const SizedBox(height: 12),
          _buildPager(),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final incoming = Map<String, dynamic>.from(_summary['incoming'] ?? {});
    final outgoing = Map<String, dynamic>.from(_summary['outgoing'] ?? {});
    final inTotal = _toNum(incoming['total']);
    final outTotal = _toNum(outgoing['total']);
    final net = _toNum(_summary['net_movement']);
    final closing = _toNum(_summary['closing']);

    return EnterprisePanel(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EnterpriseSectionHeader(
            title: 'Cash position',
            subtitle: '${_fmtDate(_dateFrom)} → ${_fmtDate(_dateTo)}',
            icon: Icons.insights_rounded,
            color: AppTheme.primary,
            trailing: IconButton(
              tooltip: 'Change date range',
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range_rounded),
            ),
          ),
          const SizedBox(height: 14),
          if (_loadingFlow)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatBox(
                        label: 'Received',
                        value: _money.format(inTotal),
                        color: AppTheme.success,
                        icon: Icons.south_west_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatBox(
                        label: 'Paid',
                        value: _money.format(outTotal),
                        color: AppTheme.danger,
                        icon: Icons.north_east_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _StatBox(
                        label: 'Net',
                        value: _money.format(net),
                        color: net >= 0 ? AppTheme.success : AppTheme.danger,
                        icon: Icons.sync_alt_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatBox(
                        label: 'Closing',
                        value: _money.format(closing),
                        color: AppTheme.navy,
                        icon: Icons.account_balance_wallet_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Direction', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                selected: _direction == 'all',
                label: const Text('All'),
                onSelected: (_) {
                  setState(() => _direction = 'all');
                  _fetchList(page: 1);
                },
              ),
              FilterChip(
                selected: _direction == 'in',
                label: const Text('Incoming'),
                onSelected: (_) {
                  setState(() => _direction = 'in');
                  _fetchList(page: 1);
                },
              ),
              FilterChip(
                selected: _direction == 'out',
                label: const Text('Outgoing'),
                onSelected: (_) {
                  setState(() => _direction = 'out');
                  _fetchList(page: 1);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Source', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                selected: _kind == 'all',
                label: const Text('All sources'),
                onSelected: (_) {
                  setState(() => _kind = 'all');
                  _fetchList(page: 1);
                },
              ),
              FilterChip(
                selected: _kind == 'received',
                label: const Text('Received'),
                onSelected: (_) {
                  setState(() => _kind = 'received');
                  _fetchList(page: 1);
                },
              ),
              FilterChip(
                selected: _kind == 'sent',
                label: const Text('Paid'),
                onSelected: (_) {
                  setState(() => _kind = 'sent');
                  _fetchList(page: 1);
                },
              ),
              FilterChip(
                selected: _kind == 'expense',
                label: const Text('Expenses'),
                onSelected: (_) {
                  setState(() => _kind = 'expense');
                  _fetchList(page: 1);
                },
              ),
              FilterChip(
                selected: _kind == 'module',
                label: const Text('Module only'),
                onSelected: (_) {
                  setState(() => _kind = 'module');
                  _fetchList(page: 1);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_items.isEmpty) {
      return EnterprisePanel(
        child: Column(
          children: const [
            SizedBox(height: 16),
            Icon(Icons.receipt_long_outlined, size: 56, color: AppTheme.textMuted),
            SizedBox(height: 10),
            Text('No entries matching filters', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w800)),
            SizedBox(height: 16),
          ],
        ),
      );
    }
    return Column(
      children: _items.map(_buildRow).toList(),
    );
  }

  Widget _buildRow(Map<String, dynamic> e) {
    final direction = (e['direction'] ?? '').toString();
    final label = (e['label'] ?? 'Entry').toString();
    final source = (e['source'] ?? 'journal').toString();
    final amount = _toNum(e['amount']);
    final color = direction == 'in' ? AppTheme.success : AppTheme.danger;
    final sourceIcon = source == 'module' ? Icons.add_circle_outline : Icons.book_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListTile(
        onTap: () => _showDetails(e),
        leading: Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(13)),
          child: Icon(
            direction == 'in' ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: color,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.navy),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surfaceSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(sourceIcon, size: 13, color: AppTheme.textMuted),
                  const SizedBox(width: 3),
                  Text(
                    source,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${e['party'] ?? 'Unlinked'} • ${e['date'] ?? '—'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          '${direction == 'in' ? '+' : '-'} ${_money.format(amount)}',
          style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildPager() {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton.icon(
          onPressed: _page > 1 ? () => _fetchList(page: _page - 1) : null,
          icon: const Icon(Icons.chevron_left),
          label: const Text('Previous'),
        ),
        const SizedBox(width: 16),
        Text('Page $_page of $_lastPage', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: _page < _lastPage ? () => _fetchList(page: _page + 1) : null,
          icon: const Icon(Icons.chevron_right),
          label: const Text('Next'),
        ),
      ],
    );
  }
}

/// Tab 2: the SAME cash movements, grouped by calendar day with running
/// opening/closing balances. Tap a day to drill into every transaction
/// that happened that day.
class _DayBookView extends StatefulWidget {
  const _DayBookView();

  @override
  State<_DayBookView> createState() => _DayBookViewState();
}

class _DayBookViewState extends State<_DayBookView> {
  late final CashLedgerService _service;
  final _money = NumberFormat('#,##0.00');
  final _dayFmt = DateFormat('EEE, d MMM');

  bool _loading = true;
  List<Map<String, dynamic>> _days = [];
  Map<String, dynamic> _totals = {};
  num _opening = 0;

  int _page = 1;
  int _lastPage = 1;

  DateTime _dateFrom = DateTime.now().subtract(const Duration(days: 29));
  DateTime _dateTo = DateTime.now();

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _service = CashLedgerService(token: token);
    _fetch(page: 1);
  }

  String _fmtDate(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString().replaceAll(',', '')) ?? 0;
  }

  Future<void> _fetch({int page = 1}) async {
    setState(() => _loading = true);
    try {
      final data = await _service.getDayBook(
        from: _fmtDate(_dateFrom),
        to: _fmtDate(_dateTo),
        page: page,
        perPage: 30,
        order: 'desc',
      );
      if (!mounted) return;
      final days = (data['days'] as List? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      final p = Map<String, dynamic>.from(data['pagination'] ?? {});
      setState(() {
        _days = days;
        _totals = Map<String, dynamic>.from(data['totals'] ?? {});
        _opening = _toNum(data['opening']);
        _page = (p['current_page'] as num?)?.toInt() ?? page;
        _lastPage = (p['last_page'] as num?)?.toInt() ?? 1;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      _fetch(page: 1);
    }
  }

  void _openDay(String date) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DayBookDetailScreen(date: date)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _fetch(page: 1),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _buildSummary(),
          const SizedBox(height: 14),
          _buildDaysList(),
          const SizedBox(height: 12),
          _buildPager(),
        ],
      ),
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
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatBox(
                        label: 'Opening',
                        value: _money.format(_opening),
                        color: AppTheme.navy,
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatBox(
                        label: 'Closing',
                        value: _money.format(closing),
                        color: AppTheme.navy,
                        icon: Icons.account_balance_wallet_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _StatBox(
                        label: 'Total received',
                        value: _money.format(totIn),
                        color: AppTheme.success,
                        icon: Icons.south_west_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatBox(
                        label: 'Total paid',
                        value: _money.format(totOut),
                        color: AppTheme.danger,
                        icon: Icons.north_east_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDaysList() {
    if (_loading) return const SizedBox.shrink();
    if (_days.isEmpty) {
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
    return Column(children: _days.map(_buildDayRow).toList());
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

  Widget _buildPager() {
    if (_days.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton.icon(
          onPressed: _page > 1 ? () => _fetch(page: _page - 1) : null,
          icon: const Icon(Icons.chevron_left),
          label: const Text('Previous'),
        ),
        const SizedBox(width: 16),
        Text('Page $_page of $_lastPage', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: _page < _lastPage ? () => _fetch(page: _page + 1) : null,
          icon: const Icon(Icons.chevron_right),
          label: const Text('Next'),
        ),
      ],
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
