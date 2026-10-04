import 'dart:async';
import 'dart:math' as math;

import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/api/sales_order_service.dart';
import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/models/sales_order_batch.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/sales_orders/parts/sales_order_bulk_actions.dart';
import 'package:enterprise_pos/screens/sales_orders/sales_order_detail_screen.dart';
import 'package:enterprise_pos/screens/sales_orders/sales_order_form_screen.dart';
import 'package:enterprise_pos/screens/subscription/subscription_management_screen.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/counteriq_desktop_shell.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class SalesOrdersScreen extends StatefulWidget {
  const SalesOrdersScreen({super.key});

  @override
  State<SalesOrdersScreen> createState() => _SalesOrdersScreenState();
}

class _SalesOrdersScreenState extends State<SalesOrdersScreen> {
  static const List<int> _pageSizes = [20, 50, 100];
  int _perPage = 20;
  static const double _rowExtent = 56;

  // ── Filters ──────────────────────────────────────────────────────────────
  String? _statusFilter;          // null = All
  int? _selectedCustomerId;
  String? _selectedCustomerLabel;
  int? _selectedSalesmanId;
  String _searchQuery = '';
  DateTime? _fromDate;
  DateTime? _toDate;
  String _sortBy = 'date';        // 'date' | 'total'

  // ── Pagination & state ───────────────────────────────────────────────────
  int _currentPage = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = true;
  bool _refreshing = false;
  String? _loadError;
  bool _isAddonInactive = false;
  List<SalesOrder> _orders = [];

  // ── Bulk selection (ids on the current page) ─────────────────────────────
  final Set<int> _selected = {};
  final Map<int, String> _heldReasons = {};
  bool _bulkBusy = false;
  String? _selectionNote;
  String? _lastBulkSummary;

  // ── Split review pane ────────────────────────────────────────────────────
  bool _reviewOpen = false;
  int? _activeOrderId;
  static const double _splitMinWidth = 1200;

  // ── Summary / filter options ─────────────────────────────────────────────
  OrderFilterOptions? _filterOptions;
  PipelineSummary? _summary;

