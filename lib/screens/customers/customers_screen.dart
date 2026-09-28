import 'dart:math' as math;

import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/forms/customer_form_screen.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/product_screen.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/customers/customers_edit_screen.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/utils/customer_display_utils.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/counteriq_desktop_shell.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  static const int _perPage = 40;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 58;

  int _lastPage = 1;
  int _total = 0;
  bool _loading = false;
  String _search = '';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final Map<int, List<Map<String, dynamic>>> _pages = {};
  final Set<int> _loadingPages = {};
  int _requestGeneration = 0;
  late CustomerService _customerService;
  VoidCallback? _branchListener;

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _customerService = CustomerService(token: token);
    final branchProvider = context.read<BranchProvider>();
    _branchListener = () => _fetchCustomers(reset: true);
    branchProvider.addListener(_branchListener!);
    _scrollController.addListener(_onScroll);
    _fetchCustomers(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    final branchProvider = context.read<BranchProvider>();
    if (_branchListener != null) branchProvider.removeListener(_branchListener!);
    super.dispose();
  }

  Future<void> _fetchCustomers({bool reset = false, int page = 1}) async {
    if (reset) ++_requestGeneration;
    final generation = _requestGeneration;
    if (reset) {
      _pages.clear();
      _loadingPages.clear();
      _lastPage = 1;
      _total = 0;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    }
    if (_loadingPages.contains(page) || page < 1 || (_total > 0 && page > _lastPage)) return;
    _loadingPages.add(page);
    if (mounted && _pages.isEmpty) setState(() => _loading = true);
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final data = await _customerService.getCustomers(
        page: page, perPage: _perPage, search: _search, includeBalance: true, branchId: branchId,
      );
      final wrapper = (data['data'] as Map<String, dynamic>?) ?? const {};
      final rows = (wrapper['customers'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ?? const <Map<String, dynamic>>[];
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _pages[page] = rows;
        _lastPage = (wrapper['last_page'] as num?)?.toInt() ?? _lastPage;
        _total = (wrapper['total'] as num?)?.toInt() ?? _total;
        _evictPages(keepPage: page);
      });
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to load customers: $e');
    } finally {
      _loadingPages.remove(page);
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _total <= 0) return;
    final first = (_scrollController.offset / _rowExtent).floor().clamp(0, _total - 1);
    final visible = (_scrollController.position.viewportDimension / _rowExtent).ceil() + 6;
    final last = (first + visible).clamp(0, _total - 1);
    final firstPage = first ~/ _perPage + 1;
    final lastPage = last ~/ _perPage + 1;
    for (var page = firstPage; page <= lastPage; page++) {
      if (!_pages.containsKey(page)) _fetchCustomers(page: page);
    }
    final nextPage = lastPage + 1;
    if (nextPage <= _lastPage && !_pages.containsKey(nextPage)) _fetchCustomers(page: nextPage);
  }

  Map<String, dynamic>? _customerAt(int index) {
    final page = index ~/ _perPage + 1;
    final offset = index % _perPage;
    final rows = _pages[page];
    if (rows == null) {
      _fetchCustomers(page: page);
      return null;
    }
    return offset < rows.length ? rows[offset] : null;
  }

  void _evictPages({required int keepPage}) {
    if (_pages.length <= _maxCachedPages) return;
    final keys = _pages.keys.toList()..sort((a, b) => (b - keepPage).abs().compareTo((a - keepPage).abs()));
    while (_pages.length > _maxCachedPages && keys.isNotEmpty) { _pages.remove(keys.removeAt(0)); }
  }

  void _searchNow() {
    setState(() => _search = _searchController.text.trim());
    _scrollController.addListener(_onScroll);
    _fetchCustomers(reset: true);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _search = '');
    _scrollController.addListener(_onScroll);
    _fetchCustomers(reset: true);
  }

  Future<void> _openForm([Map<String, dynamic>? customer]) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        settings: customer == null
            ? const RouteSettings(name: PosRouteIds.customerCreate)
            : null,
        builder: (_) => CustomerFormScreen(customer: customer),
      ),
    );
    if (result != null && mounted) await _fetchCustomers(reset: true);
  }

  Future<void> _openCustomer(Map<String, dynamic> customer) async {
    final rawId = customer['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '');
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerEditScreen(customerId: id)),
    );
    if (mounted) await _fetchCustomers(reset: true);
  }

  Future<void> _deleteCustomer(Map<String, dynamic> customer) async {
    final name = _fullName(customer);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text(
          'Delete ${name.isEmpty ? 'this customer' : name}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_rounded),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _customerService.deleteCustomer(customer['id'] as int);
      if (!mounted) return;
      AppFeedback.success(context, 'Customer deleted');
      await _fetchCustomers(reset: true);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Delete failed: $e');
    }
  }

  String _fullName(Map<String, dynamic> customer) {
    final first = (customer['first_name'] ?? '').toString().trim();
    final last = (customer['last_name'] ?? '').toString().trim();
    return [first, last].where((part) => part.isNotEmpty).join(' ');
  }

  String _customerTypeLabel(dynamic raw) {
    switch ((raw ?? 'retail').toString().toLowerCase()) {
      case 'wholesale':
        return 'Wholesale';
      case 'reseller':
        return 'Reseller';
      default:
        return 'Retail';
    }
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '').trim()) ?? 0;
  }

  String _money(dynamic value) => AppCurrency.format(value);

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthProvider>().hasPermission('manage-customers');
    return CounterIQDesktopShell(
      activeRouteId: PosRouteIds.customers,
      onOpenProducts: () => PosNavigation.openSingleton(
        routeId: PosRouteIds.products,
        builder: (_) => const ProductsScreen(),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(canManage),
            const SizedBox(height: 12),
            _buildToolbar(),
            const SizedBox(height: 10),
            Expanded(
              child: _loading && _pages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _total == 0
                      ? ListView(
                          children: [
                            const SizedBox(height: 70),
                            EnterpriseEmptyState(
                              icon: Icons.people_outline_rounded,
                              title: 'No customers found',
                              subtitle: _search.isEmpty
                                  ? 'Add customers to manage balances, receipts and ledgers.'
                                  : 'No customer matched your search.',
                              action: canManage
                                  ? FilledButton.icon(
                                      onPressed: () => _openForm(),
                                      icon: const Icon(Icons.person_add_alt_1_rounded),
                                      label: const Text('Add Customer'),
                                    )
                                  : null,
                            ),
                          ],
                        )
                      : _buildTable(canManage),
            ),
            if (_total > 0) ...[
              const SizedBox(height: 6),
              Text('$_total customers • bounded cache: ${_pages.values.fold<int>(0, (n, rows) => n + rows.length)} rows', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool canManage) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Customers',
                style: TextStyle(
                  color: AppTheme.navy,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.45,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Customer master data, area, type, balances and activity at a glance.',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            IconButton(
              tooltip: 'Refresh customers',
              onPressed: _loading ? null : () => _fetchCustomers(reset: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
            if (canManage)
              FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Add Customer'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(520.0, math.max(280.0, constraints.maxWidth * .42)).toDouble();
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: width,
                height: 42,
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _searchNow(),
                  decoration: InputDecoration(
                    hintText: 'Customer ID, name, area, phone or email',
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close_rounded, size: 18),
                          )
                        : IconButton(
                            onPressed: _searchNow,
                            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                          ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              if (_search.isNotEmpty)
                InputChip(
                  label: Text('Search: $_search'),
                  onDeleted: _clearSearch,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTable(bool canManage) {
    const widths = <double>[250, 125, 120, 180, 165, 160, 140, 130, 115, 70];
    final minWidth = widths.fold<double>(0, (sum, width) => sum + width) + 24;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(minWidth, constraints.maxWidth).toDouble();
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _tableRow(
                    const [
                      'Customer',
                      'Customer ID',
                      'Type',
                      'Area',
                      'Phone',
                      'Email',
                      'Balance',
                      'Sales',
                      'Status',
                      '',
                    ],
                    header: true,
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => _fetchCustomers(reset: true),
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        controller: _scrollController,
                        itemExtent: _rowExtent,
                        itemCount: _total,
                        cacheExtent: _rowExtent * 12,
                        itemBuilder: (_, index) {
                          final customer = _customerAt(index);
                          return customer == null ? _loadingTableRow() : _customerRow(customer, canManage);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tableRow(List<String> cells, {bool header = false}) {
    const widths = <double>[250, 125, 120, 180, 165, 160, 140, 130, 115, 70];
    return Container(
      height: header ? 42 : 58,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: header ? AppTheme.surfaceSoft : Colors.white,
        border: const Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: List.generate(cells.length, (index) {
          final numeric = index == 6 || index == 7;
          return SizedBox(
            width: widths[index],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
              cells[index],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: numeric ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                color: header ? AppTheme.textMuted : AppTheme.navy,
                fontSize: header ? 11 : 12,
                fontWeight: header ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _customerRow(Map<String, dynamic> customer, bool canManage) {
    final name = _fullName(customer);
    final customerCode = (customer['customer_code'] ?? '—').toString();
    final type = _customerTypeLabel(customer['customer_type']);
    final area = CustomerDisplayUtils.areaName(customer);
    final phone = (customer['phone'] ?? '—').toString();
    final email = (customer['email'] ?? '—').toString();
    final balance = _toDouble(customer['balance']);
    final status = (customer['status'] ?? 'active').toString();
    final cells = <String>[
      name.isEmpty ? 'Unnamed customer' : name,
      customerCode,
      type,
      area.isEmpty ? '—' : area,
      phone,
      email,
      _money(balance),
      _money(customer['total_sales']),
      status.toUpperCase(),
      '',
    ];

    return InkWell(
      onTap: () => _openCustomer(customer),
      child: Stack(
        children: [
          _tableRow(cells),
          Positioned(
            right: 12,
            top: 9,
            child: canManage
                ? PopupMenuButton<String>(
                    tooltip: 'Customer actions',
                    onSelected: (value) {
                      if (value == 'edit') _openForm(customer);
                      if (value == 'delete') _deleteCustomer(customer);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  )
                : const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
          ),
          Positioned(
            right: 83,
            top: 21,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppTheme.statusColor(status),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingTableRow() => Container(
    height: _rowExtent,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    alignment: Alignment.centerLeft,
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
    child: const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
  );
}
