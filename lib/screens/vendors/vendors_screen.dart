import 'dart:math' as math;

import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/forms/vendor_form_screen.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/product_screen.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/vendors/vendor_edit_screen.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/counteriq_desktop_shell.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class VendorsScreen extends StatefulWidget {
  const VendorsScreen({super.key});

  @override
  State<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends State<VendorsScreen> {
  static const int _perPage = 40;

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
    final token = context.read<AuthProvider>().token!;
    _vendorService = VendorService(token: token);
    final branchProvider = context.read<BranchProvider>();
    _branchListener = () => _fetchVendors(reset: true);
    branchProvider.addListener(_branchListener!);
    _fetchVendors(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    final branchProvider = context.read<BranchProvider>();
    if (_branchListener != null) branchProvider.removeListener(_branchListener!);
    super.dispose();
  }

  Future<void> _fetchVendors({bool reset = false}) async {
    if (_loading) return;
    if (mounted) setState(() => _loading = true);
    if (reset) {
      _page = 1;
      _lastPage = 1;
      _total = 0;
      _vendors.clear();
    }
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final data = await _vendorService.getVendors(
        page: _page,
        perPage: _perPage,
        search: _search,
        includeBalance: true,
        branchId: branchId,
      );
      final wrapper = (data['data'] as Map<String, dynamic>?) ?? const {};
      final rows = (wrapper['vendors'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _vendors
          ..clear()
          ..addAll(rows);
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
    if (result == true && mounted) await _fetchVendors(reset: true);
  }

  Future<void> _openVendor(Map<String, dynamic> vendor) async {
    final rawId = vendor['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '');
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VendorEditScreen(vendorId: id)),
    );
    if (mounted) await _fetchVendors(reset: true);
  }

  Future<void> _deleteVendor(Map<String, dynamic> vendor) async {
    final name = _fullName(vendor);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Vendor'),
        content: Text(
          'Delete ${name.isEmpty ? 'this vendor' : name}? This action cannot be undone.',
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
      await _vendorService.deleteVendor(vendor['id'] as int);
      if (!mounted) return;
      AppFeedback.success(context, 'Vendor deleted');
      await _fetchVendors(reset: true);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Delete failed: $e');
    }
  }

  String _fullName(Map<String, dynamic> vendor) {
    final first = (vendor['first_name'] ?? '').toString().trim();
    final last = (vendor['last_name'] ?? '').toString().trim();
    return [first, last].where((part) => part.isNotEmpty).join(' ');
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '').trim()) ?? 0;
  }

  String _money(dynamic value) => AppCurrency.format(value);

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthProvider>().hasPermission('manage-vendors');
    return CounterIQDesktopShell(
      activeRouteId: PosRouteIds.vendors,
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
                  : _vendors.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 70),
                            EnterpriseEmptyState(
                              icon: Icons.groups_2_outlined,
                              title: 'No vendors found',
                              subtitle: _search.isEmpty
                                  ? 'Add vendors to manage purchases, payments and payables.'
                                  : 'No vendor matched your search.',
                              action: canManage
                                  ? FilledButton.icon(
                                      onPressed: () => _openForm(),
                                      icon: const Icon(Icons.group_add_rounded),
                                      label: const Text('Add Vendor'),
                                    )
                                  : null,
                            ),
                          ],
                        )
                      : _buildTable(canManage),
            ),
            if (_vendors.isNotEmpty) ...[
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
                'Vendors',
                style: TextStyle(
                  color: AppTheme.navy,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.45,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Supplier master data, payables and purchasing totals in one compact view.',
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
              tooltip: 'Refresh vendors',
              onPressed: _loading ? null : () => _fetchVendors(reset: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
            if (canManage)
              FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.group_add_rounded, size: 18),
                label: const Text('Add Vendor'),
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
          final width = math.min(500.0, math.max(280.0, constraints.maxWidth * .40)).toDouble();
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
                    hintText: 'Vendor name, phone or email',
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
    const widths = <double>[260, 180, 210, 145, 145, 145, 115, 70];
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
                      'Vendor',
                      'Phone',
                      'Email',
                      'Payable',
                      'Purchases',
                      'Paid',
                      'Status',
                      '',
                    ],
                    header: true,
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => _fetchVendors(reset: true),
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemExtent: 58,
                        itemCount: _vendors.length,
                        itemBuilder: (_, index) => _vendorRow(_vendors[index], canManage),
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
    const widths = <double>[260, 180, 210, 145, 145, 145, 115, 70];
    return Container(
      height: header ? 42 : 58,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: header ? AppTheme.surfaceSoft : Colors.white,
        border: const Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: List.generate(cells.length, (index) {
          final numeric = index >= 3 && index <= 5;
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

  Widget _vendorRow(Map<String, dynamic> vendor, bool canManage) {
    final name = _fullName(vendor);
    final phone = (vendor['phone'] ?? '—').toString();
    final email = (vendor['email'] ?? '—').toString();
    final balance = _toDouble(vendor['balance']);
    final status = (vendor['status'] ?? 'active').toString();
    final cells = <String>[
      name.isEmpty ? 'Unnamed vendor' : name,
      phone,
      email,
      _money(balance),
      _money(vendor['total_purchases']),
      _money(vendor['total_payments']),
      status.toUpperCase(),
      '',
    ];

    return InkWell(
      onTap: () => _openVendor(vendor),
      child: Stack(
        children: [
          _tableRow(cells),
          Positioned(
            right: 12,
            top: 9,
            child: canManage
                ? PopupMenuButton<String>(
                    tooltip: 'Vendor actions',
                    onSelected: (value) {
                      if (value == 'edit') _openForm(vendor);
                      if (value == 'delete') _deleteVendor(vendor);
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
              'Showing $start–$end of $_total vendors',
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
                    _fetchVendors();
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
                    _fetchVendors();
                  }
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
