import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:enterprise_pos/api/cash_ledger_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/payment_method_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';

enum SubledgerKind { loans, qameti, expenses }

/// Read-only Loan / Qameti / Expense subledger tab with date-range + search
/// filters. Rows carry a payment-method chip (like the Ledger tab). Derived
/// from the GL, branch-scoped; presentation only — never mutates accounting.
class SubledgerView extends StatefulWidget {
  final SubledgerKind kind;
  const SubledgerView({super.key, required this.kind});

  @override
  State<SubledgerView> createState() => _SubledgerViewState();
}

class _SubledgerViewState extends State<SubledgerView> {
  late final CashLedgerService _service;
  final _money = const AppMoneyFormatter();
  final _dateFmt = DateFormat('yyyy-MM-dd');
  final _searchCtrl = TextEditingController();
  final ScrollController _pageScrollController = ScrollController();
  final ScrollController _transactionScrollController = ScrollController();

  static const int _requestedPerPage = 40;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 58;

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};
  final Map<int, List<Map<String, dynamic>>> _pages = {};
  final Set<int> _loadingPages = {};
  int _total = 0;
  int _serverPerPage = _requestedPerPage;
  int _lastPage = 1;
  int _requestGeneration = 0;

  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _service = CashLedgerService(token: context.read<AuthProvider>().token ?? '');
    _transactionScrollController.addListener(_onTransactionScroll);
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _pageScrollController.dispose();
    _transactionScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetch({int page = 1, bool reset = true}) async {
    if (reset) {
      _requestGeneration++;
      _pages.clear();
      _loadingPages.clear();
      _total = 0;
      _lastPage = 1;
      _serverPerPage = _requestedPerPage;
      if (_transactionScrollController.hasClients) {
        _transactionScrollController.jumpTo(0);
      }
    }
    if (page < 1 || _loadingPages.contains(page) || (!reset && _pages.containsKey(page))) return;
    final generation = _requestGeneration;
    _loadingPages.add(page);
    if (mounted && _pages.isEmpty) {
      setState(() { _loading = true; _error = null; });
    }
    final from = _from == null ? null : _dateFmt.format(_from!);
    final to = _to == null ? null : _dateFmt.format(_to!);
    final search = _searchCtrl.text.trim();
    try {
      final data = switch (widget.kind) {
        SubledgerKind.loans => await _service.getLoanSubledger(from: from, to: to, search: search, page: page, perPage: _requestedPerPage),
        SubledgerKind.qameti => await _service.getQametiSubledger(from: from, to: to, search: search, page: page, perPage: _requestedPerPage),
        SubledgerKind.expenses => await _service.getExpenseSubledger(from: from, to: to, search: search, page: page, perPage: _requestedPerPage),
      };
      if (!mounted || generation != _requestGeneration) return;
      final pagination = Map<String, dynamic>.from(data['pagination'] ?? const {});
      final rows = List<Map<String, dynamic>>.from(
        (data['transactions'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? const [],
      );
      final current = (pagination['current_page'] as num?)?.toInt() ?? page;
      final perPage = (pagination['per_page'] as num?)?.toInt() ?? _requestedPerPage;
      final total = (pagination['total'] as num?)?.toInt() ?? rows.length;
      final last = (pagination['last_page'] as num?)?.toInt() ?? 1;
      setState(() {
        _data = data;
        _pages[current] = rows;
        _serverPerPage = perPage <= 0 ? _requestedPerPage : perPage;
        _total = total;
        _lastPage = last < 1 ? 1 : last;
        _loading = false;
        _error = null;
        _evictPages(current);
      });
    } catch (e) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      _loadingPages.remove(page);
    }
  }

  void _onTransactionScroll() {
    if (!_transactionScrollController.hasClients || _total <= 0) return;
    final first = (_transactionScrollController.offset / _rowExtent).floor().clamp(0, _total - 1);
    final visible = (_transactionScrollController.position.viewportDimension / _rowExtent).ceil() + 8;
    final lastIndex = (first + visible).clamp(0, _total - 1);
    final firstPage = first ~/ _serverPerPage + 1;
    final lastPage = lastIndex ~/ _serverPerPage + 1;
    for (var p = firstPage; p <= lastPage; p++) {
      if (!_pages.containsKey(p)) _fetch(page: p, reset: false);
    }
    if (lastPage < _lastPage && !_pages.containsKey(lastPage + 1)) {
      _fetch(page: lastPage + 1, reset: false);
    }
    if (firstPage > 1 && !_pages.containsKey(firstPage - 1)) {
      _fetch(page: firstPage - 1, reset: false);
    }
    _evictPages(firstPage);
  }

  Map<String, dynamic>? _transactionAt(int index) {
    final page = index ~/ _serverPerPage + 1;
    final offset = index % _serverPerPage;
    final rows = _pages[page];
    if (rows == null) {
      _fetch(page: page, reset: false);
      return null;
    }
    return offset < rows.length ? rows[offset] : null;
  }

  void _evictPages(int keepPage) {
    if (_pages.length <= _maxCachedPages) return;
    final keys = _pages.keys.toList()
      ..sort((a, b) => (b - keepPage).abs().compareTo((a - keepPage).abs()));
    while (_pages.length > _maxCachedPages && keys.isNotEmpty) {
      _pages.remove(keys.removeAt(0));
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: (_from != null && _to != null)
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _from = picked.start;
        _to = picked.end;
      });
      _fetch();
    }
  }

  void _clearRange() {
    setState(() {
      _from = null;
      _to = null;
    });
    _fetch();
  }

  double _n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;
  String _m(dynamic v) => _money.format(_n(v));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final transactionHeight = (constraints.maxHeight * .56).clamp(320.0, 560.0);
        return Scrollbar(
          controller: _pageScrollController,
          thumbVisibility: true,
          child: RefreshIndicator(
            onRefresh: _fetch,
            child: SingleChildScrollView(
              controller: _pageScrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                children: [
                  _filterBar(),
                  const SizedBox(height: 10),
                  if (_loading)
                    const SizedBox(height: 320, child: Center(child: CircularProgressIndicator()))
                  else if (_error != null)
                    SizedBox(height: 320, child: _Retry(message: _error!, onRetry: _fetch))
                  else
                    ...switch (widget.kind) {
                      SubledgerKind.loans => _loansBody(transactionHeight),
                      SubledgerKind.qameti => _qametiBody(transactionHeight),
                      SubledgerKind.expenses => _expensesBody(transactionHeight),
                    },
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _filterBar() {
    final hasRange = _from != null && _to != null;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _fetch(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: switch (widget.kind) {
                    SubledgerKind.loans => 'Search borrower…',
                    SubledgerKind.qameti => 'Search reference / method…',
                    SubledgerKind.expenses => 'Search payee / account / method…',
                  },
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _fetch();
                          },
                        ),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(
              hasRange ? '${_dateFmt.format(_from!)} → ${_dateFmt.format(_to!)}' : 'All dates',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (hasRange)
            IconButton(
              tooltip: 'Clear dates',
              onPressed: _clearRange,
              icon: const Icon(Icons.clear_rounded, size: 18),
            ),
        ],
      ),
    );
  }

  /// Payment-method chip, mirroring the Ledger tab (friendly name).
  Widget _methodChip(dynamic method) {
    final code = (method ?? '').toString();
    if (code.isEmpty) return const SizedBox.shrink();
    final name = context.read<PaymentMethodProvider>().displayNameFor(code);
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(name,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.primaryDark)),
    );
  }

  // ── Loans ────────────────────────────────────────────────────────────────
  List<Widget> _loansBody(double transactionHeight) {
    final s = Map<String, dynamic>.from(_data['summary'] ?? {});
    final rec = Map<String, dynamic>.from(_data['reconciliation'] ?? {});
    final borrowers = _list('borrowers');
    return [
      _summaryCard('Loans Receivable (1300)', [
        _stat('Opening', s['opening']),
        _stat('Given', s['given'], color: AppTheme.danger),
        _stat('Recovered', s['recovered'], color: AppTheme.success),
        _stat('Outstanding', s['closing'], strong: true),
      ]),
      _recLine(rec),
      if (borrowers.isNotEmpty) ...[
        const SizedBox(height: 8),
        _sectionLabel('Borrowers'),
        ...borrowers.map((b) => Card(
              elevation: 0,
              shape: RoundedRectangleBorder(side: const BorderSide(color: AppTheme.border), borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.only(bottom: 5),
              child: ListTile(
                dense: true,
                visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Text('${b['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${b['party_type']} • Given ${_m(b['given'])} • Recovered ${_m(b['recovered'])}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_m(b['outstanding']), style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text('${b['status']}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
              ),
            )),
      ],
      const SizedBox(height: 8),
      _sectionLabel('Transactions'),
      _transactionPanel(
        height: transactionHeight,
        emptyText: 'No loan transactions in this period.',
        itemBuilder: (t) {
          final given = _n(t['given']) > 0;
          return Card(
            margin: const EdgeInsets.only(bottom: 5),
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: Icon(given ? Icons.north_east_rounded : Icons.south_west_rounded,
                  color: given ? AppTheme.danger : AppTheme.success),
              title: Row(children: [
                Expanded(child: Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                _methodChip(t['method']),
              ]),
              subtitle: Text('${t['party_type']} • ${t['date']} • ${given ? 'Loan given' : 'Recovered'}'),
              trailing: Text(
                given ? '-${_m(t['given'])}' : '+${_m(t['recovered'])}',
                style: TextStyle(fontWeight: FontWeight.w900, color: given ? AppTheme.danger : AppTheme.success),
              ),
            ),
          );
        },
      ),
    ];
  }

  // ── Qameti ───────────────────────────────────────────────────────────────
  List<Widget> _qametiBody(double transactionHeight) {
    final s = Map<String, dynamic>.from(_data['summary'] ?? {});
    final rec = Map<String, dynamic>.from(_data['reconciliation'] ?? {});
    return [
      _summaryCard('Qameti / Committee (1310)', [
        _stat('Opening', s['opening']),
        _stat('Payments', s['payments'], color: AppTheme.danger),
        _stat('Collections', s['collections'], color: AppTheme.success),
        _stat('Closing', s['closing'], strong: true),
      ]),
      _recLine(rec),
      const SizedBox(height: 8),
      _sectionLabel('Transactions'),
      _transactionPanel(
        height: transactionHeight,
        emptyText: 'No Qameti activity in this period.',
        itemBuilder: (t) => Card(
          elevation: 0,
          shape: RoundedRectangleBorder(side: const BorderSide(color: AppTheme.border), borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 5),
          child: ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: Row(children: [
              Expanded(child: Text('${t['reference'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700))),
              _methodChip(t['method']),
            ]),
            subtitle: Text('${t['date']} • bal ${_m(t['balance'])}'),
            trailing: Text(
              _n(t['payment']) > 0 ? '+${_m(t['payment'])}' : '-${_m(t['collection'])}',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: _n(t['payment']) > 0 ? AppTheme.danger : AppTheme.success,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  // ── Expenses ─────────────────────────────────────────────────────────────
  List<Widget> _expensesBody(double transactionHeight) {
    final s = Map<String, dynamic>.from(_data['summary'] ?? {});
    final byAccount = _list('by_account');
    return [
      _summaryCard('Expenses (period activity)', [
        _stat('Total', s['total'], color: AppTheme.danger, strong: true),
        _stat('Reversals', s['reversals'], color: AppTheme.success),
        _stat('Net', s['net'], strong: true),
      ]),
      if (byAccount.isNotEmpty) ...[
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(side: const BorderSide(color: AppTheme.border), borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('By account', style: TextStyle(fontWeight: FontWeight.w800)),
                const Divider(),
                ...byAccount.map((a) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(child: Text('${a['code']} · ${a['name']}')),
                        Text(_m(a['net']), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                    )),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 8),
      _sectionLabel('Transactions'),
      _transactionPanel(
        height: transactionHeight,
        emptyText: 'No expenses in this period.',
        itemBuilder: (t) => Card(
          elevation: 0,
          shape: RoundedRectangleBorder(side: const BorderSide(color: AppTheme.border), borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 5),
          child: ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: Row(children: [
              Expanded(child: Text('${t['payee'] ?? t['account_name'] ?? '—'}',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              _methodChip(t['method']),
            ]),
            subtitle: Text('${t['date']} • ${t['account_code']} · ${t['account_name']}'),
            trailing: Text(_m(t['amount']),
                style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.danger)),
          ),
        ),
      ),
    ];
  }

  Widget _transactionPanel({
    required double height,
    required String emptyText,
    required Widget Function(Map<String, dynamic>) itemBuilder,
  }) {
    if (_total == 0 && !_loading) return _empty(emptyText);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.fromLTRB(8, 7, 5, 7),
      child: Scrollbar(
        controller: _transactionScrollController,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _transactionScrollController,
          itemExtent: _rowExtent,
          itemCount: _total,
          cacheExtent: _rowExtent * 10,
          padding: const EdgeInsets.only(right: 8),
          itemBuilder: (_, index) {
            final row = _transactionAt(index);
            if (row == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: LinearProgressIndicator(minHeight: 2),
              );
            }
            return itemBuilder(row);
          },
        ),
      ),
    );
  }

  // ── shared bits ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _list(String key) => List<Map<String, dynamic>>.from(
        (_data[key] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? const [],
      );

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMuted, fontSize: 12)),
      );

  Widget _summaryCard(String title, List<Widget> stats) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppTheme.navy)),
            const SizedBox(height: 10),
            Row(children: [
              for (var i = 0; i < stats.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: stats[i]),
              ],
            ]),
          ],
        ),
      );

  Widget _stat(String label, dynamic value, {Color? color, bool strong = false}) => Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(_m(value), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: strong ? 15 : 14, color: color ?? AppTheme.navy)),
          ],
        ),
      );

  Widget _recLine(Map<String, dynamic> rec) {
    if (rec.isEmpty) return const SizedBox.shrink();
    final diff = _n(rec['difference']);
    final ok = diff.abs() < 0.005;
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            size: 16, color: ok ? AppTheme.success : AppTheme.warning),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ok
                ? 'Reconciles to GL (${_m(rec['gl_closing'])}).'
                : 'GL ${_m(rec['gl_closing'])} vs subledger ${_m(rec['subledger_closing'])} — diff ${_m(rec['difference'])} (pre-existing).',
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ),
      ]),
    );
  }

  Widget _empty(String msg) => Padding(
        padding: const EdgeInsets.all(28),
        child: Center(child: Text(msg, style: const TextStyle(color: AppTheme.textMuted))),
      );
}

class _Retry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _Retry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.danger)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
