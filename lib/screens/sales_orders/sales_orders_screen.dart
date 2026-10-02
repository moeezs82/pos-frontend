import 'dart:async';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/api/sales_order_service.dart';
import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/sales_orders/sales_order_detail_screen.dart';
import 'package:enterprise_pos/screens/subscription/subscription_management_screen.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
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

  // Selected Status tab: 'SUBMITTED' (Pending), 'APPROVED' (Approved), null (All)
  String? _selectedStatus = SalesOrderStatus.submitted;

  // Filters
  int? _selectedSalesmanId;
  String _searchQuery = '';
  DateTime? _fromDate;
  DateTime? _toDate;

  // Pagination & state
  int _currentPage = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = true;
  String? _loadError;
  bool _isAddonInactive = false;
  List<SalesOrder> _orders = [];

  // Filter options and metrics summary
  OrderFilterOptions? _filterOptions;
  PipelineSummary? _summary;

  // Controllers
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

  SalesOrderService _service() {
    final token = context.read<AuthProvider>().token!;
    return SalesOrderService(token: token);
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _loadInitialData() async {
    await Future.wait([
      _fetchFilterOptions(),
      _fetchSummary(),
      _fetchOrders(page: 1),
    ]);
  }

  Future<void> _fetchFilterOptions() async {
    try {
      final opts = await _service().filterOptions();
      if (mounted) {
        setState(() => _filterOptions = opts);
      }
    } catch (_) {
      // Non-critical, filter dropdowns fall back safely
    }
  }

  Future<void> _fetchSummary() async {
    try {
      final sum = await _service().summary(
        startDate: _fromDate != null ? _fmtDate(_fromDate!) : null,
        endDate: _toDate != null ? _fmtDate(_toDate!) : null,
        salesmanId: _selectedSalesmanId,
      );
      if (mounted) {
        setState(() => _summary = sum);
      }
    } catch (e) {
      if (e is ApiException && e.statusCode == 403 &&
          e.message.contains('Field Sales add-on is not active')) {
        if (mounted) setState(() => _isAddonInactive = true);
      }
    }
  }

  Future<void> _fetchOrders({required int page}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
      _isAddonInactive = false;
    });

    try {
      final response = await _service().listOrders(
        page: page,
        perPage: _perPage,
        status: _selectedStatus,
        salesmanId: _selectedSalesmanId,
        fromDate: _fromDate != null ? _fmtDate(_fromDate!) : null,
        toDate: _toDate != null ? _fmtDate(_toDate!) : null,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
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
        setState(() {
          _isAddonInactive = true;
          _loading = false;
        });
        return;
      }

      setState(() {
        _loading = false;
        _loadError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _searchQuery = val.trim());
      _fetchOrders(page: 1);
    });
  }

  Future<void> _pickFromDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
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
    if (picked != null) {
      setState(() => _toDate = picked);
      _fetchSummary();
      _fetchOrders(page: 1);
    }
  }

  void _clearDates() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _fetchSummary();
    _fetchOrders(page: 1);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final hasAddon = auth.hasAddon('field_sales');
    if (_isAddonInactive && hasAddon) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _isAddonInactive = false);
          _loadInitialData();
        }
      });
    }

    return EnterprisePage(
      title: 'Sales Orders',
      subtitle: 'Field bookings awaiting review and conversion',
      icon: Icons.assignment_outlined,
      actions: [
        OutlinedButton.icon(
          onPressed: _loading ? null : () => _loadInitialData(),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
        ),
      ],
      child: _isAddonInactive
          ? _buildAddonExplainer()
          : Column(
              children: [
                _buildToolbar(),
                const SizedBox(height: 10),
                _buildMetricsBar(),
                const SizedBox(height: 12),
                Expanded(child: _buildListContainer()),
                if (_total > 0)
                  EnterprisePaginationBar(
                    page: _currentPage,
                    lastPage: _lastPage,
                    total: _total,
                    loading: _loading,
                    onPrevious: _currentPage > 1 && !_loading
                        ? () => _fetchOrders(page: _currentPage - 1)
                        : null,
                    onNext: _currentPage < _lastPage && !_loading
                        ? () => _fetchOrders(page: _currentPage + 1)
                        : null,
                  ),
              ],
            ),
    );
  }

  Widget _buildAddonExplainer() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border),
          boxShadow: AppTheme.softShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline_rounded,
                  color: AppTheme.warning, size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'Field Sales Add-on Inactive',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'The Field Sales and Sales Orders module is an optional commercial add-on that is currently not enabled for this branch. Contact your system administrator to activate the Field Sales subscription for this branch.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textMuted,
                height: 1.45,
                fontSize: 13,
              ),
            ),
            if (context.watch<AuthProvider>().isMasterAdmin) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  PosNavigation.openSingleton(
                    routeId: PosRouteIds.subscriptions,
                    builder: (_) => const SubscriptionManagementScreen(),
                  );
                },
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Manage Subscriptions & Add-ons'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final pendingCount = _summary?.totals.pendingApproval;

    return EnterpriseToolbar(
      children: [
        // Status filter tabs: Pending (default) | Approved | All
        SegmentedButton<String?>(
          segments: [
            ButtonSegment<String?>(
              value: SalesOrderStatus.submitted,
              label: Text(pendingCount != null && pendingCount > 0
                  ? 'Pending ($pendingCount)'
                  : 'Pending'),
              icon: const Icon(Icons.pending_actions_rounded, size: 16),
            ),
            const ButtonSegment<String?>(
              value: SalesOrderStatus.approved,
              label: Text('Approved'),
              icon: Icon(Icons.check_circle_outline_rounded, size: 16),
            ),
            const ButtonSegment<String?>(
              value: null,
              label: Text('All Orders'),
              icon: Icon(Icons.list_alt_rounded, size: 16),
            ),
          ],
          selected: {_selectedStatus},
          onSelectionChanged: (selection) {
            setState(() {
              _selectedStatus = selection.first;
            });
            _fetchOrders(page: 1);
          },
        ),

        // Search field
        SizedBox(
          width: 250,
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Order # or customer...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
            ),
          ),
        ),

        // Salesman filter
        if (_filterOptions != null && _filterOptions!.salesmen.isNotEmpty)
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<int?>(
              value: _selectedSalesmanId,
              decoration: const InputDecoration(labelText: 'Salesman'),
              isExpanded: true,
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('All Salesmen'),
                ),
                ..._filterOptions!.salesmen.map((s) => DropdownMenuItem<int?>(
                      value: s.id,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (v) {
                setState(() => _selectedSalesmanId = v);
                _fetchSummary();
                _fetchOrders(page: 1);
              },
            ),
          ),

        // Date pickers
        OutlinedButton.icon(
          onPressed: _pickFromDate,
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(_fromDate == null
              ? 'From'
              : DateFormat('dd MMM yyyy').format(_fromDate!)),
        ),
        OutlinedButton.icon(
          onPressed: _pickToDate,
          icon: const Icon(Icons.event_outlined, size: 16),
          label: Text(_toDate == null
              ? 'To'
              : DateFormat('dd MMM yyyy').format(_toDate!)),
        ),
        if (_fromDate != null || _toDate != null)
          TextButton.icon(
            onPressed: _clearDates,
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Clear dates'),
          ),
      ],
    );
  }

  Widget _buildMetricsBar() {
    final sum = _summary;
    final pendingCount = sum?.totals.pendingApproval ?? 0;
    final bookedVal = sum?.totals.bookedValue ?? 0.0;
    final invoicedVal = sum?.totals.invoicedValue ?? 0.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          EnterpriseMetricChip(
            label: 'Pending Approval',
            value: '$pendingCount orders',
            color: pendingCount > 0 ? AppTheme.warning : AppTheme.success,
            icon: Icons.hourglass_top_rounded,
          ),
          const SizedBox(width: 8),
          EnterpriseMetricChip(
            label: 'Booked Value',
            value: AppCurrency.format(bookedVal),
            color: AppTheme.info,
            icon: Icons.bookmark_added_outlined,
          ),
          const SizedBox(width: 8),
          EnterpriseMetricChip(
            label: 'Invoiced Value',
            value: AppCurrency.format(invoicedVal),
            color: AppTheme.primary,
            icon: Icons.receipt_long_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildListContainer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: _loading && _orders.isEmpty
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _loadError != null && _orders.isEmpty
              ? _buildErrorState()
              : _orders.isEmpty
                  ? EnterpriseEmptyState(
                      icon: Icons.assignment_outlined,
                      title: 'No sales orders found',
                      subtitle: _selectedStatus == SalesOrderStatus.submitted
                          ? 'There are no pending sales orders awaiting approval.'
                          : 'Try changing your status, date, or search filters.',
                    )
                  : Column(
                      children: [
                        _buildTableHeader(),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _orders.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: AppTheme.border,
                            ),
                            itemBuilder: (context, index) {
                              final order = _orders[index];
                              return _buildOrderRow(order);
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppTheme.danger, size: 40),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'Failed to load sales orders',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.danger,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _fetchOrders(page: _currentPage),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceSoft,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: const Row(
        children: [
          SizedBox(width: 140, child: Text('Order #', style: _headerStyle)),
          SizedBox(width: 18),
          Expanded(
            flex: 3,
            child: Text('Customer', style: _headerStyle),
          ),
          SizedBox(width: 14),
          Expanded(
            flex: 2,
            child: Text('Salesman', style: _headerStyle),
          ),
          SizedBox(width: 14),
          SizedBox(
            width: 70,
            child: Text('Items', textAlign: TextAlign.center, style: _headerStyle),
          ),
          SizedBox(width: 14),
          SizedBox(
            width: 120,
            child: Text('Booked Total', textAlign: TextAlign.right, style: _headerStyle),
          ),
          SizedBox(width: 20),
          SizedBox(
            width: 130,
            child: Text('Status', textAlign: TextAlign.center, style: _headerStyle),
          ),
          SizedBox(width: 14),
          SizedBox(
            width: 110,
            child: Text('Age', textAlign: TextAlign.right, style: _headerStyle),
          ),
          SizedBox(width: 12),
          Icon(Icons.chevron_right_rounded, size: 18, color: Colors.transparent),
        ],
      ),
    );
  }

  static const TextStyle _headerStyle = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 12,
    color: AppTheme.textMuted,
  );

  Widget _buildOrderRow(SalesOrder order) {
    final statusColor = SalesOrderStatus.color(order.status);
    final statusLabel = SalesOrderStatus.label(order.status);
    final isOverdue = order.isStale &&
        (order.status == SalesOrderStatus.draft ||
            order.status == SalesOrderStatus.submitted);

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SalesOrderDetailScreen(orderId: order.id),
          ),
        );
        if (mounted) {
          _fetchSummary();
          _fetchOrders(page: _currentPage);
        }
      },
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // Order number
            SizedBox(
              width: 140,
              child: Row(
                children: [
                  if (isOverdue) ...[
                    const Tooltip(
                      message: 'Order sitting for > 48h',
                      child: Icon(Icons.warning_amber_rounded,
                          size: 15, color: AppTheme.warning),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      order.orderNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppTheme.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),

            // Customer
            Expanded(
              flex: 3,
              child: Text(
                order.customer?.name ?? 'Customer #${order.customerId}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 14),

            // Salesman
            Expanded(
              flex: 2,
              child: Text(
                order.salesman?.name ?? 'Salesman #${order.salesmanId}',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 14),

            // Item count
            SizedBox(
              width: 70,
              child: Text(
                '${order.items.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Booked Total
            SizedBox(
              width: 120,
              child: Text(
                AppCurrency.format(order.total),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 20),

            // Status badge
            SizedBox(
              width: 130,
              child: Center(
                child: EnterpriseStatusBadge(
                  label: statusLabel,
                  color: statusColor,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Age / date
            SizedBox(
              width: 110,
              child: Text(
                order.orderDate,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  color: isOverdue ? AppTheme.warning : AppTheme.textMuted,
                  fontWeight: isOverdue ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 12),

            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
