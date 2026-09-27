import 'package:enterprise_pos/api/product_group_service.dart';
import 'package:enterprise_pos/forms/variable_product_form_screen.dart';
import 'package:enterprise_pos/screens/product_group_detail_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
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
  static const int _perPage = 40;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 58;

  final Map<int, List<ProductGroupSummary>> _pages = <int, List<ProductGroupSummary>>{};
  final Set<int> _loadingPages = <int>{};
  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();

  late ProductGroupService _service;
  String _search = '';
  int _lastPage = 1;
  int _total = 0;
  String? _error;

  bool get _initialLoading => _loadingPages.contains(1) && _pages.isEmpty;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _service = ProductGroupService(token: auth.token!);
    _scrollController.addListener(_onScroll);
    _resetAndLoad();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _resetAndLoad() async {
    if (mounted) {
      setState(() {
        _pages.clear();
        _loadingPages.clear();
        _lastPage = 1;
        _total = 0;
        _error = null;
      });
    }
    await _loadPage(1, force: true);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _loadPage(int page, {bool force = false}) async {
    if (page < 1 || page > _lastPage && _pages.isNotEmpty) return;
    if (!force && (_pages.containsKey(page) || _loadingPages.contains(page))) return;

    if (mounted) setState(() => _loadingPages.add(page));
    try {
      final data = await _service.listGroups(
        page: page,
        perPage: _perPage,
        search: _search.isEmpty ? null : _search,
      );
      final raw = (data['groups'] as List?) ?? const [];
      final groups = raw
          .whereType<Map>()
          .map((e) => ProductGroupSummary.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      final lastPage = (data['last_page'] as num?)?.toInt() ?? 1;
      final currentPage = (data['current_page'] as num?)?.toInt() ?? page;
      final total = (data['total'] as num?)?.toInt() ??
          (lastPage <= 1 ? groups.length : (lastPage - 1) * _perPage + groups.length);

      if (!mounted) return;
      setState(() {
        _pages[currentPage] = groups;
        _lastPage = lastPage < 1 ? 1 : lastPage;
        _total = total < groups.length ? groups.length : total;
        _error = null;
        _loadingPages.remove(page);
        _evictFarPages(_visiblePageEstimate());
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPages.remove(page);
        _error = e.toString();
      });
      AppFeedback.error(context, 'Failed to load variable products: $e');
    }
  }

  void _evictFarPages(int anchorPage) {
    if (_pages.length <= _maxCachedPages) return;
    final candidates = _pages.keys.toList()
      ..sort((a, b) => (b - anchorPage).abs().compareTo((a - anchorPage).abs()));
    while (_pages.length > _maxCachedPages && candidates.isNotEmpty) {
      final remove = candidates.removeAt(0);
      if (remove == anchorPage || remove == anchorPage + 1 || remove == anchorPage - 1) {
        continue;
      }
      _pages.remove(remove);
    }
  }

  int _visiblePageEstimate() {
    if (!_scrollController.hasClients) return 1;
    final firstIndex = (_scrollController.offset / _rowExtent).floor().clamp(0, _total == 0 ? 0 : _total - 1);
    return (firstIndex ~/ _perPage) + 1;
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _total == 0) return;
    final firstIndex = (_scrollController.offset / _rowExtent).floor().clamp(0, _total - 1);
    final visibleCount = (_scrollController.position.viewportDimension / _rowExtent).ceil() + 8;
    final lastIndex = (firstIndex + visibleCount).clamp(0, _total - 1);
    final firstPage = (firstIndex ~/ _perPage) + 1;
    final lastPage = (lastIndex ~/ _perPage) + 1;
    for (var p = firstPage; p <= lastPage; p++) {
      _loadPage(p);
    }
    if (lastPage < _lastPage) _loadPage(lastPage + 1);
    if (firstPage > 1) _loadPage(firstPage - 1);
    if (_pages.length > _maxCachedPages) {
      setState(() => _evictFarPages(firstPage));
    }
  }

  ProductGroupSummary? _groupAt(int index) {
    final page = (index ~/ _perPage) + 1;
    final local = index % _perPage;
    final rows = _pages[page];
    if (rows == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPage(page));
      return null;
    }
    if (local >= rows.length) return null;
    return rows[local];
  }

  void _applySearch() {
    final next = _searchCtrl.text.trim();
    if (next == _search) return;
    _search = next;
    _resetAndLoad();
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _search = '';
    _resetAndLoad();
  }

  Future<void> _openCreate() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VariableProductFormScreen()),
    );
    if (result == true && mounted) _resetAndLoad();
  }

  Future<void> _openDetail(ProductGroupSummary group) async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductGroupDetailScreen(
          groupId: group.id,
          groupName: group.name,
        ),
      ),
    );
    if (changed == true && mounted) _resetAndLoad();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final canManage = auth.hasPermission('manage-products');

    return EnterprisePage(
      title: 'Product Groups',
      subtitle: 'Manage variable-product families and open their existing variant detail workspace.',
      icon: Icons.account_tree_outlined,
      actions: [
        OutlinedButton.icon(
          onPressed: _resetAndLoad,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
        ),
        if (canManage)
          FilledButton.icon(
            onPressed: _openCreate,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Group'),
          ),
      ],
      child: Column(
        children: [
          EnterpriseToolbar(
            children: [
              SizedBox(
                width: 360,
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: (_) => _applySearch(),
                  decoration: InputDecoration(
                    hintText: 'Search group name…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _applySearch,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Search'),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  '$_total groups • ${_pages.length} cached page${_pages.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: _initialLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null && _pages.isEmpty
                      ? _errorState()
                      : _total == 0
                          ? _buildEmpty(canManage)
                          : Column(
                              children: [
                                _tableHeader(),
                                Expanded(
                                  child: Scrollbar(
                                    controller: _scrollController,
                                    thumbVisibility: true,
                                    child: ListView.builder(
                                      controller: _scrollController,
                                      itemExtent: _rowExtent,
                                      cacheExtent: _rowExtent * 12,
                                      itemCount: _total,
                                      itemBuilder: (_, index) {
                                        final group = _groupAt(index);
                                        return group == null
                                            ? _loadingRow()
                                            : _groupRow(group);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader() => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: AppTheme.surfaceSoft,
        child: const Row(
          children: [
            Expanded(flex: 34, child: Text('GROUP', style: _headerStyle)),
            SizedBox(width: 16),
            Expanded(flex: 12, child: Text('VARIANTS', style: _headerStyle)),
            SizedBox(width: 16),
            Expanded(flex: 18, child: Text('PRICE RANGE', style: _headerStyle)),
            SizedBox(width: 16),
            Expanded(flex: 14, child: Text('STOCK', style: _headerStyle)),
            SizedBox(width: 16),
            Expanded(flex: 12, child: Text('STATUS', style: _headerStyle)),
            SizedBox(width: 16),
            SizedBox(width: 70, child: Text('ACTION', style: _headerStyle)),
          ],
        ),
      );

  Widget _groupRow(ProductGroupSummary group) {
    final priceRange = group.minPrice != null && group.maxPrice != null
        ? (group.minPrice == group.maxPrice
            ? AppCurrency.format(group.minPrice)
            : '${AppCurrency.format(group.minPrice)} – ${AppCurrency.format(group.maxPrice)}')
        : '—';
    return InkWell(
      onTap: () => _openDetail(group),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 34,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  if ((group.secondaryName ?? '').trim().isNotEmpty)
                    Text(group.secondaryName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(flex: 12, child: Text('${group.variantCount}', style: const TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(width: 16),
            Expanded(flex: 18, child: Text(priceRange, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 16),
            Expanded(flex: 14, child: Text(group.totalStock.toStringAsFixed(group.totalStock % 1 == 0 ? 0 : 2))),
            const SizedBox(width: 16),
            Expanded(
              flex: 12,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _statusBadge(group.isActive),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 70,
              child: IconButton(
                tooltip: 'Open group',
                onPressed: () => _openDetail(group),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(bool active) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: (active ? AppTheme.success : AppTheme.textMuted).withOpacity(.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: (active ? AppTheme.success : AppTheme.textMuted).withOpacity(.22)),
        ),
        child: Text(
          active ? 'Active' : 'Inactive',
          style: TextStyle(
            color: active ? AppTheme.success : AppTheme.textMuted,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      );

  Widget _loadingRow() => const DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Center(
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 34),
              const SizedBox(height: 10),
              const Text('Could not load product groups', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textMuted)),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _resetAndLoad, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
            ],
          ),
        ),
      );

  Widget _buildEmpty(bool canManage) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_tree_outlined, color: AppTheme.textMuted, size: 38),
            const SizedBox(height: 10),
            Text(
              _search.isEmpty ? 'No product groups yet' : 'No groups match “$_search”',
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.navy),
            ),
            const SizedBox(height: 4),
            const Text('Variable products are grouped here without changing variant inventory logic.', style: TextStyle(color: AppTheme.textMuted)),
            if (canManage && _search.isEmpty) ...[
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: _openCreate, icon: const Icon(Icons.add_rounded), label: const Text('Add Group')),
            ],
          ],
        ),
      );

  static const TextStyle _headerStyle = TextStyle(
    color: AppTheme.textMuted,
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: .25,
  );
}

