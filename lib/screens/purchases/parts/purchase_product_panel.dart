import 'dart:async';

import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/product_group_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/forms/product_form_screen.dart';
import 'package:enterprise_pos/services/catalog_cache_service.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/variant_picker_dialog.dart';
import 'package:flutter/material.dart';

/// Always-visible embedded product grid for the Create Purchase 2-panel layout.
///
/// Replaces the first-load auto-open of [ProductPickerGridSheet] so the
/// cashier can browse and click products without ever opening a modal.
/// [ProductPickerGridSheet] (F2) remains available as a multi-select
/// fallback for bulk additions.
class PurchaseProductPanel extends StatefulWidget {
  final String token;
  final int? vendorId;

  /// Branch used to scope the offline SQLite fallback search so results are
  /// limited to the active branch's stock. Nullable — null means "all branches"
  /// which is the safe default when no branch is selected.
  final int? branchId;

  /// IDs of products already in the cart — used to show the in-cart badge.
  final Set<int> cartProductIds;

  /// Current transaction quantities, shown inside the shared variant picker so
  /// the operator can see what is already present before adding more.
  final Map<int, double> cartProductQuantities;

  /// Catalog modification remains permission-gated even though the picker is
  /// opened from a transaction screen.
  final bool canCreateVariant;

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

  const PurchaseProductPanel({
    super.key,
    required this.token,
    required this.cartProductIds,
    this.cartProductQuantities = const <int, double>{},
    this.canCreateVariant = false,
    required this.onProductTapped,
    required this.onOpenModal,
    this.vendorId,
    this.branchId,
    this.searchFocusNode,
    this.externalSearchController,
    this.showSearchBar = true,
  });

  @override
  State<PurchaseProductPanel> createState() => _PurchaseProductPanelState();
}

class _PurchaseProductPanelState extends State<PurchaseProductPanel> {
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
  int _fetchRequestId = 0;

  late final ProductService _productService;
  late final ProductGroupService _groupService;
  late final CommonService _commonService;

