import 'package:enterprise_pos/api/cash_ledger_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_create_screen.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class CashBookScreen extends StatefulWidget {
  const CashBookScreen({super.key});

  @override
  State<CashBookScreen> createState() => _CashBookScreenState();
}

class _CashBookScreenState extends State<CashBookScreen> {
  static const int _pageSize = 40;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 58;
  // Includes every fixed column plus the row's 14 px left/right padding.
  // Keep this in sync with _tableHeader/_expenseRow so the horizontal
  // viewport never becomes narrower than its children.
  static const double _minTableWidth = 1360;

  late final CashLedgerService _service;
  final _money = const AppMoneyFormatter();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  final Map<int, List<Map<String, dynamic>>> _pages = {};
  final Map<int, int> _pageAccess = {};
  final Set<int> _loadingPages = {};
  int _requestGeneration = 0;
  int _accessTick = 0;
  int _total = 0;
  int _lastPage = 1;
  bool _initialLoading = true;
  String? _error;
  String? _voidingId;

  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _accounts = const [];
  List<Map<String, dynamic>> _methods = const [];
  List<Map<String, dynamic>> _creators = const [];
  bool _filtersLoaded = false;

  DateTimeRange? _dateRange;
  String? _accountId;
  String? _method;
  String? _createdBy;
  String? _status;
  String _search = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0),
    );
    _service = CashLedgerService(token: context.read<AuthProvider>().token!);
    _loadPage(1, reset: true, includeFilters: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double _num(dynamic value) => double.tryParse('${value ?? 0}') ?? 0;

  Future<void> _loadPage(
    int page, {
    bool reset = false,
    bool includeFilters = false,
  }) async {
    if (reset) ++_requestGeneration;
    final generation = _requestGeneration;
    if (page < 1 || _loadingPages.contains(page)) return;
    if (!reset && _pages.containsKey(page)) {
      _touchPage(page);
      return;
    }
    if (!reset && page > _lastPage) return;

    if (reset) {
      setState(() {
        _pages.clear();
        _pageAccess.clear();
        _loadingPages.clear();
        _total = 0;
        _lastPage = 1;
        _initialLoading = true;
        _error = null;
      });
    } else {
      setState(() => _loadingPages.add(page));
    }

    _loadingPages.add(page);
    try {
      final data = await _service.getExpenseHistory(
        page: page,
        perPage: _pageSize,
        from: _dateRange == null ? null : _date(_dateRange!.start),
        to: _dateRange == null ? null : _date(_dateRange!.end),
        accountId: _accountId,
        method: _method,
        createdBy: _createdBy,
        status: _status,
        search: _search,
        includeFilters: includeFilters || !_filtersLoaded,
      );
      if (!mounted || generation != _requestGeneration) return;

      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
      final pagination = Map<String, dynamic>.from(data['pagination'] as Map? ?? const {});
      final filters = data['filters'] is Map
          ? Map<String, dynamic>.from(data['filters'] as Map)
          : null;

      setState(() {
        _pages[page] = items;
        _touchPage(page);
        _total = int.tryParse('${pagination['total'] ?? 0}') ?? 0;
        final parsedLastPage = int.tryParse('${pagination['last_page'] ?? 1}') ?? 1;
        _lastPage = parsedLastPage < 1 ? 1 : parsedLastPage;
        _summary = Map<String, dynamic>.from(data['summary'] as Map? ?? const {});
        if (filters != null) {
          _accounts = _mapList(filters['expense_accounts']);
          _methods = _mapList(filters['payment_methods']);
          _creators = _mapList(filters['creators']);
          _filtersLoaded = true;
        }
        _error = null;
      });
      _evictPages(around: page);
    } catch (e) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingPages.remove(page);
        _initialLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _mapList(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);

  void _touchPage(int page) {
    _pageAccess[page] = ++_accessTick;
  }

  void _evictPages({required int around}) {
    if (_pages.length <= _maxCachedPages) return;
    final protected = <int>{around - 1, around, around + 1};
    final candidates = _pages.keys
        .where((p) => !protected.contains(p))
        .toList()
      ..sort((a, b) => (_pageAccess[a] ?? 0).compareTo(_pageAccess[b] ?? 0));

    while (_pages.length > _maxCachedPages && candidates.isNotEmpty) {
      final page = candidates.removeAt(0);
      _pages.remove(page);
      _pageAccess.remove(page);
    }
  }

  Map<String, dynamic>? _expenseAt(int index) {
    final page = (index ~/ _pageSize) + 1;
    final offset = index % _pageSize;
    final rows = _pages[page];
    if (rows == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPage(page);
      });
      return null;
    }
    _touchPage(page);
    if (offset >= rows.length) return null;
    return rows[offset];
  }

  Future<void> _applyFilters() async {
    FocusScope.of(context).unfocus();
    _search = _searchController.text.trim();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    await _loadPage(1, reset: true);
  }

  Future<void> _resetFilters() async {
    final now = DateTime.now();
    setState(() {
      _dateRange = DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 0),
      );
      _accountId = null;
      _method = null;
      _createdBy = null;
      _status = null;
      _search = '';
      _searchController.clear();
    });
    await _applyFilters();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _dateRange,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() => _dateRange = picked);
  }

  Future<void> _openExpenseCreate() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: PosRouteIds.cashLedgerCreate),
        builder: (_) => const CashLedgerCreateScreen(
          initialCategory: 'OTHER_EXPENSE',
          lockCategory: true,
        ),
      ),
    );
    if (created == true && mounted) {
      await _loadPage(1, reset: true, includeFilters: true);
    }
  }

  Future<void> _voidExpense(Map<String, dynamic> row) async {
    final id = '${row['expense_id'] ?? ''}';
    if (id.isEmpty || _voidingId != null) return;
    final amount = _money.format(row['amount']);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reverse expense?'),
        content: Text(
          'This will void expense #$id for $amount and create the reversing accounting entry. The original record remains in history.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reverse Expense'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _voidingId = id);
    try {
      await _service.voidEntry(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense reversed successfully.')),
      );
      await _loadPage(1, reset: true, includeFilters: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reverse expense: $e')),
      );
    } finally {
      if (mounted) setState(() => _voidingId = null);
    }
  }

  Future<void> _showExpense(Map<String, dynamic> row) async {
    final id = '${row['expense_id'] ?? ''}';
    if (id.isEmpty) return;
    Map<String, dynamic> detail = row;
    try {
      detail = await _service.getEntry(id);
    } catch (_) {
      // The list row still contains the management fields needed for a useful
      // read-only detail view if the secondary detail call is unavailable.
    }
    if (!mounted) return;
    final merged = <String, dynamic>{...row, ...detail};
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Expense #$id'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailLine('Date', '${row['expense_date'] ?? merged['txn_date'] ?? '—'}'),
              _detailLine('Expense Account', '${row['expense_account'] ?? '—'}'),
              _detailLine('Method', '${row['payment_method'] ?? merged['method'] ?? '—'}'),
              _detailLine('Reference', '${row['payee_reference'] ?? merged['reference_name'] ?? '—'}'),
              _detailLine('Added By', '${row['created_by_name'] ?? '—'}'),
              _detailLine('Status', '${row['status'] ?? merged['status'] ?? '—'}'),
              _detailLine('Amount', _money.format(row['amount'] ?? merged['amount'])),
              const SizedBox(height: 8),
              Text('Notes', style: Theme.of(ctx).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text('${row['note'] ?? merged['note'] ?? '—'}'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final noBranch = context.watch<BranchProvider>().isAll;
    final canManage = auth.hasPermission('manage-cashbook');

    return EnterprisePage(
      title: 'Expenses',
      subtitle: 'View, manage and reverse operational expense entries. Reversals use the existing cash-ledger accounting workflow.',
      icon: Icons.receipt_long_rounded,
      appBarActions: const [
        Padding(
          padding: EdgeInsets.only(right: 8),
          child: BranchIndicator(tappable: false),
        ),
      ],
      actions: [
        OutlinedButton.icon(
          onPressed: _initialLoading ? null : () => _loadPage(1, reset: true),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
        FilledButton.icon(
          onPressed: (!canManage || noBranch) ? null : _openExpenseCreate,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Expense'),
        ),
      ],
      child: Column(
        children: [
          _filtersCard(),
          const SizedBox(height: 12),
          _summaryStrip(),
          const SizedBox(height: 12),
          Expanded(child: _table(canManage: canManage)),
        ],
      ),
    );
  }

  Widget _filtersCard() {
    return EnterpriseToolbar(
      children: [
        SizedBox(
          width: 235,
          child: OutlinedButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.calendar_month_rounded, size: 19),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _dateRange == null
                    ? 'All dates'
                    : '${_date(_dateRange!.start)}  –  ${_date(_dateRange!.end)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        _dropdown(
          width: 190,
          value: _accountId,
          hint: 'All Accounts',
          items: _accounts
              .map((a) => DropdownMenuItem<String>(
                    value: '${a['id']}',
                    child: Text('${a['code'] ?? ''} ${a['name'] ?? ''}'.trim(), overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _accountId = v),
        ),
        _dropdown(
          width: 170,
          value: _method,
          hint: 'All Methods',
          items: _methods
              .map((m) => DropdownMenuItem<String>(
                    value: '${m['method']}',
                    child: Text('${m['display_name'] ?? m['method'] ?? ''}', overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _method = v),
        ),
        _dropdown(
          width: 170,
          value: _createdBy,
          hint: 'All Users',
          items: _creators
              .map((u) => DropdownMenuItem<String>(
                    value: '${u['id']}',
                    child: Text('${u['name'] ?? ''}', overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _createdBy = v),
        ),
        _dropdown(
          width: 145,
          value: _status,
          hint: 'All Status',
          items: const [
            DropdownMenuItem(value: 'posted', child: Text('Posted')),
            DropdownMenuItem(value: 'void', child: Text('Voided')),
          ],
          onChanged: (v) => setState(() => _status = v),
        ),
        SizedBox(
          width: 250,
          child: TextField(
            controller: _searchController,
            onSubmitted: (_) => _applyFilters(),
            decoration: const InputDecoration(
              hintText: 'Search notes, reference...',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _resetFilters,
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Reset'),
        ),
        FilledButton.icon(
          onPressed: _applyFilters,
          icon: const Icon(Icons.filter_alt_rounded),
          label: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _dropdown({
    required double width,
    required String? value,
    required String hint,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        hint: Text(hint),
        items: [
          DropdownMenuItem<String>(value: null, child: Text(hint)),
          ...items,
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _summaryStrip() {
    return Row(
      children: [
        Expanded(child: _summaryCard('Total Expenses', _summary['total_expenses'], Icons.account_balance_wallet_outlined)),
        const SizedBox(width: 10),
        Expanded(child: _summaryCard('This Month', _summary['this_month'], Icons.calendar_view_month_rounded)),
        const SizedBox(width: 10),
        Expanded(child: _summaryCard('This Week', _summary['this_week'], Icons.date_range_rounded)),
        const SizedBox(width: 10),
        Expanded(child: _summaryCard('Today', _summary['today'], Icons.today_rounded)),
      ],
    );
  }

  Widget _summaryCard(String label, dynamic value, IconData icon) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(_money.format(value), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _table({required bool canManage}) {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _pages.isEmpty) {
      return EnterpriseEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Could not load expenses',
        subtitle: _error!,
        action: FilledButton.icon(
          onPressed: () => _loadPage(1, reset: true),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      );
    }
    if (_total == 0) {
      return EnterpriseEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No expenses found',
        subtitle: 'Try changing the filters or record a new expense.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < _minTableWidth
              ? _minTableWidth
              : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _tableHeader(),
                  Expanded(
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _scrollController,
                        itemExtent: _rowExtent,
                        itemCount: _total,
                        cacheExtent: _rowExtent * 12,
                        itemBuilder: (context, index) {
                          final row = _expenseAt(index);
                          if (row == null) return _loadingRow();
                          return _expenseRow(row, canManage: canManage);
                        },
                      ),
                    ),
                  ),
                  _tableFooter(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      height: 46,
      color: AppTheme.surfaceSoft,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _head('Date', 150),
          _head('Account', 195),
          _head('Description / Notes', 310),
          _head('Method', 155),
          _head('Amount', 145, align: TextAlign.right),
          _head('Added By', 150),
          _head('Status', 115),
          _head('Actions', 112, align: TextAlign.center),
        ],
      ),
    );
  }

  Widget _head(
    String text,
    double width, {
    TextAlign align = TextAlign.left,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          text.toUpperCase(),
          textAlign: align,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: .25,
          ),
        ),
      ),
    );
  }

  Widget _expenseRow(Map<String, dynamic> row, {required bool canManage}) {
    final status = '${row['status_code'] ?? ''}'.toLowerCase();
    final voided = status == 'void';
    final id = '${row['expense_id'] ?? ''}';
    final canVoid = canManage && row['can_void'] == true && !voided;
    final description = [
      '${row['payee_reference'] ?? ''}'.trim(),
      '${row['note'] ?? ''}'.trim(),
    ].where((e) => e.isNotEmpty).join(' · ');

    return InkWell(
      onTap: () => _showExpense(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            _cell(_displayDate(row), 150),
            _cell('${row['expense_account'] ?? '—'}', 195, bold: true),
            _cell(description.isEmpty ? '—' : description, 310),
            _cell('${row['payment_method'] ?? '—'}', 155),
            _cell(_money.format(row['amount']), 145, align: TextAlign.right, bold: true, color: voided ? AppTheme.textMuted : AppTheme.danger),
            _cell('${row['created_by_name'] ?? '—'}', 150),
            SizedBox(width: 115, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Align(alignment: Alignment.centerLeft, child: _statusBadge(voided)))),
            SizedBox(
              width: 112,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'View',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showExpense(row),
                    icon: const Icon(Icons.visibility_outlined, size: 19),
                  ),
                  if (canVoid)
                    IconButton(
                      tooltip: 'Reverse expense',
                      visualDensity: VisualDensity.compact,
                      onPressed: _voidingId == id ? null : () => _voidExpense(row),
                      icon: _voidingId == id
                          ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.undo_rounded, size: 19, color: AppTheme.danger),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    String text,
    double width, {
    TextAlign align = TextAlign.left,
    bool bold = false,
    Color? color,
  }) => SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: TextStyle(
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            fontSize: 12.5,
            ),
          ),
        ),
      );

  String _displayDate(Map<String, dynamic> row) {
    final raw = '${row['created_at'] ?? ''}'.trim();
    if (raw.isNotEmpty) {
      final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
      if (parsed != null) return DateFormat('yyyy-MM-dd HH:mm').format(parsed.toLocal());
    }
    return '${row['expense_date'] ?? '—'}';
  }

  Widget _statusBadge(bool voided) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: voided ? AppTheme.danger.withOpacity(.08) : AppTheme.success.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        voided ? 'Voided' : 'Posted',
        style: TextStyle(
          color: voided ? AppTheme.danger : AppTheme.success,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _loadingRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }

  Widget _tableFooter() {
    final loadedRows = _pages.values.fold<int>(0, (sum, rows) => sum + rows.length);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceSoft,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Text(
            '$_total expense entr${_total == 1 ? 'y' : 'ies'}',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            'Bounded cache: $loadedRows rows / ${_pages.length} pages loaded',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