  // ── Controllers ───────────────────────────────────────────────────────────
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── Service helper ───────────────────────────────────────────────────────
  SalesOrderService _service() {
    final token = context.read<AuthProvider>().token!;
    return SalesOrderService(token: token);
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  // ── Data loading ─────────────────────────────────────────────────────────
  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() { _loading = true; _loadError = null; _isAddonInactive = false; });
    await Future.wait([
      _fetchFilterOptions(),
      _fetchSummary(),
      _fetchOrders(page: 1, skipLoadingState: true),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _onRefresh() async {
    if (mounted) setState(() => _refreshing = true);
    try { await _loadInitialData(); }
    finally { if (mounted) setState(() => _refreshing = false); }
  }

  Future<void> _fetchFilterOptions() async {
    try {
      final opts = await _service().filterOptions();
      if (mounted) setState(() => _filterOptions = opts);
    } catch (_) {}
  }

  Future<void> _fetchSummary() async {
    try {
      final sum = await _service().summary(
        startDate: _fromDate != null ? _fmtDate(_fromDate!) : null,
        endDate: _toDate != null ? _fmtDate(_toDate!) : null,
        salesmanId: _selectedSalesmanId,
      );
      if (mounted) setState(() => _summary = sum);
    } catch (e) {
      if (e is ApiException && e.statusCode == 403 &&
          e.message.contains('Field Sales add-on is not active')) {
        if (mounted) setState(() => _isAddonInactive = true);
      }
    }
  }

  Future<void> _fetchOrders({required int page, bool skipLoadingState = false}) async {
    if (!mounted) return;
    if (!skipLoadingState) {
      setState(() { _loading = true; _loadError = null; _isAddonInactive = false; });
    }

    try {
      final response = await _service().listOrders(
        page: page,
        perPage: _perPage,
        status: _statusFilter,
        salesmanId: _selectedSalesmanId,
        customerId: _selectedCustomerId,
        fromDate: _fromDate != null ? _fmtDate(_fromDate!) : null,
        toDate: _toDate != null ? _fmtDate(_toDate!) : null,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        sortBy: _sortBy,
      );
      if (!mounted) return;
      setState(() {
        _orders = response.orders;
        final visible = response.orders.map((o) => o.id).toSet();
        final before = _selected.length;
        _selected.retainAll(visible);
        _heldReasons.removeWhere((id, _) => !visible.contains(id));
        if (_selected.length < before) {
          _selectionNote =
              '${before - _selected.length} selected order(s) are no longer in view and were deselected.';
        }
        if (_activeOrderId != null && !visible.contains(_activeOrderId)) _activeOrderId = null;
        _currentPage = response.page;
        _lastPage = response.lastPage;
        _total = response.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode == 403 &&
          e.message.contains('Field Sales add-on is not active')) {
        setState(() { _isAddonInactive = true; _loading = false; });
        return;
      }
      setState(() { _loading = false; _loadError = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  // ── Bulk actions ─────────────────────────────────────────────────────────
  List<SalesOrder> get _selectedOrders =>
      _orders.where((o) => _selected.contains(o.id)).toList();

  bool get _allOnPage => _orders.isNotEmpty && _orders.every((o) => _selected.contains(o.id));

  void _toggleAll(bool? on) => setState(() {
        _selectionNote = null;
        if (on == true) {
          _selected.addAll(_orders.map((o) => o.id));
        } else {
          _selected.clear();
          _heldReasons.clear();
        }
      });

  void _toggleOne(int id) => setState(() {
        _selectionNote = null;
        if (!_selected.remove(id)) _selected.add(id);
        _heldReasons.remove(id);
      });

  Future<void> _runBulk(BatchAction action) async {
    if (_bulkBusy) return;
    setState(() => _bulkBusy = true);
    try {
      final result = await runBulkAction(
        context: context,
        service: _service(),
        action: action,
        selected: _selectedOrders,
      );
      if (!mounted || result == null) return;
      setState(() {
        _selected
          ..clear()
          ..addAll(result.remaining);
        _heldReasons
          ..clear()
          ..addAll(result.held);
        if (result.summaryLine.isNotEmpty) _lastBulkSummary = result.summaryLine;
      });
      await Future.wait([_fetchSummary(), _fetchOrders(page: _currentPage, skipLoadingState: true)]);
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  // ── Review pane ──────────────────────────────────────────────────────────
  bool get _splitActive =>
      _reviewOpen && MediaQuery.sizeOf(context).width >= _splitMinWidth;

  void _moveActive(int delta) {
    if (_orders.isEmpty) return;
    final i = _orders.indexWhere((o) => o.id == _activeOrderId);
    final next = (i < 0 ? (delta > 0 ? 0 : _orders.length - 1) : i + delta)
        .clamp(0, _orders.length - 1);
    setState(() => _activeOrderId = _orders[next].id);
  }

  Future<void> _openOrder(SalesOrder order) async {
    if (_splitActive) {
      setState(() => _activeOrderId = order.id);
      return;
    }
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => SalesOrderDetailScreen(orderId: order.id)));
    if (mounted) { _fetchSummary(); _fetchOrders(page: _currentPage); }
  }

  Widget _buildReviewPane() {
    final id = _activeOrderId;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(12)),
      child: id == null
          ? const EnterpriseEmptyState(
              icon: Icons.touch_app_outlined,
              title: 'Select an order to review',
              subtitle: 'Use ↑ / ↓ to move through the list.',
            )
          : SalesOrderDetailScreen(
              key: ValueKey('review-$id'),
              orderId: id,
              embedded: true,
              onChanged: () {
                if (!mounted) return;
                _fetchSummary();
                _fetchOrders(page: _currentPage, skipLoadingState: true);
              },
            ),
    );
  }

  // ── Search ───────────────────────────────────────────────────────────────
  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _searchQuery = val.trim());
      _fetchOrders(page: 1);
    });
  }

  // ── Date pickers ─────────────────────────────────────────────────────────
  Future<void> _pickFromDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) {
      setState(() => _fromDate = picked);
      _fetchSummary();
      _fetchOrders(page: 1);
    }
  }

  Future<void> _pickToDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? _fromDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) {
      setState(() => _toDate = picked);
      _fetchSummary();
      _fetchOrders(page: 1);
    }
  }

  // ── Advanced filters dialog ──────────────────────────────────────────────
  int get _advancedFilterCount => [
        _statusFilter,
        _selectedSalesmanId != null ? 'salesman' : null,
        _selectedCustomerId != null ? 'customer' : null,
      ].where((e) => e != null).length;

  Future<void> _openAdvancedFilters() async {
    var status = _statusFilter;
    var salesmanId = _selectedSalesmanId;
    var customerId = _selectedCustomerId;
    String? customerLabel = _selectedCustomerLabel;
    final salesmen = _filterOptions?.salesmen ?? const [];
    final customers = _filterOptions?.customers ?? const [];

    final applied = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          DropdownMenuItem<T?> allItem<T>(String label) =>
              DropdownMenuItem<T?>(value: null, child: Text(label));
          return AlertDialog(
            title: const Text('Order Filters'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Wrap(spacing: 12, runSpacing: 12, children: [
                  // Status — all 6 statuses
                  SizedBox(
                    width: 285,
                    child: DropdownButtonFormField<String?>(
                      value: status,
                      decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All Statuses')),
                        ...SalesOrderStatus.all.map((s) => DropdownMenuItem<String?>(
                              value: s,
                              child: Row(children: [
                                Container(
                                  width: 8, height: 8,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: SalesOrderStatus.color(s),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Text(SalesOrderStatus.label(s)),
                              ]),
                            )),
                      ],
                      onChanged: (v) => setLocal(() => status = v),
                    ),
                  ),
                  // Salesman
                  if (salesmen.isNotEmpty)
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<int?>(
                        value: salesmanId,
                        decoration: const InputDecoration(labelText: 'Salesman', border: OutlineInputBorder()),
                        items: [
                          allItem<int>('All Salesmen'),
                          ...salesmen.map((s) => DropdownMenuItem<int?>(
                                value: s.id,
                                child: Text(s.name, overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (v) => setLocal(() => salesmanId = v),
                      ),
                    ),
                  // Customer
                  if (customers.isNotEmpty)
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<int?>(
                        value: customerId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Customer', border: OutlineInputBorder()),
                        items: [
                          allItem<int>('All Customers'),
                          ...customers.map((c) => DropdownMenuItem<int?>(
                                value: c.id,
                                child: Text(c.name, overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (v) {
                          setLocal(() {
                            customerId = v;
                            customerLabel = v == null
                                ? null
                                : customers.firstWhere((c) => c.id == v).name;
                          });
                        },
                      ),
                    ),
                ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => setLocal(() {
                  status = null;
                  salesmanId = null;
                  customerId = null;
                  customerLabel = null;
                }),
                child: const Text('Clear'),
              ),
              TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Apply')),
            ],
          );
        },
      ),
    );

    if (applied != true || !mounted) return;
    setState(() {
      _statusFilter = status;
      _selectedSalesmanId = salesmanId;
      _selectedCustomerId = customerId;
      _selectedCustomerLabel = customerLabel;
    });
    _fetchSummary();
    await _fetchOrders(page: 1);
  }

  // ── Clear helpers ────────────────────────────────────────────────────────
  int get _activeFilterCount =>
      (_statusFilter != null ? 1 : 0) +
      (_selectedCustomerId != null ? 1 : 0) +
      (_selectedSalesmanId != null ? 1 : 0) +
      (_fromDate != null ? 1 : 0) +
      (_toDate != null ? 1 : 0);

  Future<void> _clearFilter(String key) async {
    setState(() {
      switch (key) {
        case 'status':   _statusFilter = null; break;
        case 'customer': _selectedCustomerId = null; _selectedCustomerLabel = null; break;
        case 'salesman': _selectedSalesmanId = null; break;
        case 'from':     _fromDate = null; break;
        case 'to':       _toDate = null; break;
      }
    });
    _fetchSummary();
    await _fetchOrders(page: 1);
  }

  Future<void> _clearAllFilters() async {
    setState(() {
      _statusFilter = null;
      _selectedCustomerId = null;
      _selectedCustomerLabel = null;
      _selectedSalesmanId = null;
      _fromDate = null;
      _toDate = null;
    });
    _fetchSummary();
    await _fetchOrders(page: 1);
  }

  // ── Salesman name lookup ─────────────────────────────────────────────────
  String _salesmanName(int? id) {
    if (id == null) return '';
    for (final s in (_filterOptions?.salesmen ?? const [])) {
      if (s.id == id) return s.name;
    }
    return '#$id';
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final hasAddon = auth.hasAddon('field_sales');
    if (_isAddonInactive && hasAddon) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) { setState(() => _isAddonInactive = false); _loadInitialData(); }
      });
    }

    final canCreate = auth.hasPermission('create-sales-orders');
    return CounterIQDesktopShell(
      activeRouteId: PosRouteIds.salesOrders,
      onOpenProducts: () {},
      child: CallbackShortcuts(
        bindings: {
          if (_splitActive) ...{
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => _moveActive(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => _moveActive(-1),
          },
        },
        child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: _isAddonInactive
            ? _buildAddonExplainer()
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _buildHeader(canCreate),
                const SizedBox(height: 12),
                _buildFilterBar(),
                if (_activeFilterCount > 0) ...[const SizedBox(height: 8), _buildActiveFilterChips()],
                const SizedBox(height: 10),
                _buildMetricsBar(),
                const SizedBox(height: 10),
                if (_refreshing) const LinearProgressIndicator(minHeight: 2),
                if (_refreshing) const SizedBox(height: 8),
                if (_selected.isNotEmpty) ...[_buildBulkBar(auth), const SizedBox(height: 8)],
                if (_selectionNote != null && _selected.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(_selectionNote!,
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ),
                Expanded(
                  child: _splitActive
                      ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(flex: 5, child: _buildListContainer()),
                          const SizedBox(width: 12),
                          Expanded(flex: 6, child: _buildReviewPane()),
                        ])
                      : _buildListContainer(),
                ),
                if (_total > 0) ...[const SizedBox(height: 8), _buildStatusBar()],
              ]),
      ),
      ),
    );
  }

  Widget _buildBulkBar(AuthProvider auth) {
    final selected = _selectedOrders;
    final total = selected.fold<double>(0, (s, o) => s + o.total);
    return SalesOrderBulkBar(
      selectedCount: _selected.length,
      selectedTotal: total,
      canSubmit: auth.hasPermission('manage-sales-orders') || auth.hasPermission('create-sales-orders'),
      canApprove: auth.hasPermission('approve-sales-orders'),
      canConvert: auth.hasPermission('convert-sales-orders'),
      canCancel: auth.hasPermission('manage-sales-orders') || auth.hasPermission('approve-sales-orders'),
      busy: _bulkBusy,
      onAction: _runBulk,
      onClear: () => setState(() { _selected.clear(); _heldReasons.clear(); }),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────
  Widget _buildHeader(bool canCreate) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Sales Orders',
              style: TextStyle(color: AppTheme.navy, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -.45)),
          SizedBox(height: 4),
          Text('Field bookings awaiting review and conversion to invoices.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
      Wrap(spacing: 8, children: [
        if (MediaQuery.sizeOf(context).width >= _splitMinWidth)
          IconButton(
            tooltip: _reviewOpen ? 'Close review pane' : 'Open review pane',
            onPressed: () => setState(() { _reviewOpen = !_reviewOpen; }),
            icon: Icon(_reviewOpen ? Icons.view_sidebar_rounded : Icons.view_sidebar_outlined),
          ),
        IconButton(tooltip: 'Refresh', onPressed: _onRefresh, icon: const Icon(Icons.refresh_rounded)),
        if (canCreate)
          FilledButton.icon(
            onPressed: () async {
              final created = await Navigator.push<bool>(
                  context, MaterialPageRoute(builder: (_) => const SalesOrderFormScreen()));
              if (created == true && mounted) _loadInitialData();
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New Sales Order'),
          ),
      ]),
    ],
  );

  // ── Filter bar (pill style, matching Sale History) ────────────────────────
  Widget _buildFilterBar() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
        color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(12)),
    child: LayoutBuilder(builder: (context, constraints) => Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Search
        SizedBox(
          width: math.min(360.0, math.max(260.0, constraints.maxWidth * .28)).toDouble(),
          height: 42,
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Order # or customer…',
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      onPressed: () { _searchController.clear(); _onSearchChanged(''); },
                      icon: const Icon(Icons.close_rounded, size: 18))
                  : null,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        // Customer filter pill
        _filterButton(
          Icons.person_outline_rounded,
          _selectedCustomerLabel ?? 'All customers',
          (_filterOptions?.customers ?? const []).isNotEmpty ? _openCustomerQuickPick : null,
        ),
        // Date from
        _filterButton(Icons.date_range_outlined,
            _fromDate == null ? 'From date' : DateFormat('dd MMM yyyy').format(_fromDate!),
            _pickFromDate),
        // Date to
        _filterButton(Icons.event_available_outlined,
            _toDate == null ? 'To date' : DateFormat('dd MMM yyyy').format(_toDate!),
            _pickToDate),
        // Sort
        PopupMenuButton<String>(
          tooltip: 'Sort orders',
          onSelected: (v) async { setState(() => _sortBy = v); await _fetchOrders(page: 1); },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'date', child: Text('Newest date')),
            PopupMenuItem(value: 'total', child: Text('Amount')),
          ],
          child: _filterSurface(Icons.swap_vert_rounded, _sortBy == 'total' ? 'Amount' : 'Date'),
        ),
        // More filters (status + salesman + customer)
        OutlinedButton.icon(
          onPressed: _openAdvancedFilters,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: Text(_advancedFilterCount == 0 ? 'More filters' : 'More filters ($_advancedFilterCount)'),
        ),
        // Clear all
        if (_activeFilterCount > 0)
          TextButton.icon(
            onPressed: _clearAllFilters,
            icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
            label: const Text('Clear'),
          ),
      ],
    )),
  );

  Widget _filterButton(IconData icon, String label, VoidCallback? onTap) =>
      InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10),
          child: _filterSurface(icon, label, disabled: onTap == null));

  Widget _filterSurface(IconData icon, String label, {bool disabled = false}) => Container(
    height: 42,
    constraints: const BoxConstraints(maxWidth: 190),
    padding: const EdgeInsets.symmetric(horizontal: 11),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: disabled ? AppTheme.border : AppTheme.borderStrong),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 17, color: disabled ? AppTheme.border : AppTheme.textMuted),
      const SizedBox(width: 7),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: disabled ? AppTheme.border : AppTheme.navy,
              fontSize: 12, fontWeight: FontWeight.w700))),
    ]),
  );

  // Quick pick for customer via dialog
  Future<void> _openCustomerQuickPick() async {
    final customers = _filterOptions?.customers ?? const [];
    if (customers.isEmpty) return;

    final search = ValueNotifier('');
    final picked = await showDialog<CustomerFilterOptionRef?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Customer'),
        content: SizedBox(
          width: 400,
          height: 440,
          child: Column(children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search customer…',
                prefixIcon: Icon(Icons.search_rounded, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => search.value = v.trim().toLowerCase(),
            ),
            const SizedBox(height: 8),
            Expanded(child: ValueListenableBuilder<String>(
              valueListenable: search,
              builder: (_, q, __) {
                final filtered = q.isEmpty
                    ? customers
                    : customers.where((c) => c.name.toLowerCase().contains(q)).toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('No customers found',
                      style: TextStyle(color: AppTheme.textMuted)));
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline_rounded, size: 18),
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      subtitle: (c.phone != null && c.phone!.isNotEmpty)
                          ? Text(c.phone!, style: const TextStyle(fontSize: 11))
                          : null,
                      onTap: () => Navigator.pop(ctx, c),
                    );
                  },
                );
              },
            )),
          ]),
        ),
        actions: [
          if (_selectedCustomerId != null)
            TextButton(
              onPressed: () {
                setState(() { _selectedCustomerId = null; _selectedCustomerLabel = null; });
                Navigator.pop(ctx);
                _fetchOrders(page: 1);
              },
              child: const Text('Clear'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );

    if (picked != null && mounted) {
      setState(() { _selectedCustomerId = picked.id; _selectedCustomerLabel = picked.name; });
      _fetchOrders(page: 1);
    }
  }

  // ── Active filter chips ───────────────────────────────────────────────────
  Widget _buildActiveFilterChips() => Wrap(spacing: 6, runSpacing: 6, children: [
    if (_statusFilter != null)
      InputChip(
        label: Text('Status: ${SalesOrderStatus.label(_statusFilter)}'),
        onDeleted: () => _clearFilter('status'),
      ),
    if (_selectedCustomerId != null)
      InputChip(
        label: Text(_selectedCustomerLabel ?? 'Customer'),
        onDeleted: () => _clearFilter('customer'),
      ),
    if (_selectedSalesmanId != null)
      InputChip(
        label: Text('Salesman: ${_salesmanName(_selectedSalesmanId)}'),
        onDeleted: () => _clearFilter('salesman'),
      ),
    if (_fromDate != null)
      InputChip(
        label: Text('From ${DateFormat('dd MMM yyyy').format(_fromDate!)}'),
        onDeleted: () => _clearFilter('from'),
      ),
    if (_toDate != null)
      InputChip(
        label: Text('To ${DateFormat('dd MMM yyyy').format(_toDate!)}'),
        onDeleted: () => _clearFilter('to'),
      ),
  ]);

  // ── Metrics bar (expanded from byStatus) ──────────────────────────────────
  Widget _buildMetricsBar() {
    final sum = _summary;
    if (sum == null) return const SizedBox.shrink();

    final byStatus = <String, StatusSummary>{
      for (final s in sum.byStatus) s.status.toUpperCase(): s,
    };

    int cnt(String s) => byStatus[s]?.count ?? 0;
    double val(String s) => byStatus[s]?.orderValue ?? 0.0;

    final pendingCount = sum.totals.pendingApproval;
    final rejectedCancelled = cnt(SalesOrderStatus.rejected) + cnt(SalesOrderStatus.cancelled);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        EnterpriseMetricChip(
          label: 'Pending Approval',
          value: '$pendingCount order${pendingCount == 1 ? '' : 's'}',
          color: pendingCount > 0 ? AppTheme.warning : AppTheme.success,
          icon: Icons.hourglass_top_rounded,
        ),
        const SizedBox(width: 8),
        EnterpriseMetricChip(
          label: 'Draft',
          value: '${cnt(SalesOrderStatus.draft)} order${cnt(SalesOrderStatus.draft) == 1 ? '' : 's'}',
          color: AppTheme.warning,
          icon: Icons.edit_note_rounded,
        ),
        const SizedBox(width: 8),
        EnterpriseMetricChip(
          label: 'Approved',
          value: '${cnt(SalesOrderStatus.approved)} order${cnt(SalesOrderStatus.approved) == 1 ? '' : 's'}',
          color: AppTheme.success,
          icon: Icons.check_circle_outline_rounded,
        ),
        const SizedBox(width: 8),
        EnterpriseMetricChip(
          label: 'Booked Value',
          value: AppCurrency.format(sum.totals.bookedValue),
          color: AppTheme.info,
          icon: Icons.bookmark_added_outlined,
        ),
        const SizedBox(width: 8),
        EnterpriseMetricChip(
          label: 'Invoiced',
          value: AppCurrency.format(val(SalesOrderStatus.converted)),
          color: AppTheme.primary,
          icon: Icons.receipt_long_outlined,
        ),
        if (rejectedCancelled > 0) ...[
          const SizedBox(width: 8),
          EnterpriseMetricChip(
            label: 'Rejected / Cancelled',
            value: '$rejectedCancelled',
            color: AppTheme.danger,
            icon: Icons.cancel_outlined,
          ),
        ],
      ]),
    );
  }

  // ── List container ────────────────────────────────────────────────────────
  Widget _buildListContainer() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(12)),
      child: _loading && _orders.isEmpty
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _loadError != null && _orders.isEmpty
              ? _buildErrorState()
              : _orders.isEmpty
                  ? EnterpriseEmptyState(
                      icon: Icons.assignment_outlined,
                      title: 'No sales orders found',
                      subtitle: _activeFilterCount > 0
                          ? 'Try changing your filters.'
                          : 'No sales orders have been created yet.',
                    )
                  : _buildTable(),
    );
  }

  Widget _buildTable() {
    final compact = _splitActive;
    // checkbox | order | customer | [salesman | items] | total | status | [date | chevron]
    final widths = compact
        ? const <double>[36, 130, 150, 110, 110]
        : const <double>[36, 160, 220, 170, 70, 130, 140, 120, 20];
    final minWidth = widths.fold<double>(0, (a, b) => a + b) + 24 + (widths.length - 1) * 14.0;

    return LayoutBuilder(builder: (context, constraints) {
      final width = math.max(minWidth, constraints.maxWidth).toDouble();
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          height: constraints.maxHeight,
          child: Column(children: [
            _buildTableHeader(widths, compact),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _orders.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
                  itemBuilder: (_, i) => _buildOrderRow(_orders[i], widths, compact),
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }

  static const _headerStyle = TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: AppTheme.textMuted);

  Widget _buildTableHeader(List<double> widths, bool compact) {
    final labels = compact
        ? const ['Order #', 'Customer', 'Booked Total', 'Status']
        : const ['Order #', 'Customer', 'Salesman', 'Items', 'Booked Total', 'Status', 'Date', ''];
    final aligns = compact
        ? const [TextAlign.left, TextAlign.left, TextAlign.right, TextAlign.center]
        : const [
            TextAlign.left, TextAlign.left, TextAlign.left, TextAlign.center,
            TextAlign.right, TextAlign.center, TextAlign.right, TextAlign.center,
          ];
    final bool? tri = _selected.isEmpty ? false : (_allOnPage ? true : null);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
          color: AppTheme.surfaceSoft,
          border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: Row(children: [
        SizedBox(
          width: widths[0],
          child: Checkbox(
            tristate: true,
            value: tri,
            onChanged: _bulkBusy ? null : (_) => _toggleAll(tri == true ? false : true),
            visualDensity: VisualDensity.compact,
          ),
        ),
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: SizedBox(
              width: widths[i + 1],
              child: Text(labels[i], textAlign: aligns[i], style: _headerStyle),
            ),
          ),
      ]),
    );
  }

  Widget _buildOrderRow(SalesOrder order, List<double> widths, bool compact) {
    final statusColor = SalesOrderStatus.color(order.status);
    final statusLabel = SalesOrderStatus.label(order.status);
    final isOverdue = order.isStale &&
        (order.status == SalesOrderStatus.draft || order.status == SalesOrderStatus.submitted);
    final isActive = compact && order.id == _activeOrderId;
    final held = _heldReasons[order.id];

    Widget cell(int i, Widget child) => Padding(
        padding: const EdgeInsets.only(left: 14), child: SizedBox(width: widths[i], child: child));

    final orderNo = Row(children: [
      if (isOverdue) ...[
        const Tooltip(message: 'Order sitting > 48h',
            child: Icon(Icons.warning_amber_rounded, size: 14, color: AppTheme.warning)),
        const SizedBox(width: 4),
      ],
      Expanded(child: Text(order.orderNumber, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.primary))),
    ]);

    final customer = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Text(order.customer?.name ?? 'Customer #${order.customerId}',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.navy)),
      if (held != null)
        Tooltip(message: held, child: Text(held, overflow: TextOverflow.ellipsis, maxLines: 1,
            style: const TextStyle(fontSize: 10.5, color: AppTheme.danger, fontWeight: FontWeight.w700))),
    ]);

    final total = Text(AppCurrency.format(order.total), textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.navy));
    final status = Center(child: EnterpriseStatusBadge(label: statusLabel, color: statusColor));

    return InkWell(
      onTap: () => _openOrder(order),
      child: Container(
        height: _rowExtent,
        color: isActive ? AppTheme.primary.withValues(alpha: 0.07) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          SizedBox(
            width: widths[0],
            child: Checkbox(
              value: _selected.contains(order.id),
              onChanged: _bulkBusy ? null : (_) => _toggleOne(order.id),
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (compact) ...[
            cell(1, orderNo),
            cell(2, customer),
            cell(3, total),
            cell(4, status),
          ] else ...[
            cell(1, orderNo),
            cell(2, customer),
            cell(3, Text(order.salesman?.name ?? 'Salesman #${order.salesmanId}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600))),
            cell(4, Text('${order.itemsCount > 0 ? order.itemsCount : order.items.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.navy))),
            cell(5, total),
            cell(6, status),
            cell(7, Text(order.orderDate, textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12,
                    color: isOverdue ? AppTheme.warning : AppTheme.textMuted,
                    fontWeight: isOverdue ? FontWeight.w800 : FontWeight.w500))),
            cell(8, const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.textMuted)),
          ],
        ]),
      ),
    );
  }

  // ── Status / pagination bar ───────────────────────────────────────────────
  Widget _buildStatusBar() => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
        color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      Text('$_total order${_total == 1 ? '' : 's'}',
          style: const TextStyle(color: AppTheme.navy, fontSize: 12, fontWeight: FontWeight.w900)),
      const SizedBox(width: 8),
      Container(width: 1, height: 16, color: AppTheme.border),
      const SizedBox(width: 8),
      Text('Page $_currentPage of $_lastPage',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(width: 12),
      const Text('Per page', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      const SizedBox(width: 6),
      DropdownButton<int>(
        value: _perPage,
        isDense: true,
        underline: const SizedBox.shrink(),
        items: [for (final n in _pageSizes) DropdownMenuItem(value: n, child: Text('$n'))],
        onChanged: _loading
            ? null
            : (n) {
                if (n == null || n == _perPage) return;
                setState(() => _perPage = n);
                _fetchOrders(page: 1);
              },
      ),
      if (_lastBulkSummary != null) ...[
        const SizedBox(width: 14),
        Flexible(
          child: Text(_lastBulkSummary!, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.navy, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ],
      const Spacer(),
      if (_loading)
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8))
      else ...[
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 20),
          tooltip: 'Previous page',
          onPressed: _currentPage > 1 ? () => _fetchOrders(page: _currentPage - 1) : null,
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded, size: 20),
          tooltip: 'Next page',
          onPressed: _currentPage < _lastPage ? () => _fetchOrders(page: _currentPage + 1) : null,
        ),
      ],
    ]),
  );

  // ── Error state ───────────────────────────────────────────────────────────
  Widget _buildErrorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 40),
        const SizedBox(height: 12),
        Text(_loadError ?? 'Failed to load sales orders',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.danger)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _fetchOrders(page: _currentPage),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Try Again'),
        ),
      ]),
    ),
  );

  // ── Add-on explainer ──────────────────────────────────────────────────────
  Widget _buildAddonExplainer() => Center(
    child: Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border), boxShadow: AppTheme.softShadow),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(height: 56, width: 56,
            decoration: BoxDecoration(color: AppTheme.warning.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.lock_outline_rounded, color: AppTheme.warning, size: 28)),
        const SizedBox(height: 16),
        const Text('Field Sales Add-on Inactive',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
        const SizedBox(height: 10),
        const Text(
          'The Field Sales and Sales Orders module is an optional commercial add-on that is currently not enabled for this branch. Contact your system administrator to activate the Field Sales subscription for this branch.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textMuted, height: 1.45, fontSize: 13),
        ),
        if (context.watch<AuthProvider>().isMasterAdmin) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => PosNavigation.openSingleton(
              routeId: PosRouteIds.subscriptions,
              builder: (_) => const SubscriptionManagementScreen(),
            ),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Manage Subscriptions & Add-ons'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ]),
    ),
  );
}
