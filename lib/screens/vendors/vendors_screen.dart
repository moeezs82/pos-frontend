import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/forms/vendor_form_screen.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/vendors/vendor_edit_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class VendorsScreen extends StatefulWidget {
  const VendorsScreen({super.key});

  @override
  State<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends State<VendorsScreen> {
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = false;
  String _search = '';
  final _searchController = TextEditingController();
  final List<Map<String, dynamic>> _vendors = [];
  late VendorService _vendorService;
  VoidCallback? _branchListener;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _vendorService = VendorService(token: token);
    final branchProv = Provider.of<BranchProvider>(context, listen: false);
    _branchListener = () => _fetchVendors(reset: true);
    branchProv.addListener(_branchListener!);
    _fetchVendors(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    final branchProv = Provider.of<BranchProvider>(context, listen: false);
    if (_branchListener != null) branchProv.removeListener(_branchListener!);
    super.dispose();
  }

  Future<void> _fetchVendors({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    if (reset) {
      _vendors.clear();
      _page = 1;
      _lastPage = 1;
      _total = 0;
    }
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final data = await _vendorService.getVendors(
        page: _page,
        search: _search,
        includeBalance: true,
        branchId: branchId,
      );
      final wrapper = (data['data'] as Map<String, dynamic>?) ?? const {};
      final items = (wrapper['vendors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      if (!mounted) return;
      setState(() {
        _vendors
          ..clear()
          ..addAll(items);
        _page = (wrapper['current_page'] as num?)?.toInt() ?? _page;
        _lastPage = (wrapper['last_page'] as num?)?.toInt() ?? _lastPage;
        _total = (wrapper['total'] as num?)?.toInt() ?? _total;
      });
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to load vendors: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _searchNow() {
    setState(() => _search = _searchController.text.trim());
    _fetchVendors(reset: true);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _search = '');
    _fetchVendors(reset: true);
  }

  Future<void> _openForm([Map<String, dynamic>? vendor]) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VendorFormScreen(vendor: vendor)),
    );
    if (result == true) _fetchVendors(reset: true);
  }

  Future<void> _deleteVendor(Map<String, dynamic> vendor) async {
    final fullName = _fullName(vendor);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Vendor'),
        content: Text('Delete ${fullName.isEmpty ? 'this vendor' : fullName}? This action cannot be undone.'),
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
      await _vendorService.deleteVendor(vendor['id'] as int);
      if (!mounted) return;
      AppFeedback.success(context, 'Vendor deleted');
      _fetchVendors(reset: true);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Delete failed: $e');
    }
  }

  String _fullName(Map<String, dynamic> v) {
    final first = (v['first_name'] ?? '').toString().trim();
    final last = (v['last_name'] ?? '').toString().trim();
    return [first, last].where((s) => s.isNotEmpty).join(' ');
  }

  String _initials(Map<String, dynamic> v) {
    final name = _fullName(v);
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0;
  }

  String _money(dynamic v) => AppCurrency.format(v);

  @override
  Widget build(BuildContext context) {
    return EnterprisePage(
      title: 'Vendors',
      subtitle: 'Manage suppliers, payable balances and purchase history.',
      icon: Icons.groups_2_rounded,
      appBarActions: const [
        Padding(
          padding: EdgeInsets.only(right: 8),
          child: BranchIndicator(tappable: false),
        ),
      ],
      actions: [
        FilledButton.icon(
          onPressed: () => _openForm(),
          icon: const Icon(Icons.group_add_rounded),
          label: const Text('Add Vendor'),
        ),
      ],
      bottomNavigationBar: _vendors.isNotEmpty
          ? EnterprisePaginationBar(
              page: _page,
              lastPage: _lastPage,
              total: _total,
              loading: _loading,
              onPrevious: _page > 1
                  ? () {
                      setState(() => _page--);
                      _fetchVendors();
                    }
                  : null,
              onNext: _page < _lastPage
                  ? () {
                      setState(() => _page++);
                      _fetchVendors();
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
                  hintText: 'Search name, phone, email...',
                  onSubmitted: (_) => _searchNow(),
                  onSearch: _searchNow,
                  onClear: _clearSearch,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _fetchVendors(reset: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _vendors.isEmpty
                    ? EnterpriseEmptyState(
                        icon: Icons.groups_2_outlined,
                        title: 'No vendors found',
                        subtitle: _search.isEmpty
                            ? 'Add vendors to manage purchases, payments and payables.'
                            : 'No vendor matched your search.',
                        action: FilledButton.icon(
                          onPressed: () => _openForm(),
                          icon: const Icon(Icons.group_add_rounded),
                          label: const Text('Add Vendor'),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _fetchVendors(reset: true),
                        child: ListView.separated(
                          itemCount: _vendors.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final v = _vendors[i];
                            final fullName = _fullName(v);
                            final email = (v['email'] ?? '—').toString();
                            final phone = (v['phone'] ?? '—').toString();
                            final status = (v['status'] ?? 'active').toString();
                            final balance = _toDouble(v['balance']);
                            final purchases = _money(v['total_purchases']);
                            final payments = _money(v['total_payments']);
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
                                    MaterialPageRoute(builder: (_) => VendorEditScreen(vendorId: v['id'])),
                                  );
                                  _fetchVendors(reset: true);
                                },
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primarySoft,
                                  foregroundColor: AppTheme.primary,
                                  child: Text(_initials(v)),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        fullName.isEmpty ? 'Unnamed vendor' : fullName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
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
                                      EnterpriseMetricChip(label: 'Phone', value: phone, color: AppTheme.info, icon: Icons.call_rounded),
                                      EnterpriseMetricChip(label: 'Payable', value: _money(balance), color: balColor, icon: Icons.account_balance_wallet_rounded),
                                      EnterpriseMetricChip(label: 'Purchases', value: purchases, color: AppTheme.primary),
                                      EnterpriseMetricChip(label: 'Paid', value: payments, color: AppTheme.success),
                                      if (email != '—') EnterpriseMetricChip(label: 'Email', value: email, color: AppTheme.textMuted),
                                    ],
                                  ),
                                ),
                                trailing: PopupMenuButton<String>(
                                  tooltip: 'Actions',
                                  onSelected: (value) {
                                    if (value == 'edit') _openForm(v);
                                    if (value == 'delete') _deleteVendor(v);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                                  ],
                                ),
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
