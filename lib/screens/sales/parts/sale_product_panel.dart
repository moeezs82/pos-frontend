import 'dart:async';

import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/forms/product_form_screen.dart';
import 'package:enterprise_pos/services/catalog_cache_service.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Always-visible embedded product grid for the Create Sale 3-panel layout.
///
/// Replaces the first-load auto-open of [ProductPickerGridSheet] so the
/// cashier can browse and click products without ever opening a modal.
/// [ProductPickerGridSheet] (F2) remains available as a multi-select
/// fallback for bulk additions.
class SaleProductPanel extends StatefulWidget {
  final String token;
  final int? vendorId;

  /// Branch used to scope the offline SQLite fallback search so results are
  /// limited to the active branch's stock. Nullable — null means "all branches"
  /// which is the safe default when no branch is selected.
  final int? branchId;

  /// IDs of products already in the cart — used to show the in-cart badge.
  final Set<int> cartProductIds;

  /// Called when the cashier taps a product card. The parent adds it to
  /// the cart immediately (qty 1) via [_applyPickedProduct].
  final void Function(Map<String, dynamic> product) onProductTapped;

  /// Called when the cashier presses the F2 / "Select Items" fallback to
  /// open [ProductPickerGridSheet] for multi-select.
  final VoidCallback onOpenModal;

  /// External focus node — when the parent requests focus on this node
  /// (e.g. via Ctrl+Shift+P or replacing the first-load modal open), the
  /// search field inside this panel receives focus.
  final FocusNode? searchFocusNode;

  /// When provided, the panel uses this controller instead of its own
  /// internal one. Useful when the parent places the search bar outside this
  /// widget (e.g. in the left cart panel's input row) so that typing in the
  /// left panel filters the product grid on the right.
  final TextEditingController? externalSearchController;

  /// When false, the top search-bar row is hidden. Use this when the parent
  /// renders the search field elsewhere (e.g. in the input row on the left).
  final bool showSearchBar;

  const SaleProductPanel({
    super.key,
    required this.token,
    required this.cartProductIds,
    required this.onProductTapped,
    required this.onOpenModal,
    this.vendorId,
    this.branchId,
    this.searchFocusNode,
    this.externalSearchController,
    this.showSearchBar = true,
  });

  @override
  State<SaleProductPanel> createState() => _SaleProductPanelState();
}

class _SaleProductPanelState extends State<SaleProductPanel> {
  // ── Controllers & focus ─────────────────────────────────────────────────
  /// Internal controller used when the parent does NOT provide its own.
  final _searchCtrl = TextEditingController();

  /// Effective controller: external if provided, otherwise internal.
  TextEditingController get _effectiveCtrl =>
      widget.externalSearchController ?? _searchCtrl;

  /// Fallback focus node when no external [widget.searchFocusNode] is supplied.
  final _internalSearchFocus = FocusNode();

  /// The focus node wired to the search TextField. If the parent supplies
  /// [widget.searchFocusNode], we use it directly so the parent's keyboard
  /// shortcuts (e.g. Ctrl+Shift+P) immediately put the cursor in the field.
  FocusNode get _activeSearchFocus =>
      widget.searchFocusNode ?? _internalSearchFocus;

  Timer? _debounce;

  // ── Data ────────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _brands = [];
  int? _selectedCategoryId;
  int? _selectedBrandId;
  int _page = 1;
  int _lastPage = 1;
  bool _loading = false;
  bool _silentRefreshing = false;
  String _search = '';

  late final ProductService _productService;
  late final CommonService _commonService;

  String get _cacheKey => ProductPickCache.keyFor(vendorId: widget.vendorId);

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _productService = ProductService(token: widget.token);
    _commonService = CommonService(token: widget.token);

    // Cache-first: show whatever was warmed by PartyPrefetch instantly.
    final cached = ProductPickCache.cache.peek(_cacheKey);
    if (cached != null) {
      _products.addAll(cached.items);
      _page = cached.currentPage;
      _lastPage = cached.lastPage;
    }

    _fetchProducts(page: 1, silent: cached != null);
    _fetchCategoriesAndBrands();