  String get _cacheKey => ProductPickCache.keyFor(vendorId: widget.vendorId);

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _productService = ProductService(token: widget.token);
    _groupService = ProductGroupService(token: widget.token);
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
  void didUpdateWidget(covariant PurchaseProductPanel oldWidget) {
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
    final requestId = ++_fetchRequestId;
    if (silent) {
      if (mounted) setState(() => _silentRefreshing = true);
    } else {
      if (mounted) setState(() => _loading = true);
    }

    try {
      final hasServerFilters =
          _selectedCategoryId != null || _selectedBrandId != null;
      final entry = _search.isEmpty && !hasServerFilters
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
              categoryId: _selectedCategoryId,
              brandId: _selectedBrandId,
              perPage: 60,
            );

      if (!mounted || requestId != _fetchRequestId) return;
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
          categoryId: _selectedCategoryId,
          brandId: _selectedBrandId,
          limit: 500,
        );
        if (mounted && requestId == _fetchRequestId) {
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
      if (mounted && requestId == _fetchRequestId) {
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

  void _onCategoryFilterChanged(int? value) {
    if (_selectedCategoryId == value) return;
    setState(() => _selectedCategoryId = value);
    // Filters are authoritative server queries online and equivalent local-SQL
    // queries offline. silent=true keeps the current grid visible while the
    // new result replaces it and also allows a filter change during startup.
    _fetchProducts(page: 1, replace: true, silent: true);
  }

  void _onBrandFilterChanged(int? value) {
    if (_selectedBrandId == value) return;
    setState(() => _selectedBrandId = value);
    _fetchProducts(page: 1, replace: true, silent: true);
  }

  // ── Derived catalog (defensive filters + variant-family grouping) ─────────
  //
  // The server/offline catalog still returns the real child products because
  // transactions, barcode scans and queued offline sales must continue using
  // product_id.  The POS browser collapses those children into one family card
  // purely for presentation.  An exact SKU/barcode search is intentionally NOT
  // collapsed so the cashier can add that exact child immediately.
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
    return _collapseVariantFamilies(list);
  }

  List<Map<String, dynamic>> _collapseVariantFamilies(
      List<Map<String, dynamic>> products) {
    final result = <Map<String, dynamic>>[];
    final seenGroups = <int>{};

    for (final product in products) {
      final groupId = _asInt(product['product_group_id']);
      if (groupId == null || _isExactSkuOrBarcodeMatch(product)) {
        result.add(product);
        continue;
      }
      if (!seenGroups.add(groupId)) continue;

      final siblings = products
          .where((p) => _asInt(p['product_group_id']) == groupId)
          .where(_isActiveProduct)
          .toList();
      if (siblings.isEmpty) continue;

      final prices = siblings
          .map((p) => _purchaseCost(p))
          .toList();
      final minPrice = prices.isEmpty ? null : prices.reduce((a, b) => a < b ? a : b);
      final maxPrice = prices.isEmpty ? null : prices.reduce((a, b) => a > b ? a : b);

      var stockKnown = true;
      var stockTotal = 0;
      for (final sibling in siblings) {
        final qty = _stockValue(sibling);
        if (qty == null) {
          stockKnown = false;
          break;
        }
        stockTotal += qty;
      }

      final first = siblings.first;
      result.add(<String, dynamic>{
        '_catalog_kind': 'variable_group',
        'product_group_id': groupId,
        'name': _groupNameFromVariant(first),
        '_group_variants': siblings,
        '_variant_count': siblings.length,
        '_min_price': minPrice,
        '_max_price': maxPrice,
        if (stockKnown) '_group_stock': stockTotal,
        'image_url': _imageUrl(first),
        'category_id': first['category_id'] ?? first['category']?['id'],
        'brand_id': first['brand_id'] ?? first['brand']?['id'],
        '_offline': siblings.every((p) => p['_offline'] == true),
      });
    }

    return result;
  }

  bool _isExactSkuOrBarcodeMatch(Map<String, dynamic> product) {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return false;
    final sku = (product['sku'] ?? '').toString().trim().toLowerCase();
    final barcode = (product['barcode'] ?? '').toString().trim().toLowerCase();
    return (sku.isNotEmpty && sku == query) ||
        (barcode.isNotEmpty && barcode == query);
  }

  static bool _isActiveProduct(Map<String, dynamic> product) {
    final raw = product['is_active'];
    if (raw == null) return true;
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final text = raw.toString().trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

  String _groupNameFromVariant(Map<String, dynamic> product) {
    var name = (product['name'] ?? '').toString().trim();
    final size = (product['variant_size'] ?? '').toString().trim();
    final color = (product['variant_color'] ?? '').toString().trim();

    // Child names are generated by the backend as:
    //   Group Name / Size / Color
    // Remove only the known suffix values, from right to left, so a slash in
    // the actual family name is preserved.
    for (final suffix in [color, size]) {
      if (suffix.isEmpty) continue;
      final marker = ' / $suffix';
      if (name.toLowerCase().endsWith(marker.toLowerCase())) {
        name = name.substring(0, name.length - marker.length).trim();
      }
    }
    return name.isEmpty ? (product['name'] ?? 'Variable Product').toString() : name;
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static double _purchaseCost(Map<String, dynamic> product) {
    for (final key in [
      'purchase_price',
      'cost_price',
      'tp',
      'unit_price',
      'price',
    ]) {
      final parsed = _asDouble(product[key]);
      if (parsed != null) return parsed;
    }
    return 0.0;
  }

  String _groupCostText(Map<String, dynamic> product) {
    final variants = (product['_group_variants'] as List?)
            ?.whereType<Map>()
            .map((v) => Map<String, dynamic>.from(v))
            .where(_isActiveProduct)
            .toList() ??
        const <Map<String, dynamic>>[];
    final prices = variants
        .map((v) => _purchaseCost(v))
        .toList();
    if (prices.isEmpty) return '';
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final minText = _compactMoney(minPrice);
    final maxText = _compactMoney(maxPrice);
    if ((minPrice - maxPrice).abs() < 0.000001) return minText;
    return '$minText – $maxText';
  }

  static String _compactMoney(double value) {
    if ((value - value.roundToDouble()).abs() < 0.000001) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
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
              'Purchase Product Browser',
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
            hintText: 'Filter supplier products by name, SKU or barcode…',
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
              onChanged: _onCategoryFilterChanged,
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
              onChanged: _onBrandFilterChanged,
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
            final isVariable = p['_catalog_kind'] == 'variable_group';
            final variants = (p['_group_variants'] as List?)
                    ?.whereType<Map>()
                    .map((v) => Map<String, dynamic>.from(v))
                    .toList() ??
                const <Map<String, dynamic>>[];
            final id = _asInt(p['id']) ?? -1;
            final inCart = isVariable
                ? variants.any((v) {
                    final variantId = _asInt(v['id']);
                    return variantId != null &&
                        widget.cartProductIds.contains(variantId);
                  })
                : widget.cartProductIds.contains(id);
            final variantCount = _asInt(p['_variant_count']) ?? 0;
            return _ProductCard(
              name: (p['name'] ?? 'Unnamed').toString(),
              sku: (p['sku'] ?? p['barcode'] ?? '').toString(),
              price: isVariable
                  ? 'Cost ${_groupCostText(p)}'
                  : 'Cost ${_compactMoney(_purchaseCost(p))}',
              imageUrl: _imageUrl(p),
              inCart: inCart,
              stock: isVariable
                  ? _asInt(p['_group_stock'])
                  : _stockValue(p),
              isVariable: isVariable,
              variantCount: variantCount,
              onTap: () => _handleProductTap(p),
            );
          },
        );
      },
    );
  }

  /// Handles a top-level POS catalog entry. Simple products and exact
  /// SKU/barcode search results are real product rows and are added directly.
  /// Variable-family cards open a selector and return one real child product.
  ///
  /// Online we refresh siblings from the group endpoint so the selector is
  /// complete even when the product page is paginated. Offline we use the
  /// cached sibling products embedded in the synthetic family card.
  Future<void> _handleProductTap(Map<String, dynamic> product) async {
    if (product['_catalog_kind'] != 'variable_group') {
      widget.onProductTapped(product);
      return;
    }

    final groupId = _asInt(product['product_group_id']);
    if (groupId == null) return;

    var groupName = (product['name'] ?? 'Variable Product').toString();
    var variants = (product['_group_variants'] as List?)
            ?.whereType<Map>()
            .map((v) => Map<String, dynamic>.from(v))
            .where(_isActiveProduct)
            .toList() ??
        <Map<String, dynamic>>[];

    final offlineOnly = product['_offline'] == true;
    if (!offlineOnly) {
      try {
        final data = await _groupService.showGroup(groupId);
        final grp = data['group'];
        if (grp is Map) {
          groupName = (grp['name'] ?? groupName).toString();
        }
        final rawProducts = data['products'] as List? ?? const [];
        final fresh = rawProducts
            .whereType<Map>()
            .map((v) => Map<String, dynamic>.from(v))
            .where(_isActiveProduct)
            .toList();
        if (fresh.isNotEmpty) variants = fresh;
      } catch (_) {
        // Network unavailable: the locally cached children below are enough
        // to select the real child product and continue the purchase normally.
      }
    }

    if (variants.isEmpty || !mounted) return;

    final result = await showDialog<VariantPickerResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VariantPickerDialog(
        groupId: groupId,
        groupName: groupName,
        variants: variants,
        mode: VariantPickerMode.purchase,
        token: widget.token,
        canCreateVariant: widget.canCreateVariant,
        existingCartQuantities: widget.cartProductQuantities,
      ),
    );
    if (!mounted || result == null) return;

    for (final selection in result.selections) {
      final payload = Map<String, dynamic>.from(selection.product)
        ..['_picker_add_qty'] = selection.quantity;
      widget.onProductTapped(payload);
    }
    if (result.catalogChanged) {
      _fetchProducts(page: 1, replace: true, silent: true);
    }
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
  final bool isVariable;
  final int variantCount;
  final VoidCallback onTap;

  const _ProductCard({
    required this.name,
    required this.sku,
    required this.price,
    required this.inCart,
    required this.onTap,
    this.imageUrl,
    this.stock,
    this.isVariable = false,
    this.variantCount = 0,
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
                        // Last/default purchase cost.
                        Row(
                          children: [
                            Expanded(
                              child: Text(
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
                            ),
                          ],
                        ),
                        if (isVariable) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(
                                Icons.tune_rounded,
                                size: 10,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  variantCount == 1 ? '1 variant' : '$variantCount variants',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else if (sku.isNotEmpty) ...[
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
