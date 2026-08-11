import 'package:enterprise_pos/api/product_group_service.dart';
import 'package:enterprise_pos/forms/variable_product_form_screen.dart';
import 'package:enterprise_pos/screens/product_group_detail_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'package:enterprise_pos/services/app_currency.dart' show AppCurrency;

/// Paginated list of variable product groups (product_groups rows) with
/// per-group aggregates: variant count, price range, total stock.
class ProductGroupsScreen extends StatefulWidget {
  const ProductGroupsScreen({super.key});

  @override
  State<ProductGroupsScreen> createState() => _ProductGroupsScreenState();
}

class _ProductGroupsScreenState extends State<ProductGroupsScreen> {
  int _page = 1;
  int _lastPage = 1;
  bool _loading = false;
  String _search = '';
  final List<ProductGroupSummary> _groups = [];
  final _searchCtrl = TextEditingController();

  late ProductGroupService _service;
  late String _token;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _token = auth.token!;
    _service = ProductGroupService(token: _token);
    _fetchGroups(reset: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchGroups({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    if (reset) {
      _groups.clear();
      _page = 1;
    }
    try {
      final data = await _service.listGroups(page: _page, search: _search);
      final raw = (data['groups'] as List?) ?? [];
      final groups = raw
          .whereType<Map>()
          .map((e) =>
              ProductGroupSummary.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      if (!mounted) return;
      setState(() {
        _groups
          ..clear()
          ..addAll(groups);
        _page = (data['current_page'] as num?)?.toInt() ?? _page;
        _lastPage = (data['last_page'] as num?)?.toInt() ?? _lastPage;
      });
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to load groups: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch() {
    setState(() => _search = _searchCtrl.text.trim());
    _fetchGroups(reset: true);
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _search = '');
    _fetchGroups(reset: true);
  }

  Future<void> _openCreate() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => const VariableProductFormScreen()),
    );
    if (result == true && mounted) _fetchGroups(reset: true);
  }

  Future<void> _openDetail(ProductGroupSummary group) async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ProductGroupDetailScreen(
                groupId: group.id,
                groupName: group.name,
              )),
    );
    if (changed == true && mounted) _fetchGroups(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final canManage = auth.hasPermission('manage-products');

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        foregroundColor: Colors.white,
        title: const Text('Variable Products'),
        actions: [
          const BranchIndicator(),
          if (canManage)
            IconButton(
              tooltip: 'New Variable Product',
              icon: const Icon(Icons.add_rounded),
              onPressed: _openCreate,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _loading && _groups.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary))
                : _groups.isEmpty
                    ? _buildEmpty(canManage)
                    : RefreshIndicator(
                        onRefresh: () => _fetchGroups(reset: true),
                        child: Column(
                          children: [
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: _groups.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) =>
                                    _GroupCard(
                                  group: _groups[i],
                                  onTap: () => _openDetail(_groups[i]),
                                ),
                              ),
                            ),
                            _buildPagination(),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: Colors.white,
      child: SizedBox(
        height: 38,
        child: TextField(
          controller: _searchCtrl,
          onSubmitted: (_) => _onSearch(),
          decoration: InputDecoration(
            hintText: 'Search variable products…',
            hintStyle:
                const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            prefixIcon: const Icon(Icons.search_rounded,
                size: 18, color: AppTheme.textMuted),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    onPressed: _clearSearch,
                    splashRadius: 14,
                  )
                : null,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppTheme.borderStrong)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                    color: AppTheme.primary, width: 1.5)),
            filled: true,
            fillColor: AppTheme.surfaceSoft,
          ),
          onChanged: (v) {
            setState(() {}); // update clear icon visibility
          },
        ),
      ),
    );
  }

  Widget _buildEmpty(bool canManage) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.grid_view_rounded,
                color: AppTheme.primary, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            _search.isEmpty
                ? 'No variable products yet'
                : 'No products matching "$_search"',
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.navy,
                fontSize: 14),
          ),
          const SizedBox(height: 4),
          const Text(
            'Variable products group multiple size/color variants\nunder one parent.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
          if (canManage && _search.isEmpty) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openCreate,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('New Variable Product'),
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPagination() {
    if (_lastPage <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.border))),
      child: Row(
        children: [
          IconButton(
            onPressed: !_loading && _page > 1
                ? () {
                    setState(() => _page--);
                    _fetchGroups();
                  }
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Text('Page $_page of $_lastPage',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted)),
          ),
          IconButton(
            onPressed: !_loading && _page < _lastPage
                ? () {
                    setState(() => _page++);
                    _fetchGroups();
                  }
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ── Group card ────────────────────────────────────────────────────────────────

class _GroupCard extends StatelessWidget {
  final ProductGroupSummary group;
  final VoidCallback onTap;

  const _GroupCard({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final priceRange = group.minPrice != null && group.maxPrice != null
        ? (group.minPrice == group.maxPrice
            ? AppCurrency.format(group.minPrice)
            : '${AppCurrency.format(group.minPrice)} – ${AppCurrency.format(group.maxPrice)}')
        : '—';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Icon / thumbnail
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: group.imageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(group.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.grid_view_rounded,
                                color: AppTheme.primary,
                                size: 22)),
                      )
                    : const Icon(Icons.grid_view_rounded,
                        color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 14),

              // Name + meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppTheme.navy),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!group.isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceSoft,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: const Text('INACTIVE',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textMuted)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 14,
                      children: [
                        _meta('${group.variantCount} variant${group.variantCount == 1 ? '' : 's'}'),
                        _meta(priceRange),
                        _meta(
                            'Stock: ${group.totalStock.toStringAsFixed(group.totalStock == group.totalStock.truncateToDouble() ? 0 : 2)}'),
                      ],
                    ),
                  ],
                ),
              ),

              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(String text) {
    return Text(text,
        style: const TextStyle(
            fontSize: 12, color: AppTheme.textMuted));
  }
}