    // When the parent supplies a search controller (the search bar lives in
    // the left panel), listen to its changes so typing there filters the grid.
    widget.externalSearchController?.addListener(_onExternalControllerChanged);
  }

  void _onExternalControllerChanged() {
    final ctrl = widget.externalSearchController;
    if (ctrl != null) _onSearchChanged(ctrl.text);
  }

  @override
  void didUpdateWidget(covariant SaleProductPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vendorId != widget.vendorId) {
      _selectedCategoryId = null;
      _selectedBrandId = null;
      _searchCtrl.clear();
      _search = '';
      _fetchProducts(page: 1, replace: true);
    }
  }

  @override
  void dispose() {
    widget.externalSearchController
        ?.removeListener(_onExternalControllerChanged);
    _debounce?.cancel();
    _searchCtrl.dispose(); // always dispose internal, even if unused
    _internalSearchFocus.dispose();
    super.dispose();
  }

  // ── Data fetching ────────────────────────────────────────────────────────
  Future<void> _fetchProducts({
    required int page,
    bool replace = true,
    bool silent = false,
  }) async {
    if (silent) {
      if (mounted) setState(() => _silentRefreshing = true);
    } else {
      if (_loading) return;
      if (mounted) setState(() => _loading = true);
    }

    try {
      final entry = _search.isEmpty
          ? await ProductPickCache.cache.refresh(
              _cacheKey,
              () => ProductPickCache.fetchPage(
                _productService,
                page: page,
                search: '',
                vendorId: widget.vendorId,
                perPage: 60,
              ),
              requestKey: '$_cacheKey::p$page',
            )
          : await ProductPickCache.fetchPage(
              _productService,
              page: page,
              search: _search,
              vendorId: widget.vendorId,
              perPage: 60,
            );

      if (!mounted) return;
      setState(() {
        if (replace) _products.clear();
        _products.addAll(entry.items);
        _page = entry.currentPage;
        _lastPage = entry.lastPage;
      });
    } catch (_) {
      // Offline / server-unreachable fallback: query the local SQLite catalog
      // so the grid stays usable when the server is down.  All matching
      // products are loaded into a single virtual page (pagination bar hides
      // automatically when _lastPage ≤ 1) so the user can search to filter
      // rather than paginating.  The server-side pagination resumes the next
      // time connectivity is restored and _fetchProducts succeeds.
      try {
        final offlineItems = await CatalogCacheService.instance.searchProducts(
          _search,
          branchId: widget.branchId,
          vendorId: widget.vendorId,
          limit: 500,
        );
        if (mounted && offlineItems.isNotEmpty) {
          setState(() {
            if (replace) _products.clear();
            _products.addAll(offlineItems);
            _page = 1;
            _lastPage = 1; // collapse pagination while offline
          });
        }
      } catch (_) {
        // Double failure: keep whatever is already on screen.
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _silentRefreshing = false;
        });
      }
    }
  }

  Future<void> _fetchCategoriesAndBrands() async {
    try {
      final cats = await _commonService.getCategories();
      if (mounted) setState(() => _categories = cats);
    } catch (_) {}
    try {
      final brands = await _commonService.getBrands();
      if (mounted) setState(() => _brands = brands);
    } catch (_) {}
  }

  void _onSearchChanged(String val) {
    final q = val.trim();

    // Instant local filter on cached products.
    final cached = ProductPickCache.cache.peek(_cacheKey);
    if (cached != null) {
      final ql = q.toLowerCase();
      final filtered = ql.isEmpty
          ? cached.items
          : cached.items.where((p) {
              final name = (p['name'] ?? '').toString().toLowerCase();
              final sku =
                  (p['sku'] ?? p['barcode'] ?? '').toString().toLowerCase();
              return name.contains(ql) || sku.contains(ql);
            }).toList();
      if (mounted) {
        setState(() {
          _products
            ..clear()
            ..addAll(filtered);
        });
      }
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      setState(() => _search = q);
      _fetchProducts(page: 1, replace: true, silent: cached != null);
    });
  }

  // ── Derived list (client-side category / brand filter) ───────────────────
  List<Map<String, dynamic>> get _filteredProducts {
    var list = _products;
    if (_selectedCategoryId != null) {
      list = list.where((p) {
        final cid = _asInt(p['category_id'] ?? p['category']?['id']);
        return cid == _selectedCategoryId;
      }).toList();
    }
    if (_selectedBrandId != null) {
      list = list.where((p) {
        final bid = _asInt(p['brand_id'] ?? p['brand']?['id']);
        return bid == _selectedBrandId;
      }).toList();
    }
    return list;
  }

  // ── Quick-add product ────────────────────────────────────────────────────
  Future<void> _quickAddProduct() async {
    final created = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProductFormScreen(vendorId: widget.vendorId),
      ),
    );
    if (created == null || !mounted) return;
    setState(() => _products.insert(0, created));
    ProductPickCache.cache.insertInto(
      _cacheKey,
      created,
      matchesExisting: (p) =>
          p['id']?.toString() == created['id']?.toString(),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  String? _imageUrl(Map<String, dynamic> p) {
    final url = p['image_url'] ?? p['image'] ?? p['thumbnail'] ?? p['photo'];
    if (url == null) return null;
    final s = url.toString().trim();
    return s.isEmpty ? null : s;
  }

  int _gridCrossAxisCount(double width) {
    if (width >= 1400) return 8;
    if (width >= 1100) return 7;
    if (width >= 900) return 6;
    if (width >= 700) return 5;
    if (width >= 500) return 4;
    if (width >= 350) return 3;
    if (width >= 220) return 2;
    return 1;
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top bar: title + F2 shortcut (search moved below filter row)
        _buildTopBar(),
        if (_silentRefreshing)
          const LinearProgressIndicator(minHeight: 2, color: AppTheme.primary),
        _buildFilterRow(),
        // ── Point 2: compact grid search — always below filter row ──────────
        _buildGridSearchBar(),
        Expanded(child: _buildGrid()),
        _buildPaginationBar(),
      ],
    );
  }

  // ── Top bar: F2 shortcut button ──────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      height: 42,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.grid_view_rounded,
            size: 15,
            color: AppTheme.textMuted,
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Product Browser',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
              ),
            ),
          ),
          Tooltip(
            message: 'Multi-select / Bulk add  (F2)',
            child: OutlinedButton.icon(
              onPressed: widget.onOpenModal,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 14),
              label: const Text('F2', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Grid search field: compact, always visible, below filter row ─────────
  Widget _buildGridSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: SizedBox(
        height: 34,
        child: TextField(
          controller: _effectiveCtrl,
          focusNode: _activeSearchFocus,
          onChanged: _onSearchChanged,
          onSubmitted: (_) => _fetchProducts(page: 1, replace: true),
          decoration: InputDecoration(
            hintText: 'Filter products by name, SKU or barcode…',
            hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 16,
              color: AppTheme.textMuted,
            ),
            suffixIcon: _effectiveCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    onPressed: () {
                      _effectiveCtrl.clear();
                      _onSearchChanged('');
                    },
                    splashRadius: 14,
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: AppTheme.borderStrong),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: AppTheme.borderStrong),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
            filled: true,
            fillColor: AppTheme.surfaceSoft,
          ),
        ),
      ),
    );
  }

  // ── Filter row: Category + Brand dropdowns ───────────────────────────────
  Widget _buildFilterRow() {
    // Always show the row so the dropdowns are always reachable.
    // Items will just say "All Categories / All Brands" when data isn't loaded.
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F5),
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          // ── Category dropdown ──────────────────────────────────────────
          Expanded(
            child: _StyledDropdown<int?>(
              value: _selectedCategoryId,
              hint: 'All Categories',
              items: [
                const _DropdownOption(value: null, label: 'All Categories'),
                ..._categories.map(
                  (cat) => _DropdownOption(
                    value: _asInt(cat['id']),
                    label: (cat['name'] ?? '').toString(),
                  ),
                ),
              ],
              onChanged: (val) => setState(() => _selectedCategoryId = val),
            ),
          ),
          const SizedBox(width: 8),
          // ── Brand dropdown ─────────────────────────────────────────────
          Expanded(
            child: _StyledDropdown<int?>(
              value: _selectedBrandId,
              hint: 'All Brands',
              items: [
                const _DropdownOption(value: null, label: 'All Brands'),
                ..._brands.map(
                  (brand) => _DropdownOption(
                    value: _asInt(brand['id']),
                    label: (brand['name'] ?? '').toString(),
                  ),
                ),
              ],
              onChanged: (val) => setState(() => _selectedBrandId = val),
            ),
          ),
        ],
      ),
    );
  }

  // ── Product grid ─────────────────────────────────────────────────────────
  Widget _buildGrid() {
    final products = _filteredProducts;

    if (_loading && products.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
      );
    }

    if (products.isEmpty) {
      return _buildEmptyState();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _gridCrossAxisCount(constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.all(6),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 5,
            mainAxisSpacing: 5,
            childAspectRatio: 0.80,
          ),
          itemCount: products.length + 1, // +1 for Quick Add card
          itemBuilder: (_, index) {
            if (index == products.length) {
              return _QuickAddCard(onTap: _quickAddProduct);
            }
            final p = products[index];
            final id = _asInt(p['id']) ?? -1;
            final inCart = widget.cartProductIds.contains(id);
            return _ProductCard(
              name: (p['name'] ?? 'Unnamed').toString(),
              sku: (p['sku'] ?? p['barcode'] ?? '').toString(),
              price: (p['price'] ?? p['tp'] ?? 0).toString(),
              imageUrl: _imageUrl(p),
              inCart: inCart,
              stock: _stockValue(p),
              onTap: () => widget.onProductTapped(p),
            );
          },
        );
      },
    );
  }

  int? _stockValue(Map<String, dynamic> p) {
    final raw = p['branch_stock'] ?? p['stock'] ?? p['quantity_in_stock'];
    if (raw == null) return null;
    if (raw is Map) {
      final qty = raw['quantity'] ?? raw['qty'] ?? raw['in_stock'];
      return _asInt(qty);
    }
    return _asInt(raw);
  }

  Widget _buildEmptyState() {
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
            child: const Icon(
              Icons.inventory_2_outlined,
              color: AppTheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _search.isEmpty
                ? 'No products found'
                : 'No products matching "$_search"',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Try a different search or add a product.',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _quickAddProduct,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Quick Add Product'),
          ),
        ],
      ),
    );
  }

  // ── Pagination bar ────────────────────────────────────────────────────────
  Widget _buildPaginationBar() {
    if (_lastPage <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: !_loading && _page > 1
                ? () => _fetchProducts(page: _page - 1, replace: true)
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
            visualDensity: VisualDensity.compact,
            tooltip: 'Previous page',
          ),
          Expanded(
            child: Text(
              'Page $_page of $_lastPage',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            onPressed: !_loading && _page < _lastPage
                ? () => _fetchProducts(page: _page + 1, replace: true)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
            visualDensity: VisualDensity.compact,
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }
}

// ── Dropdown helpers ─────────────────────────────────────────────────────────

class _DropdownOption<T> {
  final T value;
  final String label;

  const _DropdownOption({required this.value, required this.label});
}

class _StyledDropdown<T> extends StatelessWidget {
  final T value;
  final String hint;
  final List<_DropdownOption<T>> items;
  final ValueChanged<T?> onChanged;

  const _StyledDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCCCCCC)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: Color(0xFF666666),
          ),
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF333333),
            fontWeight: FontWeight.w600,
          ),
          hint: Text(
            hint,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF666666),
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          items: items
              .map(
                (opt) => DropdownMenuItem<T>(
                  value: opt.value,
                  child: Text(
                    opt.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Product card — matches reference image style ─────────────────────────────
class _ProductCard extends StatelessWidget {
  final String name;
  final String sku;
  final String price;
  final String? imageUrl;
  final bool inCart;
  final int? stock;
  final VoidCallback onTap;

  const _ProductCard({
    required this.name,
    required this.sku,
    required this.price,
    required this.inCart,
    required this.onTap,
    this.imageUrl,
    this.stock,
  });

  @override
  Widget build(BuildContext context) {
    final stockOut = stock != null && stock! <= 0;
    final stockLow = stock != null && stock! > 0 && stock! <= 5;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: inCart
                ? AppTheme.primary.withOpacity(.5)
                : const Color(0xFFDDDDDD),
            width: inCart ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Image area ────────────────────────────────────────────
                Expanded(
                  flex: 4,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                    child: Container(
                      color: const Color(0xFFEEEEEE),
                      child: imageUrl != null
                          ? Image.network(
                              imageUrl!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) =>
                                  const _ImagePlaceholder(),
                            )
                          : const _ImagePlaceholder(),
                    ),
                  ),
                ),

                // ── Text area ─────────────────────────────────────────────
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(5, 3, 5, 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Product name
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            color: Color(0xFF222222),
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Price
                        Text(
                          price,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: inCart
                                ? AppTheme.primary
                                : const Color(0xFF1A5C58),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (sku.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            sku,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ── In-cart checkmark badge ───────────────────────────────────
            if (inCart)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(.35),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 11,
                  ),
                ),
              ),

            // ── Stock badge (top-left) ────────────────────────────────────
            if (stock != null)
              Positioned(
                top: 5,
                left: 5,
                child: _StockBadge(
                  stock: stock!,
                  low: stockLow,
                  out: stockOut,
                ),
              ),

            // ── Out-of-stock overlay ──────────────────────────────────────
            if (stockOut)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.55),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Image placeholder — gray background + centered image icon (like reference) ─
class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFFEEEEEE),
      child: const Icon(
        Icons.image_outlined,
        color: Color(0xFFAAAAAA),
        size: 22,
      ),
    );
  }
}

// ── Stock badge ──────────────────────────────────────────────────────────────
class _StockBadge extends StatelessWidget {
  final int stock;
  final bool low;
  final bool out;

  const _StockBadge({
    required this.stock,
    required this.low,
    required this.out,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;

    if (out) {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFD32F2F);
      label = 'Out';
    } else if (low) {
      bg = const Color(0xFFFFF3E0);
      fg = const Color(0xFFE65100);
      label = '$stock left';
    } else {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
      label = '$stock';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ── Quick-add card ───────────────────────────────────────────────────────────
class _QuickAddCard extends StatelessWidget {
  final VoidCallback onTap;

  const _QuickAddCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: const Color(0xFFCCCCCC),
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_rounded,
                color: AppTheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Quick Add\nProduct',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
