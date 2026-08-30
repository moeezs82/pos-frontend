import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/forms/customer_form_screen.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/customers/customers_edit_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
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
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _customerService = CustomerService(token: token);
    final branchProv = Provider.of<BranchProvider>(context, listen: false);
    _branchListener = () => _fetchCustomers(reset: true);
    branchProv.addListener(_branchListener!);
    _fetchCustomers(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    final branchProv = Provider.of<BranchProvider>(context, listen: false);
    if (_branchListener != null) branchProv.removeListener(_branchListener!);
    super.dispose();
  }

  Future<void> _fetchCustomers({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    if (reset) {
      _customers.clear();
      _page = 1;
      _lastPage = 1;
      _total = 0;
    }
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final data = await _customerService.getCustomers(
        page: _page,
        search: _search,
        includeBalance: true,
        branchId: branchId,
      );
      final wrapper = (data['data'] as Map<String, dynamic>?) ?? const {};
      final items = (wrapper['customers'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      if (!mounted) return;
      setState(() {
        _customers
          ..clear()
          ..addAll(items);
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
    if (result != null) _fetchCustomers(reset: true);
  }

  Future<void> _deleteCustomer(Map<String, dynamic> customer) async {
    final fullName = _fullName(customer);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text('Delete ${fullName.isEmpty ? 'this customer' : fullName}? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
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
      _fetchCustomers(reset: true);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Delete failed: $e');
    }
  }

  String _fullName(Map<String, dynamic> c) {
    final first = (c['first_name'] ?? '').toString().trim();
    final last = (c['last_name'] ?? '').toString().trim();
    return [first, last].where((s) => s.isNotEmpty).join(' ');
  }

  String _initials(Map<String, dynamic> c) {
    final name = _fullName(c);
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
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

  Color _customerTypeColor(dynamic raw) {
    switch ((raw ?? 'retail').toString().toLowerCase()) {
      case 'wholesale':
        return AppTheme.info;
      case 'reseller':
        return AppTheme.warning;
      default:
        return AppTheme.primary;
    }
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0;
  }

  String _money(dynamic v) => AppCurrency.format(v);

  @override
  Widget build(BuildContext context) {
    final canManageCustomers = context.watch<AuthProvider>().hasPermission('manage-customers');
    return EnterprisePage(
      title: 'Customers',
      subtitle: 'Search customers, check balances and open full ledger/actions quickly.',
      icon: Icons.people_alt_rounded,
      appBarActions: const [
        Padding(
          padding: EdgeInsets.only(right: 8),
          child: BranchIndicator(tappable: false),
        ),
      ],
      actions: [
        if (canManageCustomers)
          FilledButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add Customer'),
          ),
      ],
      bottomNavigationBar: _customers.isNotEmpty
          ? EnterprisePaginationBar(
              page: _page,
              lastPage: _lastPage,
              total: _total,
              loading: _loading,
              onPrevious: _page > 1
                  ? () {
                      setState(() => _page--);
                      _fetchCustomers();
                    }
                  : null,
              onNext: _page < _lastPage
                  ? () {
                      setState(() => _page++);
                      _fetchCustomers();
                    }
                  : null,
            )
          : null,
      child: Column(
        children: [
          EnterpriseToolbar(
            children: [
              SizedBox(
                width: MediaQuery.of(context).size.width >= 720 ? 440 : double.infinity,
                child: EnterpriseSearchField(
                  controller: _searchController,
                  hintText: 'Search customer ID, name, phone, email...',
                  onSubmitted: (_) => _searchNow(),
                  onSearch: _searchNow,
                  onClear: _clearSearch,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _fetchCustomers(reset: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _customers.isEmpty
                    ? EnterpriseEmptyState(
                        icon: Icons.people_outline_rounded,
                        title: 'No customers found',
                        subtitle: _search.isEmpty
                            ? 'Add customers to manage balances, receipts and ledgers.'
                            : 'No customer matched your search.',
                        action: canManageCustomers
                            ? FilledButton.icon(
                                onPressed: () => _openForm(),
                                icon: const Icon(Icons.person_add_alt_1_rounded),
                                label: const Text('Add Customer'),
                              )
                            : null,
                      )
                    : RefreshIndicator(
                        onRefresh: () => _fetchCustomers(reset: true),
                        child: ListView.separated(
                          itemCount: _customers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final c = _customers[i];
                            final fullName = _fullName(c);
                            final email = (c['email'] ?? '—').toString();
                            final phone = (c['phone'] ?? '—').toString();
                            final status = (c['status'] ?? 'active').toString();
                            final customerCode = (c['customer_code'] ?? '').toString().trim();
                            final customerType = _customerTypeLabel(c['customer_type']);
                            final customerTypeColor = _customerTypeColor(c['customer_type']);
                            final balance = _toDouble(c['balance']);
                            final totalSales = _money(c['total_sales']);
                            final totalReceipts = _money(c['total_receipts']);
                            final balColor = balance > 0
                                ? AppTheme.warning
                                : balance < 0
                                    ? AppTheme.success
                                    : AppTheme.textMuted;

                            return Card(
                              child: ListTile(
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => CustomerEditScreen(customerId: c['id'])),
                                  );
                                  _fetchCustomers(reset: true);
                                },
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primarySoft,
                                  foregroundColor: AppTheme.primary,
                                  child: Text(_initials(c)),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        fullName.isEmpty ? 'Unnamed customer' : fullName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    EnterpriseStatusBadge(
                                      label: customerType.toUpperCase(),
                                      color: customerTypeColor,
                                    ),
                                    const SizedBox(width: 6),
                                    EnterpriseStatusBadge(
                                      label: status.toUpperCase(),
                                      color: AppTheme.statusColor(status),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (customerCode.isNotEmpty)
                                        EnterpriseMetricChip(label: 'Customer ID', value: customerCode, color: AppTheme.primary, icon: Icons.numbers_rounded),
                                      EnterpriseMetricChip(label: 'Phone', value: phone, color: AppTheme.info, icon: Icons.call_rounded),
                                      EnterpriseMetricChip(label: 'Balance', value: _money(balance), color: balColor, icon: Icons.account_balance_wallet_rounded),
                                      EnterpriseMetricChip(label: 'Sales', value: totalSales, color: AppTheme.primary),
                                      EnterpriseMetricChip(label: 'Received', value: totalReceipts, color: AppTheme.success),
                                      if (email != '—') EnterpriseMetricChip(label: 'Email', value: email, color: AppTheme.textMuted),
                                    ],
                                  ),
                                ),
                                trailing: canManageCustomers
                                    ? PopupMenuButton<String>(
                                        tooltip: 'Actions',
                                        onSelected: (value) {
                                          if (value == 'edit') _openForm(c);
                                          if (value == 'delete') _deleteCustomer(c);
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                                        ],
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
