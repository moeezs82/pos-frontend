import 'dart:async';
import 'dart:math' as math;

import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/api/sales_order_service.dart';
import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/sales_orders/sales_order_detail_screen.dart';
import 'package:enterprise_pos/screens/sales_orders/sales_order_form_screen.dart';
import 'package:enterprise_pos/screens/subscription/subscription_management_screen.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/counteriq_desktop_shell.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class SalesOrdersScreen extends StatefulWidget {
  const SalesOrdersScreen({super.key});

  @override
  State<SalesOrdersScreen> createState() => _SalesOrdersScreenState();
}

class _SalesOrdersScreenState extends State<SalesOrdersScreen> {
  static const int _perPage = 20;
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
                Expanded(child: _buildListContainer()),
                if (_total > 0) ...[const SizedBox(height: 8), _buildStatusBar()],
              ]),
      ),
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
    const widths = <double>[160, 220, 170, 70, 130, 140, 120, 20];
    final minWidth = widths.fold<double>(0, (a, b) => a + b) + 24 + (widths.length - 1) * 14.0;

    return LayoutBuilder(builder: (context, constraints) {
      final width = math.max(minWidth, constraints.maxWidth).toDouble();
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          height: constraints.maxHeight,
          child: Column(children: [
            _buildTableHeader(widths),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _orders.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
                  itemBuilder: (_, i) => _buildOrderRow(_orders[i], widths),
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }

  static const _headerStyle = TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: AppTheme.textMuted);

  Widget _buildTableHeader(List<double> widths) {
    const labels = ['Order #', 'Customer', 'Salesman', 'Items', 'Booked Total', 'Status', 'Date', ''];
    const aligns = [
      TextAlign.left, TextAlign.left, TextAlign.left, TextAlign.center,
      TextAlign.right, TextAlign.center, TextAlign.right, TextAlign.center,
    ];
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
          color: AppTheme.surfaceSoft,
          border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: Row(children: List.generate(labels.length, (i) => Padding(
        padding: EdgeInsets.only(right: i < labels.length - 1 ? 14 : 0),
        child: SizedBox(
          width: widths[i],
          child: Text(labels[i], textAlign: aligns[i], style: _headerStyle),
        ),
      ))),
    );
  }

  Widget _buildOrderRow(SalesOrder order, List<double> widths) {
    final statusColor = SalesOrderStatus.color(order.status);
    final statusLabel = SalesOrderStatus.label(order.status);
    final isOverdue = order.isStale &&
        (order.status == SalesOrderStatus.draft || order.status == SalesOrderStatus.submitted);

    return InkWell(
      onTap: () async {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => SalesOrderDetailScreen(orderId: order.id)));
        if (mounted) { _fetchSummary(); _fetchOrders(page: _currentPage); }
      },
      child: Container(
        height: _rowExtent,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          // Order #
          SizedBox(width: widths[0], child: Row(children: [
            if (isOverdue) ...[
              const Tooltip(message: 'Order sitting > 48h',
                  child: Icon(Icons.warning_amber_rounded, size: 14, color: AppTheme.warning)),
              const SizedBox(width: 4),
            ],
            Expanded(child: Text(order.orderNumber, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.primary))),
          ])),
          const SizedBox(width: 14),
          // Customer
          SizedBox(width: widths[1], child: Text(
            order.customer?.name ?? 'Customer #${order.customerId}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.navy),
          )),
          const SizedBox(width: 14),
          // Salesman
          SizedBox(width: widths[2], child: Text(
            order.salesman?.name ?? 'Salesman #${order.salesmanId}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
          )),
          const SizedBox(width: 14),
          // Items
          SizedBox(width: widths[3], child: Text('${order.itemsCount > 0 ? order.itemsCount : order.items.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.navy))),
          const SizedBox(width: 14),
          // Total
          SizedBox(width: widths[4], child: Text(AppCurrency.format(order.total),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.navy))),
          const SizedBox(width: 14),
          // Status badge
          SizedBox(width: widths[5], child: Center(
              child: EnterpriseStatusBadge(label: statusLabel, color: statusColor))),
          const SizedBox(width: 14),
          // Date
          SizedBox(width: widths[6], child: Text(order.orderDate,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12,
                  color: isOverdue ? AppTheme.warning : AppTheme.textMuted,
                  fontWeight: isOverdue ? FontWeight.w800 : FontWeight.w500))),
          const SizedBox(width: 14),
          // Chevron
          SizedBox(width: widths[7], child: const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.textMuted)),
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
