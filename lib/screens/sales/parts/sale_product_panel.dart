import 'dart:async';

import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/product_group_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/forms/product_form_screen.dart';
import 'package:enterprise_pos/services/catalog_cache_service.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/services/product_stock.dart';
import 'package:enterprise_pos/services/sale_pricing.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/product_filter_bar.dart';
import 'package:enterprise_pos/services/product_panel_filter_store.dart';
import 'package:enterprise_pos/widgets/variant_picker_dialog.dart';
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

  /// Customer classification used only to choose the default/display price.
  /// Existing cart rows are never repriced when this changes.
  final String customerType;

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

  const SaleProductPanel({
    super.key,
    required this.token,
    required this.cartProductIds,
    this.cartProductQuantities = const <int, double>{},
    this.canCreateVariant = false,
    required this.onProductTapped,
    required this.onOpenModal,
    this.vendorId,
    this.branchId,
    this.customerType = 'retail',
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
  List<Map<String, dynamic>> _vendors = [];
  int? _selectedCategoryId;
  int? _selectedBrandId;
  int? _selectedVendorId;
  String? _selectedStockStatus;
  // Active quick sort (see ProductFilterBar); null = server default order.
  String? _sortKey;
  bool _filtersExpanded = false;
  bool _filtersRestored = false;
  int _page = 1;
  int _lastPage = 1;
  // True until the remembered filters are read, so the grid shows its loading
  // state instead of flashing an unfiltered catalogue first.
  bool _loading = true;
  bool _silentRefreshing = false;
  String _search = '';
  int _fetchRequestId = 0;

  late final ProductService _productService;
  late final ProductGroupService _groupService;
  late final CommonService _commonService;
  late final VendorService _vendorService;

  String get _cacheKey => ProductPickCache.keyFor(vendorId: widget.vendorId);

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _productService = ProductService(token: widget.token);
    _groupService = ProductGroupService(token: widget.token);
    _commonService = CommonService(token: widget.token);
    _vendorService = VendorService(token: widget.token);
    if (widget.vendorId != null) {
      _selectedVendorId = widget.vendorId;
    }

    _restoreFiltersAndLoad();
    _fetchFilterData();

    // When the parent supplies a search controller (the search bar lives in
    // the left panel), listen to its changes so typing there filters the grid.
    widget.externalSearchController?.addListener(_onExternalControllerChanged);
  }

  void _onExternalControllerChanged() {
    final ctrl = widget.externalSearchController;
    if (ctrl != null) _onSearchChanged(ctrl.text);
  }

  static const String _filterScope = 'sale';

  /// Re-applies the filters remembered from the last visit (24 h, this device,
  /// see [ProductPanelFilterStore]) and then loads the first page. With
  /// nothing remembered this is the original cache-first load.
  Future<void> _restoreFiltersAndLoad() async {
    final saved =
        await ProductPanelFilterStore.load(_filterScope, widget.branchId);
    if (!mounted) return;
    if (saved != null) {
      _selectedCategoryId = saved.categoryId;
      _selectedBrandId = saved.brandId;
      // A vendor already chosen on the bill always wins over a remembered one.
      if (widget.vendorId == null) _selectedVendorId = saved.vendorId;
      _selectedStockStatus = saved.stockStatus;
      _sortKey = saved.sortKey;
      _filtersExpanded = saved.expanded;
    }

    // Cache-first: show whatever was warmed by PartyPrefetch instantly, but
    // only when no filter is applied (the cache holds the unfiltered catalogue).
    final hasFilters = _selectedCategoryId != null ||
        _selectedBrandId != null ||
        _selectedVendorId != null ||
        _selectedStockStatus != null ||
        _sortKey != null;
    final cached = hasFilters ? null : ProductPickCache.cache.peek(_cacheKey);
    setState(() {
      _filtersRestored = true;
      if (cached != null) {
        _products.addAll(cached.items);
        _page = cached.currentPage;
        _lastPage = cached.lastPage;
        _loading = false;
      }
    });
    _fetchProducts(page: 1, silent: cached != null);
  }

  /// Remembers the current selection; an empty selection removes the entry.
  void _persistFilters() {
    ProductPanelFilterStore.save(
      _filterScope,
      widget.branchId,
      ProductPanelFilters(
        categoryId: _selectedCategoryId,
        brandId: _selectedBrandId,
        // The bill's own vendor is not a user-chosen filter.
        vendorId: widget.vendorId == null ? _selectedVendorId : null,
        stockStatus: _selectedStockStatus,
        sortKey: _sortKey,
        expanded: _filtersExpanded,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant SaleProductPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vendorId != widget.vendorId) {
      _selectedCategoryId = null;
      _selectedBrandId = null;
      _selectedVendorId = widget.vendorId;
      _selectedStockStatus = null;
      _sortKey = null;
      ProductPanelFilterStore.clear(_filterScope, widget.branchId);
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
      final effectiveVendorId = _selectedVendorId ?? widget.vendorId;
      final strictVendor = _selectedVendorId != null;
      final hasServerFilters = _selectedCategoryId != null ||
          _selectedBrandId != null ||
          _selectedVendorId != null ||
          _selectedStockStatus != null ||
          _sortKey != null;

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
              vendorId: effectiveVendorId,
              strictVendor: strictVendor,
              categoryId: _selectedCategoryId,
              brandId: _selectedBrandId,
              stockStatus: _selectedStockStatus,
              sortBy: ProductSortKeys.sortByOf(_sortKey),
              sortOrder: ProductSortKeys.sortOrderOf(_sortKey),
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
        final effectiveVendorId = _selectedVendorId ?? widget.vendorId;
        final strictVendor = _selectedVendorId != null;
        final offlineItems = await CatalogCacheService.instance.searchProducts(
          _search,
          branchId: widget.branchId,
          vendorId: effectiveVendorId,
          strictVendor: strictVendor,
          categoryId: _selectedCategoryId,
          brandId: _selectedBrandId,
          stockStatus: _selectedStockStatus,
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

  Future<void> _fetchFilterData() async {
    _fetchCategoriesAndBrands();
    _fetchVendors();
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

  Future<void> _fetchVendors() async {
    try {
      final res = await _vendorService.getVendors(
        perPage: 200,
        branchId: widget.branchId,
      );
      final list = (res['data']?['vendors'] ??
          res['data']?['data'] ??
          res['data']) as List?;
      if (list != null && mounted) {
        setState(() {
          _vendors = list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
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
    _persistFilters();
    _fetchProducts(page: 1, replace: true, silent: true);
  }

  void _onBrandFilterChanged(int? value) {
    if (_selectedBrandId == value) return;
    setState(() => _selectedBrandId = value);
    _persistFilters();
    _fetchProducts(page: 1, replace: true, silent: true);
  }

  void _onVendorFilterChanged(int? value) {
    if (_selectedVendorId == value) return;
    setState(() => _selectedVendorId = value);
    _persistFilters();
    _fetchProducts(page: 1, replace: true, silent: true);
  }

  void _onStockStatusFilterChanged(String? value) {
    if (_selectedStockStatus == value) return;
    setState(() => _selectedStockStatus = value);
    _persistFilters();
    _fetchProducts(page: 1, replace: true, silent: true);
  }

  void _onSortChanged(String? key) {
    if (_sortKey == key) return;
    setState(() => _sortKey = key);
    _persistFilters();
    _fetchProducts(page: 1, replace: true, silent: true);
  }

  void _onClearAllFilters() {
    if (_selectedCategoryId == null &&
        _selectedBrandId == null &&
        _selectedVendorId == null &&
        _selectedStockStatus == null &&
        _sortKey == null) {
      return;
    }
    setState(() {
      _selectedCategoryId = null;
      _selectedBrandId = null;
      _selectedVendorId = null;
      _selectedStockStatus = null;
      _sortKey = null;
    });
    // Forget the remembered selection too, not just the on-screen one.
    ProductPanelFilterStore.clear(_filterScope, widget.branchId);
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
    if (_selectedVendorId != null) {
      list = list.where((p) {
        final vid = _asInt(p['vendor_id'] ?? p['vendor']?['id']);
        return vid == _selectedVendorId;
      }).toList();
    }
    if (_selectedStockStatus != null) {
      if (_selectedStockStatus == 'in_stock') {
        list = list.where((p) {
          final qty = ProductStock.quantity(p);
          return qty != null && qty > 0;
        }).toList();
      } else if (_selectedStockStatus == 'out_of_stock') {
        list = list.where((p) {
          final qty = ProductStock.quantity(p);
          return qty != null && qty <= 0;
        }).toList();
      } else if (_selectedStockStatus == 'low_stock') {
        list = list.where((p) {
          final qty = ProductStock.quantity(p);
          final reorder = _asDouble(p['reorder_level']) ?? 0;
          return qty != null && qty <= reorder;
        }).toList();
      }
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
          .map((p) => SalePricing.effectiveProductPrice(
                p,
                customerType: widget.customerType,
              ))
          .toList();
      final minPrice = prices.isEmpty ? null : prices.reduce((a, b) => a < b ? a : b);
      final maxPrice = prices.isEmpty ? null : prices.reduce((a, b) => a > b ? a : b);

      var stockKnown = true;
      var stockTotal = 0.0;
      for (final sibling in siblings) {
        final qty = ProductStock.quantity(sibling);
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
        'vendor_id': first['vendor_id'] ?? first['vendor']?['id'],
        'reorder_level': first['reorder_level'],
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

  String _groupPriceText(Map<String, dynamic> product) {
    final variants = (product['_group_variants'] as List?)
            ?.whereType<Map>()
            .map((v) => Map<String, dynamic>.from(v))
            .where(_isActiveProduct)
            .toList() ??
        const <Map<String, dynamic>>[];
    final prices = variants
        .map((v) => SalePricing.effectiveProductPrice(
              v,
              customerType: widget.customerType,
            ))
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

  // ── Filter + sort bar ────────────────────────────────────────────────────
  // One slim row; the dropdowns open on demand (see ProductFilterBar).
  Widget _buildFilterRow() {
    List<FilterOption<int?>> options(List<Map<String, dynamic>> source) => [
          for (final m in source)
            if (_asInt(m['id']) != null)
              FilterOption<int?>(_asInt(m['id']), (m['name'] ?? '').toString()),
        ];

    return ProductFilterBar(
      // Rebuilt once after the remembered filters are read so the bar opens in
      // the remembered expanded/collapsed state.
      key: ValueKey('product-filter-bar-$_filtersRestored'),
      categories: options(_categories),
      brands: options(_brands),
      vendors: options(_vendors),
      categoryId: _selectedCategoryId,
      brandId: _selectedBrandId,
      vendorId: _selectedVendorId,
      stockStatus: _selectedStockStatus,
      sortKey: _sortKey,
      initialExpanded: _filtersExpanded,
      onExpandedChanged: (expanded) {
        _filtersExpanded = expanded;
        _persistFilters();
      },
      onCategoryChanged: _onCategoryFilterChanged,
      onBrandChanged: _onBrandFilterChanged,
      onVendorChanged: _onVendorFilterChanged,
      onStockStatusChanged: _onStockStatusFilterChanged,
      onSortChanged: _onSortChanged,
      onClear: _onClearAllFilters,
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
                  ? _groupPriceText(p)
                  : _compactMoney(SalePricing.effectiveProductPrice(
                      p,
                      customerType: widget.customerType,
                    )),
              wholesalePricing: SalePricing.isWholesale(widget.customerType),
              imageUrl: _imageUrl(p),
              inCart: inCart,
              stock: isVariable
                  ? (p['_group_stock'] as num?)?.toDouble()
                  : ProductStock.quantity(p),
              stockUnit: isVariable
                  ? ProductStock.unitLabel(
                      variants.isEmpty ? null : variants.first,
                    )
                  : ProductStock.unitLabel(p),
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
        // to select the real child product and queue the sale normally.
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
        mode: VariantPickerMode.sale,
        token: widget.token,
        customerType: widget.customerType,
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

// ── Product card — matches reference image style ─────────────────────────────
class _ProductCard extends StatelessWidget {
  final String name;
  final String sku;
  final String price;
  final String? imageUrl;
  final bool inCart;
  final double? stock;
  final String stockUnit;
  final bool isVariable;
  final int variantCount;
  final bool wholesalePricing;
  final VoidCallback onTap;

  const _ProductCard({
    required this.name,
    required this.sku,
    required this.price,
    required this.inCart,
    required this.onTap,
    this.imageUrl,
    this.stock,
    this.stockUnit = '',
    this.isVariable = false,
    this.variantCount = 0,
    this.wholesalePricing = false,
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
                        // Effective selling price for the currently
                        // selected customer classification.
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
                            if (wholesalePricing) ...[
                              const SizedBox(width: 3),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primarySoft,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  'WHOLESALE',
                                  style: TextStyle(
                                    color: AppTheme.primaryDark,
                                    fontSize: 6.8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
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
                  unit: stockUnit,
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
  final double stock;
  final String unit;
  final bool low;
  final bool out;

  const _StockBadge({
    required this.stock,
    this.unit = '',
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
      final qty = ProductStock.formatQuantity(stock);
      label = unit.isEmpty ? '$qty left' : '$qty $unit left';
    } else {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
      final qty = ProductStock.formatQuantity(stock);
      label = unit.isEmpty ? qty : '$qty $unit';
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
