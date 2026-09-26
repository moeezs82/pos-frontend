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

  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = false;
  String _search = '';
  final _searchController = TextEditingController();
  final List<Map<String, dynamic>> _customers = [];
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
    _fetchCustomers(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    final branchProvider = context.read<BranchProvider>();
    if (_branchListener != null) branchProvider.removeListener(_branchListener!);
    super.dispose();
  }

  Future<void> _fetchCustomers({bool reset = false}) async {
    if (_loading) return;
    if (mounted) setState(() => _loading = true);
    if (reset) {
      _page = 1;
      _lastPage = 1;
      _total = 0;
      _customers.clear();
    }
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final data = await _customerService.getCustomers(
        page: _page,
        perPage: _perPage,
        search: _search,
        includeBalance: true,
        branchId: branchId,
      );
      final wrapper = (data['data'] as Map<String, dynamic>?) ?? const {};
      final rows = (wrapper['customers'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _customers
          ..clear()
          ..addAll(rows);
        _page = (wrapper['current_page'] as num?)?.toInt() ?? _page;
        _lastPage = (wrapper['last_page'] as num?)?.toInt() ?? _lastPage;
        _total = (wrapper['total'] as num?)?.toInt() ?? _total;
      });
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to load customers: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _searchNow() {
    setState(() => _search = _searchController.text.trim());
    _fetchCustomers(reset: true);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _search = '');
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
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _customers.isEmpty
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
            if (_customers.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildPaginationBar(),
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
                        itemExtent: 58,
                        itemCount: _customers.length,
                        itemBuilder: (_, index) => _customerRow(_customers[index], canManage),
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

  Widget _buildPaginationBar() {
    final start = _total == 0 ? 0 : ((_page - 1) * _perPage) + 1;
    final end = math.min(_page * _perPage, _total);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Showing $start–$end of $_total customers',
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Previous page',
            onPressed: !_loading && _page > 1
                ? () {
                    setState(() => _page--);
                    _fetchCustomers();
                  }
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text(
            'Page $_page of $_lastPage',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: !_loading && _page < _lastPage
                ? () {
                    setState(() => _page++);
                    _fetchCustomers();
                  }
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
